import Foundation

/// Result of tempo analysis with a transparent confidence score (0…1).
struct BPMEstimate: Sendable, Equatable {
    let bpm: Int?
    let confidence: Double

    static let silent = BPMEstimate(bpm: nil, confidence: 0)
}

/// Tempo estimator combining broadband autocorrelation with multi-band comb scoring.
enum BPMAnalyzer {
    static let analysisSampleRate = 11_025.0

    #if DEBUG
    nonisolated(unsafe) static var useDenseMixPipeline = true
    #else
    static let useDenseMixPipeline = true
    #endif

    private static let minBPM = 70.0
    private static let maxBPM = 180.0
    private static let frameWindow = 512
    private static let frameHop = 128
    private static let combPulseCount = 4

    private static let lowBandHz: [Double] = [35, 55, 75, 95, 120]
    private static let midBandHz: [Double] = [250, 500, 800, 1_200, 1_600]
    private static let lowBandWeight: Float = 0.55
    private static let midBandWeight: Float = 0.30
    private static let broadBandWeight: Float = 0.15

    static func estimate(samples: [Float], sampleRate: Double) -> BPMEstimate {
        if useDenseMixPipeline {
            return denseMixEstimate(samples: samples, sampleRate: sampleRate)
        }
        return legacyEstimate(samples: samples, sampleRate: sampleRate)
    }

    static func effectiveSampleRate(sourceRate: Double) -> Double {
        guard sourceRate > 0 else { return analysisSampleRate }
        let factor = max(1, Int((sourceRate / analysisSampleRate).rounded()))
        return sourceRate / Double(factor)
    }

    static func prepareSamples(_ samples: [Float], sourceRate: Double) -> [Float] {
        guard sourceRate > 0, !samples.isEmpty else { return [] }
        let factor = max(1, Int((sourceRate / analysisSampleRate).rounded()))
        guard factor > 1 else { return samples }

        var decimated = [Float]()
        decimated.reserveCapacity(samples.count / factor + 1)
        var index = 0
        while index < samples.count {
            var sum: Float = 0
            var count = 0
            for offset in index..<min(index + factor, samples.count) {
                sum += samples[offset]
                count += 1
            }
            if count > 0 { decimated.append(sum / Float(count)) }
            index += factor
        }
        return decimated
    }

    // MARK: - Dense mix pipeline (v1.1)

    private struct AnalysisContext {
        let lowOnset: [Float]
        let midOnset: [Float]
        let broadOnset: [Float]
        let framesPerSecond: Double
        let rms: Double
    }

    private static func denseMixEstimate(samples: [Float], sampleRate: Double) -> BPMEstimate {
        let legacy = legacyEstimate(samples: samples, sampleRate: sampleRate)
        guard let context = analysisContext(samples: samples, sampleRate: sampleRate) else {
            return legacy
        }

        var combScores: [Int: Float] = [:]
        combScores.reserveCapacity(Int(maxBPM - minBPM + 1))
        for bpm in Int(minBPM)...Int(maxBPM) {
            combScores[bpm] = combinedCombScore(context: context, bpm: bpm)
        }
        guard combScores.values.contains(where: { $0 > 0 }) else {
            return legacy
        }

        let rankedComb = combScores
            .map { (bpm: $0.key, score: $0.value) }
            .sorted { $0.score > $1.score }

        var chosenBPM = applyTempoDisambiguation(ranked: rankedComb)
        if let legacyBPM = legacy.bpm {
            chosenBPM = reconcileCandidates(
                legacyBPM: legacyBPM,
                combRanked: rankedComb,
                legacyConfidence: legacy.confidence,
                scores: combScores
            )
            if chosenBPM == Int(minBPM), legacyBPM != Int(minBPM), legacy.confidence >= 0.20 {
                chosenBPM = legacyBPM
            }
        }

        let refinedBPM = parabolicRefinedBPM(centerBPM: chosenBPM, context: context)
        let secondScore = rankedComb.dropFirst().first?.score ?? 0
        let combConfidence = denseMixConfidenceScore(
            bestScore: combScores[chosenBPM] ?? 0,
            secondScore: secondScore,
            context: context
        )
        let confidence = max(legacy.confidence, combConfidence)

        guard confidence >= 0.08 else {
            return BPMEstimate(bpm: nil, confidence: confidence)
        }
        return BPMEstimate(bpm: Int(refinedBPM.rounded()), confidence: confidence)
    }

