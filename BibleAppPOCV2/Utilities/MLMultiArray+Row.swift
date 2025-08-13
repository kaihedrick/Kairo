// filepath: BibleAppPOCV2/Extensions/MLMultiArray+Row.swift
import CoreML

@inline(__always) private func f16to32(_ h: UInt16) -> Float {
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

extension MLMultiArray {
    /// Read the last vocab row as [Float] from 2D [1,v] or 3D [1,1,v] logits (f16/f32).
    func lastVocabRow() -> [Float] {
        let shape = self.shape.map { $0.intValue }
        let v = shape.last ?? self.count
        switch dataType {
        case .float32:
            let base = dataPointer.bindMemory(to: Float.self, capacity: count)
            return Array(UnsafeBufferPointer(start: base.advanced(by: count - v), count: v))
        case .float16:
            let src = dataPointer.bindMemory(to: UInt16.self, capacity: count)
            var out = [Float](repeating: 0, count: v)
            let offset = count - v
            for i in 0..<v { out[i] = f16to32(src[offset + i]) }
            return out
        default:
            fatalError("Unsupported dtype \(dataType)")
        }
    }
}
