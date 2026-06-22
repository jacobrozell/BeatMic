import Foundation

enum TempoFeel: String, Sendable, Equatable, CaseIterable {
    case quarterTime
    case halfTime
    case primary
    case doubleTime

    var label: String {
        switch self {
        case .quarterTime:
            String(localized: "tempo.feel.quarter", defaultValue: "Quarter-time")
        case .halfTime:
            String(localized: "tempo.feel.half", defaultValue: "Half-time")
        case .primary:
            String(localized: "tempo.feel.primary", defaultValue: "Primary")
        case .doubleTime:
            String(localized: "tempo.feel.double", defaultValue: "Double-time")
        }
    }
}

struct TempoAlternative: Sendable, Equatable, Identifiable {
    var id: Int { bpm }
    let bpm: Int
    let feel: TempoFeel
    let isPrimary: Bool
}

struct TempoReading: Sendable, Equatable {
    let primaryBPM: Int
    let confidence: Double
    let loggedAt: Date
    let alternatives: [TempoAlternative]

    static func make(primaryBPM: Int, confidence: Double, loggedAt: Date) -> TempoReading {
        TempoReading(
            primaryBPM: primaryBPM,
            confidence: confidence,
            loggedAt: loggedAt,
            alternatives: TempoInterpretations.alternatives(for: primaryBPM)
        )
    }
}

/// Related tempos that describe the same pulse at different counting rates.
enum TempoInterpretations {
    static let displayMinBPM = 40
    static let displayMaxBPM = 240

    static func alternatives(for primaryBPM: Int) -> [TempoAlternative] {
        let multipliers: [(TempoFeel, Double)] = [
            (.quarterTime, 0.25),
            (.halfTime, 0.5),
            (.primary, 1),
            (.doubleTime, 2)
        ]

        var results: [TempoAlternative] = []
        for (feel, multiplier) in multipliers {
            let raw = Double(primaryBPM) * multiplier
            let bpm = Int(raw.rounded())
            guard bpm >= displayMinBPM, bpm <= displayMaxBPM else { continue }
            results.append(TempoAlternative(bpm: bpm, feel: feel, isPrimary: feel == .primary))
        }

        var seen = Set<Int>()
        return results
            .sorted { $0.bpm < $1.bpm }
            .filter { seen.insert($0.bpm).inserted }
    }
}
