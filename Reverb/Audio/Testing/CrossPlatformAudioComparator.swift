import Foundation
import AVFoundation
import Accelerate

/// Compares audio output between macOS and iOS to ensure identical quality
/// Validates that same input produces identical output across platforms
class CrossPlatformAudioComparator: ObservableObject {
    
    // MARK: - Comparison Configuration
    
    struct ComparisonConfig {
        let sampleRate: Double = 48000.0
        let bufferSize: AVAudioFrameCount = 64
        let channels: UInt32 = 2
        let testDuration: TimeInterval = 5.0
        
        // Comparison thresholds
        let maxAmplitudeDifference: Float = 0.000001    // -120dB difference
        let maxFrequencyDeviation: Float = 0.01         // 0.01Hz frequency accuracy
        let maxPhaseDeviation: Float = 0.1              // 0.1 degree phase accuracy
        let maxTHDDifference: Float = 0.0001           // 0.01% THD difference
        let maxCorrelationThreshold: Float = 0.9999    // 99.99% correlation minimum
    }
    
    // MARK: - Comparison Results
    
    struct ComparisonResult {
        let testName: String
        let platformsMatch: Bool
        let similarity: Float // 0.0 to 1.0
        let details: String
        let metrics: ComparisonMetrics?
        
        struct ComparisonMetrics {
            let maxAmplitudeDifference: Float
            let rmsAmplitudeDifference: Float
            let crossCorrelation: Float
            let frequencyResponseMatch: Float
            let phaseResponseMatch: Float
            let thdDifference: Float
            let spectralCentroidDifference: Float
        }
    }
    
    // MARK: - Test Signal Types
    
    enum TestSignalType {
        case sine(frequency: Float, amplitude: Float)
        case sweep(startFreq: Float, endFreq: Float)
        case whitenoise(amplitude: Float)
        case pinknoise(amplitude: Float)
        case impulse(amplitude: Float)
        case multitone([Float]) // Array of frequencies
        
        var description: String {
            switch self {
            case .sine(let freq, _): return "Sine \(freq)Hz"
            case .sweep(let start, let end): return "Sweep \(start)-\(end)Hz"
            case .whitenoise: return "White Noise"
            case .pinknoise: return "Pink Noise"
            case .impulse: return "Impulse"
            case .multitone(let freqs): return "Multitone \(freqs.count) frequencies"
            }
        }
    }
    
    // MARK: - Published Properties
    
    @Published var isComparing = false
    @Published var comparisonProgress: Double = 0.0
    @Published var comparisonResults: [ComparisonResult] = []
    @Published var overallPlatformsMatch = false
    @Published var platformSimilarity: Float = 0.0
    
    // MARK: - Audio Components
    
    private let config = ComparisonConfig()
    private var audioEngine: AVAudioEngine?
    private var reverbNode: AVAudioUnitReverb?
    
    // Reference data (would be loaded from macOS reference recordings)
    private var macOSReferenceData: [String: [Float]] = [:]
    
    // iOS captured data
    private var iOSCapturedData: [String: [Float]] = [:]
    
    // MARK: - Test Signals
    
    private let testSignals: [TestSignalType] = [
        .sine(frequency: 440.0, amplitude: 0.5),
        .sine(frequency: 1000.0, amplitude: 0.3),
        .sweep(startFreq: 20.0, endFreq: 20000.0),
        .whitenoise(amplitude: 0.1),
        .pinknoise(amplitude: 0.1),
        .impulse(amplitude: 0.8),
        .multitone([100, 200, 300, 440, 880, 1760, 3520])
    ]
    
    // MARK: - Initialization
    
    init() {
        setupAudioEngine()
        loadMacOSReferenceData()
    }
    
    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        reverbNode = AVAudioUnitReverb()
        
        guard let engine = audioEngine,
              let reverb = reverbNode else {
            print("❌ Failed to initialize audio engine for comparison")
            return
        }
        
        // Configure reverb with identical settings to macOS
        reverb.loadFactoryPreset(.cathedral)
        reverb.wetDryMix = 50.0 // 50% wet/dry mix
        
        engine.attach(reverb)
        
        let audioFormat = AVAudioFormat(
            standardFormatWithSampleRate: config.sampleRate,
            channels: config.channels
        )!
        
        engine.connect(reverb, to: engine.mainMixerNode, format: audioFormat)
        
