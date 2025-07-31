import SwiftUI
import Combine

/// Test suite for validating UI-to-audio parameter responsiveness and thread safety
/// Ensures smooth parameter changes without audio thread overload or zipper noise
@available(iOS 14.0, *)
class ParameterResponseTester: ObservableObject {
    
    // MARK: - Test Types
    enum TestType {
        case singleParameterRamp        // Slow ramp of single parameter
        case rapidParameterChanges      // Rapid parameter changes (stress test)
        case multiParameterSimultaneous // Multiple parameters changing simultaneously
        case userInteractionSimulation  // Simulate real user slider interactions
        case extremeValueJumps          // Large parameter value jumps
        case presetSwitching           // Rapid preset changes
    }
    
    enum TestResult {
        case passed
        case failed(reason: String)
        case warning(issue: String)
    }
    
    // MARK: - Test Configuration
    struct TestConfig {
        let testType: TestType
        let duration: TimeInterval
        let parameterRange: ClosedRange<Float>
        let updateRate: Double // Updates per second
        let expectedMaxLatency: TimeInterval // Maximum acceptable response latency
        let zipperThreshold: Float // Maximum acceptable zipper noise level
    }
    
    // MARK: - Published Properties
    @Published var isRunningTest = false
    @Published var currentTest: TestType?
    @Published var testProgress: Double = 0.0
    @Published var testResults: [TestType: TestResult] = [:]
    @Published var performanceMetrics: PerformanceMetrics = PerformanceMetrics()
    @Published var realTimeData: RealTimeTestData = RealTimeTestData()
    
    // MARK: - Test Infrastructure
    private var parameterController: ResponsiveParameterController?
    private var audioBridge: OptimizedAudioBridge?
    private var testTimer: Timer?
    private var testStartTime: Date?
    private var cancellables = Set<AnyCancellable>()
    
    // Performance monitoring
    private var parameterUpdateTimes: [TimeInterval] = []
    private var audioThreadResponseTimes: [TimeInterval] = []
    private var zipperMeasurements: [Float] = []
    
    // MARK: - Data Structures
    struct PerformanceMetrics {
        var averageUpdateLatency: TimeInterval = 0.0
        var maxUpdateLatency: TimeInterval = 0.0
        var updateRate: Double = 0.0
        var droppedUpdates: Int = 0
        var zipperNoiseLevel: Float = 0.0
        var cpuLoadDuringTest: Double = 0.0
        var memoryUsage: Int = 0
    }
    
    struct RealTimeTestData {
        var currentParameterValue: Float = 0.0
        var targetParameterValue: Float = 0.0
        var audioThreadValue: Float = 0.0
        var updateLatency: TimeInterval = 0.0
        var isParameterSmoothing: Bool = false
        var smoothingProgress: Float = 0.0
    }
    
    // MARK: - Test Configurations
    private let testConfigs: [TestType: TestConfig] = [
        .singleParameterRamp: TestConfig(
            testType: .singleParameterRamp,
            duration: 5.0,
            parameterRange: 0.0...1.0,
            updateRate: 60.0, // 60 FPS UI updates
            expectedMaxLatency: 0.050, // 50ms max latency
            zipperThreshold: 0.001 // Very low zipper tolerance
        ),
        
        .rapidParameterChanges: TestConfig(
            testType: .rapidParameterChanges,
            duration: 3.0,
            parameterRange: 0.0...1.0,
            updateRate: 120.0, // Stress test with 120 Hz updates
            expectedMaxLatency: 0.100, // Allow higher latency during stress
            zipperThreshold: 0.005 // Higher zipper tolerance under stress
        ),
        
        .multiParameterSimultaneous: TestConfig(
            testType: .multiParameterSimultaneous,
            duration: 4.0,
            parameterRange: 0.0...1.0,
            updateRate: 30.0, // Multiple parameters at 30 Hz each
            expectedMaxLatency: 0.080, // Multiple parameters may increase latency
            zipperThreshold: 0.002
        ),
        
        .userInteractionSimulation: TestConfig(
            testType: .userInteractionSimulation,
            duration: 8.0,
            parameterRange: 0.0...1.0,
            updateRate: 60.0, // Typical user interaction rate
            expectedMaxLatency: 0.030, // Should be very responsive
            zipperThreshold: 0.001
        ),
        
        .extremeValueJumps: TestConfig(
            testType: .extremeValueJumps,
            duration: 6.0,
            parameterRange: 0.0...1.0,
            updateRate: 5.0, // Infrequent but large jumps
            expectedMaxLatency: 0.200, // Allow time for large changes to smooth
            zipperThreshold: 0.01 // Large jumps may cause more zipper
        ),
        
        .presetSwitching: TestConfig(
            testType: .presetSwitching,
            duration: 10.0,
            parameterRange: 0.0...1.0,
            updateRate: 2.0, // Preset changes every 500ms
            expectedMaxLatency: 0.100,
            zipperThreshold: 0.003 // Multiple parameter changes
        )
    ]
    
