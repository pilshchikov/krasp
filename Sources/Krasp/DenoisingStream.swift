import Foundation

struct NoiseProcessMetrics {
    let reduction: Float
}

enum DenoisingError: LocalizedError {
    case unavailable(String)
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .unavailable(let message): return message
        case .invalidOutput: return "DPDFNet returned invalid audio; processing stopped"
        }
    }
}

enum SuppressionControl {
    // 25% = 15 dB, 50% = 30 dB, 75% = 45 dB; 100% is fully processed.
    static func originalWeight(amount: Float) -> Float {
        let amount = amount.isFinite ? max(0, min(1, amount)) : 1
        return amount >= 1 ? 0 : pow(10, -60 * amount / 20)
    }
}

private struct SampleQueue {
    private var storage: [Float] = []
    private var offset = 0
    var count: Int { storage.count - offset }

    mutating func append(_ samples: [Float]) { storage.append(contentsOf: samples) }

    mutating func take(_ count: Int) -> [Float] {
        precondition(count <= self.count)
        let result = Array(storage[offset..<(offset + count)])
        offset += count
        if offset >= 4_096 {
            storage.removeFirst(offset)
            offset = 0
        }
        return result
    }
}

final class DenoisingStream {
    static let hop = 480
    // One runtime warmup hop plus up to one partial capture hop, fixed for all block sizes.
    static let latencySamples = 2 * hop - 1
    private var input = SampleQueue()
    private var original = SampleQueue()
    private var output = SampleQueue()
    private var originalOutput = SampleQueue()
    private var hasWarmedUp = false
    private var previousOriginalWeight: Float?
    private(set) var alignedOriginal: [Float] = []

    init() { reset() }

    func reset() {
        input = SampleQueue()
        original = SampleQueue()
        output = SampleQueue()
        originalOutput = SampleQueue()
        let silence = [Float](repeating: 0, count: Self.latencySamples)
        output.append(silence)
        originalOutput.append(silence)
        alignedOriginal = []
        hasWarmedUp = false
        previousOriginalWeight = nil
    }

    func process(_ samples: [Float], amount: Float,
                 enhance: ([Float]) throws -> [Float]) throws -> [Float] {
        input.append(samples)
        while input.count >= Self.hop {
            let block = input.take(Self.hop)
            original.append(block)
            let cleaned = try enhance(block)
            if !hasWarmedUp {
                guard cleaned.isEmpty else { throw DenoisingError.invalidOutput }
                hasWarmedUp = true
                continue
            }
            guard cleaned.count == Self.hop, cleaned.allSatisfy(\.isFinite) else {
                throw DenoisingError.invalidOutput
            }
            // The streaming runtime omits its first hop and returns audio from time zero.
            let dry = original.take(Self.hop)
            let target = SuppressionControl.originalWeight(amount: amount)
            let initial = previousOriginalWeight ?? target
            var mixed = cleaned
            for i in mixed.indices {
                let weight = initial + (target - initial) * Float(i + 1) / Float(Self.hop)
                mixed[i] = cleaned[i] * (1 - weight) + dry[i] * weight
            }
            previousOriginalWeight = target
            output.append(mixed)
            originalOutput.append(dry)
        }
        guard output.count >= samples.count else { throw DenoisingError.invalidOutput }
        alignedOriginal = originalOutput.take(samples.count)
        return output.take(samples.count)
    }
}
