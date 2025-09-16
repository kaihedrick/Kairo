// filepath: BibleAppPOCV2/Utilities/TokenizerFiles.swift
import Foundation

// MARK: - Asset Loading Errors

enum AssetError: Error {
    case notFound(String)
    case badData(String)
}

// MARK: - Tokenizer Asset Management

public enum TokenizerAssets {

    // MARK: - Asset Location

    /// Locate a tokenizer asset by name, trying multiple formats and locations
    ///
    /// - Parameter name: The base name of the asset (without extension)
    /// - Returns: URL of the found asset
    /// - Throws: AssetError if asset cannot be found
    private static func url(_ name: String) throws -> URL {
        #if DEBUG
        print("🔍 DEBUG: TokenizerAssets.url() looking for: \(name)")
        #endif

        let extensions = ["json", "txt", ""]
        for ext in extensions {
            let fullName = ext.isEmpty ? name : "\(name).\(ext)"

            #if DEBUG
            print("🔍 DEBUG: Trying to find: \(fullName)")
            #endif

            // First try root bundle (where files are actually located)
            if let u = Bundle.main.url(forResource: name, withExtension: ext) {
                #if DEBUG
                print("✅ Found \(fullName) in root bundle: \(u.path)")
                #endif
                return u
            }

            // Then try ios_integration_assets specifically
            if let u = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "ios_integration_assets") {
                #if DEBUG
                print("✅ Found \(fullName) in ios_integration_assets: \(u.path)")
                #endif
                return u
            }

            // Then try ML/Models/ios_integration_assets
            if let u = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "ML/Models/ios_integration_assets") {
                #if DEBUG
                print("✅ Found \(fullName) in ML/Models/ios_integration_assets: \(u.path)")
                #endif
                return u
            }

            // Finally fall back to BundleLoader
            if let u = BundleLoader.url(name: name, ext: ext) {
                #if DEBUG
                print("✅ Found \(fullName) via BundleLoader: \(u.path)")
                #endif
                return u
            } else {
                #if DEBUG
                print("❌ Not found: \(fullName)")
                #endif
            }
        }
        throw AssetError.notFound(name)
    }

    // MARK: - Asset Loading

    /// Load and decode JSON asset from bundle
    ///
    /// - Parameters:
    ///   - name: The name of the JSON file (without extension)
    ///   - type: The type to decode the JSON as
    /// - Returns: Decoded object of the specified type
    /// - Throws: AssetError or JSON decoding errors
    public static func loadJSON<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        let fileURL = try url(name)

        #if DEBUG
        print("🔍 DEBUG: Loading \(name) from: \(fileURL.path)")
        #endif

        let data = try Data(contentsOf: fileURL)

        #if DEBUG
        print("🔍 DEBUG: \(name) data size: \(data.count) bytes")
        let string = String(data: data, encoding: .utf8)?.prefix(200) ?? "unable to decode"
        print("🔍 DEBUG: \(name) content preview: \(string)...")
        #endif

        do {
            let result = try JSONDecoder().decode(T.self, from: data)

            #if DEBUG
            print("🔍 DEBUG: Successfully decoded \(name) as \(type)")
            #endif

            return result
        } catch let error as DecodingError {
            #if DEBUG
            print("❌ JSON decoding error for \(name): \(error)")
            #endif
            throw error
        }
    }

    /// Load text asset from bundle
    ///
    /// - Parameter name: The name of the text file (without extension)
    /// - Returns: Contents of the text file as a string
    /// - Throws: AssetError if file cannot be read or decoded
    public static func loadText(_ name: String) throws -> String {
        let data = try Data(contentsOf: try url(name))
        guard let s = String(data: data, encoding: .utf8) else {
            throw AssetError.badData(name)
        }
        return s
    }
}

// MARK: - Model Structs

public struct ExportReport: Decodable {
    public struct IO: Decodable {
        let seq_len: Int
        let n_layer: Int
        let n_head: Int
        let head_dim: Int
        let use_cache: Bool
    }
    public let model_io: IO
}

public struct AddedTokenEntry: Decodable {
    let id: Int
    let content: String
}

public struct TokenizerArtifacts {
    public let idToToken: [Int: String]
    public let tokenToId: [String: Int]
    public let merges: [(String, String)]
    public let addedTokens: [String: Int] // content -> id
    public let report: ExportReport

