import AVFoundation
import CoreMedia
import Foundation

enum AudioCaptureError: LocalizedError {
    case microphoneNotFound
    case cannotCreateInput(String)
    case cannotAddInput
    case cannotAddOutput

    var errorDescription: String? {
        switch self {
        case .microphoneNotFound:
            return "Selected microphone is not available"
        case let .cannotCreateInput(reason):
            return "Cannot open microphone: \(reason)"
        case .cannotAddInput:
            return "Cannot add microphone input"
        case .cannotAddOutput:
            return "Cannot add audio processor"
        }
    }
}

final class AudioCaptureController: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    var onMeterUpdate: (@Sendable (_ input: Double, _ reduction: Double) -> Void)?
    private let settingsLock = NSLock()
    private var storedSuppressionAmount: Float = 0.75
    private var storedOutputGain: Float = 1
    var suppressionAmount: Float {
        get { settingsLock.withLock { storedSuppressionAmount } }
        set { settingsLock.withLock { storedSuppressionAmount = newValue } }
    }
    var outputGain: Float {
        get { settingsLock.withLock { storedOutputGain } }
        set { settingsLock.withLock { storedOutputGain = newValue } }
    }
    var processorName: String {
        neuralSuppressor.isAvailable ? "DPDFNet · 48 kHz" : "DPDFNet unavailable"
    }

    var onMonitorError: (@Sendable (String) -> Void)?
    private let monitor = MicrophoneMonitor()
    private var monitorSource: MonitorSource = .processed

    func setMonitoring(_ enabled: Bool) throws {
        try processingQueue.sync {
            if enabled {
                try monitor.start()
            } else {
                monitor.stop()
            }
        }
    }

    func setMonitorSource(_ source: MonitorSource) {
        processingQueue.sync {
            monitorSource = source
            monitor.reset()
        }
    }

    private let session = AVCaptureSession()
    private let processingQueue = DispatchQueue(label: "io.github.pilshchikov.krasp.audio", qos: .userInitiated)
    private let neuralSuppressor = NeuralNoiseSuppressor()
    var onProcessingError: (@Sendable (String) -> Void)?
    private var processingFailed = false
    private var output: AVCaptureAudioDataOutput?
    private var sink: any VirtualMicrophoneSink = SharedMemoryVirtualMicrophoneSink()
    private var lastMeterUpdate = DispatchTime.now()

    func start(deviceUID: String?) throws {
        stop()
        guard neuralSuppressor.isAvailable else {
            throw DenoisingError.unavailable(neuralSuppressor.loadError)
        }

        guard let device = captureDevice(uid: deviceUID) else {
            throw AudioCaptureError.microphoneNotFound
        }

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw AudioCaptureError.cannotCreateInput(error.localizedDescription)
        }

        let audioOutput = AVCaptureAudioDataOutput()
        audioOutput.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false
        ]
        audioOutput.setSampleBufferDelegate(self, queue: processingQueue)

        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }

        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw AudioCaptureError.cannotAddInput
        }
        session.addInput(input)

        guard session.canAddOutput(audioOutput) else {
            session.commitConfiguration()
            throw AudioCaptureError.cannotAddOutput
        }
        session.addOutput(audioOutput)
        session.commitConfiguration()

        neuralSuppressor.reset()
        processingFailed = false
        output = audioOutput
        session.startRunning()
    }

    func stop() {
        if session.isRunning {
            session.stopRunning()
        }

        output?.setSampleBufferDelegate(nil, queue: nil)
        output = nil
        // Finish callbacks before resetting processors or starting another device.
        processingQueue.sync { monitor.stop() }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard !processingFailed, CMSampleBufferDataIsReady(sampleBuffer) else {
            return
        }

        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0 else {
            return
        }

        var samples = [Float](repeating: 0, count: frameCount)
        let copyStatus = samples.withUnsafeMutableBytes { rawBuffer in
            let audioBuffer = AudioBuffer(
                mNumberChannels: 1,
                mDataByteSize: UInt32(rawBuffer.count),
                mData: rawBuffer.baseAddress
            )
            var bufferList = AudioBufferList(mNumberBuffers: 1, mBuffers: audioBuffer)
            return CMSampleBufferCopyPCMDataIntoAudioBufferList(
                sampleBuffer,
                at: 0,
                frameCount: Int32(frameCount),
                into: &bufferList
            )
        }

        guard copyStatus == noErr else {
            return
        }

        let inputRMS = AudioMeter.rms(samples)
        let sampleRate = Self.sampleRate(from: sampleBuffer) ?? 48_000
        let metrics: NoiseProcessMetrics
        do {
            guard sampleRate == 48_000 else {
                throw DenoisingError.unavailable("Microphone must provide 48 kHz audio")
            }
            metrics = try neuralSuppressor.process(samples: &samples, amount: suppressionAmount)
        } catch {
            processingFailed = true
            monitor.stop()
            onProcessingError?(error.localizedDescription)
            return
        }
        applyOutputGain(to: &samples)

        samples.withUnsafeBufferPointer { pointer in
            sink.write(samples: pointer, sampleRate: sampleRate)
        }

        do {
            try monitor.write(monitorSource == .original ? neuralSuppressor.alignedOriginal : samples)
        } catch {
            monitor.stop()
            onMonitorError?(error.localizedDescription)
        }

        publishMeters(input: inputRMS, reduction: metrics.reduction)
    }

    private func publishMeters(input: Float, reduction: Float) {
        let now = DispatchTime.now()
        let elapsed = now.uptimeNanoseconds - lastMeterUpdate.uptimeNanoseconds
        guard elapsed > 50_000_000 else {
            return
        }

        lastMeterUpdate = now
        onMeterUpdate?(
            AudioMeter.normalizedLevel(input),
            Double(max(0, min(1, reduction)))
        )
    }

    private func captureDevice(uid: String?) -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )

        let devices = discovery.devices.filter {
            $0.uniqueID != AudioDeviceManager.virtualMicrophoneUID
        }
        if let uid {
            return devices.first { $0.uniqueID == uid }
        }
        if let preferred = AVCaptureDevice.default(for: .audio),
           devices.contains(where: { $0.uniqueID == preferred.uniqueID }) {
            return preferred
        }
        return devices.first
    }

    private static func sampleRate(from sampleBuffer: CMSampleBuffer) -> Double? {
        guard
            let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
            let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        else {
            return nil
        }

        return streamDescription.pointee.mSampleRate
    }

    private func applyOutputGain(to samples: inout [Float]) {
        let clampedGain = max(OutputLevel.minimumGain, min(OutputLevel.maximumGain, outputGain))
        for index in samples.indices {
            samples[index] = max(-1, min(1, samples[index] * clampedGain))
        }
    }
}

private enum OutputLevel {
    static let minimumGain: Float = 0.5
    static let maximumGain: Float = 2.0
}
