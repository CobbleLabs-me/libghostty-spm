import Darwin
import Foundation

/// Runtime assets required by Ghostty's exec backend.
///
/// The package owns these assets and always points libghostty at this immutable
/// bundle location before the C runtime initializes. User-level Ghostty
/// resources and configuration are never consulted.
public enum GhosttyRuntimeResources {
    /// The package-bundled Ghostty resource directory.
    ///
    /// Ghostty expects shell integration below this directory and its compiled
    /// terminfo database in a sibling `terminfo` directory. `themes/` is the
    /// bundled Ghostty theme set, so a config's `theme = <name>` resolves
    /// without a Ghostty.app install.
    public static var directoryURL: URL? {
        resources.url(forResource: "Ghostty", withExtension: nil)
    }

    /// The compiled terminfo database exported to child shells by Ghostty.
    public static var terminfoDirectoryURL: URL? {
        resources.url(forResource: "terminfo", withExtension: nil)
    }

    /// The package's resource bundle, located the way an app actually ships it.
    ///
    /// SwiftPM's generated `Bundle.module` only looks next to `Bundle.main`
    /// (the `.app` root — where codesign forbids extra content) and at the
    /// absolute build path of the machine that compiled it. An app that copies
    /// the bundle into `Contents/Resources` therefore works on the developer's
    /// Mac via the build-path fallback and `fatalError`s at launch everywhere
    /// else. Check the app's resource directory first; `Bundle.module` stays as
    /// the last resort so `swift run` and tests keep working.
    private static let resources: Bundle = {
        let name = "GhosttyKit_GhosttyTerminal.bundle"
        let candidates = [Bundle.main.resourceURL, Bundle.main.bundleURL]
        for url in candidates.compactMap({ $0?.appendingPathComponent(name) }) {
            if let bundle = Bundle(url: url) { return bundle }
        }
        return Bundle.module
    }()

    static func configureEnvironment() {
        guard let path = directoryURL?.path else { return }
        setenv("GHOSTTY_RESOURCES_DIR", path, 1)
    }
}
