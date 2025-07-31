import Foundation
import OSLog
import os.signpost

#if canImport(MetricKit)
import MetricKit
#endif

/// Instruments profiler for comprehensive performance analysis
/// Integrates with Time Profiler, Audio, and custom signposts for detailed optimization insights
@available(iOS 14.0, *)
class InstrumentsProfiler: ObservableObject {
    
    // MARK: - Profiling Categories
    enum ProfilingCategory {
        case audioProcessing    // Real-time audio thread profiling
        case memoryAllocation  // Memory allocation and deallocation tracking
        case cpuIntensive      // CPU-intensive operations (NEON, vDSP)
        case backgroundTasks   // Background processing profiling
        case userInterface     // UI responsiveness tracking
        case fileIO           // File operations (recording, batch processing)
    }
    
    enum AudioMetric {
        case renderTime        // Audio render callback duration
        case bufferUnderrun    // Audio buffer underruns/dropouts
        case cpuLoad          // CPU load during audio processing
        case memoryPressure   // Memory pressure events
        case thermalThrottling // Thermal throttling events
    }
    
    // MARK: - Published Properties
    @Published var isProfilingEnabled = false
    @Published var currentProfilingSession: String = ""
    @Published var collectedMetrics: [String: Any] = [:]
    @Published var performanceWarnings: [String] = []
    
    // MARK: - Private Properties
    private let audioLogger = Logger(subsystem: "com.reverb.audio", category: "performance")
    private let memoryLogger = Logger(subsystem: "com.reverb.memory", category: "allocation")
    private let cpuLogger = Logger(subsystem: "com.reverb.cpu", category: "optimization")
    private let backgroundLogger = Logger(subsystem: "com.reverb.background", category: "tasks")
    
    // OS Signpost loggers for Instruments integration
    private let audioSignpostLog = OSLog(subsystem: "com.reverb.audio", category: "signposts")
    private let memorySignpostLog = OSLog(subsystem: "com.reverb.memory", category: "signposts")
    private let cpuSignpostLog = OSLog(subsystem: "com.reverb.cpu", category: "signposts")
    
    // Performance counters
    private var audioRenderTimes: [TimeInterval] = []
    private var memoryAllocations: [MemoryAllocation] = []
    private var cpuLoadSamples: [Double] = []
    private var thermalEvents: [ThermalEvent] = []
    
    // Signpost IDs for tracking operations
    private var nextSignpostID: OSSignpostID = OSSignpostID(log: OSLog.disabled)
    private var activeSignposts: [String: OSSignpostID] = [:]
    
    // MetricKit integration
    #if canImport(MetricKit)
    private var metricSubscriber: MXMetricManagerSubscriber?
    #endif
    
    // Timing infrastructure
    private var highResolutionTimer: DispatchSourceTimer?
    private let profilingQueue = DispatchQueue(label: "com.reverb.profiling", qos: .utility)
    
    // MARK: - Data Structures
    struct MemoryAllocation {
        let timestamp: Date
        let size: Int
        let category: String
        let stackTrace: [String]?
    }
    
    struct AudioPerformanceMetric {
        let timestamp: Date
        let renderDuration: TimeInterval
        let bufferSize: Int
        let sampleRate: Double
        let cpuLoad: Double
        let didDropout: Bool
    }
    
    struct ThermalEvent {
        let timestamp: Date
        let thermalState: ProcessInfo.ThermalState
        let cpuLoadAtEvent: Double
    }
    
    // MARK: - Initialization
    override init() {
        super.init()
        setupMetricKitSubscriber()
        setupPerformanceMonitoring()
    }
    
    deinit {
        stopProfiling()
        #if canImport(MetricKit)
        if let subscriber = metricSubscriber {
            MXMetricManager.shared.remove(subscriber)
        }
        #endif
    }
    
    // MARK: - Profiling Control
    func startProfiling(sessionName: String = "Default Session") {
        currentProfilingSession = sessionName
        isProfilingEnabled = true
        
        // Clear previous metrics
        audioRenderTimes.removeAll()
        memoryAllocations.removeAll()
        cpuLoadSamples.removeAll()
        thermalEvents.removeAll()
        performanceWarnings.removeAll()
        
        // Start high-resolution monitoring
        startHighResolutionMonitoring()
        
        audioLogger.info("🎯 Profiling session started: \(sessionName)")
        
        // Create session start signpost
        let signpostID = OSSignpostID(log: audioSignpostLog)
        os_signpost(.begin, log: audioSignpostLog, name: "Profiling Session", signpostID: signpostID, "Session: %{public}s", sessionName)
    }
    