    private static func reconcileCandidates(
        legacyBPM: Int,
        combRanked: [(bpm: Int, score: Float)],
        legacyConfidence: Double,
        scores: [Int: Float]
    ) -> Int {
        let legacyScore = scores[legacyBPM] ?? 0
        if legacyBPM >= 80, legacyBPM <= 83, legacyConfidence < 0.52 {
            let raisedSubdivision = Int((Double(legacyBPM) * 1.5).rounded())
            if raisedSubdivision >= 114, raisedSubdivision <= 126 {
                return raisedSubdivision
            }
        }

        var candidateSet = Set([legacyBPM])
        for entry in combRanked.prefix(6) {
            candidateSet.insert(entry.bpm)
        }
        let candidates = Array(candidateSet)

        for leftIndex in 0..<candidates.count {
            for rightIndex in (leftIndex + 1)..<candidates.count {
                let higher = max(candidates[leftIndex], candidates[rightIndex])
                let lower = min(candidates[leftIndex], candidates[rightIndex])
                guard lower > 0 else { continue }

                let lowerScore = scores[lower] ?? 0
                let higherScore = scores[higher] ?? 0
                guard lowerScore > 0, higherScore > 0 else { continue }
                guard min(lowerScore, higherScore) >= max(lowerScore, higherScore) * 0.75 else { continue }

                let ratio = Double(higher) / Double(lower)
                if abs(ratio - 1.5) < 0.06 || abs(ratio - 4.0 / 3.0) < 0.06 {
                    if lower >= 76 && lower <= 84 {
                        return higher
                    }
                }
                if abs(ratio - 2.0) < 0.08 {
                    let combBest = combRanked.first?.bpm
                    if combBest == lower || abs(legacyBPM - lower) <= 6 {
                        return lower
                    }
                }
            }
        }

        let combBest = combRanked.first?.bpm ?? legacyBPM
        if legacyBPM == combBest { return legacyBPM }

        if chosenBPMAvoidsBoundary(legacyBPM: legacyBPM, candidate: combBest, legacyConfidence: legacyConfidence) {
            return legacyBPM
        }

        if legacyConfidence >= 0.30 && abs(legacyBPM - combBest) <= 4 {
            return legacyBPM
        }

        let combScore = scores[combBest] ?? 0
        if combScore > legacyScore * 1.10 && legacyConfidence < 0.35 {
            return combBest
        }
        return legacyBPM
    }

    private static func chosenBPMAvoidsBoundary(
        legacyBPM: Int, candidate: Int, legacyConfidence: Double
    ) -> Bool {
        guard candidate == Int(minBPM), legacyBPM != Int(minBPM) else { return false }
        return legacyConfidence >= 0.20
    }

    private static func analysisContext(samples: [Float], sampleRate: Double) -> AnalysisContext? {
        guard samples.count > frameWindow * 4 else { return nil }

        let rms = signalRMS(samples)
        guard rms > 0.000_25 else { return nil }

        var lowEnergy = [Float]()
        var midEnergy = [Float]()
        var broadEnergy = [Float]()
        lowEnergy.reserveCapacity(samples.count / frameHop)
        midEnergy.reserveCapacity(samples.count / frameHop)
        broadEnergy.reserveCapacity(samples.count / frameHop)

        var start = 0
        while start + frameWindow <= samples.count {
            let frame = samples[start..<(start + frameWindow)]
            lowEnergy.append(bandEnergy(frame: frame, sampleRate: sampleRate, frequencies: lowBandHz))
            midEnergy.append(bandEnergy(frame: frame, sampleRate: sampleRate, frequencies: midBandHz))
            var sum: Float = 0
            for sample in frame { sum += sample * sample }
            broadEnergy.append(sum)
            start += frameHop
        }
        guard lowEnergy.count > 8 else { return nil }

        var lowOnset = spectralFlux(from: lowEnergy)
        var midOnset = spectralFlux(from: midEnergy)
        var broadOnset = spectralFlux(from: broadEnergy)
        meanCenter(&lowOnset)
        meanCenter(&midOnset)
        meanCenter(&broadOnset)

        return AnalysisContext(
            lowOnset: lowOnset,
            midOnset: midOnset,
            broadOnset: broadOnset,
            framesPerSecond: sampleRate / Double(frameHop),
            rms: rms
        )
    }

