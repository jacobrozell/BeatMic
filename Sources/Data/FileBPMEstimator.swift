import AVFoundation
import Foundation

/// Loads mono PCM from a bundled or on-disk audio file for tempo analysis.
enum AudioFileLoader {
    static func loadMonoSamples(
        url: URL,
        targetRate: Double = BPMAnalyzer.analysisSampleRate,
        maxSeconds: Double = 90
    ) -> (samples: [Float], sampleRate: Double)? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let nativeRate = format.sampleRate
        guard nativeRate > 0 else { return nil }

        let framesToRead = min(
            AVAudioFrameCount(file.length),
            AVAudioFrameCount(nativeRate * maxSeconds)
        )
        guard framesToRead > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesToRead),
              (try? file.read(into: buffer, frameCount: framesToRead)) != nil,
              let channels = buffer.floatChannelData else { return nil }

        let channelCount = Int(format.channelCount)
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return nil }

        var mono = [Float](repeating: 0, count: frameLength)
        for channel in 0..<channelCount {
            let data = channels[channel]
            for index in 0..<frameLength {
                mono[index] += data[index]
            }
        }
        if channelCount > 1 {
            let scale = 1 / Float(channelCount)
            for index in 0..<frameLength { mono[index] *= scale }
        }

        let prepared = BPMAnalyzer.prepareSamples(mono, sourceRate: nativeRate)
        let effectiveRate = BPMAnalyzer.effectiveSampleRate(sourceRate: nativeRate)
        let normalized = AudioLevelNormalizer.normalize(prepared)
        return (normalized, effectiveRate)
    }
}

enum FileBPMEstimator {
    static func estimate(url: URL) -> BPMEstimate {
        guard let audio = AudioFileLoader.loadMonoSamples(url: url),
              Double(audio.samples.count) > audio.sampleRate else {
            return .silent
        }
        return BPMAnalyzer.estimate(samples: audio.samples, sampleRate: audio.sampleRate)
    }
}
