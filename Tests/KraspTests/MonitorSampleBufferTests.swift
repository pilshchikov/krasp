import Testing
@testable import Krasp

struct MonitorSampleBufferTests {
    private func read(_ buffer: MonitorSampleBuffer, count: Int) -> [Float] {
        var output = [Float](repeating: -1, count: count)
        output.withUnsafeMutableBufferPointer { buffer.read(into: $0) }
        return output
    }

    @Test func underrunProducesSilenceWithoutRepeatingAudio() {
        let buffer = MonitorSampleBuffer(capacity: 4)
        buffer.append([0.1, 0.2])
        #expect(read(buffer, count: 4) == [0.1, 0.2, 0, 0])
        #expect(read(buffer, count: 2) == [0, 0])
    }

    @Test func overflowKeepsNewestAudio() {
        let buffer = MonitorSampleBuffer(capacity: 3)
        buffer.append([1, 2, 3, 4, 5])
        #expect(read(buffer, count: 3) == [3, 4, 5])
    }

    @Test func wraparoundPreservesOrderAcrossCallbacks() {
        let buffer = MonitorSampleBuffer(capacity: 4)
        buffer.append([1, 2, 3])
        #expect(read(buffer, count: 2) == [1, 2])
        buffer.append([4, 5, 6])
        #expect(read(buffer, count: 4) == [3, 4, 5, 6])
    }

    @Test func resetDiscardsPreviousSource() {
        let buffer = MonitorSampleBuffer(capacity: 4)
        buffer.append([1, 2])
        buffer.reset()
        buffer.append([3])
        #expect(read(buffer, count: 3) == [3, 0, 0])
    }
}
