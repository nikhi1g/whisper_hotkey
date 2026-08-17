import Foundation

/// Review state shared by the UI and App integration: the raw transcript, the
/// processed result when available, the preservation report, the profile that
/// produced the result, and whether the processor was unavailable (raw shown).
public struct PostProcessPreview: Equatable, Sendable {
    public var rawText: String
    public var processed: PostProcessResult?
    public var report: PreservationReport
    public var profile: SemanticProfileID
    public var unavailable: Bool

    public init(
        rawText: String,
        processed: PostProcessResult?,
        report: PreservationReport,
        profile: SemanticProfileID,
        unavailable: Bool
    ) {
        self.rawText = rawText
        self.processed = processed
        self.report = report
        self.profile = profile
        self.unavailable = unavailable
    }
}