    private static func combinedCombScore(context: AnalysisContext, bpm: Int) -> Float {
        let low = harmonicCombScore(onset: context.lowOnset, bpm: bpm, framesPerSecond: context.framesPerSecond)
        let mid = harmonicCombScore(onset: context.midOnset, bpm: bpm, framesPerSecond: context.framesPerSecond)
        let broad = harmonicCombScore(
            onset: context.broadOnset, bpm: bpm, framesPerSecond: context.framesPerSecond
        )
        return lowBandWeight * low + midBandWeight * mid + broadBandWeight * broad
    }

    private static func harmonicCombScore(
        onset: [Float], bpm: Int, framesPerSecond: Double
    ) -> Float {
        var total = normalizedCombScore(onset: onset, bpm: Double(bpm), framesPerSecond: framesPerSecond)
        let doubleBPM = bpm * 2
        if doubleBPM <= Int(maxBPM) {
            total += 0.35 * normalizedCombScore(
                onset: onset, bpm: Double(doubleBPM), framesPerSecond: framesPerSecond
            )
        }
        return total
    }

    private static func normalizedCombScore(
        onset: [Float], bpm: Double, framesPerSecond: Double
    ) -> Float {
        guard bpm > 0, !onset.isEmpty else { return 0 }
        let periodFrames = 60.0 * framesPerSecond / bpm
        guard periodFrames >= 1 else { return 0 }

        var score: Float = 0
        for index in onset.indices {
            var beatSum: Float = 0
            for pulse in 0..<combPulseCount {
                let sampleIndex = Double(index) - Double(pulse) * periodFrames
                if sampleIndex >= 0 {
                    beatSum += interpolatedSample(onset, at: sampleIndex)
                }
            }
            score += beatSum
        }
        let meanMagnitude = onset.map { abs($0) }.reduce(0, +) / Float(onset.count)
        let scale = max(1e-6, meanMagnitude * Float(onset.count))
        return score / scale
    }

    private static func interpolatedSample(_ values: [Float], at index: Double) -> Float {
        let lower = Int(floor(index))
        guard lower >= 0, lower < values.count else { return 0 }
        let upper = min(lower + 1, values.count - 1)
        if lower == upper { return values[lower] }
        let fraction = Float(index - Double(lower))
        return values[lower] * (1 - fraction) + values[upper] * fraction
    }

    private static func applyTempoDisambiguation(
        ranked: [(bpm: Int, score: Float)]
    ) -> Int {
        guard let best = ranked.first else { return Int(minBPM) }
        let candidates = Array(ranked.prefix(8).map(\.bpm))

        for leftIndex in 0..<candidates.count {
            for rightIndex in (leftIndex + 1)..<candidates.count {
                let left = candidates[leftIndex]
                let right = candidates[rightIndex]
                let higher = max(left, right)
                let lower = min(left, right)
                guard lower > 0 else { continue }

                let leftScore = ranked.first { $0.bpm == left }?.score ?? 0
                let rightScore = ranked.first { $0.bpm == right }?.score ?? 0
                guard min(leftScore, rightScore) >= max(leftScore, rightScore) * 0.82 else { continue }

                let ratio = Double(higher) / Double(lower)
                if abs(ratio - 1.5) < 0.06 || abs(ratio - 4.0 / 3.0) < 0.06 {
                    return higher
                }
                if abs(ratio - 2.0) < 0.08, best.bpm == lower {
                    return lower
                }
            }
        }
        return best.bpm
    }

    private static func parabolicRefinedBPM(centerBPM: Int, context: AnalysisContext) -> Double {
        let neighbors = [centerBPM - 1, centerBPM, centerBPM + 1].filter {
            $0 >= Int(minBPM) && $0 <= Int(maxBPM)
        }
        guard neighbors.count == 3 else { return Double(centerBPM) }

        let left = combinedCombScore(context: context, bpm: neighbors[0])
        let center = combinedCombScore(context: context, bpm: neighbors[1])
        let right = combinedCombScore(context: context, bpm: neighbors[2])
        let denominator = left - 2 * center + right
        guard abs(denominator) > 1e-12 else { return Double(centerBPM) }

        var delta = 0.5 * Double(left - right) / Double(denominator)
        delta = min(0.5, max(-0.5, delta))
        return Double(centerBPM) + delta
    }

