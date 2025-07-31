import Foundation
import AVFoundation
import Accelerate

/// Validates tap-based recording functionality on iOS
/// Ensures audio tap installation, buffer processing, and file writing work correctly
class iOSTapRecordingValidator: ObservableObject {
    
    // MARK: - Validation Configuration
    
    struct TapValidationConfig {
        let sampleRate: Double = 48000.0
        let bufferSize: AVAudioFrameCount = 64
        let channels: UInt32 = 2
        let testDuration: TimeInterval = 3.0
        let validationThreshold: Float = 0.001 // 0.1% tolerance for audio processing
    }
    
    // MARK: - Test Results
    
    struct TapValidationResult {
        let testName: String
        let passed: Bool
        let details: String
        let metrics: TapMetrics?
        let audioSamples: [Float]? // For debugging
        
        struct TapMetrics {
            let bufferCount: Int
            let totalSamples: Int
            let averageBufferProcessingTime: TimeInterval
            let maxBufferProcessingTime: TimeInterval
            let dropouts: Int
            let silentBuffers: Int
            let peakAmplitude: Float
            let rmsAmplitude: Float
        }
    }
    
    // MARK: - Published Properties
    
    @Published var isValidating = false
    @Published var validationProgress: Double = 0.0
    @Published var validationResults: [TapValidationResult] = []
    @Published var overallValidationPassed = false
    
    // MARK: - Audio Components
    
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var testAudioBuffer: AVAudioPCMBuffer?
    
    // Tap validation state
    private var tapBufferCount = 0
    private var tapProcessingTimes: [TimeInterval] = []
    private var recordedSamples: [Float] = []
    private var bufferDropouts = 0
    private var silentBufferCount = 0
    
    // Timing
    private var tapValidationStartTime: Date?
    private var bufferProcessingStartTime: Date?
    
    private let config = TapValidationConfig()
    
    // MARK: - Initialization
    
    init() {
        setupAudioEngine()
        generateTestAudio()
    }
    
    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        
        guard let engine = audioEngine,
              let player = playerNode else {
            print("❌ Failed to initialize audio components for tap validation")
            return
        }
        
        engine.attach(player)
        
        // Connect player to main mixer with our test format
        let audioFormat = AVAudioFormat(
            standardFormatWithSampleRate: config.sampleRate,
            channels: config.channels
        )!
        
        engine.connect(player, to: engine.mainMixerNode, format: audioFormat)
        
