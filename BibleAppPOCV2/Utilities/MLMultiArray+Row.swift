// filepath: BibleAppPOCV2/Utilities/MLMultiArray+Row.swift

// 🚫 AI/ML functionality is completely disabled
#if AI_FEATURES

import CoreML

// MARK: - MLMultiArray Extensions for Logits Processing

public extension MLMultiArray {

    // MARK: Legacy Methods

    /// Extract logits row assuming shape [1, vocab] (legacy method)
    func lastVocabRow() -> [Float] {
        let n = count
        var out = [Float](repeating: 0, count: n)

        dataPointer.bindMemory(to: Float.self, capacity: n)
            .withMemoryRebound(to: Float.self, capacity: n) { src in
                for i in 0..<n { out[i] = src[i] }
            }

        return out
    }

    // MARK: Modern Logits Extraction

    /// Extract logits row for a given position in shape [1, seq_len, vocab_size] or [seq_len, vocab_size]
    /// Automatically derives vocab size from tensor shape and handles both 2D and 3D tensors.
    ///
    /// - Parameter position: The sequence position to extract logits for
    /// - Returns: Array of logits for the specified position, or empty array on error
    func logitsRow(at position: Int) -> [Float] {
        // Handle both [1, seq_len, vocab_size] (3D) and [seq_len, vocab_size] (2D) shapes
        let (seqLen, vocabSize): (Int, Int)
        let offset: Int

        if shape.count == 3 && shape[0].intValue == 1 {
            // 3D shape: [1, seq_len, vocab_size] (batched input)
            seqLen = shape[1].intValue
            vocabSize = shape[2].intValue
            offset = position * vocabSize
        } else if shape.count == 2 {
            // 2D shape: [seq_len, vocab_size] (single sequence)
            seqLen = shape[0].intValue
            vocabSize = shape[1].intValue
            offset = position * vocabSize
        } else {
            #if DEBUG
            print("❌ Invalid logits shape: \(shape) - expected [1, seq_len, vocab_size] or [seq_len, vocab_size]")
            #endif
            return []
        }

        guard position >= 0 && position < seqLen else {
            #if DEBUG
            print("❌ Invalid position \(position) for seq_len \(seqLen)")
            #endif
            return []
        }

        var out = [Float](repeating: 0, count: vocabSize)

        dataPointer.bindMemory(to: Float.self, capacity: count)
            .withMemoryRebound(to: Float.self, capacity: count) { src in
                for i in 0..<vocabSize {
                    out[i] = src[offset + i]
                }
            }

        return out
    }

    /// Extract the last position's logits row (handles both 2D and 3D shapes)
    ///
    /// - Returns: Array of logits for the last position in the sequence
    func lastPositionLogitsRow() -> [Float] {
        let seqLen: Int

        if shape.count == 3 && shape[0].intValue == 1 {
            // 3D shape: [1, seq_len, vocab_size]
            seqLen = shape[1].intValue
        } else if shape.count == 2 {
            // 2D shape: [seq_len, vocab_size]
            seqLen = shape[0].intValue
        } else {
            #if DEBUG
            print("❌ Invalid shape for logits extraction: \(shape)")
            #endif
            return []
        }

        return logitsRow(at: seqLen - 1)
    }
}

#endif // AI_FEATURES
