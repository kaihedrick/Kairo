// filepath: BibleAppPOCV2/Utilities/PerformanceMonitor.swift
import SwiftUI
import os.log

// MARK: - Performance Monitor

class PerformanceMonitor: ObservableObject {
    private let logger = Logger(subsystem: "BibleAppPOCV2", category: "Performance")
<<<<<<< HEAD

    @Published var memoryUsage: Double = 0
    @Published var frameRate: Double = 0

    private var startTime: CFTimeInterval = 0
    private var frameCount: Int = 0
    private var lastFrameTime: CFTimeInterval = 0

=======
    
    @Published var memoryUsage: Double = 0
    @Published var frameRate: Double = 0
    
    private var startTime: CFTimeInterval = 0
    private var frameCount: Int = 0
    private var lastFrameTime: CFTimeInterval = 0
    
>>>>>>> a8b6634e7d680102bb44bcc5a3f496034a5a7d44
    init() {
        startTime = CACurrentMediaTime()
        startMonitoring()
    }
<<<<<<< HEAD

=======
    
>>>>>>> a8b6634e7d680102bb44bcc5a3f496034a5a7d44
    private func startMonitoring() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.updateMemoryUsage()
        }
    }
<<<<<<< HEAD

    private func updateMemoryUsage() {
        var info = mach_task_basic_info()  // Use 'var' instead of 'let'
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4

=======
    
    private func updateMemoryUsage() {
        var info = mach_task_basic_info()  // Use 'var' instead of 'let'
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
>>>>>>> a8b6634e7d680102bb44bcc5a3f496034a5a7d44
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
<<<<<<< HEAD

=======
        
>>>>>>> a8b6634e7d680102bb44bcc5a3f496034a5a7d44
        if kerr == KERN_SUCCESS {
            let memoryUsageMB = Double(info.resident_size) / 1024 / 1024
            DispatchQueue.main.async {
                self.memoryUsage = memoryUsageMB
            }
        }
    }
<<<<<<< HEAD

    func recordFrame() {
        frameCount += 1
        let currentTime = CACurrentMediaTime()

=======
    
    func recordFrame() {
        frameCount += 1
        let currentTime = CACurrentMediaTime()
        
>>>>>>> a8b6634e7d680102bb44bcc5a3f496034a5a7d44
        if currentTime - lastFrameTime >= 1.0 {
            let fps = Double(frameCount) / (currentTime - lastFrameTime)
            DispatchQueue.main.async {
                self.frameRate = fps
            }
            frameCount = 0
            lastFrameTime = currentTime
        }
    }
<<<<<<< HEAD

=======
    
>>>>>>> a8b6634e7d680102bb44bcc5a3f496034a5a7d44
    func logPerformanceMetrics() {
        logger.info("Performance Metrics - Memory: \(self.memoryUsage, privacy: .public)MB, FPS: \(self.frameRate, privacy: .public)")
    }
}

<<<<<<< HEAD
// MARK: - Performance Timer for Data Loading Tests

class PerformanceTestTimer: ObservableObject {
    private let logger = Logger(subsystem: "BibleAppPOCV2", category: "PerformanceTestTimer")
    private var timers: [String: CFTimeInterval] = [:]
    private var measurements: [String: [Double]] = [:]

    // MARK: - Stopwatch Timer Methods

    func startTimer(_ name: String) {
        timers[name] = CACurrentMediaTime()
        logger.debug("⏱️ Started timer: \(name)")
    }

    func stopTimer(_ name: String) -> Double? {
        guard let startTime = timers[name] else {
            logger.warning("⚠️ Timer '\(name)' was never started")
            return nil
        }

        let elapsed = CACurrentMediaTime() - startTime
        timers.removeValue(forKey: name)

        // Store measurement for statistics
        if measurements[name] == nil {
            measurements[name] = []
        }
        measurements[name]?.append(elapsed)

        logger.info("⏱️ Timer '\(name)' completed in \(String(format: "%.4f", elapsed * 1000))ms")
        return elapsed
    }

    func measureTime(_ name: String, operation: () async throws -> Void) async throws {
        startTimer(name)
        do {
            try await operation()
            _ = stopTimer(name)
        } catch {
            _ = stopTimer(name)
            throw error
        }
    }

    func measureTime(_ name: String, operation: () throws -> Void) throws {
        startTimer(name)
        do {
            try operation()
            _ = stopTimer(name)
        } catch {
            _ = stopTimer(name)
            throw error
        }
    }

    // MARK: - LRU Cache Performance Testing

    struct CachePerformanceMetrics {
        let operation: String
        let cacheHit: Bool
        let loadTime: Double
        let memoryUsage: Double
        let cacheSize: Int
        let timestamp: Date

        var description: String {
            let hitMiss = cacheHit ? "CACHE HIT" : "CACHE MISS"
            return "📊 \(operation): \(hitMiss) - \(String(format: "%.4f", loadTime * 1000))ms - \(String(format: "%.1f", memoryUsage))MB - Cache Size: \(cacheSize)"
        }
    }

    private var cacheMetrics: [CachePerformanceMetrics] = []

    func recordCachePerformance(operation: String, cacheHit: Bool, loadTime: Double, memoryUsage: Double, cacheSize: Int) {
        let metric = CachePerformanceMetrics(
            operation: operation,
            cacheHit: cacheHit,
            loadTime: loadTime,
            memoryUsage: memoryUsage,
            cacheSize: cacheSize,
            timestamp: Date()
        )

        cacheMetrics.append(metric)
        logger.info("\(metric.description)")
    }

    // MARK: - Chapter Loading Performance Tests

    func testChapterLoadingPerformance(book: String, chapters: [Int], dataLoader: OptimizedBibleDataLoader) async {
        logger.info("🧪 Starting Chapter Loading Performance Test for \(book)")

        var totalLoadTime: Double = 0
        var cacheHits = 0
        var cacheMisses = 0

        for chapter in chapters {
            let operationName = "Load_\(book)_\(chapter)"

            do {
                let startTime = CACurrentMediaTime()
                let result = await dataLoader.loadChapterContent(book: book, chapter: chapter)
                let loadTime = CACurrentMediaTime() - startTime

                totalLoadTime += loadTime

                if result != nil {
                    // Check if it was a cache hit by attempting to load again immediately
                    let secondStartTime = CACurrentMediaTime()
                    _ = await dataLoader.loadChapterContent(book: book, chapter: chapter)
                    let secondLoadTime = CACurrentMediaTime() - secondStartTime

                    let wasCacheHit = secondLoadTime < (loadTime * 0.1) // 10x faster indicates cache hit
                    if wasCacheHit { cacheHits += 1 } else { cacheMisses += 1 }

                    // Get current memory usage
                    let memoryUsage = getCurrentMemoryUsage()

                    recordCachePerformance(
                        operation: operationName,
                        cacheHit: wasCacheHit,
                        loadTime: loadTime,
                        memoryUsage: memoryUsage,
                        cacheSize: await getCacheStats(from: dataLoader).size
                    )
                } else {
                    logger.warning("❌ Failed to load \(book) \(chapter)")
                }
            }
        }

        let avgLoadTime = totalLoadTime / Double(chapters.count)
        logger.info("📈 Chapter Loading Test Results:")
        logger.info("   - Total Chapters: \(chapters.count)")
        logger.info("   - Cache Hits: \(cacheHits)")
        logger.info("   - Cache Misses: \(cacheMisses)")
        logger.info("   - Average Load Time: \(String(format: "%.4f", avgLoadTime * 1000))ms")
        logger.info("   - Hit Rate: \(String(format: "%.1f", Double(cacheHits) / Double(chapters.count) * 100))%")
    }

    // MARK: - On-Screen Reader Performance Tests

    func testOnScreenReaderPerformance(book: String, chapter: Int, dataLoader: OptimizedBibleDataLoader) async {
        logger.info("📖 Testing On-Screen Reader Performance for \(book) \(chapter)")

        startTimer("Reader_Load_Chapter")

        // Simulate loading chapter for on-screen display
        if let chapterContent = await dataLoader.loadChapterContent(book: book, chapter: chapter) {
            let loadTime = stopTimer("Reader_Load_Chapter") ?? 0

            // Simulate rendering time (text measurement, layout)
            startTimer("Reader_Render_Verses")
            let verseCount = chapterContent.verses.count
            // Simulate text processing for each verse
            for verse in chapterContent.verses.prefix(min(10, verseCount)) { // Test first 10 verses
                _ = verse.text.count // Simulate text measurement
            }
            let renderTime = stopTimer("Reader_Render_Verses") ?? 0

            let totalTime = loadTime + renderTime
            let memoryUsage = getCurrentMemoryUsage()

            logger.info("📖 Reader Performance Results:")
            logger.info("   - Chapter Load Time: \(String(format: "%.4f", loadTime * 1000))ms")
            logger.info("   - Render Time (10 verses): \(String(format: "%.4f", renderTime * 1000))ms")
            logger.info("   - Total Time: \(String(format: "%.4f", totalTime * 1000))ms")
            logger.info("   - Memory Usage: \(String(format: "%.1f", memoryUsage))MB")
            logger.info("   - Verses Loaded: \(verseCount)")
        } else {
            _ = stopTimer("Reader_Load_Chapter")
            logger.warning("❌ Failed to load chapter for reader test")
        }
    }

    // MARK: - Statistics and Reporting

    func getTimerStatistics(_ name: String) -> (count: Int, average: Double, min: Double, max: Double)? {
        guard let times = measurements[name], !times.isEmpty else { return nil }

        let count = times.count
        let average = times.reduce(0, +) / Double(count)
        let min = times.min() ?? 0
        let max = times.max() ?? 0

        return (count, average, min, max)
    }

    func getAllTimerStatistics() -> [String: (count: Int, average: Double, min: Double, max: Double)] {
        var stats: [String: (count: Int, average: Double, min: Double, max: Double)] = [:]

        for (name, _) in measurements {
            if let stat = getTimerStatistics(name) {
                stats[name] = stat
            }
        }

        return stats
    }

    func getCachePerformanceHistory() -> [CachePerformanceMetrics] {
        return cacheMetrics
    }

    func generatePerformanceReport() -> String {
        var report = "📊 Performance Test Report\n"
        report += "==========================\n\n"

        // Timer Statistics
        report += "⏱️ Timer Statistics:\n"
        for (name, stats) in getAllTimerStatistics() {
            report += "   \(name):\n"
            report += "     Count: \(stats.count)\n"
            report += "     Average: \(String(format: "%.4f", stats.average * 1000))ms\n"
            report += "     Min: \(String(format: "%.4f", stats.min * 1000))ms\n"
            report += "     Max: \(String(format: "%.4f", stats.max * 1000))ms\n\n"
        }

        // Cache Performance
        if !cacheMetrics.isEmpty {
            report += "💾 Cache Performance:\n"
            let cacheHits = cacheMetrics.filter { $0.cacheHit }.count
            let cacheMisses = cacheMetrics.filter { !$0.cacheHit }.count
            let hitRate = Double(cacheHits) / Double(cacheHits + cacheMisses) * 100

            report += "   Total Operations: \(cacheMetrics.count)\n"
            report += "   Cache Hits: \(cacheHits)\n"
            report += "   Cache Misses: \(cacheMisses)\n"
            report += "   Hit Rate: \(String(format: "%.1f", hitRate))%\n\n"

            // Average load times
            let hitTimes = cacheMetrics.filter { $0.cacheHit }.map { $0.loadTime }
            let missTimes = cacheMetrics.filter { !$0.cacheHit }.map { $0.loadTime }

            if !hitTimes.isEmpty {
                let avgHitTime = hitTimes.reduce(0, +) / Double(hitTimes.count)
                report += "   Average Cache Hit Time: \(String(format: "%.4f", avgHitTime * 1000))ms\n"
            }

            if !missTimes.isEmpty {
                let avgMissTime = missTimes.reduce(0, +) / Double(missTimes.count)
                report += "   Average Cache Miss Time: \(String(format: "%.4f", avgMissTime * 1000))ms\n"
            }
        }

        return report
    }

    func clearMeasurements() {
        measurements.removeAll()
        cacheMetrics.removeAll()
        timers.removeAll()
        logger.info("🧹 Cleared all performance measurements")
    }

    // MARK: - Helper Methods

    private func getCurrentMemoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }

        if kerr == KERN_SUCCESS {
            return Double(info.resident_size) / 1024 / 1024
        }

        return 0
    }

    private func getCacheStats(from dataLoader: OptimizedBibleDataLoader) async -> (size: Int, capacity: Int) {
        let stats = await dataLoader.getCacheStats()
        return (size: stats.size, capacity: 20) // capacity not exposed, using default
    }
}

=======
>>>>>>> a8b6634e7d680102bb44bcc5a3f496034a5a7d44
// MARK: - C Interface for mach_task_basic_info
struct mach_task_basic_info {
    var virtual_size: mach_vm_size_t = 0
    var resident_size: mach_vm_size_t = 0
    var resident_size_max: mach_vm_size_t = 0
    var user_time: time_value_t = time_value_t()
    var system_time: time_value_t = time_value_t()
    var policy: policy_t = 0
    var suspend_count: integer_t = 0
<<<<<<< HEAD
}
=======
}
>>>>>>> a8b6634e7d680102bb44bcc5a3f496034a5a7d44
