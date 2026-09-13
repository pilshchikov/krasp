import Foundation
import Testing
@testable import Krasp

struct DenoisingStreamTests {
    @Test func suppressionUsesDecibels() {
        #expect(SuppressionControl.originalWeight(amount: 0) == 1)
        #expect(abs(SuppressionControl.originalWeight(amount: 0.5) - 0.0316228) < 0.00001)
        #expect(SuppressionControl.originalWeight(amount: 0.75) < 0.006)
        #expect(SuppressionControl.originalWeight(amount: 1) == 0)
    }

    private func run(_ input: [Float], chunks: [Int], amount: Float) throws -> [Float] {
        let stream = DenoisingStream()
        var previous: [Float]?
        var offset = 0
        var chunkIndex = 0
        var result: [Float] = []
        while offset < input.count {
            let count = min(chunks[chunkIndex % chunks.count], input.count - offset)
            result += try stream.process(Array(input[offset..<(offset + count)]), amount: amount) { block in
                defer { previous = block }
                return previous?.map { $0 * 0.1 } ?? []
            }
            offset += count
            chunkIndex += 1
        }
        return result
    }

    @Test func arbitraryCaptureBlocksHaveIdenticalOutputAndFixedDelay() throws {
        let input = (0..<12_000).map { Float($0 % 101) / 101 }
        let regular = try run(input, chunks: [480], amount: 0.5)
        let irregular = try run(input, chunks: [1, 127, 512, 1_024, 33], amount: 0.5)
        #expect(regular == irregular)
        #expect(regular.prefix(DenoisingStream.latencySamples).allSatisfy { $0 == 0 })
        let weight = SuppressionControl.originalWeight(amount: 0.5)
        for i in DenoisingStream.latencySamples..<regular.count {
            let original = input[i - DenoisingStream.latencySamples]
            #expect(abs(regular[i] - original * (0.1 * (1 - weight) + weight)) < 0.00001)
        }
    }

    @Test func fullSuppressionNeverLeaksOriginalSamples() throws {
        let stream = DenoisingStream()
        var warm = false
        for _ in 0..<25 {
            let output = try stream.process([Float](repeating: 1, count: 512), amount: 1) { _ in
                defer { warm = true }
                return warm ? [Float](repeating: 0, count: 480) : []
            }
            #expect(output.allSatisfy { $0 == 0 })
        }
    }

    @Test func zeroSuppressionIsAlignedOriginal() throws {
        let input = (0..<5_000).map { Float($0 % 71) / 71 }
        let result = try run(input, chunks: [512], amount: 0)
        #expect(Array(result.dropFirst(DenoisingStream.latencySamples)) == Array(input.prefix(input.count - DenoisingStream.latencySamples)))
    }

    @Test func resetRemovesOldAudioAndWarmupState() throws {
        let stream = DenoisingStream()
        _ = try stream.process([Float](repeating: 1, count: 480), amount: 1) { _ in [] }
        stream.reset()
        let output = try stream.process([Float](repeating: 0.2, count: 480), amount: 1) { _ in [] }
        #expect(output.allSatisfy { $0 == 0 })
    }

    @Test func unexpectedRuntimeUnderrunFailsInsteadOfLeakingAudio() throws {
        let stream = DenoisingStream()
        _ = try stream.process([Float](repeating: 1, count: 480), amount: 1) { _ in [] }
        #expect(throws: (any Error).self) {
            _ = try stream.process([Float](repeating: 1, count: 480), amount: 1) { _ in [] }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["KRASP_TEST_DPDFNET"] == "1"))
    func realDPDFNetLoadsProcessesAndResets() throws {
        let directory = ProcessInfo.processInfo.environment["KRASP_DPDFNET_RESOURCES"].map { URL(fileURLWithPath: $0) }
        let denoiser = NeuralNoiseSuppressor(resourceDirectory: directory)
        try #require(denoiser.isAvailable, Comment(rawValue: denoiser.loadError))
        let input = (0..<24_000).map { i in Float(sin(Double(i) * 0.023) * 0.1) }
        func process() throws -> [Float] {
            var result: [Float] = []
            for offset in stride(from: 0, to: input.count, by: 512) {
                var chunk = Array(input[offset..<min(offset + 512, input.count)])
                _ = try denoiser.process(samples: &chunk, amount: 1)
                result += chunk
            }
            return result
        }
        let first = try process()
        #expect(first.count == input.count)
        #expect(first.allSatisfy { $0.isFinite })
        #expect(first.prefix(DenoisingStream.latencySamples).allSatisfy { $0 == 0 })
        #expect(first.dropFirst(DenoisingStream.latencySamples).contains { abs($0) > 0.000001 })
        denoiser.reset()
        let second = try process()
        #expect(zip(first, second).allSatisfy { abs($0 - $1) < 0.000001 })
    }
}
