// MLMultiArray+Row.swift
import CoreML

public extension MLMultiArray {
    // assuming shape [1, vocab]
    func lastVocabRow() -> [Float] {
        let n = count
        var out = [Float](repeating: 0, count: n)
        dataPointer.bindMemory(to: Float.self, capacity: n).withMemoryRebound(to: Float.self, capacity: n) { src in
            for i in 0..<n { out[i] = src[i] }
        }
        return out
    }
}