    func stopProfiling() {
        guard isProfilingEnabled else { return }
        
        isProfilingEnabled = false
        stopHighResolutionMonitoring()
        
        // Generate final performance report
        generatePerformanceReport()
        
        audioLogger.info("⏹️ Profiling session stopped: \(currentProfilingSession)")
        
        // End session signpost
        if let signpostID = activeSignposts["session"] {
            os_signpost(.end, log: audioSignpostLog, name: "Profiling Session", signpostID: signpostID)
            activeSignposts.removeValue(forKey: "session")
        }
    }
    
    // MARK: - Audio Performance Profiling
    func beginAudioRenderProfiling(bufferSize: Int, sampleRate: Double) -> String {
        guard isProfilingEnabled else { return "" }
        
        let profilingID = UUID().uuidString
        let signpostID = OSSignpostID(log: audioSignpostLog)
        activeSignposts[profilingID] = signpostID
        
        os_signpost(.begin, log: audioSignpostLog, name: "Audio Render", signpostID: signpostID,
                   "Buffer: %d frames, Sample Rate: %.0f Hz", bufferSize, sampleRate)
        
        return profilingID
    }
    
    func endAudioRenderProfiling(profilingID: String, renderDuration: TimeInterval, 
                                cpuLoad: Double, didDropout: Bool) {
        guard isProfilingEnabled, !profilingID.isEmpty else { return }
        
        // Record metric
        let metric = AudioPerformanceMetric(
            timestamp: Date(),
            renderDuration: renderDuration,
            bufferSize: 0, // Would be provided in real implementation
            sampleRate: 0, // Would be provided in real implementation  
            cpuLoad: cpuLoad,
            didDropout: didDropout
        )
        
        profilingQueue.async {
            self.audioRenderTimes.append(renderDuration)
            self.cpuLoadSamples.append(cpuLoad)
            
            // Check for performance issues
            if didDropout {
                DispatchQueue.main.async {
                    self.performanceWarnings.append("Audio dropout detected at \(Date())")
                }
            }
            
            if cpuLoad > 80.0 {
                DispatchQueue.main.async {
                    self.performanceWarnings.append("High CPU load: \(String(format: "%.1f", cpuLoad))% at \(Date())")
                }
            }
        }
        
        // End signpost
        if let signpostID = activeSignposts[profilingID] {
            os_signpost(.end, log: audioSignpostLog, name: "Audio Render", signpostID: signpostID,
                       "Duration: %.3f ms, CPU: %.1f%%, Dropout: %{BOOL}d", 
                       renderDuration * 1000, cpuLoad, didDropout)
            activeSignposts.removeValue(forKey: profilingID)
        }
        
        audioLogger.debug("🎵 Audio render: \(String(format: "%.3f", renderDuration * 1000))ms, CPU: \(String(format: "%.1f", cpuLoad))%")
    }
    
    // MARK: - Memory Profiling
    func trackMemoryAllocation(size: Int, category: String, 
                              includeStackTrace: Bool = false) {
        guard isProfilingEnabled else { return }
        
        let allocation = MemoryAllocation(
            timestamp: Date(),
            size: size,
            category: category,
            stackTrace: includeStackTrace ? getStackTrace() : nil
        )
        
        profilingQueue.async {
            self.memoryAllocations.append(allocation)
        }
        
        memoryLogger.debug("📦 Memory allocation: \(size) bytes for \(category)")
        
        // Create memory allocation signpost
        let signpostID = OSSignpostID(log: memorySignpostLog)
        os_signpost(.event, log: memorySignpostLog, name: "Memory Allocation", signpostID: signpostID,
                   "Size: %d bytes, Category: %{public}s", size, category)
    }
    
    func beginMemoryOperation(operationName: String) -> String {
        guard isProfilingEnabled else { return "" }
        
        let operationID = UUID().uuidString
        let signpostID = OSSignpostID(log: memorySignpostLog)
        activeSignposts[operationID] = signpostID
        
        os_signpost(.begin, log: memorySignpostLog, name: "Memory Operation", signpostID: signpostID,
                   "Operation: %{public}s", operationName)
        
        return operationID
    }
    
    func endMemoryOperation(operationID: String, totalAllocated: Int, totalFreed: Int) {
        guard isProfilingEnabled, !operationID.isEmpty else { return }
        
        if let signpostID = activeSignposts[operationID] {
            os_signpost(.end, log: memorySignpostLog, name: "Memory Operation", signpostID: signpostID,
                       "Allocated: %d bytes, Freed: %d bytes, Net: %d bytes", 
                       totalAllocated, totalFreed, totalAllocated - totalFreed)
            activeSignposts.removeValue(forKey: operationID)
        }
        
        memoryLogger.info("🔄 Memory operation completed: +\(totalAllocated) -\(totalFreed) = \(totalAllocated - totalFreed) bytes")
    }
    
