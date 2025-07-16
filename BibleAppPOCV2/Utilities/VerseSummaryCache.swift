class VerseSummaryCache {
    static let shared = VerseSummaryCache()
    private var cache: [String: VerseSummary] = [:]

    private init() {}

    func getCachedSummary(for key: VerseKey) -> VerseSummary? {
        let id = "\(key.book)_\(key.chapter)_\(key.verse)"
        return cache[id]
    }

    func saveSummary(_ summary: VerseSummary) {
        let id = "\(summary.book)_\(summary.chapter)_\(summary.verse)"
        cache[id] = summary
    }

    func clear() {
        cache.removeAll()
    }
}
