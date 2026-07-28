import AppKit
import XCTest
@testable import WhisperHotkeySystem

final class TargetEditabilityPolicyTests: XCTestCase {
    func testStandardTextRoleWithRangeIsSelectionAwareEvenWhenRangeIsReadOnly() {
        XCTAssertEqual(
            mode(
                role: kAXTextAreaRole,
                selectionRange: NSRange(location: 42, length: 0),
                selectionRangeIsSettable: false
            ),
            .selectionAware
        )
    }

    func testTerminalAndElectronTextRolesCanUseOpaqueFallback() {
        XCTAssertEqual(
            mode(role: kAXTextAreaRole),
            .opaque
        )
        XCTAssertEqual(
            mode(role: kAXTextFieldRole),
            .opaque
        )
    }

    func testUnknownRoleWithoutSelectionEvidenceIsUnavailable() {
        XCTAssertEqual(
            mode(role: kAXGroupRole),
            .unavailable
        )
    }

    func testUnknownRoleRequiresSettableSelectionEvidence() {
        let range = NSRange(location: 4, length: 2)
        XCTAssertEqual(
            mode(
                role: kAXGroupRole,
                selectionRange: range,
                selectionRangeIsSettable: false
            ),
            .unavailable
        )
        XCTAssertEqual(
            mode(
                role: kAXGroupRole,
                selectionRange: range,
                selectionRangeIsSettable: true
            ),
            .selectionAware
        )
    }

    func testSecureTextSubroleIsAlwaysUnavailable() {
        XCTAssertEqual(
            mode(
                role: kAXTextFieldRole,
                subrole: kAXSecureTextFieldSubrole,
                selectionRange: NSRange(location: 0, length: 0),
                selectionRangeIsSettable: true
            ),
            .unavailable
        )
    }

    func testDisabledTextRoleIsUnavailable() {
        XCTAssertEqual(
            mode(role: kAXTextAreaRole, isEnabled: false),
            .unavailable
        )
    }

    func testUnreliableSecureSubroleReadFailsClosed() {
        XCTAssertEqual(
            mode(
                role: kAXTextFieldRole,
                subroleIsReliable: false
            ),
            .unavailable
        )
    }

    func testUnreliableMissingSelectionRangeFailsClosed() {
        XCTAssertEqual(
            mode(
                role: kAXTextAreaRole,
                selectionRangeIsReliable: false
            ),
            .unavailable
        )
    }

    private func mode(
        role: String?,
        subrole: String? = nil,
        subroleIsReliable: Bool = true,
        isEnabled: Bool = true,
        selectionRange: NSRange? = nil,
        selectionRangeIsReliable: Bool = true,
        selectionRangeIsSettable: Bool = false
    ) -> TargetTextMode {
        TargetEditabilityPolicy.textMode(
            role: role,
            subrole: subrole,
            subroleIsReliable: subroleIsReliable,
            isEnabled: isEnabled,
            selectionRange: selectionRange,
            selectionRangeIsReliable: selectionRangeIsReliable,
            selectionRangeIsSettable: selectionRangeIsSettable
        )
    }
}