    // MARK: - CPU Optimization Profiling
    func beginCPUIntensiveOperation(operationName: String, expectedDuration: TimeInterval? = nil) -> String {
        guard isProfilingEnabled else { return "" }
        
        let operationID = UUID().uuidString
        let signpostID = OSSignpostID(log: cpuSignpostLog)
        activeSignposts[operationID] = signpostID
        
        if let duration = expectedDuration {
            os_signpost(.begin, log: cpuSignpostLog, name: "CPU Operation", signpostID: signpostID,
                       "Operation: %{public}s, Expected: %.3f ms", operationName, duration * 1000)
        } else {
            os_signpost(.begin, log: cpuSignpostLog, name: "CPU Operation", signpostID: signpostID,
                       "Operation: %{public}s", operationName)
        }
        
        return operationID
    }
    
    func endCPUIntensiveOperation(operationID: String, actualDuration: TimeInterval, 
                                 samplesProcessed: Int, optimizationUsed: String) {
        guard isProfilingEnabled, !operationID.isEmpty else { return }
        
        if let signpostID = activeSignposts[operationID] {
            let samplesPerSecond = Double(samplesProcessed) / actualDuration
            os_signpost(.end, log: cpuSignpostLog, name: "CPU Operation", signpostID: signpostID,
                       "Duration: %.3f ms, Samples: %d, Rate: %.0f samples/sec, Optimization: %{public}s",
                       actualDuration * 1000, samplesProcessed, samplesPerSecond, optimizationUsed)
            activeSignposts.removeValue(forKey: operationID)
        }
        
        cpuLogger.info("⚡ CPU operation: \(String(format: "%.3f", actualDuration * 1000))ms, \(samplesProcessed) samples, \(optimizationUsed)")
    }
    
    // MARK: - Background Task Profiling
    func beginBackgroundTask(taskName: String, estimatedDuration: TimeInterval? = nil) -> String {
        guard isProfilingEnabled else { return "" }
        
        let taskID = UUID().uuidString
        let signpostID = OSSignpostID(log: audioSignpostLog) // Using audio log for background tasks
        activeSignposts[taskID] = signpostID
        
        if let duration = estimatedDuration {
            os_signpost(.begin, log: audioSignpostLog, name: "Background Task", signpostID: signpostID,
                       "Task: %{public}s, Estimated: %.1f sec", taskName, duration)
        } else {
            os_signpost(.begin, log: audioSignpostLog, name: "Background Task", signpostID: signpostID,
                       "Task: %{public}s", taskName)
        }
        
        backgroundLogger.info("🔄 Background task started: \(taskName)")
        return taskID
    }
    
    func endBackgroundTask(taskID: String, actualDuration: TimeInterval, 
                          itemsProcessed: Int, success: Bool) {
        guard isProfilingEnabled, !taskID.isEmpty else { return }
        
        if let signpostID = activeSignposts[taskID] {
            os_signpost(.end, log: audioSignpostLog, name: "Background Task", signpostID: signpostID,
                       "Duration: %.1f sec, Items: %d, Success: %{BOOL}d",
                       actualDuration, itemsProcessed, success)
            activeSignposts.removeValue(forKey: taskID)
        }
        
        let status = success ? "✅" : "❌"
        backgroundLogger.info("\(status) Background task completed: \(String(format: "%.1f", actualDuration))s, \(itemsProcessed) items")
    }
    
    // MARK: - Thermal State Monitoring
    func recordThermalEvent(thermalState: ProcessInfo.ThermalState, currentCPULoad: Double) {
        guard isProfilingEnabled else { return }
        
        let event = ThermalEvent(
            timestamp: Date(),
            thermalState: thermalState,
            cpuLoadAtEvent: currentCPULoad
        )
        
        profilingQueue.async {
            self.thermalEvents.append(event)
        }
        
        // Create thermal event signpost
        let signpostID = OSSignpostID(log: cpuSignpostLog)
        os_signpost(.event, log: cpuSignpostLog, name: "Thermal Event", signpostID: signpostID,
                   "State: %{public}s, CPU Load: %.1f%%", String(describing: thermalState), currentCPULoad)
        
        let emoji = thermalState == .critical ? "🔥" : thermalState == .serious ? "🌡️" : "📊"
        cpuLogger.info("\(emoji) Thermal state: \(String(describing: thermalState)), CPU: \(String(format: "%.1f", currentCPULoad))%")
        
        // Add performance warning for concerning thermal states
        if thermalState == .serious || thermalState == .critical {
            DispatchQueue.main.async {
                self.performanceWarnings.append("Thermal \(thermalState) at \(Date()) with \(String(format: "%.1f", currentCPULoad))% CPU")
            }
        }
    }
    
