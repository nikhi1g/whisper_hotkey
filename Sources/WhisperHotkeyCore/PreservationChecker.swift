import Foundation

public struct PreservationReport: Equatable, Sendable {
    public var issues: [String]
    public var pass: Bool

    public init(issues: [String], pass: Bool) {
        self.issues = issues
        self.pass = pass
    }
}

/// Verifies that every protected token survived post-processing verbatim.
///
/// Protected tokens are the request's `protectedTerms` plus tokens
/// auto-protected from `rawText`: URLs, `inline code` spans, and
/// numbers/percentages.  Every token absent from `finalText` is reported in
/// `issues`, deduplicated and sorted.
public enum PreservationChecker {
    public static func report(
        _ request: PostProcessRequest,
        _ result: PostProcessResult
    ) -> PreservationReport {
        let urlPattern = /(?:https?:\/\/|www\.)[^\s]+/
        let codeSpanPattern = /`([^`\n]+)`/
        let percentPattern = /\b\d+(?:[.,]\d+)*%/
        let numberPattern = /\b\d+(?:[.,]\d+)*\b/
        var tokens = Set<String>()
        tokens.formUnion(request.protectedTerms)
        for match in request.rawText.matches(of: urlPattern) {
            tokens.insert(
                String(match.output).trimmingCharacters(in: .punctuationCharacters)
            )
        }
        for match in request.rawText.matches(of: codeSpanPattern) {
            tokens.insert(String(match.output.1))
        }
        for match in request.rawText.matches(of: percentPattern) {
            tokens.insert(String(match.output))
        }
        for match in request.rawText.matches(of: numberPattern) {
            tokens.insert(String(match.output))
        }
        let issues = tokens.filter { !result.finalText.contains($0) }.sorted()
        return PreservationReport(issues: issues, pass: issues.isEmpty)
    }

}
