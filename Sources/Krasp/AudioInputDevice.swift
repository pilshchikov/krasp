import CoreAudio
import Foundation

struct AudioInputDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let isDefault: Bool

    var displayName: String {
        isDefault ? "\(name) (Default)" : name
    }
}
