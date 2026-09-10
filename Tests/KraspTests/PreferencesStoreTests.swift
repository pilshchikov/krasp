import Foundation
import Testing
@testable import Krasp

struct PreferencesStoreTests {
    private func withStore(_ check: (PreferencesStore, UserDefaults) -> Void) {
        let suite = "KraspTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        check(PreferencesStore(defaults: defaults), defaults)
    }

    @Test func missingSettingsUseDefaults() {
        withStore { store, _ in
            #expect(store.suppressionAmount == 0.75)
            #expect(store.outputGain == 1)
        }
    }

    @Test func zeroSuppressionSurvivesReload() {
        withStore { store, defaults in
            store.suppressionAmount = 0
            #expect(PreferencesStore(defaults: defaults).suppressionAmount == 0)
        }
    }

    @Test func invalidSettingsStayWithinSupportedBounds() {
        withStore { store, defaults in
            defaults.set(10.0, forKey: "suppressionAmount")
            defaults.set(-2.0, forKey: "outputGain")
            #expect(store.suppressionAmount == 1)
            #expect(store.outputGain == 0.5)
            defaults.set(Double.nan, forKey: "suppressionAmount")
            defaults.set(Double.infinity, forKey: "outputGain")
            #expect(store.suppressionAmount == 0.75)
            #expect(store.outputGain == 1)
        }
    }

    @Test func savedValuesSurviveReload() {
        withStore { store, defaults in
            store.suppressionAmount = 0.6
            store.outputGain = 1.8
            store.isEnabled = true
            store.selectedDeviceUID = "physical-microphone"
            let reloaded = PreferencesStore(defaults: defaults)
            #expect(reloaded.suppressionAmount == 0.6)
            #expect(reloaded.outputGain == 1.8)
            #expect(reloaded.isEnabled)
            #expect(reloaded.selectedDeviceUID == "physical-microphone")
        }
    }
}
