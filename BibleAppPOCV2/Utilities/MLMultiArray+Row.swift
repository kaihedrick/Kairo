// MLMultiArray+Row.swift
import CoreML

public extension MLMultiArray {
    // assuming shape [1, vocab] - for backward compatibility
    func lastVocabRow() -> [Float] {
        let n = count
        var out = [Float](repeating: 0, count: n)
        dataPointer.bindMemory(to: Float.self, capacity: n).withMemoryRebound(to: Float.self, capacity: n) { src in
            for i in 0..<n { out[i] = src[i] }
        }
        return out
    }

    // NEW: Extract logits row for position i from shape [1, seq_len, vocab_size]
    // Self-describing version that derives vocab size from actual tensor shape[2]
    func logitsRow(at position: Int) -> [Float] {
        guard shape.count == 3,
              shape[0].intValue == 1 else {
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
        dataPointer.bindMemory(to: Float.self, capacity: count).withMemoryRebound(to: Float.self, capacity: count) { src in
            for i in 0..<vocabSize {
                out[i] = src[offset + i]
            }
        }
        return out
    }

    // NEW: Extract logits row for position i from shape [1, seq_len, vocab_size]
    // Legacy version with external vocabSize parameter (for backward compatibility)
    func logitsRow(at position: Int, vocabSize: Int = 50399) -> [Float] {
        guard shape.count == 3,
              shape[0].intValue == 1,
              shape[2].intValue == vocabSize else {
            print("❌ Invalid logits shape for 3D extraction: \(shape) (expected vocabSize: \(vocabSize))")
            return []
        }

        let seqLen = shape[1].intValue
        guard position >= 0 && position < seqLen else {
            print("❌ Invalid position \(position) for seq_len \(seqLen)")
            return []
        }

        var out = [Float](repeating: 0, count: vocabSize)
        let offset = position * vocabSize
        dataPointer.bindMemory(to: Float.self, capacity: count).withMemoryRebound(to: Float.self, capacity: count) { src in
            for i in 0..<vocabSize {
                out[i] = src[offset + i]
            }
        }
        return out
    }

    // NEW: Extract the last position's logits row from [1, seq_len, vocab_size]
    func lastPositionLogitsRow(vocabSize: Int = 50399) -> [Float] {
        guard shape.count == 3,
              shape[0].intValue == 1,
              shape[2].intValue == vocabSize else {
            print("❌ Invalid shape for 3D logits extraction: \(shape)")
            return []
        }

        let seqLen = shape[1].intValue
        return logitsRow(at: seqLen - 1, vocabSize: vocabSize)
    }
}