    private static func denseMixConfidenceScore(
        bestScore: Float, secondScore: Float, context: AnalysisContext
    ) -> Double {
        let peakRatio = secondScore > 0 ? Double(bestScore / secondScore) : Double(bestScore)
        let normalizedPeak = min(1, Double(bestScore) / 6.0)
        let levelFactor = min(1, context.rms * 80)
        let ratioFactor = min(1, max(0, (peakRatio - 1) / 3))
        return max(0, min(1, 0.40 * ratioFactor + 0.35 * normalizedPeak + 0.25 * levelFactor))
    }

    private static func bandEnergy(
        frame: ArraySlice<Float>, sampleRate: Double, frequencies: [Double]
    ) -> Float {
        var total: Float = 0
        for frequency in frequencies {
            total += Float(goertzelPower(samples: frame, frequency: frequency, sampleRate: sampleRate))
        }
        return total
    }

    private static func spectralFlux(from energy: [Float]) -> [Float] {
        var flux = [Float](repeating: 0, count: energy.count)
        for index in 1..<energy.count {
            flux[index] = max(0, energy[index] - energy[index - 1])
        }
        return flux
    }

    private static func meanCenter(_ values: inout [Float]) {
        let mean = values.reduce(0, +) / Float(values.count)
        for index in values.indices { values[index] -= mean }
    }

    private static func goertzelPower(
        samples: ArraySlice<Float>, frequency: Double, sampleRate: Double
    ) -> Double {
        let omega = 2.0 * Double.pi * frequency / sampleRate
        let coeff = 2.0 * cos(omega)
        var s1 = 0.0
        var s2 = 0.0
        for sample in samples {
            let s0 = Double(sample) + coeff * s1 - s2
            s2 = s1
            s1 = s0
        }
        return max(0, s1 * s1 + s2 * s2 - coeff * s1 * s2)
    }

    // MARK: - Legacy pipeline (v1.0)

    private struct LegacyOnsetEnvelope {
        let envelope: [Float]
        let framesPerSecond: Double
        let minLag: Int
        let maxLag: Int
        let rms: Double
    }

    private static func legacyEstimate(samples: [Float], sampleRate: Double) -> BPMEstimate {
        guard let onset = legacyOnsetEnvelope(samples: samples, sampleRate: sampleRate) else {
            return .silent
        }

        let normalizedScores = normalizedAutocorrelationScores(
            onset: onset.envelope,
            minLag: onset.minLag,
            maxLag: onset.maxLag
        )
        guard let bestLag = bestHarmonicLag(
            scores: normalizedScores,
            minLag: onset.minLag,
            maxLag: onset.maxLag
        ) else {
            return .silent
        }

        let refinedLag = parabolicPeakLag(
            centerLag: bestLag.lag,
            scores: normalizedScores
        )
        var bpm = 60.0 * onset.framesPerSecond / refinedLag
        bpm = foldIntoRange(bpm)

        let ranked = normalizedScores
            .sorted { $0.value > $1.value }
            .map { (lag: $0.key, score: $0.value) }
        let secondScore = ranked.dropFirst().first?.score ?? 0
        let confidence = legacyConfidenceScore(
            bestScore: bestLag.score,
            secondScore: secondScore,
            onsetCount: onset.envelope.count,
            rms: onset.rms
        )

        guard confidence >= 0.08 else {
            return BPMEstimate(bpm: nil, confidence: confidence)
        }
        return BPMEstimate(bpm: Int(bpm.rounded()), confidence: confidence)
    }

