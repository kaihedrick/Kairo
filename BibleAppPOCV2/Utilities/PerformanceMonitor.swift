// filepath: BibleAppPOCV2/Utilities/PerformanceMonitor.swift
import SwiftUI
import os.log

// MARK: - Performance Monitor

class PerformanceMonitor: ObservableObject {
    private let logger = Logger(subsystem: "BibleAppPOCV2", category: "Performance")
    
    @Published var memoryUsage: Double = 0
    @Published var frameRate: Double = 0
    
    private var startTime: CFTimeInterval = 0
    private var frameCount: Int = 0
    private var lastFrameTime: CFTimeInterval = 0
    
    init() {
        startTime = CACurrentMediaTime()
        startMonitoring()
    }
    
    private func startMonitoring() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.updateMemoryUsage()
        }
    }
    
    private func updateMemoryUsage() {
        var info = mach_task_basic_info()  // Use 'var' instead of 'let'
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
            let memoryUsageMB = Double(info.resident_size) / 1024 / 1024
            DispatchQueue.main.async {
                self.memoryUsage = memoryUsageMB
            }
        }
    }
    
    func recordFrame() {
        frameCount += 1
        let currentTime = CACurrentMediaTime()
        
        if currentTime - lastFrameTime >= 1.0 {
            let fps = Double(frameCount) / (currentTime - lastFrameTime)
            DispatchQueue.main.async {
                self.frameRate = fps
            }
            frameCount = 0
            lastFrameTime = currentTime
        }
    }
    
    func logPerformanceMetrics() {
        logger.info("Performance Metrics - Memory: \(self.memoryUsage, privacy: .public)MB, FPS: \(self.frameRate, privacy: .public)")
    }
}

// MARK: - C Interface for mach_task_basic_info
struct mach_task_basic_info {
    var virtual_size: mach_vm_size_t = 0
    var resident_size: mach_vm_size_t = 0
    var resident_size_max: mach_vm_size_t = 0
    var user_time: time_value_t = time_value_t()
    var system_time: time_value_t = time_value_t()
    var policy: policy_t = 0
    var suspend_count: integer_t = 0
}
