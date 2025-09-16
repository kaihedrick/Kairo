// filepath: BibleAppPOCV2/Utilities/BundleLoader.swift
import Foundation

// MARK: - Bundle Asset Loading Utility

/// Utility for loading assets from the app bundle with support for multiple subdirectory layouts
/// Covers old export paths (`ios_integration_assets`) and new Core ML bundle paths (`ML/Models`)
enum BundleLoader {

    // MARK: - Subdirectory Search Paths

    /// Common subdirectory layouts inside the app bundle
    /// Prioritizes ios_integration_assets first, then ML/Models, then root fallback
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

    // MARK: - Asset Location

    /// Try to locate a resource file in the bundle across all known subdirs
    ///
    /// - Parameters:
    ///   - name: The name of the resource file (without extension)
    ///   - ext: The file extension
    ///   - preferredSubdirs: Optional custom list of subdirectories to search (defaults to standard list)
    /// - Returns: URL of the found resource, or nil if not found
    static func url(name: String, ext: String, preferredSubdirs: [String]? = nil) -> URL? {
        let dirs = preferredSubdirs ?? subdirs
        for sub in dirs {
            if let u = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: sub) {
                #if DEBUG
                print("📁 BundleLoader: Found \(name).\(ext) in subdirectory: '\(sub)' -> \(u.path)")
                #endif
                return u
            }
        }
        return nil
    }

    /// Locate a resource file in the bundle across all known subdirs (throws if not found)
    ///
    /// - Parameters:
    ///   - name: The name of the resource file (without extension)
    ///   - ext: The file extension
    /// - Returns: URL of the found resource
    /// - Throws: NSError if the resource is not found
    static func require(name: String, ext: String) throws -> URL {
        if let u = url(name: name, ext: ext) { return u }
        throw NSError(
            domain: "BundleLoader",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "❌ Missing \(name).\(ext) in app bundle"]
        )
    }
}