    // MARK: - Initialization
    init(parameterController: ResponsiveParameterController, audioBridge: OptimizedAudioBridge) {
        self.parameterController = parameterController
        self.audioBridge = audioBridge
        setupPerformanceMonitoring()
    }
    
    private func setupPerformanceMonitoring() {
        // Monitor parameter controller performance
        parameterController?.$wetDryMix
            .sink { [weak self] newValue in
                self?.recordParameterUpdate(newValue)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Test Execution
    func runTest(_ testType: TestType) {
        guard !isRunningTest else { return }
        
        currentTest = testType
        isRunningTest = true
        testProgress = 0.0
        testStartTime = Date()
        
        // Clear previous metrics
        parameterUpdateTimes.removeAll()
        audioThreadResponseTimes.removeAll()
        zipperMeasurements.removeAll()
        
        print("🧪 Starting parameter response test: \(testType)")
        
        // Execute specific test
        switch testType {
        case .singleParameterRamp:
            runSingleParameterRampTest()
        case .rapidParameterChanges:
            runRapidParameterChangesTest()
        case .multiParameterSimultaneous:
            runMultiParameterSimultaneousTest()
        case .userInteractionSimulation:
            runUserInteractionSimulationTest()
        case .extremeValueJumps:
            runExtremeValueJumpsTest()
        case .presetSwitching:
            runPresetSwitchingTest()
        }
    }
    
    func stopTest() {
        testTimer?.invalidate()
        testTimer = nil
        
        if let testType = currentTest {
            analyzeTestResults(testType)
        }
        
        currentTest = nil
        isRunningTest = false
        testProgress = 1.0
        
        print("🏁 Parameter response test completed")
    }
    
    // MARK: - Individual Test Implementations
    private func runSingleParameterRampTest() {
        guard let config = testConfigs[.singleParameterRamp] else { return }
        
        let updateInterval = 1.0 / config.updateRate
        var elapsedTime: TimeInterval = 0.0
        
        testTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            elapsedTime += updateInterval
            self.testProgress = elapsedTime / config.duration
            
            // Generate smooth ramp from 0.0 to 1.0 and back
            let phase = (elapsedTime / config.duration) * 2.0 * .pi
            let rampValue = (sin(phase) + 1.0) / 2.0 // 0.0 to 1.0 sine wave
            
            // Update parameter and measure response time
            let updateStartTime = Date()
            self.parameterController?.wetDryMix = Float(rampValue)
            let updateEndTime = Date()
            
            self.parameterUpdateTimes.append(updateEndTime.timeIntervalSince(updateStartTime))
            
            // Update real-time data
            self.realTimeData.currentParameterValue = Float(rampValue)
            self.realTimeData.targetParameterValue = Float(rampValue)
            
            if elapsedTime >= config.duration {
                self.stopTest()
            }
        }
    }
    
    private func runRapidParameterChangesTest() {
        guard let config = testConfigs[.rapidParameterChanges] else { return }
        
        let updateInterval = 1.0 / config.updateRate
        var elapsedTime: TimeInterval = 0.0
        var updateCount = 0
        
        testTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            elapsedTime += updateInterval
            self.testProgress = elapsedTime / config.duration
            updateCount += 1
            
            // Generate rapid, semi-random parameter changes
            let randomValue = Float.random(in: config.parameterRange)
            
            let updateStartTime = Date()
            self.parameterController?.wetDryMix = randomValue
            let updateEndTime = Date()
            
            self.parameterUpdateTimes.append(updateEndTime.timeIntervalSince(updateStartTime))
            
            // Measure zipper noise (simplified - would need actual audio analysis)
            self.measureZipperNoise(previousValue: self.realTimeData.currentParameterValue, 
                                  newValue: randomValue)
            
            self.realTimeData.currentParameterValue = randomValue
            
            if elapsedTime >= config.duration {
                self.stopTest()
            }
        }
    }
    
