import Foundation
import AVFoundation
import UIKit
import BackgroundTasks

/// Background audio manager inspired by AD 480 RE capabilities
/// Manages background processing, battery optimization, and user notifications
@available(iOS 14.0, *)
class BackgroundAudioManager: ObservableObject {
    
    // MARK: - Background Processing States
    enum BackgroundMode {
        case disabled           // No background processing
        case monitoring        // Monitor only, minimal processing
        case recording         // Active recording with full processing
        case processing        // Offline/batch processing in background
    }
    
    enum BatteryStrategy {
        case performance       // Maximum quality, ignore battery
        case balanced         // Balance quality and battery life
        case conservation     // Minimum processing, save battery
        case adaptive         // Adapt based on battery level and charging
    }
    
    // MARK: - Published Properties
    @Published var currentBackgroundMode: BackgroundMode = .disabled
    @Published var batteryStrategy: BatteryStrategy = .adaptive
    @Published var isBackgroundProcessingEnabled = false
    @Published var estimatedBatteryImpact: Double = 0.0 // Hours of battery usage
    @Published var backgroundActivityDescription = ""
    
    // MARK: - Private Properties
    private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid
    private var backgroundAppRefreshTask: BGAppRefreshTask?
    private var backgroundProcessingTask: BGProcessingTask?
    
    // Audio session and processing
    private var audioSession: AVAudioSession
    private var backgroundAudioEngine: AVAudioEngine?
    private weak var memoryBatteryManager: MemoryBatteryManager?
    
    // Battery monitoring
    private var batteryMonitor: Timer?
    private var thermalStateObserver: NSObjectProtocol?
    private var batteryLevelObserver: NSObjectProtocol?
    
    // Background processing configuration
    private let backgroundIdentifier = "com.reverb.background-processing"
    private let backgroundRefreshIdentifier = "com.reverb.background-refresh"
    
    // Performance tracking
    private var backgroundStartTime: Date?
    private var processingTimeAccumulator: TimeInterval = 0
    
    // MARK: - Initialization
    init() {
        self.audioSession = AVAudioSession.sharedInstance()
        
        setupBackgroundTaskHandlers()
        setupBatteryMonitoring()
        setupThermalMonitoring()
        
        // Request background app refresh if not already granted
        requestBackgroundPermissions()
    }
    
    deinit {
        stopBackgroundProcessing()
        cleanupObservers()
    }
    