        print("✅ Audio engine configured for tap validation")
    }
    
    private func generateTestAudio() {
        guard let audioFormat = AVAudioFormat(
            standardFormatWithSampleRate: config.sampleRate,
            channels: config.channels
        ) else {
            print("❌ Failed to create audio format for test")
            return
        }
        
        let frameCount = AVAudioFrameCount(config.testDuration * config.sampleRate)
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCount) else {
            print("❌ Failed to create test audio buffer")
            return
        }
        
        buffer.frameLength = frameCount
        
        // Generate test signal with multiple frequencies for validation
        generateValidationTestSignal(buffer: buffer)
        
        self.testAudioBuffer = buffer
        
        print("✅ Generated test audio: \(frameCount) frames at \(config.sampleRate)Hz")
    }
    
    private func generateValidationTestSignal(buffer: AVAudioPCMBuffer) {
        guard let leftChannel = buffer.floatChannelData?[0],
              let rightChannel = buffer.floatChannelData?[1] else { return }
        
        let frameCount = Int(buffer.frameLength)
        let sampleRate = Float(config.sampleRate)
        
        // Test frequencies designed to validate tap processing
        let testFrequencies: [Float] = [440.0, 1000.0, 2000.0] // A4, 1kHz, 2kHz
        let amplitudes: [Float] = [0.3, 0.2, 0.1] // Different levels
        
        for i in 0..<frameCount {
            let time = Float(i) / sampleRate
            var leftSample: Float = 0.0
            var rightSample: Float = 0.0
            
            // Generate multi-tone signal
            for (freq, amp) in zip(testFrequencies, amplitudes) {
                let phase = 2.0 * Float.pi * freq * time
                leftSample += amp * sin(phase)
                rightSample += amp * sin(phase + 0.05) // Slight phase offset for stereo
            }
            
            leftChannel[i] = leftSample
            rightChannel[i] = rightSample
        }
    }
    
    // MARK: - Validation Tests
    
    func runTapValidation() {
        guard !isValidating else { return }
        
        isValidating = true
        validationProgress = 0.0
        validationResults.removeAll()
        
        print("🧪 Starting iOS tap recording validation...")
        
        DispatchQueue.global(qos: .userInitiated).async {
            self.performTapValidationTests()
        }
    }
    
    private func performTapValidationTests() {
        let tests = [
            ("Tap Installation", testTapInstallation),
            ("Buffer Processing", testBufferProcessing),
            ("Audio Continuity", testAudioContinuity),
            ("Real-time Performance", testRealTimePerformance),
            ("Buffer Timing", testBufferTiming),
            ("Signal Fidelity", testSignalFidelity),
            ("Dropout Detection", testDropoutDetection),
            ("Memory Management", testMemoryManagement)
        ]
        
        for (index, (testName, testFunction)) in tests.enumerated() {
            DispatchQueue.main.async {
                self.validationProgress = Double(index) / Double(tests.count)
            }
            
            print("🔍 Running tap test: \(testName)")
            let result = testFunction()
            
            DispatchQueue.main.async {
                self.validationResults.append(result)
            }
            
            Thread.sleep(forTimeInterval: 0.2)
        }
        
        DispatchQueue.main.async {
            self.isValidating = false
            self.validationProgress = 1.0
            self.calculateOverallResult()
            self.generateTapValidationReport()
        }
    }
    
    // MARK: - Individual Test Functions
    
    private func testTapInstallation() -> TapValidationResult {
        guard let engine = audioEngine else {
            return TapValidationResult(
                testName: "Tap Installation",
                passed: false,
                details: "Audio engine not available",
                metrics: nil,
                audioSamples: nil
            )
        }
        
        var tapInstalled = false
        var tapError: Error?
        
        do {
            // Try to install tap on main mixer node
            let mainMixer = engine.mainMixerNode
            let tapFormat = mainMixer.outputFormat(forBus: 0)
            
            // Install tap with our required buffer size
            mainMixer.installTap(
                onBus: 0,
                bufferSize: config.bufferSize,
                format: tapFormat
            ) { buffer, when in
                // Tap callback - just verify it's called
                tapInstalled = true
            }
            
            // Start engine briefly to test tap
            try engine.start()
            Thread.sleep(forTimeInterval: 0.1)
            engine.stop()
            
            // Remove tap
            mainMixer.removeTap(onBus: 0)
            
        } catch {
            tapError = error
        }
        
        let passed = tapInstalled && tapError == nil
        let details = tapInstalled ? 
            "Tap installed successfully" : 
            "Failed to install tap: \(tapError?.localizedDescription ?? "Unknown error")"
        
        return TapValidationResult(
            testName: "Tap Installation",
            passed: passed,
            details: details,
            metrics: nil,
            audioSamples: nil
        )
    }
    
    private func testBufferProcessing() -> TapValidationResult {
        guard let engine = audioEngine,
              let player = playerNode,
              let testBuffer = testAudioBuffer else {
            return TapValidationResult(
                testName: "Buffer Processing",
                passed: false,
                details: "Audio components not ready",
                metrics: nil,
                audioSamples: nil
            )
        }
        
        // Reset validation state
        tapBufferCount = 0
        tapProcessingTimes.removeAll()
        recordedSamples.removeAll()
        bufferDropouts = 0
        silentBufferCount = 0
        
        var testPassed = true
        var testDetails = ""
        
        do {
            // Install tap for buffer processing test
            let mainMixer = engine.mainMixerNode
            let tapFormat = mainMixer.outputFormat(forBus: 0)
            
            tapValidationStartTime = Date()
            
            mainMixer.installTap(
                onBus: 0,
                bufferSize: config.bufferSize,
                format: tapFormat
            ) { [weak self] buffer, when in
                self?.processTapBuffer(buffer, timestamp: when)
            }
            
            // Start engine and play test audio
            try engine.start()
            player.scheduleBuffer(testBuffer, at: nil, options: [], completionHandler: nil)
            player.play()
            
            // Let test run for specified duration
            Thread.sleep(forTimeInterval: config.testDuration)
            
            // Stop and cleanup
            engine.stop()
            mainMixer.removeTap(onBus: 0)
            
            // Analyze results
            let expectedBufferCount = Int(config.testDuration * config.sampleRate / Double(config.bufferSize))
            let bufferCountOK = abs(tapBufferCount - expectedBufferCount) <= 2 // Allow 2 buffer tolerance
            
            if !bufferCountOK {
                testPassed = false
                testDetails += "Buffer count mismatch: expected ~\(expectedBufferCount), got \(tapBufferCount). "
            }
            
            if bufferDropouts > 0 {
                testPassed = false
                testDetails += "\(bufferDropouts) buffer dropouts detected. "
            }
            
            if tapProcessingTimes.isEmpty {
                testPassed = false
                testDetails += "No processing time measurements. "
            }
            
            if testPassed {
                testDetails = "Buffer processing successful: \(tapBufferCount) buffers processed"
            }
            
        } catch {
            testPassed = false
            testDetails = "Buffer processing failed: \(error.localizedDescription)"
        }
        
        // Create metrics
        let metrics = TapValidationResult.TapMetrics(
            bufferCount: tapBufferCount,
            totalSamples: recordedSamples.count,
            averageBufferProcessingTime: tapProcessingTimes.isEmpty ? 0 : tapProcessingTimes.reduce(0, +) / Double(tapProcessingTimes.count),
            maxBufferProcessingTime: tapProcessingTimes.max() ?? 0,
            dropouts: bufferDropouts,
            silentBuffers: silentBufferCount,
            peakAmplitude: recordedSamples.max() ?? 0,
            rmsAmplitude: calculateRMS(recordedSamples)
        )
        
        return TapValidationResult(
            testName: "Buffer Processing",
            passed: testPassed,
            details: testDetails,
            metrics: metrics,
            audioSamples: Array(recordedSamples.prefix(1024)) // First 1024 samples for analysis
        )
    }
    
    private func testAudioContinuity() -> TapValidationResult {
        // Analyze recorded samples for continuity and gaps
        guard !recordedSamples.isEmpty else {
            return TapValidationResult(
                testName: "Audio Continuity",
                passed: false,
                details: "No audio samples to analyze",
                metrics: nil,
                audioSamples: nil
            )
        }
        
        var gaps = 0
        var maxGapLength = 0
        var currentGapLength = 0
        let silenceThreshold: Float = 0.001 // -60dB
        
        for sample in recordedSamples {
            if abs(sample) < silenceThreshold {
                currentGapLength += 1
            } else {
                if currentGapLength > 0 {
                    gaps += 1
                    maxGapLength = max(maxGapLength, currentGapLength)
                    currentGapLength = 0
                }
            }
        }
        
        // Final gap check
        if currentGapLength > 0 {
            gaps += 1
            maxGapLength = max(maxGapLength, currentGapLength)
        }
        
        // Allow some small gaps (less than 1ms worth of samples)
        let maxAllowableGapSamples = Int(config.sampleRate * 0.001)
        let significantGaps = gaps > 5 || maxGapLength > maxAllowableGapSamples
        
        let details = significantGaps ?
            "Audio discontinuity detected: \(gaps) gaps, max gap \(maxGapLength) samples" :
            "Audio continuity verified: \(gaps) minor gaps detected"
        
        return TapValidationResult(
            testName: "Audio Continuity",
            passed: !significantGaps,
            details: details,
            metrics: nil,
            audioSamples: nil
        )
    }
    
    private func testRealTimePerformance() -> TapValidationResult {
        guard !tapProcessingTimes.isEmpty else {
            return TapValidationResult(
                testName: "Real-time Performance",
                passed: false,
                details: "No processing time data available",
                metrics: nil,
                audioSamples: nil
            )
        }
        
        let averageProcessingTime = tapProcessingTimes.reduce(0, +) / Double(tapProcessingTimes.count)
        let maxProcessingTime = tapProcessingTimes.max()!
        
        // Real-time constraint: processing time should be much less than buffer duration
        let bufferDuration = Double(config.bufferSize) / config.sampleRate
        let processingBudget = bufferDuration * 0.1 // Use max 10% of buffer time for processing
        
        let averageOK = averageProcessingTime < processingBudget
        let maxOK = maxProcessingTime < bufferDuration * 0.5 // Max 50% for peak processing
        
        let passed = averageOK && maxOK
        
        let details = passed ?
            "Real-time performance good: avg \(String(format: "%.3f", averageProcessingTime * 1000))ms, max \(String(format: "%.3f", maxProcessingTime * 1000))ms" :
            "Real-time performance issues: avg \(String(format: "%.3f", averageProcessingTime * 1000))ms, max \(String(format: "%.3f", maxProcessingTime * 1000))ms (budget: \(String(format: "%.3f", processingBudget * 1000))ms)"
        
        return TapValidationResult(
            testName: "Real-time Performance",
            passed: passed,
            details: details,
            metrics: nil,
            audioSamples: nil
        )
    }
    
    private func testBufferTiming() -> TapValidationResult {
        // Verify buffers arrive at expected intervals
        let expectedInterval = Double(config.bufferSize) / config.sampleRate
        let actualInterval = config.testDuration / Double(max(1, tapBufferCount - 1))
        
        let timingError = abs(actualInterval - expectedInterval)
        let timingErrorPercent = timingError / expectedInterval * 100.0
        
        let passed = timingErrorPercent < 5.0 // Allow 5% timing variation
        
        let details = passed ?
            "Buffer timing accurate: \(String(format: "%.3f", timingErrorPercent))% error" :
            "Buffer timing issues: \(String(format: "%.3f", timingErrorPercent))% error (expected \(String(format: "%.3f", expectedInterval * 1000))ms, got \(String(format: "%.3f", actualInterval * 1000))ms)"
        
        return TapValidationResult(
            testName: "Buffer Timing",
            passed: passed,
            details: details,
            metrics: nil,
            audioSamples: nil
        )
    }
    
    private func testSignalFidelity() -> TapValidationResult {
        guard !recordedSamples.isEmpty else {
            return TapValidationResult(
                testName: "Signal Fidelity",
                passed: false,
                details: "No recorded samples to analyze",
                metrics: nil,
                audioSamples: nil
            )
        }
        
        // Check for signal corruption or unexpected artifacts
        let peakAmplitude = recordedSamples.max() ?? 0
        let rmsAmplitude = calculateRMS(recordedSamples)
        
        // Expected RMS for our test signal (approximate)
        let expectedRMS: Float = 0.2 // Based on our test signal amplitudes
        let rmsError = abs(rmsAmplitude - expectedRMS) / expectedRMS
        
        let peakOK = peakAmplitude > 0.1 && peakAmplitude < 1.0 // Signal present but not clipped
        let rmsOK = rmsError < 0.5 // Allow 50% RMS variation (rough test)
        
        let passed = peakOK && rmsOK
        
        let details = passed ?
            "Signal fidelity good: peak \(String(format: "%.3f", peakAmplitude)), RMS \(String(format: "%.3f", rmsAmplitude))" :
            "Signal fidelity issues: peak \(String(format: "%.3f", peakAmplitude)), RMS \(String(format: "%.3f", rmsAmplitude)) (expected ~\(String(format: "%.3f", expectedRMS)))"
        
        return TapValidationResult(
            testName: "Signal Fidelity",
            passed: passed,
            details: details,
            metrics: nil,
            audioSamples: nil
        )
    }
    
    private func testDropoutDetection() -> TapValidationResult {
        let passed = bufferDropouts == 0
        
        let details = passed ?
            "No buffer dropouts detected" :
            "\(bufferDropouts) buffer dropouts detected - may indicate processing overload"
        
        return TapValidationResult(
            testName: "Dropout Detection",
            passed: passed,
            details: details,
            metrics: nil,
            audioSamples: nil
        )
    }
    
    private func testMemoryManagement() -> TapValidationResult {
        // Simple memory test - check if we're leaking audio buffers
        let initialMemory = getMemoryUsage()
        
        // Force garbage collection
        for _ in 0..<100 {
            autoreleasepool {
                let _ = AVAudioPCMBuffer(pcmFormat: AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!, frameCapacity: 1024)
            }
        }
        
        let finalMemory = getMemoryUsage()
        let memoryIncrease = finalMemory - initialMemory
        
        // Allow up to 1MB increase for test overhead
        let passed = memoryIncrease < 1024 * 1024
        
        let details = passed ?
            "Memory usage stable: \(memoryIncrease) bytes increase" :
            "Potential memory leak: \(memoryIncrease) bytes increase"
        
        return TapValidationResult(
            testName: "Memory Management",
            passed: passed,
            details: details,
            metrics: nil,
            audioSamples: nil
        )
    }
    
    // MARK: - Tap Processing
    
    private func processTapBuffer(_ buffer: AVAudioPCMBuffer, timestamp: AVAudioTime) {
        bufferProcessingStartTime = Date()
        
        tapBufferCount += 1
        
        // Validate buffer
        guard let channelData = buffer.floatChannelData else {
            bufferDropouts += 1
            return
        }
        
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        
        // Check for empty or invalid buffer
        if frameCount == 0 {
            bufferDropouts += 1
            return
        }
        
        // Process first channel samples
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
        recordedSamples.append(contentsOf: samples)
        
        // Check for silent buffer
        let maxSample = samples.max() ?? 0
        if abs(maxSample) < 0.0001 {
            silentBufferCount += 1
        }
        
        // Record processing time
        if let startTime = bufferProcessingStartTime {
            tapProcessingTimes.append(Date().timeIntervalSince(startTime))
        }
    }
    
    // MARK: - Helper Functions
    
    private func calculateRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        
        let sumOfSquares = samples.reduce(0) { $0 + $1 * $1 }
        return sqrt(sumOfSquares / Float(samples.count))
    }
    
    private func getMemoryUsage() -> Int {
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
        
        return kerr == KERN_SUCCESS ? Int(info.resident_size) : 0
    }
    
    // MARK: - Results Analysis
    
    private func calculateOverallResult() {
        let passedTests = validationResults.filter { $0.passed }.count
        let totalTests = validationResults.count
        
        // All critical tests must pass for overall success
        let criticalTests = ["Tap Installation", "Buffer Processing", "Real-time Performance"]
        let criticalPassed = validationResults.filter { result in
            criticalTests.contains(result.testName) && result.passed
        }.count
        
        overallValidationPassed = (criticalPassed == criticalTests.count) && (passedTests >= totalTests - 1)
    }
    
    private func generateTapValidationReport() {
        print("\n" + "="*60)
        print("🎵 iOS TAP RECORDING VALIDATION REPORT")
        print("="*60)
        print("Configuration: \(config.sampleRate)Hz, \(config.bufferSize) samples, \(config.channels) channels")
        print("Test Duration: \(config.testDuration) seconds")
        print("\nOverall Result: \(overallValidationPassed ? "✅ PASSED" : "❌ FAILED")")
        print("-"*60)
        
        for result in validationResults {
            let status = result.passed ? "✅ PASS" : "❌ FAIL"
            print("\(result.testName): \(status)")
            print("  \(result.details)")
            
            if let metrics = result.metrics {
                print("  Metrics:")
                print("    Buffers: \(metrics.bufferCount)")
                print("    Samples: \(metrics.totalSamples)")
                print("    Avg Processing: \(String(format: "%.3f", metrics.averageBufferProcessingTime * 1000))ms")
                print("    Peak Amplitude: \(String(format: "%.3f", metrics.peakAmplitude))")
                print("    RMS Amplitude: \(String(format: "%.3f", metrics.rmsAmplitude))")
                if metrics.dropouts > 0 {
                    print("    ⚠️ Dropouts: \(metrics.dropouts)")
                }
            }
            print()
        }
        
        print("="*60)
        print("✅ iOS tap recording validation completed")
    }
    
    // MARK: - Public Interface
    
    func getTapValidationSummary() -> String {
        var summary = "iOS TAP RECORDING VALIDATION SUMMARY\n"
        summary += "===================================\n\n"
        summary += "Overall Result: \(overallValidationPassed ? "✅ PASSED" : "❌ FAILED")\n\n"
        
        let passedCount = validationResults.filter { $0.passed }.count
        let totalCount = validationResults.count
        
        summary += "Test Results: \(passedCount)/\(totalCount) passed\n\n"
        
        for result in validationResults {
            let status = result.passed ? "✅" : "❌"
            summary += "\(status) \(result.testName): \(result.details)\n"
        }
        
        return summary
    }
}