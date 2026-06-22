import Foundation

/// Brings quiet mic/file windows up to a consistent level before tempo analysis.
///
/// Raw microphone capture is often 10–40× quieter than bundled metronome fixtures.
/// Normalization improves onset detection without changing what the input meter shows.
enum AudioLevelNormalizer {
    static let noiseFloor: Float = 0.000_08
    static let targetRMS: Float = 0.12
    static let maxGain: Float = 48

    static func normalize(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return samples }
        let rms = signalRMS(samples)
        guard rms > noiseFloor else { return samples }
        let gain = min(maxGain, targetRMS / rms)
        guard gain > 1.01 else { return samples }
        return samples.map { $0 * gain }
    }

    static func signalRMS(_ samples: [Float]) -> Float {
        let sum = samples.reduce(0.0) { $0 + Double($1 * $1) }
        return Float((sum / Double(samples.count)).squareRoot())
    }
}