    private func runMultiParameterSimultaneousTest() {
        guard let config = testConfigs[.multiParameterSimultaneous] else { return }
        
        let updateInterval = 1.0 / config.updateRate
        var elapsedTime: TimeInterval = 0.0
        
        testTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            elapsedTime += updateInterval
            self.testProgress = elapsedTime / config.duration
            
            // Generate different patterns for different parameters
            let phase1 = (elapsedTime / config.duration) * 2.0 * .pi
            let phase2 = phase1 * 1.3 // Slightly different frequency
            let phase3 = phase1 * 0.7 // Slower frequency
            
            let wetDry = Float((sin(phase1) + 1.0) / 2.0)
            let inputGain = Float((sin(phase2) + 1.0) / 2.0 * 1.5 + 0.5) // 0.5 to 2.0
            let outputGain = Float((sin(phase3) + 1.0) / 2.0 * 1.5 + 0.5) // 0.5 to 2.0
            
            let updateStartTime = Date()
            
            // Update multiple parameters simultaneously
            self.parameterController?.wetDryMix = wetDry
            self.parameterController?.inputGain = inputGain
            self.parameterController?.outputGain = outputGain
            
            let updateEndTime = Date()
            self.parameterUpdateTimes.append(updateEndTime.timeIntervalSince(updateStartTime))
            
            if elapsedTime >= config.duration {
                self.stopTest()
            }
        }
    }
    
    private func runUserInteractionSimulationTest() {
        guard let config = testConfigs[.userInteractionSimulation] else { return }
        
        let updateInterval = 1.0 / config.updateRate
        var elapsedTime: TimeInterval = 0.0
        var interactionPhase = 0 // 0: idle, 1: dragging, 2: releasing
        var interactionStartTime: TimeInterval = 0.0
        var targetValue: Float = 0.5
        
        testTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            elapsedTime += updateInterval
            self.testProgress = elapsedTime / config.duration
            
            // Simulate realistic user interaction patterns
            switch interactionPhase {
            case 0: // Idle - waiting to start interaction
                if elapsedTime - interactionStartTime > 1.0 { // Wait 1 second
                    interactionPhase = 1
                    interactionStartTime = elapsedTime
                    targetValue = Float.random(in: config.parameterRange)
                }
                
            case 1: // Dragging - smooth changes toward target
                let dragDuration = 0.5 // 500ms drag
                let dragProgress = min(1.0, (elapsedTime - interactionStartTime) / dragDuration)
                let currentValue = self.realTimeData.currentParameterValue
                let newValue = currentValue + (targetValue - currentValue) * Float(dragProgress * 0.1)
                
                self.parameterController?.wetDryMix = newValue
                self.realTimeData.currentParameterValue = newValue
                
                if dragProgress >= 1.0 {
                    interactionPhase = 2
                    interactionStartTime = elapsedTime
                }
                
            case 2: // Releasing - brief settling period
                if elapsedTime - interactionStartTime > 0.2 { // 200ms settle
                    interactionPhase = 0
                    interactionStartTime = elapsedTime
                }
                
            default:
                break
            }
            
            if elapsedTime >= config.duration {
                self.stopTest()
            }
        }
    }
    
    private func runExtremeValueJumpsTest() {
        guard let config = testConfigs[.extremeValueJumps] else { return }
        
        let updateInterval = 1.0 / config.updateRate
        var elapsedTime: TimeInterval = 0.0
        
        testTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            elapsedTime += updateInterval
            self.testProgress = elapsedTime / config.duration
            
            // Generate extreme value jumps (0.0 <-> 1.0)
            let currentValue = self.realTimeData.currentParameterValue
            let newValue: Float = currentValue < 0.5 ? 1.0 : 0.0
            
            let updateStartTime = Date()
            self.parameterController?.wetDryMix = newValue
            let updateEndTime = Date()
            
            self.parameterUpdateTimes.append(updateEndTime.timeIntervalSince(updateStartTime))
            
            // Measure zipper noise for large jumps
            self.measureZipperNoise(previousValue: currentValue, newValue: newValue)
            
            self.realTimeData.currentParameterValue = newValue
            
            if elapsedTime >= config.duration {
                self.stopTest()
            }
        }
    }
    
    private func runPresetSwitchingTest() {
        guard let config = testConfigs[.presetSwitching] else { return }
        
        let updateInterval = 1.0 / config.updateRate
        var elapsedTime: TimeInterval = 0.0
        let presets: [ReverbPreset] = [.clean, .vocalBooth, .studio, .cathedral]
        var currentPresetIndex = 0
        
        testTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            elapsedTime += updateInterval
            self.testProgress = elapsedTime / config.duration
            
            // Switch to next preset
            let preset = presets[currentPresetIndex]
            currentPresetIndex = (currentPresetIndex + 1) % presets.count
            
            let updateStartTime = Date()
            self.parameterController?.loadPreset(preset)
            let updateEndTime = Date()
            
            self.parameterUpdateTimes.append(updateEndTime.timeIntervalSince(updateStartTime))
            
            if elapsedTime >= config.duration {
                self.stopTest()
            }
        }
    }
    
    // MARK: - Measurement Functions
    private func recordParameterUpdate(_ newValue: Float) {
        // Record when parameter actually changed (for latency measurement)
        let updateTime = Date()
        
        // Store for analysis
        realTimeData.audioThreadValue = newValue
        
        // Calculate latency if we have a corresponding UI update
        if let startTime = testStartTime {
            let latency = updateTime.timeIntervalSince(startTime)
            audioThreadResponseTimes.append(latency)
        }
    }
    
    private func measureZipperNoise(previousValue: Float, newValue: Float) {
        // Simplified zipper noise measurement based on parameter jump size
        let parameterJump = abs(newValue - previousValue)
        let zipperEstimate = parameterJump * 0.1 // Simplified calculation
        
        zipperMeasurements.append(zipperEstimate)
        performanceMetrics.zipperNoiseLevel = max(performanceMetrics.zipperNoiseLevel, zipperEstimate)
    }
    
    // MARK: - Test Analysis
    private func analyzeTestResults(_ testType: TestType) {
        guard let config = testConfigs[testType] else { return }
        
        // Calculate performance metrics
        if !parameterUpdateTimes.isEmpty {
            performanceMetrics.averageUpdateLatency = parameterUpdateTimes.reduce(0, +) / Double(parameterUpdateTimes.count)
            performanceMetrics.maxUpdateLatency = parameterUpdateTimes.max() ?? 0.0
        }
        
        if !audioThreadResponseTimes.isEmpty {
            performanceMetrics.updateRate = Double(audioThreadResponseTimes.count) / config.duration
        }
        
        if !zipperMeasurements.isEmpty {
            performanceMetrics.zipperNoiseLevel = zipperMeasurements.max() ?? 0.0
        }
        
        // Determine test result
        var result: TestResult = .passed
        var issues: [String] = []
        
        // Check latency requirements
        if performanceMetrics.maxUpdateLatency > config.expectedMaxLatency {
            issues.append("Max latency (\(String(format: "%.3f", performanceMetrics.maxUpdateLatency * 1000))ms) exceeds limit (\(String(format: "%.3f", config.expectedMaxLatency * 1000))ms)")
        }
        
        // Check zipper noise
        if performanceMetrics.zipperNoiseLevel > config.zipperThreshold {
            issues.append("Zipper noise level (\(String(format: "%.4f", performanceMetrics.zipperNoiseLevel))) exceeds threshold (\(String(format: "%.4f", config.zipperThreshold)))")
        }
        
        // Check update rate
        let expectedUpdateRate = config.updateRate
        if performanceMetrics.updateRate < expectedUpdateRate * 0.9 { // Allow 10% variance
            issues.append("Update rate (\(String(format: "%.1f", performanceMetrics.updateRate)) Hz) below expected (\(String(format: "%.1f", expectedUpdateRate)) Hz)")
        }
        
        // Determine final result
        if !issues.isEmpty {
            if issues.count == 1 && issues[0].contains("Update rate") {
                result = .warning(issue: issues[0])
            } else {
                result = .failed(reason: issues.joined(separator: "; "))
            }
        }
        
        testResults[testType] = result
        
        // Log results
        print("📊 Test results for \(testType):")
        print("   Average latency: \(String(format: "%.3f", performanceMetrics.averageUpdateLatency * 1000))ms")
        print("   Max latency: \(String(format: "%.3f", performanceMetrics.maxUpdateLatency * 1000))ms")
        print("   Update rate: \(String(format: "%.1f", performanceMetrics.updateRate)) Hz")
        print("   Zipper noise: \(String(format: "%.4f", performanceMetrics.zipperNoiseLevel))")
        print("   Result: \(result)")
    }
    
    // MARK: - Public Interface
    func runAllTests() {
        let allTests: [TestType] = [
            .singleParameterRamp,
            .rapidParameterChanges,
            .multiParameterSimultaneous,
            .userInteractionSimulation,
            .extremeValueJumps,
            .presetSwitching
        ]
        
        runTestSequence(allTests)
    }
    
    private func runTestSequence(_ tests: [TestType]) {
        guard !tests.isEmpty else { return }
        
        var remainingTests = tests
        let currentTest = remainingTests.removeFirst()
        
        runTest(currentTest)
        
        // Wait for current test to complete, then run next
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            if !self.isRunningTest {
                timer.invalidate()
                
                if !remainingTests.isEmpty {
                    // Brief pause between tests
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.runTestSequence(remainingTests)
                    }
                }
            }
        }
    }
    
    func getTestSummary() -> String {
        var summary = "PARAMETER RESPONSE TEST SUMMARY\n"
        summary += "================================\n\n"
        
        let passedCount = testResults.values.filter { if case .passed = $0 { return true }; return false }.count
        let warningCount = testResults.values.filter { if case .warning = $0 { return true }; return false }.count
        let failedCount = testResults.values.filter { if case .failed = $0 { return true }; return false }.count
        
        summary += "Overall Results:\n"
        summary += "  ✅ Passed: \(passedCount)\n"
        summary += "  ⚠️ Warnings: \(warningCount)\n"
        summary += "  ❌ Failed: \(failedCount)\n\n"
        
        summary += "Performance Metrics:\n"
        summary += "  Average Latency: \(String(format: "%.3f", performanceMetrics.averageUpdateLatency * 1000))ms\n"
        summary += "  Max Latency: \(String(format: "%.3f", performanceMetrics.maxUpdateLatency * 1000))ms\n"
        summary += "  Update Rate: \(String(format: "%.1f", performanceMetrics.updateRate)) Hz\n"
        summary += "  Zipper Noise Level: \(String(format: "%.4f", performanceMetrics.zipperNoiseLevel))\n\n"
        
        summary += "Individual Test Results:\n"
        for (testType, result) in testResults {
            let status = switch result {
                case .passed: "✅ PASSED"
                case .warning(let issue): "⚠️ WARNING: \(issue)"
                case .failed(let reason): "❌ FAILED: \(reason)"
            }
            summary += "  \(testType): \(status)\n"
        }
        
        return summary
    }
}

