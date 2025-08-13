import CoreML

struct KVSpec {
    let nLayer: Int
    let nHead: Int
    let headDim: Int
}

struct KVCaches {
    var k: [MLMultiArray]
    var v: [MLMultiArray]
}

enum KVCacheError: Error { case allocate }

func makeZeroCache(spec: KVSpec) throws -> KVCaches {
    // Shape: [1, nHead, 0, headDim]  (0-length time axis; allowed by MLProgram)
    func z(_ s: [Int]) throws -> MLMultiArray {
        // Note: if your device/OS rejects 0-length allocations,
        // change `0` → `1` and also pass an empty attention mask for the first call.
        return try MLMultiArray(shape: s.map(NSNumber.init), dataType: .float16)
    }
    var ks: [MLMultiArray] = []
    var vs: [MLMultiArray] = []
    for _ in 0..<spec.nLayer {
        ks.append(try z([1, spec.nHead, 0, spec.headDim]))
        vs.append(try z([1, spec.nHead, 0, spec.headDim]))
    }
    return KVCaches(k: ks, v: vs)
}
