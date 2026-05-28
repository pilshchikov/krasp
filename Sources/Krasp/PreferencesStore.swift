import Foundation

final class PreferencesStore {
    private enum Key {
        static let selectedDeviceUID = "selectedDeviceUID"
        static let suppressionAmount = "suppressionAmount"
        static let outputGain = "outputGain"
        static let isEnabled = "isEnabled"
    }

    private let defaults = UserDefaults.standard

    var selectedDeviceUID: String? {
        get { defaults.string(forKey: Key.selectedDeviceUID) }
        set { defaults.set(newValue, forKey: Key.selectedDeviceUID) }
    }

    var suppressionAmount: Double {
        get {
            let stored = defaults.double(forKey: Key.suppressionAmount)
            return stored == 0 ? 0.75 : stored
        }
        set {
            defaults.set(newValue, forKey: Key.suppressionAmount)
        }
    }

    var outputGain: Double {
        get {
            let stored = defaults.double(forKey: Key.outputGain)
            return stored == 0 ? 1.0 : stored
        }
        set {
            defaults.set(newValue, forKey: Key.outputGain)
        }
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: Key.isEnabled) }
        set { defaults.set(newValue, forKey: Key.isEnabled) }
    }
}
