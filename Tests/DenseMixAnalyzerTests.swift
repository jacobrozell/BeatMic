import Foundation
import Testing
@testable import BeatMic

@Suite("Dense mix analyzer")
struct DenseMixAnalyzerTests {
    private let sampleRate = BPMAnalyzer.analysisSampleRate

    /// 120 BPM kick plus faster hi-hat grid (simulates Insomniak-style subdivision confusion).
    private func kickAndHiHatTrack(seconds: Double) -> [Float] {
        let count = Int(seconds * sampleRate)
        var samples = [Float](repeating: 0, count: count)

        let kickPeriod = Int(60.0 / 120.0 * sampleRate)
        let hatPeriod = Int(60.0 / 180.0 * sampleRate)
        let kickLength = min(256, kickPeriod)
        let hatLength = 24

        var kickIndex = 0
        while kickIndex < count {
            for offset in 0..<min(kickLength, count - kickIndex) {
                let time = Double(offset) / sampleRate
                samples[kickIndex + offset] += 0.9 * Float(sin(2 * Double.pi * 60 * time) * exp(-time * 40))
            }
            kickIndex += kickPeriod
        }

        var hatIndex = 0
        while hatIndex < count {
            for offset in 0..<min(hatLength, count - hatIndex) {
                let phase = Float(hatIndex + offset) * 0.73
                samples[hatIndex + offset] += 0.35 * (phase.truncatingRemainder(dividingBy: 1) - 0.5)
            }
            hatIndex += hatPeriod
        }

        return samples
    }

    @Test("Dense mix pipeline detects 120 BPM kick under faster hi-hats")
    func kickUnderHiHats() {
        let samples = kickAndHiHatTrack(seconds: 20)
        let result = BPMAnalyzer.estimate(samples: samples, sampleRate: sampleRate)
        #expect(result.bpm != nil)
        if let bpm = result.bpm {
            #expect(abs(bpm - 120) <= 6)
        }
    }

    @Test("Legacy pipeline remains available for regression comparison")
    func legacyPipelineStillWorks() {
        let previous = BPMAnalyzer.useDenseMixPipeline
        BPMAnalyzer.useDenseMixPipeline = false
        defer { BPMAnalyzer.useDenseMixPipeline = previous }

        let count = Int(20 * sampleRate)
        var samples = [Float](repeating: 0, count: count)
        let period = Int(60.0 / 120.0 * sampleRate)
        var index = 0
        while index < count {
            for offset in index..<min(index + 128, count) { samples[offset] = 1 }
            index += period
        }

        let result = BPMAnalyzer.estimate(samples: samples, sampleRate: sampleRate)
        #expect(result.bpm != nil)
        if let bpm = result.bpm {
            #expect(abs(bpm - 120) <= 6)
        }
    }
}