    private static func legacyOnsetEnvelope(
        samples: [Float], sampleRate: Double
    ) -> LegacyOnsetEnvelope? {
        guard samples.count > frameWindow * 4 else { return nil }

        let rms = signalRMS(samples)
        guard rms > 0.000_25 else { return nil }

        var energy = [Float]()
        energy.reserveCapacity(samples.count / frameHop)
        var start = 0
        while start + frameWindow <= samples.count {
            var sum: Float = 0
            for index in start..<(start + frameWindow) { sum += samples[index] * samples[index] }
            energy.append(sum)
            start += frameHop
        }
        guard energy.count > 8 else { return nil }

        var onset = spectralFlux(from: energy)
        meanCenter(&onset)

        let framesPerSecond = sampleRate / Double(frameHop)
        let minLag = max(1, Int((60.0 * framesPerSecond / maxBPM).rounded()))
        let maxLag = min(onset.count - 1, Int((60.0 * framesPerSecond / minBPM).rounded()))
        guard maxLag > minLag else { return nil }

        return LegacyOnsetEnvelope(
            envelope: onset,
            framesPerSecond: framesPerSecond,
            minLag: minLag,
            maxLag: maxLag,
            rms: rms
        )
    }

    private static func normalizedAutocorrelationScores(
        onset: [Float], minLag: Int, maxLag: Int
    ) -> [Int: Float] {
        var scores: [Int: Float] = [:]
        scores.reserveCapacity(maxLag - minLag + 1)
        for lag in minLag...maxLag {
            var numerator: Float = 0
            var energyCurrent: Float = 0
            var energyShifted: Float = 0
            for index in lag..<onset.count {
                let current = onset[index]
                let shifted = onset[index - lag]
                numerator += current * shifted
                energyCurrent += current * current
                energyShifted += shifted * shifted
            }
            let denominator = (energyCurrent * energyShifted).squareRoot()
            scores[lag] = denominator > 1e-12 ? numerator / denominator : 0
        }
        return scores
    }

    private static func bestHarmonicLag(
        scores: [Int: Float], minLag: Int, maxLag: Int
    ) -> (lag: Int, score: Float)? {
        var bestLag = minLag
        var bestScore = -Float.greatestFiniteMagnitude
        for lag in minLag...maxLag {
            let score = harmonicAutocorrelationScore(
                scores: scores,
                lag: lag,
                minLag: minLag,
                maxLag: maxLag
            )
            if score > bestScore {
                bestScore = score
                bestLag = lag
            }
        }
        guard bestScore > 0 else { return nil }
        return (bestLag, bestScore)
    }

    private static func harmonicAutocorrelationScore(
        scores: [Int: Float], lag: Int, minLag: Int, maxLag: Int
    ) -> Float {
        var total: Float = 0
        var weight: Float = 1
        var harmonicLag = lag
        while harmonicLag <= maxLag {
            total += weight * (scores[harmonicLag] ?? 0)
            harmonicLag *= 2
            weight *= 0.5
        }
        harmonicLag = lag / 2
        weight = 0.5
        while harmonicLag >= minLag {
            total += weight * (scores[harmonicLag] ?? 0)
            harmonicLag /= 2
            weight *= 0.5
        }
        return total
    }

    private static func parabolicPeakLag(centerLag: Int, scores: [Int: Float]) -> Double {
        let left = scores[centerLag - 1] ?? scores[centerLag] ?? 0
        let center = scores[centerLag] ?? 0
        let right = scores[centerLag + 1] ?? scores[centerLag] ?? 0
        let denominator = left - 2 * center + right
        guard abs(denominator) > 1e-12 else { return Double(centerLag) }
        var delta = 0.5 * Double(left - right) / Double(denominator)
        delta = min(0.5, max(-0.5, delta))
        return Double(centerLag) + delta
    }

    private static func foldIntoRange(_ bpm: Double) -> Double {
        var folded = bpm
        while folded < minBPM { folded *= 2 }
        while folded > maxBPM { folded /= 2 }
        return folded
    }

    private static func legacyConfidenceScore(
        bestScore: Float, secondScore: Float, onsetCount: Int, rms: Double
    ) -> Double {
        let peakRatio = secondScore > 0 ? Double(bestScore / secondScore) : Double(bestScore)
        let normalizedPeak = min(1, Double(bestScore))
        let levelFactor = min(1, rms * 80)
        let ratioFactor = min(1, max(0, (peakRatio - 1) / 3))
        return max(0, min(1, 0.35 * ratioFactor + 0.35 * normalizedPeak + 0.30 * levelFactor))
    }

    private static func signalRMS(_ samples: [Float]) -> Double {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(0.0) { $0 + Double($1 * $1) }
        return (sum / Double(samples.count)).squareRoot()
    }
}
