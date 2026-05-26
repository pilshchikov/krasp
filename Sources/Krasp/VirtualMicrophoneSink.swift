import Foundation

protocol VirtualMicrophoneSink: Sendable {
    func write(samples: UnsafeBufferPointer<Float>, sampleRate: Double)
}

struct NullVirtualMicrophoneSink: VirtualMicrophoneSink {
    func write(samples: UnsafeBufferPointer<Float>, sampleRate: Double) {
        _ = samples
        _ = sampleRate
    }
}