    /// Load all tokenizer artifacts from the bundle
    ///
    /// - Returns: Complete tokenizer artifacts including vocab, merges, and special tokens
    /// - Throws: AssetError or JSON decoding errors if any assets are missing or invalid
    public static func load() throws -> TokenizerArtifacts {
        #if DEBUG
        print("🔍 DEBUG: Starting TokenizerArtifacts.load()...")
        #endif

        // MARK: Load id_to_token.json
        let id2tok = try TokenizerAssets.loadJSON("id_to_token.json", as: [String:String].self)
        var idToToken: [Int:String] = [:]
        id2tok.forEach { if let k = Int($0.key) { idToToken[k] = $0.value } }

        // MARK: Load vocab.json
        let vocab = try TokenizerAssets.loadJSON("vocab.json", as: [String:Int].self)

        // MARK: Load merges.txt
        #if DEBUG
        print("🔍 DEBUG: Loading merges.txt...")
        #endif
        let mergesTxt = try TokenizerAssets.loadText("merges.txt")
        #if DEBUG
        print("🔍 DEBUG: merges.txt length: \(mergesTxt.count) characters")
        #endif

        var merges: [(String,String)] = []

        // Handle both Unix (\n) and Windows (\r\n) line endings
        let lines = mergesTxt.components(separatedBy: .newlines)
            .filter { !$0.isEmpty } // Remove empty lines
        print("🔍 DEBUG: merges.txt has \(lines.count) lines after filtering")

        // If we only have 1 line, it might be due to line ending issues
        if lines.count == 1 {
            print("⚠️ merges.txt appears to be a single line, trying alternative parsing...")
            let altLines = mergesTxt.split(separator: "\r\n")
            if altLines.count > 1 {
                print("✅ Found \(altLines.count) lines with \\r\\n parsing")
                for (index, line) in altLines.enumerated() {
                    if line.hasPrefix("#") {
                        if index < 5 { print("🔍 DEBUG: Skipping comment line \(index)") }
                        continue
                    }
                    let parts = line.split(separator: " ")
                    if parts.count == 2 {
                        merges.append((String(parts[0]), String(parts[1])))
                    }
                }
            }
        } else {
            // Normal parsing
            for (index, line) in lines.enumerated() {
                if line.hasPrefix("#") {
                    if index < 5 { print("🔍 DEBUG: Skipping comment line \(index)") }
                    continue
                }
                let parts = line.split(separator: " ")
                if parts.count == 2 {
                    merges.append((String(parts[0]), String(parts[1])))
                } else if index < 10 {
                    print("⚠️ Unexpected line format at \(index): '\(line)'")
                }
            }
        }
        print("🔍 DEBUG: Successfully parsed \(merges.count) merges")

        // added_tokens.json - try different formats
        var added: [String:Int] = [:]
        if let dict = try? TokenizerAssets.loadJSON("added_tokens.json", as: [String:Int].self) {
            // Direct format: {"[TOKEN]": 12345}
            added = dict
            print("🔍 DEBUG: Successfully parsed added_tokens.json as [String:Int] with \(dict.count) entries")
        } else if let arr = try? TokenizerAssets.loadJSON("added_tokens.json", as: [AddedTokenEntry].self) {
            // Array format: [{"content": "[TOKEN]", "id": 12345}]
            for e in arr { added[e.content] = e.id }
            print("🔍 DEBUG: Successfully parsed added_tokens.json as [AddedTokenEntry] with \(arr.count) entries")
        } else if let dict = try? TokenizerAssets.loadJSON("added_tokens.json", as: [String:AddedTokenEntry].self) {
            // Dictionary format: {"[TOKEN]": {"content": "[TOKEN]", "id": 12345}}
            for (_, e) in dict { added[e.content] = e.id }
            print("🔍 DEBUG: Successfully parsed added_tokens.json as [String:AddedTokenEntry] with \(dict.count) entries")
        } else {
            print("❌ Failed to parse added_tokens.json in any expected format")
        }

        // export_report.json
        let report = try TokenizerAssets.loadJSON("export_report.json", as: ExportReport.self)

        return TokenizerArtifacts(
            idToToken: idToToken,
            tokenToId: vocab,
            merges: merges,
            addedTokens: added,
            report: report
        )
    }
}
