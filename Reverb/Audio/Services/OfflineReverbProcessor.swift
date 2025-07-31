import Foundation
import AVFoundation
import OSLog

/// Offline reverb processor inspired by AD 480 RE offline processing capabilities
/// Processes audio files through reverb engine faster than real-time using AVAudioEngine.manualRenderingMode
class OfflineReverbProcessor: ObservableObject {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Reverb", category: "OfflineProcessor")
    
    // MARK: - Processing State
    @Published var isProcessing = false
    @Published var processingProgress: Double = 0.0
    @Published var processingSpeed: Double = 1.0 // Multiplier vs real-time
    @Published var currentFile: String = ""
    
    // MARK: - Processing Options
    enum ProcessingMode: String, CaseIterable {
        case wetOnly = "wet"
        case dryOnly = "dry"
        case mixOnly = "mix"
        case wetDrySeparate = "wet_dry"
        
        var displayName: String {
            switch self {
            case .wetOnly: return "Wet seulement"
            case .dryOnly: return "Dry seulement"
            case .mixOnly: return "Mix wet/dry"
            case .wetDrySeparate: return "Wet + Dry séparés"
            }
        }
        
        var description: String {
            switch self {
            case .wetOnly: return "Signal de réverbération isolé"
            case .dryOnly: return "Signal direct inchangé"
            case .mixOnly: return "Mix wet/dry selon réglages"
            case .wetDrySeparate: return "Deux fichiers séparés"
            }
        }
    }
    
    enum OutputFormat: String, CaseIterable {
        case wav = "wav"
        case aiff = "aiff"
        case caf = "caf"
        
        var displayName: String {
            switch self {
            case .wav: return "WAV (Standard)"
            case .aiff: return "AIFF (Apple)"
            case .caf: return "CAF (Core Audio)"
            }
        }
        
        var fileType: AVFileType {
            switch self {
            case .wav: return .wav
            case .aiff: return .aiff
            case .caf: return .caf
            }
        }
    }
    
    // MARK: - Processing Configuration
    struct ProcessingSettings {
        var reverbPreset: ReverbPreset = .cathedral
        var customSettings: CustomReverbSettings = .default
        var wetDryMix: Float = 0.5
        var inputGain: Float = 1.0
        var outputGain: Float = 1.0
        var mode: ProcessingMode = .mixOnly
        var outputFormat: OutputFormat = .wav
        var sampleRate: Double = 48000
        var bitDepth: Int = 24
        var useHighQuality: Bool = true
    }
    
    // MARK: - Audio Components
    private var offlineEngine: AVAudioEngine?
    private var reverbUnit: AVAudioUnitReverb?
    private var reverbBridge: ReverbBridge?
    private var playerNode: AVAudioPlayerNode?
    
    // MARK: - Processing State
    private var processingTask: Task<Void, Error>?
    private var startTime: Date?
    private var totalFrames: AVAudioFramePosition = 0
    private var processedFrames: AVAudioFramePosition = 0
    
    // MARK: - Initialization
    init() {
        logger.info("🎛️ OfflineReverbProcessor initialized")
    }
    
