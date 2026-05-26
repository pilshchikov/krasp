import Foundation

struct NoiseProcessMetrics {
    let reduction: Float
}

final class AdaptiveNoiseSuppressor: @unchecked Sendable {
    private var noiseFloor: Float = 0.006
    private var smoothedGain: Float = 1
    private var previousInput: Float = 0
    private var previousHighPassOutput: Float = 0

    func reset() {
        noiseFloor = 0.006
        smoothedGain = 1
        previousInput = 0
        previousHighPassOutput = 0
    }

    func process(samples: inout [Float], amount: Float) -> NoiseProcessMetrics {
        guard !samples.isEmpty else {
            return NoiseProcessMetrics(reduction: 0)
        }

        let clampedAmount = max(0, min(1, amount))
        var highPassed = [Float]()
        highPassed.reserveCapacity(samples.count)

        for sample in samples {
            let filtered = highPass(sample)
            highPassed.append(filtered)
        }

        let rms = AudioMeter.rms(highPassed)
        updateNoiseFloor(with: rms)

        let threshold = max(noiseFloor * 2.8, 0.004)
        let noiseGain = max(0.05, 1 - (0.9 * clampedAmount))
        let targetGain: Float = rms < threshold ? noiseGain : 1

        var gainAccumulator: Float = 0
        for index in highPassed.indices {
            smoothedGain = (smoothedGain * 0.94) + (targetGain * 0.06)
            samples[index] = softClip(highPassed[index] * smoothedGain)
            gainAccumulator += smoothedGain
        }

        let averageGain = gainAccumulator / Float(highPassed.count)
        return NoiseProcessMetrics(reduction: 1 - averageGain)
    }

    private func updateNoiseFloor(with rms: Float) {
        if rms < noiseFloor * 1.8 {
            noiseFloor = (noiseFloor * 0.995) + (rms * 0.005)
        } else {
            noiseFloor = min(noiseFloor * 1.0002, 0.03)
        }
    }

    private func highPass(_ sample: Float) -> Float {
        let alpha: Float = 0.985
        let output = alpha * (previousHighPassOutput + sample - previousInput)
        previousInput = sample
        previousHighPassOutput = output
        return output
    }

    private func softClip(_ sample: Float) -> Float {
        let clamped = max(-1.2, min(1.2, sample))
        return clamped / (1 + abs(clamped) * 0.08)
    }
}
