// filepath: BibleAppPOCV2/Utilities/BundleLoader.swift
import Foundation

enum BundleLoader {
    /// Common subdirectory layouts inside the app bundle
    /// We also check ios_integration_assets because Xcode often nests JSONs there.
    private static let subdirs: [String] = [
        "Resources/ML/ios_integration_assets",
        "ML/ios_integration_assets",
        "ios_integration_assets",
        "Resources/ML",
        "ML",
        "" // root
    ]

    static func url(name: String, ext: String, preferredSubdirs: [String]? = nil) -> URL? {
        let subs = preferredSubdirs ?? subdirs
        for sub in subs {
            if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: sub) {
                return url
            }
        }
        return nil
    }

    static func require(name: String, ext: String) throws -> URL {
        if let u = url(name: name, ext: ext) { return u }
        throw NSError(domain: "BundleLoader", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Missing \(name).\(ext) in app bundle"])
    }
}
