// TokenizerFiles.swift
import Foundation

enum AssetError: Error { case notFound(String), badData(String) }

public enum TokenizerAssets {
    private static func url(_ name: String) throws -> URL {
        // Use BundleLoader which searches multiple subdirectories including "ML/Models"
        // Handle files with different extensions by trying common ones
<<<<<<< HEAD
        print("🔍 DEBUG: TokenizerAssets.url() looking for: \(name)")
        let extensions = ["json", "txt", ""]
        for ext in extensions {
            let fullName = ext.isEmpty ? name : "\(name).\(ext)"
            print("🔍 DEBUG: Trying to find: \(fullName)")
            if let url = BundleLoader.url(name: name, ext: ext) {
                print("✅ Found \(fullName) at: \(url.path)")
                return url
            } else {
                print("❌ Not found: \(fullName)")
=======
        let extensions = ["json", "txt", ""]
        for ext in extensions {
            if let url = BundleLoader.url(name: name, ext: ext) {
                return url
>>>>>>> a8b6634e7d680102bb44bcc5a3f496034a5a7d44
            }
        }
        throw AssetError.notFound(name)
    }

    public static func loadJSON<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        let data = try Data(contentsOf: try url(name))
        return try JSONDecoder().decode(T.self, from: data)
    }

    public static func loadText(_ name: String) throws -> String {
        let data = try Data(contentsOf: try url(name))
        guard let s = String(data: data, encoding: .utf8) else { throw AssetError.badData(name) }
        return s
    }
}

// Model structs
public struct ExportReport: Decodable {
    public struct IO: Decodable { let seq_len: Int; let n_layer: Int; let n_head: Int; let head_dim: Int; let use_cache: Bool }
    public let model_io: IO
}

public struct AddedTokenEntry: Decodable { let id: Int; let content: String }

public struct TokenizerArtifacts {
    public let idToToken: [Int: String]
    public let tokenToId: [String: Int]
    public let merges: [(String, String)]
    public let addedTokens: [String: Int] // content -> id
    public let report: ExportReport

    public static func load() throws -> TokenizerArtifacts {
        // id_to_token.json
        let id2tok = try TokenizerAssets.loadJSON("id_to_token.json", as: [String:String].self)
        var idToToken: [Int:String] = [:]; id2tok.forEach { if let k = Int($0.key) { idToToken[k] = $0.value } }

        // vocab.json (token -> id)
        let vocab = try TokenizerAssets.loadJSON("vocab.json", as: [String:Int].self)

        // merges.txt (skip header line if present)
<<<<<<< HEAD
        print("🔍 DEBUG: Loading merges.txt...")
        let mergesTxt = try TokenizerAssets.loadText("merges.txt")
        print("🔍 DEBUG: merges.txt length: \(mergesTxt.count) characters")
        print("🔍 DEBUG: First 200 characters of merges.txt: '\(String(mergesTxt.prefix(200)))'")

        var merges: [(String,String)] = []
        let lines = mergesTxt.split(separator: "\n")
        print("🔍 DEBUG: merges.txt has \(lines.count) lines")

        for (index, line) in lines.enumerated() {
            if index < 5 { // Debug first few lines
                print("🔍 DEBUG: Line \(index): '\(line)'")
            }
            if line.hasPrefix("#") {
                if index < 5 { print("🔍 DEBUG: Skipping comment line \(index)") }
                continue
            }
            let parts = line.split(separator: " ")
            if parts.count == 2 {
                merges.append((String(parts[0]), String(parts[1])))
            } else if index < 10 { // Debug first few non-comment lines
                print("🔍 DEBUG: Unexpected line format at \(index): '\(line)' - parts: \(parts)")
            }
        }
        print("🔍 DEBUG: Successfully parsed \(merges.count) merges")
=======
        let mergesTxt = try TokenizerAssets.loadText("merges.txt")
        var merges: [(String,String)] = []
        for line in mergesTxt.split(separator: "\n") {
            if line.hasPrefix("#") { continue }
            let parts = line.split(separator: " ")
            if parts.count == 2 { merges.append((String(parts[0]), String(parts[1]))) }
        }
>>>>>>> a8b6634e7d680102bb44bcc5a3f496034a5a7d44

        // added_tokens.json → content->id
        var added: [String:Int] = [:]
        if let arr = try? TokenizerAssets.loadJSON("added_tokens.json", as: [AddedTokenEntry].self) {
            for e in arr { added[e.content] = e.id }
        } else if let dict = try? TokenizerAssets.loadJSON("added_tokens.json", as: [String:AddedTokenEntry].self) {
            for (_, e) in dict { added[e.content] = e.id }
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