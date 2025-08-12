// filepath: BibleAppPOCV2/Utilities/BundleLoader.swift
import Foundation

enum BundleLoader {
    // Common subdirectory layouts inside the app bundle
    static let subdirs: [String] = [
        "Resources/ML/ios_integration_assets",
        "ML/ios_integration_assets",
        "ios_integration_assets",
        "Resources/ML",
        "ML",
        "" // root
    ]

    static func url(name: String, ext: String) -> URL? {
        for d in subdirs {
            if let u = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: d) {
                return u
            }
        }
        return nil
    }

    static func require(_ name: String, _ ext: String) -> URL {
        guard let u = url(name: name, ext: ext) else {
            fatalError("Tokenizer asset missing from bundle: \(name).\(ext). Add to Copy Bundle Resources.")
        }
        return u
    }
}

extension Notification.Name {
    static let coreMLBibleModelReady = Notification.Name("coreMLBibleModelReady")
}