    // MARK: - File Processing
    func processAudioFile(
        inputURL: URL,
        outputDirectory: URL,
        settings: ProcessingSettings
    ) async throws -> [String: URL] {
        
        guard !isProcessing else {
            throw ProcessingError.processingInProgress
        }
        
        logger.info("🔄 Starting offline processing: \(inputURL.lastPathComponent)")
        
        // Update state
        DispatchQueue.main.async {
            self.isProcessing = true
            self.processingProgress = 0.0
            self.currentFile = inputURL.lastPathComponent
            self.startTime = Date()
        }
        
        do {
            let results = try await performOfflineProcessing(
                inputURL: inputURL,
                outputDirectory: outputDirectory,
                settings: settings
            )
            
            // Processing completed successfully
            DispatchQueue.main.async {
                self.isProcessing = false
                self.processingProgress = 1.0
                self.currentFile = ""
            }
            
            logger.info("✅ Offline processing completed: \(results.count) file(s)")
            return results
            
        } catch {
            // Processing failed
            DispatchQueue.main.async {
                self.isProcessing = false
                self.processingProgress = 0.0
                self.currentFile = ""
            }
            
            logger.error("❌ Offline processing failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    private func performOfflineProcessing(
        inputURL: URL,
        outputDirectory: URL,
        settings: ProcessingSettings
    ) async throws -> [String: URL] {
        
        // Load input file
        let inputFile = try AVAudioFile(forReading: inputURL)
        let inputFormat = inputFile.processingFormat
        
        logger.info("📂 Input file: \(inputFormat.sampleRate) Hz, \(inputFormat.channelCount) ch, \(inputFile.length) frames")
        
        // Create processing format (optimal for offline processing)
        let processingFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: settings.sampleRate,
            channels: inputFormat.channelCount,
            interleaved: false
        )!
        
        // Update total frames for progress tracking
        totalFrames = inputFile.length
        processedFrames = 0
        
        var results: [String: URL] = [:]
        
        // Process based on mode
        switch settings.mode {
        case .wetOnly:
            let wetURL = createOutputURL(inputURL: inputURL, outputDirectory: outputDirectory, suffix: "wet", format: settings.outputFormat)
            try await processWithMode(inputFile: inputFile, outputURL: wetURL, settings: settings, mode: .wetOnly, processingFormat: processingFormat)
            results["wet"] = wetURL
            
        case .dryOnly:
            let dryURL = createOutputURL(inputURL: inputURL, outputDirectory: outputDirectory, suffix: "dry", format: settings.outputFormat)
            try await processWithMode(inputFile: inputFile, outputURL: dryURL, settings: settings, mode: .dryOnly, processingFormat: processingFormat)
            results["dry"] = dryURL
            
        case .mixOnly:
            let mixURL = createOutputURL(inputURL: inputURL, outputDirectory: outputDirectory, suffix: "processed", format: settings.outputFormat)
            try await processWithMode(inputFile: inputFile, outputURL: mixURL, settings: settings, mode: .mixOnly, processingFormat: processingFormat)
            results["mix"] = mixURL
            
        case .wetDrySeparate:
            let wetURL = createOutputURL(inputURL: inputURL, outputDirectory: outputDirectory, suffix: "wet", format: settings.outputFormat)
            let dryURL = createOutputURL(inputURL: inputURL, outputDirectory: outputDirectory, suffix: "dry", format: settings.outputFormat)
            
            // Process wet and dry separately
            try await processWithMode(inputFile: inputFile, outputURL: wetURL, settings: settings, mode: .wetOnly, processingFormat: processingFormat, progressOffset: 0.0, progressScale: 0.5)
            
            // Reset for second pass
            processedFrames = 0
            try await processWithMode(inputFile: inputFile, outputURL: dryURL, settings: settings, mode: .dryOnly, processingFormat: processingFormat, progressOffset: 0.5, progressScale: 0.5)
            
            results["wet"] = wetURL
            results["dry"] = dryURL
        }
        
        return results
    }
    
    private func processWithMode(
        inputFile: AVAudioFile,
        outputURL: URL,
        settings: ProcessingSettings,
        mode: ProcessingMode,
        processingFormat: AVAudioFormat,
        progressOffset: Double = 0.0,
        progressScale: Double = 1.0
    ) async throws {
        
        logger.info("⚙️ Processing in mode: \(mode.rawValue)")
        
        // Create offline audio engine
        let engine = AVAudioEngine()
        
        // Enable manual rendering mode for offline processing
        try engine.enableManualRenderingMode(.offline, format: processingFormat, maximumFrameCount: 1024)
        
        // Create audio nodes
        let playerNode = AVAudioPlayerNode()
        let mixerNode = AVAudioMixerNode()
        let outputMixerNode = AVAudioMixerNode()
        
        // Attach nodes
        engine.attach(playerNode)
        engine.attach(mixerNode)
        engine.attach(outputMixerNode)
        
        // Create and configure reverb based on mode
        if mode == .wetOnly || mode == .mixOnly {
            let reverbUnit = AVAudioUnitReverb()
            configureReverb(reverbUnit, settings: settings)
            engine.attach(reverbUnit)
            
            if mode == .wetOnly {
                // Wet only: Input -> Reverb -> Output
                try engine.connect(playerNode, to: reverbUnit, format: processingFormat)
                try engine.connect(reverbUnit, to: outputMixerNode, format: processingFormat)
            } else {
                // Mix mode: Input -> [Direct + Reverb] -> Mix -> Output
                try engine.connect(playerNode, to: mixerNode, format: processingFormat)
                try engine.connect(playerNode, to: reverbUnit, format: processingFormat)
                try engine.connect(reverbUnit, to: mixerNode, format: processingFormat)
                try engine.connect(mixerNode, to: outputMixerNode, format: processingFormat)
                
                // Configure wet/dry mix
                mixerNode.outputVolume = 1.0
                reverbUnit.wetDryMix = settings.wetDryMix * 100
            }
        } else {
            // Dry only: Input -> Output (bypass reverb)
            try engine.connect(playerNode, to: outputMixerNode, format: processingFormat)
        }
        
        // Configure final output
        outputMixerNode.outputVolume = settings.outputGain
        
        // Connect to engine output
        try engine.connect(outputMixerNode, to: engine.mainMixerNode, format: processingFormat)
        
        // Start engine
        try engine.start()
        
        // Create output file
        let outputFile = try AVAudioFile(
            forWriting: outputURL,
            settings: createOutputSettings(format: settings.outputFormat, sampleRate: settings.sampleRate, channels: processingFormat.channelCount, bitDepth: settings.bitDepth)
        )
        
        // Schedule input file for playback
        playerNode.scheduleFile(inputFile, at: nil)
        playerNode.play()
        
        // Process audio in chunks
        let bufferSize: AVAudioFrameCount = 1024
        let buffer = AVAudioPCMBuffer(pcmFormat: processingFormat, frameCapacity: bufferSize)!
        
        let totalSamples = inputFile.length
        var processedSamples: AVAudioFramePosition = 0
        
        while processedSamples < totalSamples {
            let framesToRender = min(bufferSize, AVAudioFrameCount(totalSamples - processedSamples))
            
            // Manual rendering - this is the key for offline processing
            try engine.manualRenderingBlock(framesToRender, buffer) { (bufferToFill, frameCount) in
                bufferToFill.frameLength = frameCount
                return .success
            }
            
            // Write processed buffer to output file
            if buffer.frameLength > 0 {
                try outputFile.write(from: buffer)
                processedSamples += AVAudioFramePosition(buffer.frameLength)
                
                // Update progress
                let progress = progressOffset + (Double(processedSamples) / Double(totalSamples)) * progressScale
                DispatchQueue.main.async {
                    self.processingProgress = progress
                    self.updateProcessingSpeed()
                }
            }
            
            // Check for cancellation
            try Task.checkCancellation()
        }
        
        // Stop engine
        engine.stop()
        
        logger.info("✅ Mode \(mode.rawValue) processing completed: \(processedSamples) samples")
    }
    
    private func configureReverb(_ reverbUnit: AVAudioUnitReverb, settings: ProcessingSettings) {
        switch settings.reverbPreset {
        case .clean:
            reverbUnit.wetDryMix = 0
        case .vocalBooth:
            reverbUnit.loadFactoryPreset(.smallRoom)
            reverbUnit.wetDryMix = 100
        case .studio:
            reverbUnit.loadFactoryPreset(.mediumRoom)
            reverbUnit.wetDryMix = 100
        case .cathedral:
            reverbUnit.loadFactoryPreset(.cathedral)
            reverbUnit.wetDryMix = 100
        case .custom:
            reverbUnit.loadFactoryPreset(.mediumRoom)
            reverbUnit.wetDryMix = 100
            // Apply custom settings
            // TODO: Implement custom reverb parameter mapping
        }
        
        logger.info("🎛️ Configured reverb preset: \(settings.reverbPreset.rawValue)")
    }
    
    private func createOutputURL(inputURL: URL, outputDirectory: URL, suffix: String, format: OutputFormat) -> URL {
        let inputName = inputURL.deletingPathExtension().lastPathComponent
        let timestamp = DateFormatter().string(from: Date()).replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: ":", with: "-")
        let filename = "\(inputName)_\(suffix)_\(timestamp).\(format.rawValue)"
        return outputDirectory.appendingPathComponent(filename)
    }
    
