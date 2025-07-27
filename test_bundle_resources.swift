import Foundation

// Test script to check bundle resources
print("🔍 Checking bundle resources...")

// Get all bundle resources
if let resourcePath = Bundle.main.resourcePath {
    print("📁 Bundle resource path: \(resourcePath)")
    
    do {
        let contents = try FileManager.default.contentsOfDirectory(atPath: resourcePath)
        print("📦 Bundle contents:")
        for item in contents.sorted() {
            print("  - \(item)")
        }
    } catch {
        print("❌ Error reading bundle contents: \(error)")
    }
} else {
    print("❌ No resource path found")
}

// Check specific ML resources
print("\n🔍 Checking ML resources specifically...")

// Try to find the BART model
let possiblePaths = [
    "BibleSummarizer_full.mlpackage",
    "Resources/ML/BibleSummarizer_full.mlpackage",
    "ML/BibleSummarizer_full.mlpackage"
]

for path in possiblePaths {
    if let url = Bundle.main.url(forResource: path, withExtension: nil) {
        print("✅ Found model at: \(url.path)")
    } else {
        print("❌ Not found: \(path)")
    }
}

// Check if we can find any .mlpackage files
if let urls = Bundle.main.urls(forResourcesWithExtension: "mlpackage", subdirectory: nil) {
    print("\n📦 Found .mlpackage files:")
    for url in urls {
        print("  - \(url.lastPathComponent)")
    }
} else {
    print("\n❌ No .mlpackage files found in bundle")
}

// Check subdirectories
if let urls = Bundle.main.urls(forResourcesWithExtension: nil, subdirectory: "Resources/ML") {
    print("\n📦 Found Resources/ML contents:")
    for url in urls {
        print("  - \(url.lastPathComponent)")
    }
} else {
    print("\n❌ No Resources/ML subdirectory found")
} 