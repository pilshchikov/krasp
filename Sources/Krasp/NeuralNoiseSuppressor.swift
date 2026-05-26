import Darwin
import Foundation

final class NeuralNoiseSuppressor: @unchecked Sendable {
    private typealias DFCreate = @convention(c) (UnsafePointer<CChar>, Float, UnsafePointer<CChar>?) -> OpaquePointer?
    private typealias DFGetFrameLength = @convention(c) (OpaquePointer?) -> Int
    private typealias DFProcessFrame = @convention(c) (OpaquePointer?, UnsafeMutablePointer<Float>?, UnsafeMutablePointer<Float>?) -> Float
    private typealias DFFree = @convention(c) (OpaquePointer?) -> Void
    private typealias DFSetAttenLim = @convention(c) (OpaquePointer?, Float) -> Void

    private var libraryHandle: UnsafeMutableRawPointer?
    private var state: OpaquePointer?
    private var getFrameLength: DFGetFrameLength?
    private var processFrame: DFProcessFrame?
    private var freeState: DFFree?
    private var setAttenLim: DFSetAttenLim?

    private var input48 = [Float]()
    private var output48 = [Float]()
    private var frame16 = [Float]()
    private var enhanced16 = [Float]()
    private var modelFrameLength = 160
    private var lastInputRMS: Float = 0
    private var lastOutputRMS: Float = 0

    var isAvailable: Bool {
        state != nil && processFrame != nil
    }

    init() {
        load()
    }

    deinit {
        if let state {
            freeState?(state)
        }
        if let libraryHandle {
            dlclose(libraryHandle)
        }
    }

    func reset() {
        input48.removeAll(keepingCapacity: true)
        output48.removeAll(keepingCapacity: true)
        lastInputRMS = 0
        lastOutputRMS = 0
    }

    func process(samples: inout [Float], amount: Float) -> NoiseProcessMetrics {
        guard isAvailable, !samples.isEmpty else {
            return NoiseProcessMetrics(reduction: 0)
        }

        input48.append(contentsOf: samples)
        while input48.count >= NeuralFrame.inputSampleCount48k {
            let frame48 = Array(input48.prefix(NeuralFrame.inputSampleCount48k))
            input48.removeFirst(NeuralFrame.inputSampleCount48k)
            processFrame48(frame48)
        }

        let dry = samples
        let clampedAmount = max(0, min(1, amount))
        for index in samples.indices {
            let processed = output48.isEmpty ? 0 : output48.removeFirst()
            samples[index] = (processed * clampedAmount) + (dry[index] * (1 - clampedAmount))
        }

        let reduction = lastInputRMS > 0 ? max(0, min(1, 1 - (lastOutputRMS / lastInputRMS))) : 0
        return NoiseProcessMetrics(reduction: reduction)
    }

    private func processFrame48(_ frame48: [Float]) {
        guard let state, let processFrame else {
            return
        }

        frame16 = Downsampler.downsample48To16(frame48)
        if frame16.count != modelFrameLength {
            frame16 = Array(frame16.prefix(modelFrameLength)) + [Float](repeating: 0, count: max(0, modelFrameLength - frame16.count))
        }

        enhanced16 = [Float](repeating: 0, count: modelFrameLength)
        lastInputRMS = AudioMeter.rms(frame16)

        frame16.withUnsafeMutableBufferPointer { inputPointer in
            enhanced16.withUnsafeMutableBufferPointer { outputPointer in
                _ = processFrame(state, inputPointer.baseAddress, outputPointer.baseAddress)
            }
        }

        lastOutputRMS = AudioMeter.rms(enhanced16)
        output48.append(contentsOf: Downsampler.upsample16To48(enhanced16))
    }

    private func load() {
        guard
            let resourceURL = Bundle.main.resourceURL,
            let libraryPath = firstExistingPath([
                resourceURL.appendingPathComponent("libdf.dylib").path,
                FileManager.default.currentDirectoryPath + "/.build/release/libdf.dylib",
                "/tmp/DeepFilterNet/target/release/libdf.dylib"
            ]),
            let modelPath = firstExistingPath([
                resourceURL.appendingPathComponent("advanced_dfnet16k_model_best_onnx.tar.gz").path,
                FileManager.default.currentDirectoryPath + "/ThirdParty/Hush/advanced_dfnet16k_model_best_onnx.tar.gz"
            ])
        else {
            return
        }

        guard let handle = dlopen(libraryPath, RTLD_NOW | RTLD_LOCAL) else {
            return
        }

        libraryHandle = handle
        guard
            let createSymbol = dlsym(handle, "df_create"),
            let frameLengthSymbol = dlsym(handle, "df_get_frame_length"),
            let processSymbol = dlsym(handle, "df_process_frame"),
            let freeSymbol = dlsym(handle, "df_free")
        else {
            return
        }

        let create = unsafeBitCast(createSymbol, to: DFCreate.self)
        getFrameLength = unsafeBitCast(frameLengthSymbol, to: DFGetFrameLength.self)
        processFrame = unsafeBitCast(processSymbol, to: DFProcessFrame.self)
        freeState = unsafeBitCast(freeSymbol, to: DFFree.self)

        if let attenSymbol = dlsym(handle, "df_set_atten_lim") {
            setAttenLim = unsafeBitCast(attenSymbol, to: DFSetAttenLim.self)
        }

        modelPath.withCString { modelCString in
            state = create(modelCString, 100, nil)
        }

        if let state, let getFrameLength {
            modelFrameLength = getFrameLength(state)
            setAttenLim?(state, 100)
        }
    }

    private func firstExistingPath(_ candidates: [String]) -> String? {
        candidates.first { FileManager.default.fileExists(atPath: $0) }
    }
}

private enum NeuralFrame {
    static let inputSampleCount48k = 480
}

private enum Downsampler {
    static func downsample48To16(_ input: [Float]) -> [Float] {
        var output = [Float]()
        output.reserveCapacity(input.count / 3)

        var index = 0
        while index + 2 < input.count {
            output.append((input[index] + input[index + 1] + input[index + 2]) / 3)
            index += 3
        }

        return output
    }

    static func upsample16To48(_ input: [Float]) -> [Float] {
        guard !input.isEmpty else {
            return []
        }

        var output = [Float]()
        output.reserveCapacity(input.count * 3)

        for index in input.indices {
            let current = input[index]
            let next = index + 1 < input.count ? input[index + 1] : current
            output.append(current)
            output.append(current + ((next - current) / 3))
            output.append(current + ((next - current) * 2 / 3))
        }

        return output
    }
}
