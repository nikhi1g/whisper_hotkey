import XCTest
@testable import WhisperHotkeyShell
import WhisperHotkeyCore

final class CustomThemeEditorViewControllerTests: XCTestCase {
    @MainActor
    func testValidHexUpdatesLivePreviewAndSavesNamedPreset() {
        var saved: CustomBadgeTheme?
        let controller = CustomThemeEditorViewController(theme: nil) {
            saved = $0
        }

        controller.setValuesForTesting(
            name: "Terminal Lime",
            mode: .dark,
            background: "#101216",
            text: "#F7F7F7",
            accent: "#AAFF00"
        )

        XCTAssertTrue(controller.saveIsEnabledForTesting)
        XCTAssertTrue(controller.controlsFitWindowForTesting)
        XCTAssertEqual(
            controller.previewThemeForTesting?.name,
            "Terminal Lime"
        )
        XCTAssertEqual(
            controller.previewThemeForTesting?.accentHex,
            "#AAFF00"
        )
        XCTAssertTrue(controller.previewShowsActivityOriginForTesting)

        controller.saveForTesting()
        XCTAssertEqual(saved, controller.previewThemeForTesting)
    }

    @MainActor
    func testInvalidHexDisablesSavingAndKeepsLastValidPreview() {
        let controller = CustomThemeEditorViewController(theme: nil) { _ in }
        let original = controller.previewThemeForTesting

        controller.setValuesForTesting(
            name: "Invalid",
            mode: .light,
            background: "#XYZ123",
            text: "#111111",
            accent: "#0066CC"
        )

        XCTAssertFalse(controller.saveIsEnabledForTesting)
        XCTAssertEqual(controller.previewThemeForTesting, original)
    }
}