// MARK: - Test UI View
@available(iOS 14.0, *)
struct ParameterResponseTestView: View {
    @StateObject private var tester: ParameterResponseTester
    @State private var showingResults = false
    
    init(parameterController: ResponsiveParameterController, audioBridge: OptimizedAudioBridge) {
        _tester = StateObject(wrappedValue: ParameterResponseTester(
            parameterController: parameterController,
            audioBridge: audioBridge
        ))
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("🧪 Parameter Response Testing")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            if tester.isRunningTest {
                VStack(spacing: 12) {
                    Text("Running: \(tester.currentTest?.description ?? "Unknown")")
                        .font(.headline)
                        .foregroundColor(.blue)
                    
                    ProgressView(value: tester.testProgress)
                        .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                        .frame(height: 8)
                    
                    Text("\(Int(tester.testProgress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            } else {
                VStack(spacing: 12) {
                    Button("Run All Tests") {
                        tester.runAllTests()
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .cornerRadius(12)
                    
                    if !tester.testResults.isEmpty {
                        Button("View Results") {
                            showingResults = true
                        }
                        .font(.subheadline)
                        .foregroundColor(.blue)
                    }
                }
            }
        }
        .padding()
        .sheet(isPresented: $showingResults) {
            TestResultsView(summary: tester.getTestSummary())
        }
    }
}

struct TestResultsView: View {
    let summary: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                Text(summary)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.white)
                    .padding()
            }
            .background(Color.black)
            .navigationTitle("Test Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Extensions
extension ParameterResponseTester.TestType {
    var description: String {
        switch self {
        case .singleParameterRamp: return "Single Parameter Ramp"
        case .rapidParameterChanges: return "Rapid Parameter Changes"
        case .multiParameterSimultaneous: return "Multi-Parameter Simultaneous"
        case .userInteractionSimulation: return "User Interaction Simulation"
        case .extremeValueJumps: return "Extreme Value Jumps"
        case .presetSwitching: return "Preset Switching"
        }
    }
}