    // MARK: - Performance Analysis
    func generatePerformanceReport() -> String {
        var report = """
        === REVERB PERFORMANCE REPORT ===
        Session: \(currentProfilingSession)
        Generated: \(Date())
        
        """
        
        // Audio Performance Analysis
        if !audioRenderTimes.isEmpty {
            let avgRenderTime = audioRenderTimes.reduce(0, +) / Double(audioRenderTimes.count)
            let maxRenderTime = audioRenderTimes.max() ?? 0
            let minRenderTime = audioRenderTimes.min() ?? 0
            
            report += """
            🎵 AUDIO PERFORMANCE:
            - Render calls: \(audioRenderTimes.count)
            - Average render time: \(String(format: "%.3f", avgRenderTime * 1000)) ms
            - Maximum render time: \(String(format: "%.3f", maxRenderTime * 1000)) ms
            - Minimum render time: \(String(format: "%.3f", minRenderTime * 1000)) ms
            
            """
        }
        
        // CPU Load Analysis
        if !cpuLoadSamples.isEmpty {
            let avgCPULoad = cpuLoadSamples.reduce(0, +) / Double(cpuLoadSamples.count)
            let maxCPULoad = cpuLoadSamples.max() ?? 0
            let highLoadCount = cpuLoadSamples.filter { $0 > 80.0 }.count
            
            report += """
            ⚡ CPU PERFORMANCE:
            - Average CPU load: \(String(format: "%.1f", avgCPULoad))%
            - Peak CPU load: \(String(format: "%.1f", maxCPULoad))%
            - High load events (>80%): \(highLoadCount)
            
            """
        }
        
        // Memory Analysis
        if !memoryAllocations.isEmpty {
            let totalAllocated = memoryAllocations.reduce(0) { $0 + $1.size }
            let allocationsPerCategory = Dictionary(grouping: memoryAllocations) { $0.category }
            
            report += """
            📦 MEMORY PERFORMANCE:
            - Total allocations: \(memoryAllocations.count)
            - Total memory allocated: \(formatBytes(totalAllocated))
            - Categories:
            """
            
            for (category, allocations) in allocationsPerCategory {
                let categoryTotal = allocations.reduce(0) { $0 + $1.size }
                report += "  - \(category): \(allocations.count) allocations, \(formatBytes(categoryTotal))\n"
            }
            report += "\n"
        }
        
        // Thermal Events
        if !thermalEvents.isEmpty {
            report += """
            🌡️ THERMAL EVENTS:
            - Total thermal events: \(thermalEvents.count)
            """
            
            let eventsByState = Dictionary(grouping: thermalEvents) { $0.thermalState }
            for (state, events) in eventsByState {
                report += "  - \(state): \(events.count) events\n"
            }
            report += "\n"
        }
        
        // Performance Warnings
        if !performanceWarnings.isEmpty {
            report += """
            ⚠️ PERFORMANCE WARNINGS:
            """
            for warning in performanceWarnings {
                report += "- \(warning)\n"
            }
            report += "\n"
        }
        
        // Recommendations
        report += generateRecommendations()
        
        // Update collected metrics
        DispatchQueue.main.async {
            self.collectedMetrics = [
                "audioRenderTimes": self.audioRenderTimes,
                "cpuLoadSamples": self.cpuLoadSamples,
                "memoryAllocations": self.memoryAllocations.count,
                "thermalEvents": self.thermalEvents.count,
                "performanceWarnings": self.performanceWarnings.count
            ]
        }
        
        audioLogger.info("📊 Performance report generated: \(report.count) characters")
        return report
    }
    
