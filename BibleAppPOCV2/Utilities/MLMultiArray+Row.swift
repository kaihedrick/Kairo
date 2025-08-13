// Utilities/MLMultiArray+Row.swift
import CoreML

extension MLMultiArray {
    /// Return logits[t, 0..vocab) as Float; supports [vocab], [1, vocab], [1, seq, vocab].
    /// NOTE: The returned buffer is valid only until the next model call. If you need to keep it,
    /// copy it into your own [Float].
    func rowAsFloat(atTime t: Int, vocab: Int) -> UnsafeBufferPointer<Float> {
        let shape = self.shape.map { $0.intValue }
        let rank = shape.count
        let seq  = (rank == 3 ? shape[1] : 1)
        let tt   = max(0, min(t, seq - 1))
        let baseOffset = (rank == 3 ? tt : 0) * vocab

        switch dataType {
        case .float32:
            let base = dataPointer.bindMemory(to: Float.self, capacity: count)
            return UnsafeBufferPointer(start: base.advanced(by: baseOffset), count: vocab)

        case .float16:
            // Convert just this row to f32 into a scratch buffer
            let src = dataPointer.bindMemory(to: UInt16.self, capacity: count)
            let scratch = UnsafeMutablePointer<Float>.allocate(capacity: vocab)
            // Minimal half->float conversion
            @inline(__always) func f16to32(_ h: UInt16) -> Float {
                let s = (h & 0x8000) != 0
                let e = Int((h & 0x7C00) >> 10)
                var f = Int(h & 0x03FF)
                let val: Float
                if e == 0 {
                    if f == 0 { val = 0 }
                    else {
                        var exp = -14
                        while (f & 0x400) == 0 { f <<= 1; exp -= 1 }
                        f &= 0x3FF
                        val = ldexpf(Float(f) / 1024 + 1, Int32(exp))
                    }
                } else if e == 31 { val = .infinity }
                else { val = ldexpf(Float(f) / 1024 + 1, Int32(e - 15)) }
                return s ? -val : val
            }
            for i in 0..<vocab { scratch[i] = f16to32(src[baseOffset + i]) }
            return UnsafeBufferPointer(start: scratch, count: vocab)

        default:
            fatalError("Unsupported MLMultiArray dtype \(dataType)")
        }
    }
}