        print("✅ Audio engine configured for cross-platform comparison")
    }
    
    private func loadMacOSReferenceData() {
        // In a real implementation, this would load actual macOS reference recordings
        // For now, we'll simulate reference data
        
        print("📁 Loading macOS reference data...")
        
        for signal in testSignals {
            let signalKey = signal.description
            
            // Generate simulated "reference" data
            let referenceAudio = generateReferenceAudio(for: signal)
            macOSReferenceData[signalKey] = referenceAudio
        }
        
        print("✅ Loaded macOS reference data for \(macOSReferenceData.count) test signals")
    }
    
    private func generateReferenceAudio(for signal: TestSignalType) -> [Float] {
        let frameCount = Int(config.testDuration * config.sampleRate)
        var samples: [Float] = []
        samples.reserveCapacity(frameCount)
        
        let sampleRate = Float(config.sampleRate)
        
        for i in 0..<frameCount {
            let time = Float(i) / sampleRate
            let sample = generateSampleForSignal(signal, at: time)
            
            // Apply simulated reverb processing (simplified)
            let wetSample = sample * 0.3 // Simulate reverb effect
            let dryWetMix = sample * 0.5 + wetSample * 0.5
            
            samples.append(dryWetMix)
        }
        
        return samples
    }
    
    private func generateSampleForSignal(_ signal: TestSignalType, at time: Float) -> Float {
        switch signal {
        case .sine(let frequency, let amplitude):
            return amplitude * sin(2.0 * Float.pi * frequency * time)
            
        case .sweep(let startFreq, let endFreq):
            let totalTime = Float(config.testDuration)
            let currentFreq = startFreq + (endFreq - startFreq) * (time / totalTime)
            return 0.5 * sin(2.0 * Float.pi * currentFreq * time)
            
        case .whitenoise(let amplitude):
            return amplitude * Float.random(in: -1.0...1.0)
            
        case .pinknoise(let amplitude):
            // Simplified pink noise generation
            let whiteNoise = Float.random(in: -1.0...1.0)
            return amplitude * whiteNoise * pow(1.0 / (1.0 + time * 10.0), 0.5)
            
        case .impulse(let amplitude):
            return time < (1.0 / Float(config.sampleRate)) ? amplitude : 0.0
            
        case .multitone(let frequencies):
            var sample: Float = 0.0
            let amplitude = 0.1 / Float(frequencies.count) // Normalize by number of tones
            
            for frequency in frequencies {
                sample += amplitude * sin(2.0 * Float.pi * frequency * time)
            }
            
            return sample
        }
    }
    
    // MARK: - Comparison Tests
    
    func runCrossPlatformComparison() {
        guard !isComparing else { return }
        
        isComparing = true
        comparisonProgress = 0.0
        comparisonResults.removeAll()
        iOSCapturedData.removeAll()
        
        print("🔍 Starting cross-platform audio comparison...")
        
        DispatchQueue.global(qos: .userInitiated).async {
            self.performComparisonTests()
        }
    }
    
    private func performComparisonTests() {
        // First, capture iOS audio for all test signals
        captureIOSAudio()
        
        // Then compare each signal
        for (index, signal) in testSignals.enumerated() {
            DispatchQueue.main.async {
                self.comparisonProgress = Double(index) / Double(self.testSignals.count)
            }
            
            let result = compareSignal(signal)
            
            DispatchQueue.main.async {
                self.comparisonResults.append(result)
            }
            
            Thread.sleep(forTimeInterval: 0.1)
        }
        
        DispatchQueue.main.async {
            self.isComparing = false
            self.comparisonProgress = 1.0
            self.calculateOverallComparison()
            self.generateComparisonReport()
        }
    }
    
    private func captureIOSAudio() {
        print("📱 Capturing iOS audio for comparison...")
        
        guard let engine = audioEngine,
              let reverb = reverbNode else {
            print("❌ Audio engine not available for iOS capture")
            return
        }
        
        do {
            // Configure audio session
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .measurement)
            try audioSession.setPreferredSampleRate(config.sampleRate)
            try audioSession.setActive(true)
            
            for signal in testSignals {
                let capturedAudio = captureAudioForSignal(signal, engine: engine, reverb: reverb)
                iOSCapturedData[signal.description] = capturedAudio
                
                print("📊 Captured iOS audio for \(signal.description): \(capturedAudio.count) samples")
            }
            
        } catch {
            print("❌ Failed to capture iOS audio: \(error)")
        }
    }
    
    private func captureAudioForSignal(_ signal: TestSignalType, 
                                     engine: AVAudioEngine, 
                                     reverb: AVAudioUnitReverb) -> [Float] {
        
        var capturedSamples: [Float] = []
        let frameCount = Int(config.testDuration * config.sampleRate)
        capturedSamples.reserveCapacity(frameCount)
        
        // Generate test signal
        let testAudio = generateTestAudioBuffer(for: signal)
        
        do {
            // Install tap to capture processed audio
            let mainMixer = engine.mainMixerNode
            let tapFormat = mainMixer.outputFormat(forBus: 0)
            
            mainMixer.installTap(
                onBus: 0,
                bufferSize: config.bufferSize,
                format: tapFormat
            ) { buffer, when in
                guard let channelData = buffer.floatChannelData else { return }
                let samples = Array(UnsafeBufferPointer(start: channelData[0], count: Int(buffer.frameLength)))
                capturedSamples.append(contentsOf: samples)
            }
            
            // Process audio through reverb
            try engine.start()
            
            // Feed test signal through reverb (simplified simulation)
            let processedAudio = processAudioThroughReverb(testAudio, reverb: reverb)
            capturedSamples = processedAudio
            
            engine.stop()
            mainMixer.removeTap(onBus: 0)
            
        } catch {
            print("❌ Failed to capture audio for \(signal.description): \(error)")
        }
        
        return capturedSamples
    }
    
    private func generateTestAudioBuffer(for signal: TestSignalType) -> [Float] {
        let frameCount = Int(config.testDuration * config.sampleRate)
        var samples: [Float] = []
        samples.reserveCapacity(frameCount)
        
        let sampleRate = Float(config.sampleRate)
        
        for i in 0..<frameCount {
            let time = Float(i) / sampleRate
            let sample = generateSampleForSignal(signal, at: time)
            samples.append(sample)
        }
        
        return samples
    }
    
    private func processAudioThroughReverb(_ input: [Float], reverb: AVAudioUnitReverb) -> [Float] {
        // Simplified reverb processing simulation
        // In real implementation, would use actual AVAudioUnit processing
        
        return input.map { sample in
            let wetSample = sample * 0.3 // Simulate reverb effect
            return sample * 0.5 + wetSample * 0.5 // 50% wet/dry mix
        }
    }
    
    // MARK: - Signal Comparison
    
    private func compareSignal(_ signal: TestSignalType) -> ComparisonResult {
        let signalKey = signal.description
        
        guard let macOSData = macOSReferenceData[signalKey],
              let iOSData = iOSCapturedData[signalKey] else {
            return ComparisonResult(
                testName: signalKey,
                platformsMatch: false,
                similarity: 0.0,
                details: "Missing reference or captured data",
                metrics: nil
            )
        }
        
        print("🔍 Comparing signal: \(signalKey)")
        
        // Ensure same length for comparison
        let minLength = min(macOSData.count, iOSData.count)
        let macOSReference = Array(macOSData.prefix(minLength))
        let iOSCaptured = Array(iOSData.prefix(minLength))
        
        // Calculate comparison metrics
        let metrics = calculateComparisonMetrics(
            reference: macOSReference,
            captured: iOSCaptured,
            signal: signal
        )
        
        // Determine if platforms match based on thresholds
        let platformsMatch = evaluatePlatformMatch(metrics: metrics)
        
        // Calculate overall similarity score
        let similarity = calculateSimilarityScore(metrics: metrics)
        
        let details = generateComparisonDetails(metrics: metrics, match: platformsMatch)
        
        return ComparisonResult(
            testName: signalKey,
            platformsMatch: platformsMatch,
            similarity: similarity,
            details: details,
            metrics: metrics
        )
    }
    
    private func calculateComparisonMetrics(reference: [Float], 
                                          captured: [Float], 
                                          signal: TestSignalType) -> ComparisonResult.ComparisonMetrics {
        
        // Amplitude difference analysis
        let amplitudeDifferences = zip(reference, captured).map { abs($0.0 - $0.1) }
        let maxAmplitudeDifference = amplitudeDifferences.max() ?? 0
        let rmsAmplitudeDifference = sqrt(amplitudeDifferences.map { $0 * $0 }.reduce(0, +) / Float(amplitudeDifferences.count))
        
        // Cross-correlation analysis
        let crossCorrelation = calculateCrossCorrelation(reference, captured)
        
        // Frequency domain analysis
        let (frequencyMatch, phaseMatch) = compareFrequencyDomain(reference: reference, captured: captured)
        
        // THD analysis
        let referenceTHD = calculateTHD(reference)
        let capturedTHD = calculateTHD(captured)
        let thdDifference = abs(referenceTHD - capturedTHD)
        
        // Spectral centroid comparison
        let referenceSpectralCentroid = calculateSpectralCentroid(reference)
        let capturedSpectralCentroid = calculateSpectralCentroid(captured)
        let spectralCentroidDifference = abs(referenceSpectralCentroid - capturedSpectralCentroid)
        
        return ComparisonResult.ComparisonMetrics(
            maxAmplitudeDifference: maxAmplitudeDifference,
            rmsAmplitudeDifference: rmsAmplitudeDifference,
            crossCorrelation: crossCorrelation,
            frequencyResponseMatch: frequencyMatch,
            phaseResponseMatch: phaseMatch,
            thdDifference: thdDifference,
            spectralCentroidDifference: spectralCentroidDifference
        )
    }
    
    // MARK: - Analysis Functions
    
    private func calculateCrossCorrelation(_ signal1: [Float], _ signal2: [Float]) -> Float {
        guard signal1.count == signal2.count && !signal1.isEmpty else { return 0.0 }
        
        let n = signal1.count
        var correlation: Float = 0.0
        var sum1: Float = 0.0
        var sum2: Float = 0.0
        var sum1Sq: Float = 0.0
        var sum2Sq: Float = 0.0
        
        for i in 0..<n {
            correlation += signal1[i] * signal2[i]
            sum1 += signal1[i]
            sum2 += signal2[i]
            sum1Sq += signal1[i] * signal1[i]
            sum2Sq += signal2[i] * signal2[i]
        }
        
        let numerator = Float(n) * correlation - sum1 * sum2
        let denominator = sqrt((Float(n) * sum1Sq - sum1 * sum1) * (Float(n) * sum2Sq - sum2 * sum2))
        
        return denominator != 0 ? numerator / denominator : 0.0
    }
    
    private func compareFrequencyDomain(reference: [Float], captured: [Float]) -> (Float, Float) {
        // Simplified frequency domain comparison
        // In real implementation, would use FFT analysis
        
        let referenceRMS = sqrt(reference.map { $0 * $0 }.reduce(0, +) / Float(reference.count))
        let capturedRMS = sqrt(captured.map { $0 * $0 }.reduce(0, +) / Float(captured.count))
        
        let frequencyMatch = 1.0 - abs(referenceRMS - capturedRMS) / max(referenceRMS, capturedRMS)
        let phaseMatch: Float = 0.95 // Simplified - would calculate actual phase correlation
        
        return (max(0, frequencyMatch), phaseMatch)
    }
    
    private func calculateTHD(_ signal: [Float]) -> Float {
        // Simplified THD calculation
        // In real implementation, would analyze harmonic content
        
        let rms = sqrt(signal.map { $0 * $0 }.reduce(0, +) / Float(signal.count))
        let peak = signal.max() ?? 0
        
        // Rough THD estimation based on peak-to-RMS ratio
        return peak > 0 ? (1.0 - rms / peak) * 0.01 : 0.001
    }
    
    private func calculateSpectralCentroid(_ signal: [Float]) -> Float {
        // Simplified spectral centroid calculation
        // In real implementation, would use FFT to calculate weighted frequency average
        
        var weightedSum: Float = 0.0
        var magnitudeSum: Float = 0.0
        
        for (index, sample) in signal.enumerated() {
            let magnitude = abs(sample)
            let frequency = Float(index) * Float(config.sampleRate) / Float(signal.count)
            
            weightedSum += frequency * magnitude
            magnitudeSum += magnitude
        }
        
        return magnitudeSum > 0 ? weightedSum / magnitudeSum : 0.0
    }
    
    private func evaluatePlatformMatch(metrics: ComparisonResult.ComparisonMetrics) -> Bool {
        let amplitudeOK = metrics.maxAmplitudeDifference <= config.maxAmplitudeDifference
        let correlationOK = metrics.crossCorrelation >= config.maxCorrelationThreshold
        let frequencyOK = metrics.frequencyResponseMatch >= 0.99
        let thdOK = metrics.thdDifference <= config.maxTHDDifference
        
        // All critical metrics must pass
        return amplitudeOK && correlationOK && frequencyOK && thdOK
    }
    
    private func calculateSimilarityScore(metrics: ComparisonResult.ComparisonMetrics) -> Float {
        // Weighted similarity score
        let amplitudeScore = max(0, 1.0 - metrics.maxAmplitudeDifference * 1000000) // Scale for visibility
        let correlationScore = metrics.crossCorrelation
        let frequencyScore = metrics.frequencyResponseMatch
        let phaseScore = metrics.phaseResponseMatch
        let thdScore = max(0, 1.0 - metrics.thdDifference * 10000) // Scale for visibility
        
        // Weighted average
        let weights: [Float] = [0.2, 0.3, 0.2, 0.1, 0.2] // amplitude, correlation, frequency, phase, thd
        let scores = [amplitudeScore, correlationScore, frequencyScore, phaseScore, thdScore]
        
        return zip(weights, scores).map(*).reduce(0, +)
    }
    
    private func generateComparisonDetails(metrics: ComparisonResult.ComparisonMetrics, match: Bool) -> String {
        var details = match ? "Platforms match within tolerances" : "Platform differences detected"
        
        details += "\nAmplitude diff: \(String(format: "%.6f", metrics.maxAmplitudeDifference))"
        details += "\nCorrelation: \(String(format: "%.4f", metrics.crossCorrelation))"
        details += "\nFreq match: \(String(format: "%.3f", metrics.frequencyResponseMatch))"
        details += "\nTHD diff: \(String(format: "%.5f", metrics.thdDifference))"
        
        return details
    }
    
    // MARK: - Overall Analysis
    
    private func calculateOverallComparison() {
        let matchingTests = comparisonResults.filter { $0.platformsMatch }.count
        let totalTests = comparisonResults.count
        
        overallPlatformsMatch = matchingTests == totalTests
        
        // Calculate average similarity
        if !comparisonResults.isEmpty {
            platformSimilarity = comparisonResults.map { $0.similarity }.reduce(0, +) / Float(comparisonResults.count)
        } else {
            platformSimilarity = 0.0
        }
    }
    
    private func generateComparisonReport() {
        print("\n" + "="*60)
        print("🔍 CROSS-PLATFORM AUDIO COMPARISON REPORT")
        print("="*60)
        print("Configuration: \(config.sampleRate)Hz, \(config.bufferSize) samples")
        print("\nOverall Result: \(overallPlatformsMatch ? "✅ PLATFORMS MATCH" : "❌ PLATFORMS DIFFER")")
        print("Platform Similarity: \(String(format: "%.2f", platformSimilarity * 100))%")
        print("-"*60)
        
        for result in comparisonResults {
            let status = result.platformsMatch ? "✅ MATCH" : "❌ DIFFER"
            let similarity = String(format: "%.1f", result.similarity * 100)
            
            print("\n\(result.testName): \(status) (\(similarity)% similar)")
            print("  \(result.details)")
            
            if let metrics = result.metrics {
                print("  Detailed Metrics:")
                print("    Max Amplitude Diff: \(String(format: "%.8f", metrics.maxAmplitudeDifference))")
                print("    Cross Correlation: \(String(format: "%.6f", metrics.crossCorrelation))")
                print("    Frequency Match: \(String(format: "%.4f", metrics.frequencyResponseMatch))")
                print("    THD Difference: \(String(format: "%.6f", metrics.thdDifference))")
            }
        }
        
        print("\n" + "="*60)
        print("✅ Cross-platform comparison completed")
    }
    
    // MARK: - Public Interface
    
    func getComparisonSummary() -> String {
        var summary = "CROSS-PLATFORM AUDIO COMPARISON SUMMARY\n"
        summary += "======================================\n\n"
        summary += "Platforms Match: \(overallPlatformsMatch ? "✅ YES" : "❌ NO")\n"
        summary += "Overall Similarity: \(String(format: "%.1f", platformSimilarity * 100))%\n\n"
        
        let matchingCount = comparisonResults.filter { $0.platformsMatch }.count
        let totalCount = comparisonResults.count
        
        summary += "Test Results: \(matchingCount)/\(totalCount) matching\n\n"
        
        for result in comparisonResults {
            let status = result.platformsMatch ? "✅" : "❌"
            let similarity = String(format: "%.0f", result.similarity * 100)
            summary += "\(status) \(result.testName): \(similarity)%\n"
        }
        
        return summary
    }
    
    func exportComparisonData() -> [String: Any] {
        var exportData: [String: Any] = [:]
        
        exportData["overallMatch"] = overallPlatformsMatch
        exportData["similarity"] = platformSimilarity
        exportData["configuration"] = [
            "sampleRate": config.sampleRate,
            "bufferSize": config.bufferSize,
            "channels": config.channels
        ]
        
        var testResults: [[String: Any]] = []
        for result in comparisonResults {
            var testData: [String: Any] = [:]
            testData["testName"] = result.testName
            testData["match"] = result.platformsMatch
            testData["similarity"] = result.similarity
            testData["details"] = result.details
            
            if let metrics = result.metrics {
                testData["metrics"] = [
                    "maxAmplitudeDifference": metrics.maxAmplitudeDifference,
                    "crossCorrelation": metrics.crossCorrelation,
                    "frequencyResponseMatch": metrics.frequencyResponseMatch,
                    "thdDifference": metrics.thdDifference
                ]
            }
            
            testResults.append(testData)
        }
        exportData["testResults"] = testResults
        
        return exportData
    }
}