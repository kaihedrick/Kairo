#if DEBUG
import Foundation

// Constants needed by debug functions
private let EOS_TOKEN_ID: Int32 = 50256

extension BibleCommentaryGenerator {
    func probeSpecials(ref: String, text: String) async {
        guard isReady, model != nil, tokenizer != nil else {
            print("❌ B) Specials probe failed: Generator not ready")
            print("  - isReady: \(isReady)")
            print("  - model loaded: \(model != nil)")
            print("  - tokenizer loaded: \(tokenizer != nil)")
            return
        }

        do {
            // Use the buffered generation method for real testing
            let result = try await generateSinglePassBuffered(ref: ref, verseText: text)
            print("=== B) Specials Probe Results ===")
            print("Generated text:", result.prefix(200))
            print("Contains [END_COMMENTARY]:", result.contains("[END_COMMENTARY]"))
            print("Contains [START_DEVOTIONAL]:", result.contains("[START_DEVOTIONAL]"))
            print("Contains [END_DEVOTIONAL]:", result.contains("[END_DEVOTIONAL]"))
        } catch {
            print("❌ B) Specials probe failed:", error.localizedDescription)
        }
    }

    func probeSectioning(ref: String, text: String) async {
        guard isReady, model != nil, tokenizer != nil else {
            print("❌ D/E) Sectioning probe failed: Generator not ready")
            print("  - isReady: \(isReady)")
            print("  - model loaded: \(model != nil)")
            print("  - tokenizer loaded: \(tokenizer != nil)")
            return
        }

        do {
            // Use the buffered generation method for real testing
            let result = try await generateSinglePassBuffered(ref: ref, verseText: text)
            print("=== D/E) Sectioning Probe Results ===")
            print("Generated text:", result.prefix(300))

            // Check marker order
            let p1 = result.range(of: "[END_COMMENTARY]")?.lowerBound
            let p2 = result.range(of: "[START_DEVOTIONAL]")?.lowerBound
            let p3 = result.range(of: "[END_DEVOTIONAL]")?.lowerBound

            let orderOk = (p1 != nil && p2 != nil && p3 != nil && p1! < p2! && p2! < p3!)
            print("D) Markers order OK:", orderOk)

            if let p1 = p1, let p2 = p2, let p3 = p3 {
                print("  [END_COMMENTARY] at position:", result.distance(from: result.startIndex, to: p1))
                print("  [START_DEVOTIONAL] at position:", result.distance(from: result.startIndex, to: p2))
                print("  [END_DEVOTIONAL] at position:", result.distance(from: result.startIndex, to: p3))
            }

        } catch {
            print("❌ D/E) Sectioning probe failed:", error.localizedDescription)
        }
    }
}
#endif