    // MARK: - Background Processing Setup
    private func setupBackgroundTaskHandlers() {
        // Register background task handlers
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: backgroundIdentifier,
            using: nil
        ) { [weak self] task in
            self?.handleBackgroundProcessing(task as! BGProcessingTask)
        }
        
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: backgroundRefreshIdentifier,
            using: nil
        ) { [weak self] task in
            self?.handleBackgroundRefresh(task as! BGAppRefreshTask)
        }
    }
    
    private func requestBackgroundPermissions() {
        // Request background app refresh
        UIApplication.shared.setMinimumBackgroundFetchInterval(
            UIApplication.backgroundFetchIntervalMinimum
        )
        
        // Note: User must enable background app refresh in Settings
        // We can only inform them about the benefits
    }
    
    // MARK: - Background Mode Management
    func enableBackgroundProcessing(mode: BackgroundMode, 
                                  strategy: BatteryStrategy = .adaptive) {
        
        guard mode != .disabled else {
            disableBackgroundProcessing()
            return
        }
        
        currentBackgroundMode = mode
        batteryStrategy = strategy
        isBackgroundProcessingEnabled = true
        
        // Configure audio session for background processing
        configureBackgroundAudioSession()
        
        // Schedule background tasks
        scheduleBackgroundTasks()
        
        // Update battery impact estimation
        updateBatteryImpactEstimate()
        
        // Update activity description for user
        updateBackgroundActivityDescription()
        
        print("🔄 Background processing enabled: \(mode) with \(strategy) strategy")
    }
    
    func disableBackgroundProcessing() {
        currentBackgroundMode = .disabled
        isBackgroundProcessingEnabled = false
        
        // Cancel scheduled background tasks
        BGTaskScheduler.shared.cancelAllTaskRequests()
        
        // End current background task
        endBackgroundTask()
        
        // Reset audio session configuration
        resetAudioSessionConfiguration()
        
        print("⏹️ Background processing disabled")
    }
    
    // MARK: - Audio Session Configuration
    private func configureBackgroundAudioSession() {
        do {
            // Configure for background audio processing
            try audioSession.setCategory(
                .playAndRecord,
                mode: .default,
                options: [
                    .mixWithOthers,           // Allow other apps to play audio
                    .allowBluetooth,          // Support Bluetooth audio
                    .allowBluetoothA2DP,      // Support high-quality Bluetooth
                    .duckOthers               // Duck other audio when processing
                ]
            )
            
            // Set preferred sample rate and buffer size based on battery strategy
            let (sampleRate, bufferSize) = getOptimalAudioSettings()
            
            try audioSession.setPreferredSampleRate(sampleRate)
            try audioSession.setPreferredIOBufferDuration(Double(bufferSize) / sampleRate)
            
            // Activate the session
            try audioSession.setActive(true)
            
            print("🎵 Background audio session configured: \(sampleRate)Hz, \(bufferSize) frames")
            
        } catch {
            print("❌ Failed to configure background audio session: \(error)")
        }
    }
    
    private func resetAudioSessionConfiguration() {
        do {
            // Reset to default configuration when not in background
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [])
            try audioSession.setActive(false)
        } catch {
            print("⚠️ Failed to reset audio session: \(error)")
        }
    }
    
    private func getOptimalAudioSettings() -> (sampleRate: Double, bufferSize: Int) {
        switch batteryStrategy {
        case .performance:
            return (48000, 128)     // High quality, more battery usage
        case .balanced:
            return (44100, 256)     // Good quality, moderate battery usage
        case .conservation:
            return (44100, 512)     // Lower quality, less battery usage
        case .adaptive:
            // Adapt based on current battery level and charging status
            let batteryLevel = UIDevice.current.batteryLevel
            let isCharging = UIDevice.current.batteryState == .charging
            
            if isCharging || batteryLevel > 0.8 {
                return (48000, 256)     // Good quality when power available
            } else if batteryLevel > 0.3 {
                return (44100, 256)     // Balanced when moderate battery
            } else {
                return (44100, 512)     // Conservative when low battery
            }
        }
    }
    
    // MARK: - Background Task Handling
    private func handleBackgroundProcessing(_ task: BGProcessingTask) {
        backgroundProcessingTask = task
        
        // Set expiration handler
        task.expirationHandler = { [weak self] in
            self?.endBackgroundProcessingTask()
        }
        
        // Start background processing
        Task {
            await performBackgroundProcessing()
            self.completeBackgroundProcessingTask(success: true)
        }
    }
    
    private func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
        backgroundAppRefreshTask = task
        
        // Set expiration handler
        task.expirationHandler = { [weak self] in
            self?.endBackgroundRefreshTask()
        }
        
        // Perform background refresh
        Task {
            await performBackgroundRefresh()
            self.completeBackgroundRefreshTask(success: true)
        }
    }
    
    private func performBackgroundProcessing() async {
        print("🔄 Starting background processing...")
        backgroundStartTime = Date()
        
        switch currentBackgroundMode {
        case .monitoring:
            await performBackgroundMonitoring()
        case .recording:
            await performBackgroundRecording()
        case .processing:
            await performBackgroundBatchProcessing()
        case .disabled:
            break
        }
        
        // Update processing time accumulator
        if let startTime = backgroundStartTime {
            processingTimeAccumulator += Date().timeIntervalSince(startTime)
        }
        
        print("✅ Background processing completed")
    }
    
    private func performBackgroundRefresh() async {
        print("🔄 Performing background refresh...")
        
        // Update battery impact estimates
        updateBatteryImpactEstimate()
        
        // Check thermal state and adjust strategy if needed
        checkThermalStateAndAdapt()
        
        // Schedule next background processing if needed
        if isBackgroundProcessingEnabled {
            scheduleBackgroundTasks()
        }
        
        print("✅ Background refresh completed")
    }
    
    // MARK: - Specific Background Operations
    private func performBackgroundMonitoring() async {
        // Minimal processing - just monitor audio levels and system state
        // This mode has very low battery impact
        
        guard let engine = createLightweightAudioEngine() else { return }
        
        let processingTime: TimeInterval = 5.0 // Process for 5 seconds
        let endTime = Date().addingTimeInterval(processingTime)
        
        while Date() < endTime && backgroundProcessingTask != nil {
            // Minimal level monitoring
            await Task.sleep(nanoseconds: 100_000_000) // 100ms intervals
            
            // Update memory/battery manager if available
            memoryBatteryManager?.updateCPULoad(5.0) // Low CPU usage
        }
        
        engine.stop()
    }
    
    private func performBackgroundRecording() async {
        // Active recording with full reverb processing
        // Higher battery impact but necessary for real-time recording
        
        print("🎙️ Starting background recording session...")
        
        guard let engine = createFullAudioEngine() else { return }
        
        // Record for up to 30 minutes or until task expires
        let maxRecordingTime: TimeInterval = 30 * 60 // 30 minutes
        let endTime = Date().addingTimeInterval(maxRecordingTime)
        
        while Date() < endTime && backgroundProcessingTask != nil {
            // Process audio with full reverb pipeline
            await Task.sleep(nanoseconds: 50_000_000) // 50ms intervals for responsive processing
            
            // Update performance metrics
            memoryBatteryManager?.updateCPULoad(25.0) // Moderate CPU usage
        }
        
        engine.stop()
        print("⏹️ Background recording session ended")
    }
    
    private func performBackgroundBatchProcessing() async {
        // Offline batch processing in background
        // Can have high CPU usage but should adapt to thermal conditions
        
        print("⚡ Starting background batch processing...")
        
        // Create processing queue with thermal-aware settings
        let processingQuality = getThermalAwareProcessingQuality()
        
        // Simulate batch processing (in real implementation, this would process actual files)
        let batchSize = getBatchSizeForCurrentConditions()
        
        for i in 0..<batchSize {
            guard backgroundProcessingTask != nil else { break }
            
            // Process one item
            await processBackgroundBatchItem(index: i, quality: processingQuality)
            
            // Check thermal state periodically
            if i % 5 == 0 {
                checkThermalStateAndAdapt()
            }
            
            // Brief pause to prevent overheating
            await Task.sleep(nanoseconds: 100_000_000) // 100ms between items
        }
        
        print("✅ Background batch processing completed")
    }
    
    private func processBackgroundBatchItem(index: Int, quality: ProcessingQuality) async {
        // Simulate processing one batch item
        let processingTimeMs = quality == .minimal ? 50 : quality == .standard ? 100 : 200
        await Task.sleep(nanoseconds: UInt64(processingTimeMs * 1_000_000))
        
        // Update CPU load based on processing quality
        let cpuLoad = quality == .minimal ? 15.0 : quality == .standard ? 30.0 : 50.0
        memoryBatteryManager?.updateCPULoad(cpuLoad)
    }
    
    // MARK: - Audio Engine Creation
    private func createLightweightAudioEngine() -> AVAudioEngine? {
        let engine = AVAudioEngine()
        
        // Minimal configuration for monitoring only
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        
        // Simple pass-through with level monitoring
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, time in
            // Minimal processing - just level detection
            // This has very low CPU impact
        }
        
        do {
            try engine.start()
            return engine
        } catch {
            print("❌ Failed to start lightweight audio engine: \(error)")
            return nil
        }
    }
    
    private func createFullAudioEngine() -> AVAudioEngine? {
        let engine = AVAudioEngine()
        
        // Full configuration with reverb processing
        let inputNode = engine.inputNode
        let outputNode = engine.outputNode
        let reverbNode = AVAudioUnitReverb()
        
        // Configure reverb for background processing (reduced quality for battery)
        reverbNode.loadFactoryPreset(.mediumRoom)
        reverbNode.wetDryMix = 30 // Reduced wet signal for battery savings
        
        // Connect nodes
        engine.attach(reverbNode)
        engine.connect(inputNode, to: reverbNode, format: inputNode.outputFormat(forBus: 0))
        engine.connect(reverbNode, to: outputNode, format: reverbNode.outputFormat(forBus: 0))
        
        do {
            try engine.start()
            return engine
        } catch {
            print("❌ Failed to start full audio engine: \(error)")
            return nil
        }
    }
    
    // MARK: - Task Scheduling
    private func scheduleBackgroundTasks() {
        // Schedule background processing task
        let processingRequest = BGProcessingTaskRequest(identifier: backgroundIdentifier)
        processingRequest.requiresNetworkConnectivity = false
        processingRequest.requiresExternalPower = batteryStrategy == .performance
        processingRequest.earliestBeginDate = Date(timeIntervalSinceNow: 10) // 10 seconds from now
        
        do {
            try BGTaskScheduler.shared.submit(processingRequest)
            print("📅 Background processing task scheduled")
        } catch {
            print("❌ Failed to schedule background processing: \(error)")
        }
        
        // Schedule background refresh task
        let refreshRequest = BGAppRefreshTaskRequest(identifier: backgroundRefreshIdentifier)
        refreshRequest.earliestBeginDate = Date(timeIntervalSinceNow: 60) // 1 minute from now
        
        do {
            try BGTaskScheduler.shared.submit(refreshRequest)
            print("📅 Background refresh task scheduled")
        } catch {
            print("❌ Failed to schedule background refresh: \(error)")
        }
    }
    
    // MARK: - Task Completion
    private func completeBackgroundProcessingTask(success: Bool) {
        backgroundProcessingTask?.setTaskCompleted(success: success)
        backgroundProcessingTask = nil
        
        // Schedule next task if still enabled
        if isBackgroundProcessingEnabled {
            scheduleBackgroundTasks()
        }
    }
    
    private func completeBackgroundRefreshTask(success: Bool) {
        backgroundAppRefreshTask?.setTaskCompleted(success: success)
        backgroundAppRefreshTask = nil
    }
    
    private func endBackgroundProcessingTask() {
        backgroundProcessingTask?.setTaskCompleted(success: false)
        backgroundProcessingTask = nil
    }
    
    private func endBackgroundRefreshTask() {
        backgroundAppRefreshTask?.setTaskCompleted(success: false)
        backgroundAppRefreshTask = nil
    }
    
    private func endBackgroundTask() {
        if backgroundTaskIdentifier != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
            backgroundTaskIdentifier = .invalid
        }
    }
    
    // MARK: - Battery and Thermal Management
    private func setupBatteryMonitoring() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        
        batteryLevelObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.batteryLevelDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleBatteryLevelChange()
        }
    }
    
    private func setupThermalMonitoring() {
        thermalStateObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleThermalStateChange()
        }
    }
    
    private func handleBatteryLevelChange() {
        let batteryLevel = UIDevice.current.batteryLevel
        let isCharging = UIDevice.current.batteryState == .charging
        
        print("🔋 Battery level changed: \(Int(batteryLevel * 100))% (charging: \(isCharging))")
        
        // Adapt strategy based on battery level
        if batteryStrategy == .adaptive {
            adaptStrategyBasedOnBattery()
        }
        
        updateBatteryImpactEstimate()
    }
    
    private func handleThermalStateChange() {
        let thermalState = ProcessInfo.processInfo.thermalState
        print("🌡️ Thermal state changed: \(thermalState)")
        
        checkThermalStateAndAdapt()
    }
    
    private func adaptStrategyBasedOnBattery() {
        let batteryLevel = UIDevice.current.batteryLevel
        let isCharging = UIDevice.current.batteryState == .charging
        
        if isCharging {
            // Can use more aggressive processing when charging
            if currentBackgroundMode == .processing {
                memoryBatteryManager?.setPowerMode(.highPerformance)
            }
        } else if batteryLevel < 0.2 {
            // Very conservative when battery is low
            memoryBatteryManager?.setPowerMode(.powerSaver)
            
            // Consider disabling non-essential background processing
            if currentBackgroundMode == .processing {
                print("⚠️ Low battery detected, reducing background processing")
            }
        } else if batteryLevel < 0.5 {
            // Balanced approach for moderate battery
            memoryBatteryManager?.setPowerMode(.balanced)
        }
    }
    
    private func checkThermalStateAndAdapt() {
        let thermalState = ProcessInfo.processInfo.thermalState
        
        switch thermalState {
        case .nominal:
            // Normal operation
            break
        case .fair:
            // Slight throttling
            memoryBatteryManager?.setPowerMode(.balanced)
        case .serious:
            // Significant throttling
            memoryBatteryManager?.setPowerMode(.powerSaver)
            print("🌡️ Thermal throttling: reducing background processing")
        case .critical:
            // Emergency throttling - stop non-essential processing
            if currentBackgroundMode == .processing {
                print("🔥 Critical thermal state: suspending background processing")
                // Could temporarily disable background processing
            }
            memoryBatteryManager?.setPowerMode(.powerSaver)
        @unknown default:
            break
        }
    }
    
    private func getThermalAwareProcessingQuality() -> ProcessingQuality {
        let thermalState = ProcessInfo.processInfo.thermalState
        
        switch thermalState {
        case .nominal:
            return .standard
        case .fair:
            return .standard
        case .serious:
            return .minimal
        case .critical:
            return .minimal
        @unknown default:
            return .minimal
        }
    }
    
    private func getBatchSizeForCurrentConditions() -> Int {
        let thermalState = ProcessInfo.processInfo.thermalState
        let batteryLevel = UIDevice.current.batteryLevel
        
        var batchSize = 10 // Default batch size
        
        // Reduce batch size in adverse conditions
        if thermalState == .serious || thermalState == .critical {
            batchSize = 3
        } else if batteryLevel < 0.3 {
            batchSize = 5
        }
        
        return batchSize
    }
    
    // MARK: - Battery Impact Estimation
    private func updateBatteryImpactEstimate() {
        // Estimate battery usage based on current configuration
        var hourlyImpact: Double = 0.0
        
        switch currentBackgroundMode {
        case .disabled:
            hourlyImpact = 0.0
        case .monitoring:
            hourlyImpact = 0.5 // Very light monitoring
        case .recording:
            hourlyImpact = 8.0 // Active recording with processing
        case .processing:
            hourlyImpact = 4.0 // Batch processing
        }
        
        // Adjust based on battery strategy
        switch batteryStrategy {
        case .performance:
            hourlyImpact *= 1.5
        case .balanced:
            hourlyImpact *= 1.0
        case .conservation:
            hourlyImpact *= 0.6
        case .adaptive:
            hourlyImpact *= UIDevice.current.batteryState == .charging ? 1.2 : 0.8
        }
        
        // Convert to estimated hours of usage
        let currentBatteryLevel = UIDevice.current.batteryLevel
        estimatedBatteryImpact = currentBatteryLevel > 0 ? Double(currentBatteryLevel) / (hourlyImpact / 100.0) : 0.0
        
        print("🔋 Estimated battery impact: \(String(format: "%.1f", hourlyImpact))%/hour, \(String(format: "%.1f", estimatedBatteryImpact))h remaining")
    }
    
    private func updateBackgroundActivityDescription() {
        switch currentBackgroundMode {
        case .disabled:
            backgroundActivityDescription = "Background processing disabled"
        case .monitoring:
            backgroundActivityDescription = "Monitoring audio levels in background"
        case .recording:
            backgroundActivityDescription = "Recording with reverb processing in background"
        case .processing:
            backgroundActivityDescription = "Processing audio files in background"
        }
        
        backgroundActivityDescription += " (Strategy: \(batteryStrategy))"
    }
    
    // MARK: - Cleanup
    private func cleanupObservers() {
        if let observer = batteryLevelObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        
        if let observer = thermalStateObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        
        batteryMonitor?.invalidate()
        batteryMonitor = nil
    }
    
    // MARK: - Public Interface
    func getCurrentBackgroundStatus() -> String {
        if !isBackgroundProcessingEnabled {
            return "Background processing disabled"
        }
        
        let batteryLevel = Int(UIDevice.current.batteryLevel * 100)
        let thermalState = ProcessInfo.processInfo.thermalState
        let isCharging = UIDevice.current.batteryState == .charging
        
        return """
        Mode: \(currentBackgroundMode)
        Strategy: \(batteryStrategy)
        Battery: \(batteryLevel)% \(isCharging ? "(charging)" : "")
        Thermal: \(thermalState)
        Estimated Impact: \(String(format: "%.1f", estimatedBatteryImpact))h
        Processing Time: \(String(format: "%.1f", processingTimeAccumulator))s
        """
    }
    
    func shouldAllowBackgroundProcessing() -> Bool {
        // Check if conditions are suitable for background processing
        let batteryLevel = UIDevice.current.batteryLevel
        let thermalState = ProcessInfo.processInfo.thermalState
        
        // Don't process if battery is critically low or device is overheating
        if batteryLevel < 0.05 || thermalState == .critical {
            return false
        }
        
        return isBackgroundProcessingEnabled
    }
}

// Supporting enums and types
enum ProcessingQuality {
    case minimal
    case standard
    case maximum
}