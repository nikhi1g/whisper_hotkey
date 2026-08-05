import Foundation

/// Where the running application bundle lives relative to `/Applications`.
///
/// A download that is opened straight from `~/Downloads` is quarantined, so
/// macOS launches it from a read-only App Translocation mount. That copy cannot
/// be updated in place, keeps its Gatekeeper prompt on every fresh copy, and
/// disappears when the original is moved, so the first run offers to install
/// the app properly before any of that becomes the user's problem.
public enum ApplicationInstallLocation: Equatable, Sendable {
    /// Already in a standard Applications folder. Nothing to offer.
    case installed
    /// Running from the read-only Gatekeeper shadow copy of a quarantined app.
    case translocated
    /// Running from an ordinary location that is not an Applications folder.
    case unmanaged

    public var needsInstallOffer: Bool {
        self != .installed
    }
}

public enum ApplicationInstallLocator {
    /// macOS mounts quarantined apps under a path containing this component.
    /// `SecTranslocate*` is not surfaced to Swift, and the path marker is the
    /// documented, stable characteristic of a translocated bundle.
    static let translocationMarker = "/AppTranslocation/"

    public static func systemApplicationsURL() -> URL {
        URL(fileURLWithPath: "/Applications", isDirectory: true)
    }

    /// Applications folders an install is not worth offering for.
    public static func managedParents(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        [
            systemApplicationsURL(),
            homeDirectory.appendingPathComponent(
                "Applications",
                isDirectory: true
            ),
        ]
    }

    public static func locate(
        bundleURL: URL,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> ApplicationInstallLocation {
        if bundleURL.path.contains(translocationMarker) {
            return .translocated
        }
        // Compare paths, not URLs. `resolvingSymlinksInPath` keeps the trailing
        // slash on a directory URL it cannot resolve but drops it on one it
        // can, and URL equality is string-based, so two spellings of the same
        // directory compared unequal wherever the path did not exist. That put
        // an app installed in ~/Applications into `.unmanaged` and offered to
        // reinstall it.
        let parent = bundleURL
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()
            .path
        let isManaged = managedParents(homeDirectory: homeDirectory).contains {
            $0.standardizedFileURL.resolvingSymlinksInPath().path == parent
        }
        return isManaged ? .installed : .unmanaged
    }

    /// Destination for an install, preserving the bundle's own name.
    public static func destinationURL(for bundleURL: URL) -> URL {
        systemApplicationsURL().appendingPathComponent(
            bundleURL.lastPathComponent,
            isDirectory: true
        )
    }
}
