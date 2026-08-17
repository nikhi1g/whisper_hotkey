import Foundation

/// Auto-send is eligible only when the processor reports low meaning-change
/// risk, resolved every uncertain span, and preserved every protected token.
public enum AutoSendGate {
    public static func evaluate(
        _ result: PostProcessResult,
        _ report: PreservationReport
    ) -> Bool {
        result.meaningChangeRisk == .low
            && result.unresolvedSpans.isEmpty
            && report.pass
    }
}
