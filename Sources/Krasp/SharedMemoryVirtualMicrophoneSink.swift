import Darwin
import Foundation

final class SharedMemoryVirtualMicrophoneSink: VirtualMicrophoneSink, @unchecked Sendable {
    private let lock = NSLock()
    private var mapping: UnsafeMutableRawPointer?
    private let byteCount: Int

    init() {
        byteCount = MemoryLayout<Header>.stride + (Constants.capacityFrames * MemoryLayout<Float>.stride)
        mapping = Self.openMapping(byteCount: byteCount)
        initializeHeaderIfNeeded()
    }

    deinit {
        if let mapping {
            munmap(mapping, byteCount)
        }
    }

    func write(samples: UnsafeBufferPointer<Float>, sampleRate: Double) {
        guard let mapping, !samples.isEmpty else {
            return
        }

        lock.lock()
        defer { lock.unlock() }

        let header = mapping.assumingMemoryBound(to: Header.self)
        let sampleBase = mapping.advanced(by: MemoryLayout<Header>.stride).assumingMemoryBound(to: Float.self)
        var writeIndex = Int(header.pointee.writeIndex % UInt64(Constants.capacityFrames))

        for sample in samples {
            sampleBase[writeIndex] = sample
            writeIndex += 1
            if writeIndex == Constants.capacityFrames {
                writeIndex = 0
            }
        }

        header.pointee.sampleRate = sampleRate
        header.pointee.writeIndex &+= UInt64(samples.count)
        header.pointee.generation &+= 1
    }

    private func initializeHeaderIfNeeded() {
        guard let mapping else {
            return
        }

        let header = mapping.assumingMemoryBound(to: Header.self)
        if header.pointee.magic != Constants.magic || header.pointee.version != Constants.version {
            memset(mapping, 0, byteCount)
            header.pointee.magic = Constants.magic
            header.pointee.version = Constants.version
            header.pointee.capacityFrames = UInt32(Constants.capacityFrames)
            header.pointee.channels = 1
            header.pointee.sampleRate = Constants.sampleRate
            header.pointee.writeIndex = 0
            header.pointee.generation = 0
        }
    }

    private static func openMapping(byteCount: Int) -> UnsafeMutableRawPointer? {
        let fd = open(Constants.filePath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR | S_IRGRP | S_IWGRP | S_IROTH | S_IWOTH)
        guard fd >= 0 else {
            return nil
        }
        defer { close(fd) }

        guard ftruncate(fd, off_t(byteCount)) == 0 else {
            return nil
        }

        let mapped = mmap(nil, byteCount, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0)
        guard mapped != MAP_FAILED else {
            return nil
        }

        return mapped
    }
}

private enum Constants {
    static let filePath = "/tmp/io.github.pilshchikov.krasp.audio"
    static let magic: UInt32 = 0x4B525350
    static let version: UInt32 = 1
    static let capacityFrames = 192_000
    static let sampleRate = 48_000.0
}

private struct Header {
    var magic: UInt32
    var version: UInt32
    var capacityFrames: UInt32
    var channels: UInt32
    var sampleRate: Double
    var writeIndex: UInt64
    var generation: UInt64
}
