import Foundation

/// GPT-2 byte encoder mapping (bytes_to_unicode). Use for byte-level BPE encoding.
struct GPT2ByteEncoder {
    static func make() -> [UInt8: String] {
        var bs: [UInt8] = Array(33...126) + Array(161...172) + Array(174...255)
        var cs = bs.map { UnicodeScalar(Int($0))! }

        var n: Int = 0
        for b in 0...255 where !bs.contains(UInt8(b)) {
            bs.append(UInt8(b))
            cs.append(UnicodeScalar(256 + n)!)
            n += 1
        }

        var map: [UInt8: String] = [:]
        for (b, c) in zip(bs, cs) {
            map[b] = String(Character(c))
        }
        return map
    }
}


