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
    var suppressionAmount: Float = 0.75
    var outputGain: Float = 1
    var processorName: String {
        neuralSuppressor.isAvailable ? "Hush neural 2026" : "Fallback DSP"
    }

    private let session = AVCaptureSession()
    private let processingQueue = DispatchQueue(label: "io.github.pilshchikov.krasp.audio", qos: .userInitiated)
    private let neuralSuppressor = NeuralNoiseSuppressor()
    private let suppressor = AdaptiveNoiseSuppressor()
    private var output: AVCaptureAudioDataOutput?
    private var sink: any VirtualMicrophoneSink = SharedMemoryVirtualMicrophoneSink()
    private var lastMeterUpdate = DispatchTime.now()

    func start(deviceUID: String?) throws {
        stop()

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
        suppressor.reset()
        output = audioOutput
        session.startRunning()
    }

    func stop() {
        if session.isRunning {
            session.stopRunning()
        }

        output?.setSampleBufferDelegate(nil, queue: nil)
        output = nil
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else {
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
        let metrics = neuralSuppressor.isAvailable
            ? neuralSuppressor.process(samples: &samples, amount: suppressionAmount)
            : suppressor.process(samples: &samples, amount: suppressionAmount)
        let sampleRate = Self.sampleRate(from: sampleBuffer) ?? 48_000
        applyOutputGain(to: &samples)

        samples.withUnsafeBufferPointer { pointer in
            sink.write(samples: pointer, sampleRate: sampleRate)
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

        if let uid, let selected = discovery.devices.first(where: { $0.uniqueID == uid }) {
            return selected
        }

        return AVCaptureDevice.default(for: .audio) ?? discovery.devices.first
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
        guard clampedGain != 1 else {
            return
        }

        for index in samples.indices {
            samples[index] = Self.softLimit(samples[index] * clampedGain)
        }
    }

    private static func softLimit(_ sample: Float) -> Float {
        let clamped = max(-OutputLevel.softLimitCeiling, min(OutputLevel.softLimitCeiling, sample))
        return clamped / (1 + abs(clamped) * 0.04)
    }
}

private enum OutputLevel {
    static let minimumGain: Float = 0.5
    static let maximumGain: Float = 2.0
    static let softLimitCeiling: Float = 1.5
}
