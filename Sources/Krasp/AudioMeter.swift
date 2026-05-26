import Foundation

enum AudioMeter {
    static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else {
            return 0
        }

        var sum: Float = 0
        for sample in samples {
            sum += sample * sample
        }

        return sqrt(sum / Float(samples.count))
    }

    static func normalizedLevel(_ rms: Float) -> Double {
        guard rms > 0 else {
            return 0
        }

        let decibels = 20 * log10(Double(rms))
        return max(0, min(1, (decibels + 60) / 60))
    }
}