    private func createOutputSettings(format: OutputFormat, sampleRate: Double, channels: AVAudioChannelCount, bitDepth: Int) -> [String: Any] {
        var settings: [String: Any] = [
            AVFormatIDKey: getFormatID(for: format),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
        ]
        
        if format == .wav || format == .aiff {
            settings[AVLinearPCMBitDepthKey] = bitDepth
            settings[AVLinearPCMIsFloatKey] = bitDepth == 32
            settings[AVLinearPCMIsBigEndianKey] = format == .aiff
            settings[AVLinearPCMIsNonInterleaved] = false
        }
        
        return settings
    }
    
    private func getFormatID(for format: OutputFormat) -> AudioFormatID {
        switch format {
        case .wav: return kAudioFormatLinearPCM
        case .aiff: return kAudioFormatLinearPCM
        case .caf: return kAudioFormatLinearPCM
        }
    }
    
    private func updateProcessingSpeed() {
        guard let startTime = startTime else { return }
        
        let elapsedTime = Date().timeIntervalSince(startTime)
        let audioProcessed = Double(processedFrames) / (totalFrames > 0 ? Double(totalFrames) : 1.0)
        let estimatedAudioDuration = Double(totalFrames) / 48000.0 // Assume 48kHz
        
        if elapsedTime > 0 && audioProcessed > 0 {
            let speedMultiplier = (audioProcessed * estimatedAudioDuration) / elapsedTime
            DispatchQueue.main.async {
                self.processingSpeed = speedMultiplier
            }
        }
    }
    