    private func generateRecommendations() -> String {
        var recommendations = "🎯 OPTIMIZATION RECOMMENDATIONS:\n"
        
        // Audio recommendations
        if let maxRenderTime = audioRenderTimes.max(), maxRenderTime > 0.005 { // 5ms threshold
            recommendations += "- Consider increasing buffer size to reduce render time spikes\n"
        }
        
        // CPU recommendations
        if let maxCPULoad = cpuLoadSamples.max(), maxCPULoad > 90.0 {
            recommendations += "- High CPU usage detected - consider enabling power saving mode\n"
        }
        
        // Memory recommendations
        let totalMemory = memoryAllocations.reduce(0) { $0 + $1.size }
        if totalMemory > 50 * 1024 * 1024 { // 50MB threshold
            recommendations += "- High memory usage - consider using memory pools for frequent allocations\n"
        }
        
        // Thermal recommendations
        let criticalThermalEvents = thermalEvents.filter { $0.thermalState == .critical }.count
        if criticalThermalEvents > 0 {
            recommendations += "- Critical thermal events detected - implement thermal throttling\n"
        }
        
        if recommendations == "🎯 OPTIMIZATION RECOMMENDATIONS:\n" {
            recommendations += "- Performance looks good! No specific recommendations at this time.\n"
        }
        
        return recommendations + "\n"
    }
    
    // MARK: - MetricKit Integration
    private func setupMetricKitSubscriber() {
        #if canImport(MetricKit)
        if #available(iOS 13.0, *) {
            metricSubscriber = MetricKitSubscriber()
            MXMetricManager.shared.add(metricSubscriber!)
        }
        #endif
    }
    
    // MARK: - High-Resolution Monitoring
    private func startHighResolutionMonitoring() {
        highResolutionTimer = DispatchSource.makeTimerSource(queue: profilingQueue)
        highResolutionTimer?.schedule(deadline: .now(), repeating: .milliseconds(100)) // 10Hz monitoring
        
        highResolutionTimer?.setEventHandler { [weak self] in
            self?.collectHighResolutionMetrics()
        }
        
        highResolutionTimer?.resume()
    }
    
    private func stopHighResolutionMonitoring() {
        highResolutionTimer?.cancel()
        highResolutionTimer = nil
    }
    
    private func collectHighResolutionMetrics() {
        // Collect system metrics periodically
        let thermalState = ProcessInfo.processInfo.thermalState
        let memoryPressure = ProcessInfo.processInfo.isLowPowerModeEnabled
        
        // Record thermal state changes
        if let lastEvent = thermalEvents.last, lastEvent.thermalState != thermalState {
            recordThermalEvent(thermalState: thermalState, currentCPULoad: 0.0) // CPU load would be measured separately
        }
    }
    
    // MARK: - Utility Functions
    private func getStackTrace() -> [String] {
        return Thread.callStackSymbols
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    // MARK: - Public Interface
    func exportPerformanceData(to url: URL) {
        let report = generatePerformanceReport()
        
        do {
            try report.write(to: url, atomically: true, encoding: .utf8)
            audioLogger.info("📄 Performance report exported to: \(url.lastPathComponent)")
        } catch {
            audioLogger.error("❌ Failed to export performance report: \(error.localizedDescription)")
        }
    }
    
    func getAverageAudioRenderTime() -> TimeInterval {
        guard !audioRenderTimes.isEmpty else { return 0 }
        return audioRenderTimes.reduce(0, +) / Double(audioRenderTimes.count)
    }
    
    func getAverageCPULoad() -> Double {
        guard !cpuLoadSamples.isEmpty else { return 0 }
        return cpuLoadSamples.reduce(0, +) / Double(cpuLoadSamples.count)
    }
    
    func getTotalMemoryAllocated() -> Int {
        return memoryAllocations.reduce(0) { $0 + $1.size }
    }
    
    func hasPerformanceIssues() -> Bool {
        return !performanceWarnings.isEmpty || 
               getAverageCPULoad() > 80.0 || 
               getAverageAudioRenderTime() > 0.005 ||
               thermalEvents.contains { $0.thermalState == .critical }
    }
}

// MARK: - MetricKit Subscriber
#if canImport(MetricKit)
@available(iOS 13.0, *)
private class MetricKitSubscriber: NSObject, MXMetricManagerSubscriber {
    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            // Process MetricKit data
            if let cpuMetrics = payload.cpuMetrics {
                print("📊 MetricKit CPU: \(cpuMetrics.cumulativeCPUTime)")
            }
            
            if let memoryMetrics = payload.memoryMetrics {
                print("📦 MetricKit Memory: Peak \(memoryMetrics.peakMemoryUsage) bytes")
            }
            
            if let powerMetrics = payload.powerMetrics {
                print("🔋 MetricKit Power: CPU \(powerMetrics.cpuMetrics.cumulativeCPUTime)")
            }
        }
    }
    
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            // Process diagnostic data
            if let cpuException = payload.cpuExceptionDiagnostics {
                print("⚠️ MetricKit CPU Exception: \(cpuException)")
            }
            
            if let hangDiagnostic = payload.hangDiagnostics {
                print("⚠️ MetricKit Hang: \(hangDiagnostic)")
            }
        }
    }
}
#endif