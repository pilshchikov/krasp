import CDPDFNet
import Foundation

final class NeuralNoiseSuppressor: @unchecked Sendable {
    private var state: OpaquePointer?
    private let stream = DenoisingStream()
    private(set) var loadError = "DPDFNet model or runtime is missing. Rebuild with make app."
    var isAvailable: Bool { state != nil }
    var alignedOriginal: [Float] { stream.alignedOriginal }

    init(resourceDirectory: URL? = nil) {
        let directories = resourceDirectory.map { [$0] } ?? [
            Bundle.main.resourceURL,
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("ThirdParty/DPDFNet")
        ].compactMap { $0 }
        for directory in directories {
            let model = directory.appendingPathComponent("dpdfnet2_48khz_hr.onnx")
            let libraries = [directory.appendingPathComponent("libsherpa-onnx-c-api.dylib"),
                             directory.appendingPathComponent("runtime/libsherpa-onnx-c-api.dylib")]
            guard FileManager.default.fileExists(atPath: model.path),
                  let library = libraries.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else { continue }
            var error = [CChar](repeating: 0, count: 1_024)
            state = krasp_denoiser_create(library.path, model.path, &error, Int32(error.count))
            if state != nil { return }
            loadError = String(decoding: error.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }
    }

    deinit { krasp_denoiser_destroy(state) }

    func reset() {
        krasp_denoiser_reset(state)
        stream.reset()
    }

    func process(samples: inout [Float], amount: Float) throws -> NoiseProcessMetrics {
        guard let state else { throw DenoisingError.unavailable(loadError) }
        samples = try stream.process(samples, amount: amount) { block in
            var cleaned = [Float](repeating: 0, count: DenoisingStream.hop)
            let count = block.withUnsafeBufferPointer { input in
                cleaned.withUnsafeMutableBufferPointer { output in
                    krasp_denoiser_process(state, input.baseAddress, output.baseAddress)
                }
            }
            guard count >= 0 else { throw DenoisingError.invalidOutput }
            return count == 0 ? [] : cleaned
        }
        let inputRMS = AudioMeter.rms(stream.alignedOriginal)
        let outputRMS = AudioMeter.rms(samples)
        return NoiseProcessMetrics(reduction: inputRMS > 0 ? max(0, min(1, 1 - outputRMS / inputRMS)) : 0)
    }
}
