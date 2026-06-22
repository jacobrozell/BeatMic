import Foundation

struct AlbumReferenceTrack: Sendable, Equatable {
    let filenameContains: String
    let expectedBPM: Int
    let toleranceBPM: Int
    let minimumConfidence: Double

    init(
        filenameContains: String,
        expectedBPM: Int,
        toleranceBPM: Int = 8,
        minimumConfidence: Double = 0.15
    ) {
        self.filenameContains = filenameContains
        self.expectedBPM = expectedBPM
        self.toleranceBPM = toleranceBPM
        self.minimumConfidence = minimumConfidence
    }
}

typealias FacesReferenceTrack = AlbumReferenceTrack
