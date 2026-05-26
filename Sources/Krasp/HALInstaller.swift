import AppKit
import CoreAudio
import Foundation

enum VirtualMicrophoneInstallState: Equatable {
    case missing
    case needsUpdate
    case installed
    case installing
    case failed(String)

    var title: String {
        switch self {
        case .missing:
            return "Virtual microphone not installed"
        case .needsUpdate:
            return "Virtual microphone needs repair"
        case .installed:
            return "Virtual microphone installed"
        case .installing:
            return "Installing virtual microphone"
        case .failed:
            return "Virtual microphone install failed"
        }
    }

    var actionTitle: String {
        switch self {
        case .installed:
            return "Reinstall"
        case .needsUpdate:
            return "Repair"
        case .installing:
            return "Installing"
        case .missing, .failed:
            return "Install"
        }
    }

    var isInstalling: Bool {
        if case .installing = self {
            return true
        }
        return false
    }
}

final class HALInstaller: @unchecked Sendable {
    private let driverName = "KraspHAL.driver"
    private let installPath = "/Library/Audio/Plug-Ins/HAL/KraspHAL.driver"
    private let legacyUserInstallPath = "\(NSHomeDirectory())/Library/Audio/Plug-Ins/HAL/KraspHAL.driver"

    func installState() -> VirtualMicrophoneInstallState {
        let installedExecutable = "\(installPath)/Contents/MacOS/KraspHAL"
        let legacyExists = FileManager.default.fileExists(atPath: legacyUserInstallPath)

        guard FileManager.default.fileExists(atPath: installedExecutable) else {
            return legacyExists ? .needsUpdate : .missing
        }

        guard let embeddedExecutable = embeddedDriverURL()?.appendingPathComponent("Contents/MacOS/KraspHAL") else {
            return legacyExists ? .needsUpdate : .installed
        }

        let installedMatchesEmbedded = (try? Data(contentsOf: URL(fileURLWithPath: installedExecutable))) == (try? Data(contentsOf: embeddedExecutable))
        return installedMatchesEmbedded && !legacyExists && Self.isVirtualMicrophoneRegistered() ? .installed : .needsUpdate
    }

    func installEmbeddedDriver() async -> VirtualMicrophoneInstallState {
        guard let embeddedDriver = embeddedDriverURL() else {
            return .failed("Bundled HAL driver is missing")
        }

        guard FileManager.default.fileExists(atPath: embeddedDriver.path) else {
            return .failed("Bundled HAL driver is missing")
        }

        let script = """
        do shell script "\(Self.appleScriptEscaped(adminInstallCommand(source: embeddedDriver.path)))" with administrator privileges
        """

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                let result = NSAppleScript(source: script)?.executeAndReturnError(&error)

                if result != nil {
                    continuation.resume(returning: self.waitForInstallState())
                } else {
                    let message = (error?[NSAppleScript.errorMessage] as? String) ?? "macOS denied the install"
                    continuation.resume(returning: .failed(message))
                }
            }
        }
    }

    private func embeddedDriverURL() -> URL? {
        Bundle.main.resourceURL?.appendingPathComponent(driverName)
    }

    private func waitForInstallState() -> VirtualMicrophoneInstallState {
        for _ in 0..<24 {
            let state = installState()
            if state == .installed {
                return state
            }
            Thread.sleep(forTimeInterval: 0.25)
        }

        return installState()
    }

    private func adminInstallCommand(source: String) -> String {
        [
            "/bin/mkdir -p /Library/Audio/Plug-Ins/HAL",
            "/bin/rm -rf \(Self.shellQuoted(installPath))",
            "/bin/rm -rf \(Self.shellQuoted(legacyUserInstallPath))",
            "/bin/cp -R \(Self.shellQuoted(source)) \(Self.shellQuoted(installPath))",
            "/usr/sbin/chown -R root:wheel \(Self.shellQuoted(installPath))",
            "/bin/chmod -R go-w \(Self.shellQuoted(installPath))",
            "/usr/bin/killall coreaudiod"
        ].joined(separator: " && ")
    }

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func appleScriptEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func isVirtualMicrophoneRegistered() -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let systemObject = AudioObjectID(kAudioObjectSystemObject)

        guard AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &dataSize) == noErr else {
            return false
        }

        var deviceIDs = [AudioDeviceID](repeating: 0, count: Int(dataSize) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &dataSize, &deviceIDs) == noErr else {
            return false
        }

        return deviceIDs.contains { deviceID in
            deviceUID(deviceID) == "io.github.pilshchikov.krasp.microphone"
        }
    }

    private static func deviceUID(_ deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0

        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr else {
            return nil
        }

        var value: Unmanaged<CFString>?
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &value) == noErr else {
            return nil
        }

        return value?.takeRetainedValue() as String?
    }
}
