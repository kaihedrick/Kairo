// filepath: BibleAppPOCV2/Utilities/BundleLoader.swift
import Foundation

enum BundleLoader {
    /// Common subdirectory layouts inside the app bundle.
    /// Covers old export paths (`ios_integration_assets`) and new Core ML bundle paths (`ML/Models`).
    /// Prioritize ios_integration_assets first, then ML/Models, then root fallback
    private static let subdirs: [String] = [
        "ios_integration_assets",              // <- PRIORITY: direct ios_integration_assets
        "ML/Models/ios_integration_assets",    // <- PRIORITY: ML/Models path
        "Resources/ML/ios_integration_assets",
        "ML/ios_integration_assets",
        "Resources/ML",
        "ML",
        "ML/Models",
        ""                                     // fallback root (last resort)
    ]

    /// Try to locate a resource file in the bundle across all known subdirs.
    static func url(name: String, ext: String, preferredSubdirs: [String]? = nil) -> URL? {
        let dirs = preferredSubdirs ?? subdirs
        for sub in dirs {
            if let u = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: sub) {
                print("📁 BundleLoader: Found \(name).\(ext) in subdirectory: '\(sub)' -> \(u.path)")
                return u
            }
        }
        return nil
    }

    /// Throws if the resource is not found.
    static func require(name: String, ext: String) throws -> URL {
        if let u = url(name: name, ext: ext) { return u }
        throw NSError(
            domain: "BundleLoader",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "❌ Missing \(name).\(ext) in app bundle"]
        )
    }
}
