import Foundation

public struct AccuracyPolicy: Equatable, Sendable {
    public let maximumCandidates: Int
    public let maximumConcurrentIndependentEngines: Int
    public let maximumConcurrentCallsPerEngine: Int
    public let maximumRetryFraction: Double
    public let retryPaddingSeconds: Double
    public let stableObservationCount: Int
    public let maximumUncommittedSeconds: Double
    public let maximumAlignmentCells: Int
    public let maximumRetrySpanSamples: Int64

    public init(
        maximumCandidates: Int = 6,
        maximumConcurrentIndependentEngines: Int = 2,
        maximumConcurrentCallsPerEngine: Int = 1,
        maximumRetryFraction: Double = 0.30,
        retryPaddingSeconds: Double = 0.75,
        stableObservationCount: Int = 2,
        maximumUncommittedSeconds: Double = 8.0,
        maximumAlignmentCells: Int = 1_000_000,
        maximumRetrySpanSamples: Int64 = 20_000
    ) {
        precondition(maximumCandidates >= 1)
        precondition(maximumConcurrentIndependentEngines >= 1)
        precondition(maximumConcurrentCallsPerEngine == 1)
        precondition((0 ... 1).contains(maximumRetryFraction))
        precondition(retryPaddingSeconds >= 0)
        precondition(stableObservationCount >= 2)
        precondition(maximumUncommittedSeconds > 0)
        precondition(maximumAlignmentCells >= 1)
        precondition(maximumRetrySpanSamples >= 0)

        self.maximumCandidates = maximumCandidates
        self.maximumConcurrentIndependentEngines = maximumConcurrentIndependentEngines
        self.maximumConcurrentCallsPerEngine = maximumConcurrentCallsPerEngine
        self.maximumRetryFraction = maximumRetryFraction
        self.retryPaddingSeconds = retryPaddingSeconds
        self.stableObservationCount = stableObservationCount
        self.maximumUncommittedSeconds = maximumUncommittedSeconds
        self.maximumAlignmentCells = maximumAlignmentCells
        self.maximumRetrySpanSamples = maximumRetrySpanSamples
    }

    public static let defaultPolicy = AccuracyPolicy()

    public static let m5ProMaximumAccuracy = AccuracyPolicy(
        maximumCandidates: 8,
        maximumConcurrentIndependentEngines: 2,
        maximumConcurrentCallsPerEngine: 1,
        maximumRetryFraction: 0.35,
        retryPaddingSeconds: 0.90,
        stableObservationCount: 2,
        maximumUncommittedSeconds: 8.0,
        maximumAlignmentCells: 1_500_000,
        maximumRetrySpanSamples: 32_000
    )
}
