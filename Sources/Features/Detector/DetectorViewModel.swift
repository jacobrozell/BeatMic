import AVFoundation
import Foundation
import Observation

enum MicPermissionState: Equatable {
    case unknown
    case denied
    case granted
}

private enum DetectorStatusCopy {
    static let idle = String(
        localized: "detector.status.idle",
        defaultValue: "Hold your phone near the music and tap Listen."
    )
    static let needMic = String(
        localized: "detector.status.needMic",
        defaultValue: "Microphone access is required to listen."
    )
    static let listening = String(
        localized: "detector.status.listening",
        defaultValue: "Listening… keep the mic near the beat."
    )
    static let captureFailed = String(
        localized: "detector.status.captureFailed",
        defaultValue: "Could not start the microphone."
    )
    static let estimating = String(
        localized: "detector.status.estimating",
        defaultValue: "Estimating tempo…"
    )
    static let quiet = String(
        localized: "detector.status.quiet",
        defaultValue: "Signal is very quiet — move closer to the speaker."
    )
}

@MainActor
@Observable
final class DetectorViewModel {
    private(set) var estimate = BPMEstimate.silent
    private(set) var loggedReading: TempoReading?
    private(set) var inputLevel: Float = 0
    private(set) var permission: MicPermissionState = .unknown
    private(set) var isListening = false
    private(set) var statusMessage = DetectorStatusCopy.idle

    private let capture = LiveAudioCapture()
    private var analysisTask: Task<Void, Never>?
    private var mockTask: Task<Void, Never>?
    private var recentEstimates: [Int] = []

    var displayedBPM: Int? {
        loggedReading?.primaryBPM ?? estimate.bpm
    }

    var loggedTimestampText: String? {
        loggedReading.map { ReadingTimestampFormatter.string(for: $0.loggedAt) }
    }

    func refreshPermission() {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            permission = .granted
        case .denied:
            permission = .denied
        case .undetermined:
            permission = .unknown
        @unknown default:
            permission = .unknown
        }
    }

    func requestPermission() async {
        let granted = await AVAudioApplication.requestRecordPermission()
        permission = granted ? .granted : .denied
    }

    func toggleListening() async {
        if isListening {
            stopListening()
        } else {
            await startListening()
        }
    }

    func startListening() async {
        loggedReading = nil
        estimate = BPMEstimate.silent
        recentEstimates.removeAll()

        if let mockBPM = LaunchConfiguration.mockBPM {
            startMockListening(bpm: mockBPM)
            return
        }
        guard permission == .granted else {
            statusMessage = DetectorStatusCopy.needMic
            return
        }
        do {
            try capture.start()
            isListening = true
            statusMessage = DetectorStatusCopy.listening
            startAnalysisLoop()
        } catch {
            isListening = false
            statusMessage = DetectorStatusCopy.captureFailed
        }
    }

    func stopListening() {
        analysisTask?.cancel()
        analysisTask = nil
        mockTask?.cancel()
        mockTask = nil
        if LaunchConfiguration.mockBPM == nil {
            capture.stop()
        }
        isListening = false
        inputLevel = 0
        estimate = BPMEstimate.silent
        statusMessage = loggedReading == nil
            ? DetectorStatusCopy.idle
            : DetectorStatusCopy.estimating
    }

    private func startAnalysisLoop() {
        analysisTask?.cancel()
        analysisTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(900))
                await self?.analyzeLatestWindow()
            }
        }
    }

    private func analyzeLatestWindow() {
        guard isListening else { return }
        inputLevel = capture.inputLevel
        let samples = capture.recentSamples(maxSeconds: 12)
        let prepared = BPMAnalyzer.prepareSamples(samples, sourceRate: capture.sampleRate)
        let normalized = AudioLevelNormalizer.normalize(prepared)
        let analysisRate = BPMAnalyzer.effectiveSampleRate(sourceRate: capture.sampleRate)
        let raw = BPMAnalyzer.estimate(samples: normalized, sampleRate: analysisRate)
        estimate = smooth(raw)
        if let bpm = estimate.bpm, estimate.confidence >= 0.12 {
            recordReading(primaryBPM: bpm, confidence: estimate.confidence)
        }
        updateStatus(for: estimate)
    }

    private func recordReading(primaryBPM: Int, confidence: Double) {
        if let loggedReading, abs(loggedReading.primaryBPM - primaryBPM) <= 4 {
            self.loggedReading = TempoReading.make(
                primaryBPM: loggedReading.primaryBPM,
                confidence: confidence,
                loggedAt: loggedReading.loggedAt
            )
            return
        }
        loggedReading = TempoReading.make(
            primaryBPM: primaryBPM,
            confidence: confidence,
            loggedAt: Date()
        )
    }

    private func smooth(_ raw: BPMEstimate) -> BPMEstimate {
        guard let bpm = raw.bpm, raw.confidence >= 0.12 else {
            return BPMEstimate(bpm: nil, confidence: raw.confidence)
        }
        recentEstimates.append(bpm)
        if recentEstimates.count > 5 { recentEstimates.removeFirst() }
        let sorted = recentEstimates.sorted()
        let median = sorted[sorted.count / 2]
        let stableCount = recentEstimates.filter { abs($0 - median) <= 4 }.count
        let stability = Double(stableCount) / Double(recentEstimates.count)
        let boosted = min(1, raw.confidence * (0.75 + 0.25 * stability))
        return BPMEstimate(bpm: median, confidence: boosted)
    }

    private func updateStatus(for estimate: BPMEstimate) {
        if loggedReading != nil || estimate.bpm != nil {
            statusMessage = DetectorStatusCopy.estimating
        } else if inputLevel < 0.015 {
            statusMessage = DetectorStatusCopy.quiet
        } else {
            statusMessage = DetectorStatusCopy.listening
        }
    }

    private func startMockListening(bpm: Int) {
        isListening = true
        inputLevel = 0.45
        estimate = BPMEstimate(bpm: bpm, confidence: 0.82)
        loggedReading = TempoReading.make(primaryBPM: bpm, confidence: 0.82, loggedAt: Date())
        statusMessage = DetectorStatusCopy.estimating
        mockTask?.cancel()
        mockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                await MainActor.run {
                    self?.inputLevel = Float.random(in: 0.25...0.65)
                }
            }
        }
    }
}

#if DEBUG
extension DetectorViewModel {
    func logReadingForTesting(primaryBPM: Int, confidence: Double, loggedAt: Date) {
        if let loggedReading, abs(loggedReading.primaryBPM - primaryBPM) <= 4 {
            self.loggedReading = TempoReading.make(
                primaryBPM: loggedReading.primaryBPM,
                confidence: confidence,
                loggedAt: loggedReading.loggedAt
            )
        } else {
            loggedReading = TempoReading.make(
                primaryBPM: primaryBPM,
                confidence: confidence,
                loggedAt: loggedAt
            )
        }
    }
}
#endif
