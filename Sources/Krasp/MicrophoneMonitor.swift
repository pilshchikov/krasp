import AVFoundation
import Foundation

enum MonitorSource: String, CaseIterable {
    case processed = "Cleaned"
    case original = "Original"
}

// A bounded queue keeps monitoring live if the output device stalls.
final class MonitorSampleBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float]
    private var readIndex = 0
    private var count = 0

    init(capacity: Int = 4_800) {
        precondition(capacity > 0)
        samples = .init(repeating: 0, count: capacity)
    }

    func reset() {
        lock.withLock {
            readIndex = 0
            count = 0
        }
    }

    func append(_ input: [Float]) {
        lock.withLock {
            for sample in input {
                if count == samples.count {
                    readIndex = (readIndex + 1) % samples.count
                    count -= 1
                }
                samples[(readIndex + count) % samples.count] = sample
                count += 1
            }
        }
    }

    func read(into output: UnsafeMutableBufferPointer<Float>) {
        lock.withLock {
            for index in output.indices {
                if count > 0 {
                    output[index] = samples[readIndex]
                    readIndex = (readIndex + 1) % samples.count
                    count -= 1
                } else {
                    output[index] = 0
                }
            }
        }
    }
}

// Lifecycle and writes run on the capture processing queue.
final class MicrophoneMonitor {
    private var engine: AVAudioEngine?
    private let buffer = MonitorSampleBuffer()

    func start() throws {
        stop()
        let engine = AVAudioEngine()
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let buffer = self.buffer
        let source = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            if let data = buffers.first?.mData {
                buffer.read(into: UnsafeMutableBufferPointer(
                    start: data.assumingMemoryBound(to: Float.self), count: Int(frameCount)
                ))
            }
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        engine.prepare()
        try engine.start()
        self.engine = engine
    }

    func stop() {
        engine?.stop()
        engine = nil
        buffer.reset()
    }

    func reset() {
        buffer.reset()
    }

    func write(_ samples: [Float]) throws {
        guard let engine else { return }
        // Audio route changes can stop the engine. Resume with fresh audio.
        if !engine.isRunning {
            buffer.reset()
            try engine.start()
        }
        buffer.append(samples)
    }
}