    // MARK: - Cancellation
    func cancelProcessing() {
        processingTask?.cancel()
        
        DispatchQueue.main.async {
            self.isProcessing = false
            self.processingProgress = 0.0
            self.currentFile = ""
            self.processingSpeed = 1.0
        }
        
        logger.info("❌ Offline processing cancelled")
    }
    
    // MARK: - Error Types
    enum ProcessingError: LocalizedError {
        case processingInProgress
        case invalidInputFile
        case outputDirectoryNotAccessible
        case engineSetupFailed
        case renderingFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .processingInProgress:
                return "Traitement déjà en cours"
            case .invalidInputFile:
                return "Fichier d'entrée invalide"
            case .outputDirectoryNotAccessible:
                return "Répertoire de sortie inaccessible"
            case .engineSetupFailed:
                return "Échec de configuration du moteur audio"
            case .renderingFailed(let message):
                return "Échec du rendu: \(message)"
            }
        }
    }
    
    // MARK: - Utility Methods
    func getSupportedInputFormats() -> [String] {
        return ["wav", "aiff", "caf", "mp3", "m4a", "aac"]
    }
    
    func validateInputFile(_ url: URL) -> Bool {
        let fileExtension = url.pathExtension.lowercased()
        return getSupportedInputFormats().contains(fileExtension)
    }
    
    func estimateProcessingTime(for inputURL: URL) -> TimeInterval? {
        do {
            let file = try AVAudioFile(forReading: inputURL)
            let duration = Double(file.length) / file.fileFormat.sampleRate
            
            // Estimate based on typical offline processing speed (usually 5-20x faster than real-time)
            let estimatedSpeed = 10.0 // Conservative estimate
            return duration / estimatedSpeed
        } catch {
            logger.error("❌ Failed to estimate processing time: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Progress Reporting
    var progressDescription: String {
        if isProcessing {
            let percentage = Int(processingProgress * 100)
            let speedText = String(format: "%.1fx", processingSpeed)
            return "\(percentage)% - \(speedText) vitesse"
        }
        return "Prêt"
    }
    
    deinit {
        cancelProcessing()
        logger.info("🗑️ OfflineReverbProcessor deinitialized")
    }
}