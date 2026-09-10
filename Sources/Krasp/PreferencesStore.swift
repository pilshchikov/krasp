import Foundation

final class PreferencesStore {
    private enum Key {
        static let selectedDeviceUID = "selectedDeviceUID"
        static let suppressionAmount = "suppressionAmount"
        static let outputGain = "outputGain"
        static let isEnabled = "isEnabled"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var selectedDeviceUID: String? {
        get { defaults.string(forKey: Key.selectedDeviceUID) }
        set { defaults.set(newValue, forKey: Key.selectedDeviceUID) }
    }

    var suppressionAmount: Double {
        get {
            boundedValue(forKey: Key.suppressionAmount, fallback: 0.75, range: 0...1)
        }
        set {
            defaults.set(newValue, forKey: Key.suppressionAmount)
        }
    }

    var outputGain: Double {
        get {
            boundedValue(forKey: Key.outputGain, fallback: 1.0, range: 0.5...2)
        }
        set {
            defaults.set(newValue, forKey: Key.outputGain)
        }
    }

    private func boundedValue(forKey key: String, fallback: Double, range: ClosedRange<Double>) -> Double {
        guard let stored = defaults.object(forKey: key) as? NSNumber else { return fallback }
        let value = stored.doubleValue
        guard value.isFinite else { return fallback }
        return min(range.upperBound, max(range.lowerBound, value))
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: Key.isEnabled) }
        set { defaults.set(newValue, forKey: Key.isEnabled) }
    }
}
