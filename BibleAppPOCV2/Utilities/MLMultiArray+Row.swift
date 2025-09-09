// filepath: BibleAppPOCV2/Utilities/MLMultiArray+Row.swift
import CoreML

public extension MLMultiArray {
    /// Extract logits row assuming shape [1, vocab] (legacy)
    func lastVocabRow() -> [Float] {
        let n = count
        var out = [Float](repeating: 0, count: n)
        dataPointer.bindMemory(to: Float.self, capacity: n)
            .withMemoryRebound(to: Float.self, capacity: n) { src in
                for i in 0..<n { out[i] = src[i] }
            }
        return out
    }

    /// Extract logits row for a given position in shape [1, seq_len, vocab_size]
    /// Automatically derives vocab size from tensor shape.
    func logitsRow(at position: Int) -> [Float] {
        guard shape.count == 3, shape[0].intValue == 1 else {
            print("❌ Invalid logits shape for 3D extraction: \(shape)")
            return []
        }

        let seqLen = shape[1].intValue
        let vocabSize = shape[2].intValue
        guard position >= 0 && position < seqLen else {
            print("❌ Invalid position \(position) for seq_len \(seqLen)")
            return []
        }

        var out = [Float](repeating: 0, count: vocabSize)
        let offset = position * vocabSize
        dataPointer.bindMemory(to: Float.self, capacity: count)
            .withMemoryRebound(to: Float.self, capacity: count) { src in
                for i in 0..<vocabSize {
                    out[i] = src[offset + i]
                }
            }
        return out
    }

    /// Extract the last position’s logits row
    func lastPositionLogitsRow() -> [Float] {
        guard shape.count == 3, shape[0].intValue == 1 else {
            print("❌ Invalid shape for 3D logits extraction: \(shape)")
            return []
        }
        let seqLen = shape[1].intValue
        return logitsRow(at: seqLen - 1)
    }
}
