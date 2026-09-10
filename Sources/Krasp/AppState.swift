import AVFoundation
import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var devices: [AudioInputDevice] = []
    @Published var selectedDeviceUID: String? {
        didSet {
            preferences.selectedDeviceUID = selectedDeviceUID
            restartIfNeeded()
        }
    }
    @Published var suppressionAmount: Double {
        didSet {
            preferences.suppressionAmount = suppressionAmount
            audioController.suppressionAmount = Float(suppressionAmount)
        }
    }
    @Published var outputGain: Double {
        didSet {
            preferences.outputGain = outputGain
            audioController.outputGain = Float(outputGain)
        }
    }
    @Published var isEnabled: Bool {
        didSet {
            preferences.isEnabled = isEnabled
            isEnabled ? start() : stop()
        }
    }
    @Published var canRun = false
    @Published var statusText = "Checking microphone access"
    @Published var inputLevel = 0.0
    @Published var reductionLevel = 0.0
    @Published var virtualMicrophoneState: VirtualMicrophoneInstallState = .missing
    @Published var processorName = "Checking"

    private var hasPrepared = false
    private let preferences = PreferencesStore()
    private let deviceManager = AudioDeviceManager()
    private let audioController = AudioCaptureController()
    private let halInstaller = HALInstaller()

    init() {
        selectedDeviceUID = preferences.selectedDeviceUID
        suppressionAmount = preferences.suppressionAmount
        outputGain = preferences.outputGain
        isEnabled = preferences.isEnabled

        audioController.suppressionAmount = Float(preferences.suppressionAmount)
        audioController.outputGain = Float(preferences.outputGain)
        processorName = audioController.processorName
        audioController.onMeterUpdate = { [weak self] input, reduction in
            Task { @MainActor in
                self?.inputLevel = input
                self?.reductionLevel = reduction
            }
        }
    }

    func prepare() async {
        guard !hasPrepared else { return }
        hasPrepared = true

        refreshVirtualMicrophoneState()
        await refreshDevices()
    }

    func refreshDevices() async {
        // Suppress selection-triggered restarts until permissions and devices agree.
        canRun = false
        audioController.stop()
        inputLevel = 0
        reductionLevel = 0
        let refreshed = deviceManager.inputDevices()
        devices = refreshed

        if selectedDeviceUID == nil || !refreshed.contains(where: { $0.uid == selectedDeviceUID }) {
            selectedDeviceUID = refreshed.first(where: \.isDefault)?.uid ?? refreshed.first?.uid
        }

        await requestMicrophoneAccess()
        refreshVirtualMicrophoneState()
        if isEnabled && canRun {
            start()
        } else if canRun {
            statusText = "Noise cancellation disabled"
        }
    }

    func refreshVirtualMicrophoneState() {
        virtualMicrophoneState = halInstaller.installState()
    }

    func installVirtualMicrophone() {
        guard !virtualMicrophoneState.isInstalling else {
            return
        }

        virtualMicrophoneState = .installing
        Task {
            let state = await halInstaller.installEmbeddedDriver()
            virtualMicrophoneState = state
            await refreshDevices()
        }
    }

    private func requestMicrophoneAccess() async {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            canRun = !devices.isEmpty
            statusText = devices.isEmpty ? "No input microphones found" : "Ready"
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            canRun = granted && !devices.isEmpty
            statusText = granted
                ? (devices.isEmpty ? "No input microphones found" : "Ready")
                : "Microphone access denied"
        case .denied, .restricted:
            canRun = false
            statusText = "Microphone access denied"
        @unknown default:
            canRun = false
            statusText = "Unknown microphone permission state"
        }
    }

    private func restartIfNeeded() {
        guard isEnabled, canRun else { return }
        start()
    }

    private func start() {
        guard canRun else {
            statusText = "Cannot start without microphone access"
            return
        }

        do {
            try audioController.start(deviceUID: selectedDeviceUID)
            processorName = audioController.processorName
            statusText = "Noise cancellation enabled"
        } catch {
            isEnabled = false
            statusText = error.localizedDescription
        }
    }

    private func stop() {
        audioController.stop()
        inputLevel = 0
        reductionLevel = 0
        statusText = canRun ? "Noise cancellation disabled" : statusText
    }
}
