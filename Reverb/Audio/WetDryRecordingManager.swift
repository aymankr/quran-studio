import Foundation
import AVFoundation
import OSLog

/// Advanced recording manager for simultaneous wet/dry/mix recording
/// Supports professional post-production workflows with separate wet and dry tracks
class WetDryRecordingManager: ObservableObject {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Reverb", category: "WetDryRecording")
    
    // MARK: - Recording Modes
    enum RecordingMode: String, CaseIterable {
        case mixOnly = "mix"           // Current behavior - wet/dry mixed signal
        case wetOnly = "wet"           // Wet signal only (reverb output)
        case dryOnly = "dry"           // Dry signal only (direct input)
        case wetDrySeparate = "wet_dry" // Both wet and dry to separate files
        case all = "all"               // Mix + Wet + Dry (3 files)
        
        var displayName: String {
            switch self {
            case .mixOnly: return "Mix seulement"
            case .wetOnly: return "Wet seulement"
            case .dryOnly: return "Dry seulement"
            case .wetDrySeparate: return "Wet + Dry séparés"
            case .all: return "Mix + Wet + Dry"
            }
        }
        
        var description: String {
            switch self {
            case .mixOnly: return "Signal traité tel qu'entendu (comportement actuel)"
            case .wetOnly: return "Signal de réverbération isolé"
            case .dryOnly: return "Signal direct sans traitement"
            case .wetDrySeparate: return "Deux fichiers pour post-production"
            case .all: return "Trois fichiers pour flexibilité maximale"
            }
        }
        
        var fileCount: Int {
            switch self {
            case .mixOnly, .wetOnly, .dryOnly: return 1
            case .wetDrySeparate: return 2
            case .all: return 3
            }
        }
    }
    
    // MARK: - Recording State
    @Published var isRecording = false
    @Published var recordingMode: RecordingMode = .mixOnly
    @Published var recordingDuration: TimeInterval = 0
    
    // MARK: - Recording URLs
    private var currentMixURL: URL?
    private var currentWetURL: URL?
    private var currentDryURL: URL?
    
    // MARK: - Audio Components
    private weak var audioEngineService: AudioEngineService?
    private var wetDryAudioEngine: WetDryAudioEngine?
    private var recordingTimer: Timer?
    private var recordingStartTime: Date?
    
    // MARK: - Non-blocking recorders for each channel
    private var mixRecorder: NonBlockingAudioRecorder?
    private var wetRecorder: NonBlockingAudioRecorder?
    private var dryRecorder: NonBlockingAudioRecorder?
    
    // MARK: - Directory Management
    private let recordingDirectory: URL
    
    // MARK: - Format Configuration
    private let targetFormat: AVAudioFormat
    
    // MARK: - Initialization
    init(audioEngineService: AudioEngineService? = nil, useWetDryEngine: Bool = false) {
        self.audioEngineService = audioEngineService
        
        // Initialize dedicated wet/dry engine if requested
        if useWetDryEngine {
            self.wetDryAudioEngine = WetDryAudioEngine()
        }
        
        // Setup recording directory
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.recordingDirectory = documentsDir.appendingPathComponent("WetDryRecordings", isDirectory: true)
        
        // Setup optimal recording format (Float32 non-interleaved, 48kHz, 2-channel)
        self.targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48000,
            channels: 2,
            interleaved: false
        )!
        
        setupRecordingDirectory()
        logger.info("🎙️ WetDryRecordingManager initialized")
    }
    
    private func setupRecordingDirectory() {
        do {
            if !FileManager.default.fileExists(atPath: recordingDirectory.path) {
                try FileManager.default.createDirectory(
                    at: recordingDirectory,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o755]
                )
                logger.info("✅ Created wet/dry recording directory: \(self.recordingDirectory.path)")
            }
        } catch {
            logger.error("❌ Failed to setup wet/dry recording directory: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Recording Control
    func startRecording(mode: RecordingMode = .mixOnly, format: String = "wav") async throws -> [String: URL] {
        guard !isRecording else {
            throw RecordingError.recordingInProgress
        }
        
        guard let audioEngineService = audioEngineService else {
            throw RecordingError.audioEngineUnavailable
        }
        
        logger.info("🎙️ Starting wet/dry recording with mode: \(mode.rawValue)")
        
        recordingMode = mode
        let timestamp = generateTimestamp()
        var recordingURLs: [String: URL] = [:]
        
        // Create recording URLs based on mode
        switch mode {
        case .mixOnly:
            currentMixURL = createRecordingURL(for: "mix", timestamp: timestamp, format: format)
            recordingURLs["mix"] = currentMixURL!
            
        case .wetOnly:
            currentWetURL = createRecordingURL(for: "wet", timestamp: timestamp, format: format)
            recordingURLs["wet"] = currentWetURL!
            
        case .dryOnly:
            currentDryURL = createRecordingURL(for: "dry", timestamp: timestamp, format: format)
            recordingURLs["dry"] = currentDryURL!
            
        case .wetDrySeparate:
            currentWetURL = createRecordingURL(for: "wet", timestamp: timestamp, format: format)
            currentDryURL = createRecordingURL(for: "dry", timestamp: timestamp, format: format)
            recordingURLs["wet"] = currentWetURL!
            recordingURLs["dry"] = currentDryURL!
            
        case .all:
            currentMixURL = createRecordingURL(for: "mix", timestamp: timestamp, format: format)
            currentWetURL = createRecordingURL(for: "wet", timestamp: timestamp, format: format)
            currentDryURL = createRecordingURL(for: "dry", timestamp: timestamp, format: format)
            recordingURLs["mix"] = currentMixURL!
            recordingURLs["wet"] = currentWetURL!
            recordingURLs["dry"] = currentDryURL!
        }
        
        // Install taps based on recording mode
        try await installRecordingTaps(mode: mode, audioEngineService: audioEngineService)
        
        // Start recording timer
        startRecordingTimer()
        
        // Update state
        DispatchQueue.main.async {
            self.isRecording = true
            self.recordingStartTime = Date()
        }
        
        logger.info("✅ Wet/dry recording started with \(recordingURLs.count) file(s)")
        return recordingURLs
    }
    
    func stopRecording() async throws -> [String: (url: URL, duration: TimeInterval, fileSize: Int64)] {
        guard isRecording else {
            throw RecordingError.noActiveRecording
        }
        
        guard let audioEngineService = audioEngineService else {
            throw RecordingError.audioEngineUnavailable
        }
        
        logger.info("🛑 Stopping wet/dry recording")
        
        // Stop recording timer
        stopRecordingTimer()
        
        // Remove taps and get statistics
        let tapStats = try await removeRecordingTaps(audioEngineService: audioEngineService)
        
        // Wait for files to be finalized
        try await Task.sleep(nanoseconds: 500_000_000) // 500ms
        
        // Collect results
        var results: [String: (url: URL, duration: TimeInterval, fileSize: Int64)] = [:]
        let duration = recordingDuration
        
        if let mixURL = currentMixURL {
            let fileSize = try getFileSize(for: mixURL)
            results["mix"] = (url: mixURL, duration: duration, fileSize: fileSize)
        }
        
        if let wetURL = currentWetURL {
            let fileSize = try getFileSize(for: wetURL)
            results["wet"] = (url: wetURL, duration: duration, fileSize: fileSize)
        }
        
        if let dryURL = currentDryURL {
            let fileSize = try getFileSize(for: dryURL)
            results["dry"] = (url: dryURL, duration: duration, fileSize: fileSize)
        }
        
        // Cleanup
        cleanup()
        
        logger.info("✅ Wet/dry recording completed with \(results.count) file(s)")
        
        return results
    }
    
    // MARK: - Tap Management
    private func installRecordingTaps(mode: RecordingMode, audioEngineService: AudioEngineService) async throws {
        
        // Get audio nodes for tapping
        guard let recordingMixer = audioEngineService.getRecordingMixer() else {
            throw RecordingError.audioEngineUnavailable
        }
        
        let bufferSize: AVAudioFrameCount = 1024
        let tapFormat = targetFormat
        
        switch mode {
        case .mixOnly:
            // Tap the final mix (current behavior)
            if let mixURL = currentMixURL {
                try installMixTap(on: recordingMixer, url: mixURL, bufferSize: bufferSize, format: tapFormat)
            }
            
        case .wetOnly:
            // Tap the wet signal only
            if let wetURL = currentWetURL {
                try await installWetTap(audioEngineService: audioEngineService, url: wetURL, bufferSize: bufferSize, format: tapFormat)
            }
            
        case .dryOnly:
            // Tap the dry signal only  
            if let dryURL = currentDryURL {
                try await installDryTap(audioEngineService: audioEngineService, url: dryURL, bufferSize: bufferSize, format: tapFormat)
            }
            
        case .wetDrySeparate:
            // Tap both wet and dry separately
            if let wetURL = currentWetURL {
                try await installWetTap(audioEngineService: audioEngineService, url: wetURL, bufferSize: bufferSize, format: tapFormat)
            }
            if let dryURL = currentDryURL {
                try await installDryTap(audioEngineService: audioEngineService, url: dryURL, bufferSize: bufferSize, format: tapFormat)
            }
            
        case .all:
            // Tap mix, wet, and dry
            if let mixURL = currentMixURL {
                try installMixTap(on: recordingMixer, url: mixURL, bufferSize: bufferSize, format: tapFormat)
            }
            if let wetURL = currentWetURL {
                try await installWetTap(audioEngineService: audioEngineService, url: wetURL, bufferSize: bufferSize, format: tapFormat)
            }
            if let dryURL = currentDryURL {
                try await installDryTap(audioEngineService: audioEngineService, url: dryURL, bufferSize: bufferSize, format: tapFormat)
            }
        }
    }
    
    private func installMixTap(on node: AVAudioMixerNode, url: URL, bufferSize: AVAudioFrameCount, format: AVAudioFormat) throws {
        logger.info("📍 Installing mix tap on recording mixer")
        
        mixRecorder = NonBlockingAudioRecorder(
            recordingURL: url,
            format: format,
            bufferSize: bufferSize
        )
        
        mixRecorder?.startRecording()
        
        node.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, time in
            _ = self?.mixRecorder?.writeAudioBuffer(buffer)
        }
    }
    
    private func installWetTap(audioEngineService: AudioEngineService, url: URL, bufferSize: AVAudioFrameCount, format: AVAudioFormat) async throws {
        logger.info("📍 Installing wet tap for reverb output")
        
        wetRecorder = NonBlockingAudioRecorder(
            recordingURL: url,
            format: format,
            bufferSize: bufferSize
        )
        
        wetRecorder?.startRecording()
        
        // Use dedicated wet/dry engine if available
        if let wetDryEngine = wetDryAudioEngine {
            let success = wetDryEngine.installWetTap(bufferSize: bufferSize) { [weak self] buffer, time in
                _ = self?.wetRecorder?.writeAudioBuffer(buffer)
            }
            
            if !success {
                throw RecordingError.audioEngineUnavailable
            }
        } else {
            // Fallback: Use existing recording mixer with note about limitations
            guard let recordingMixer = audioEngineService.getRecordingMixer() else {
                throw RecordingError.audioEngineUnavailable
            }
            
            logger.warning("⚠️ Using fallback wet tap - true wet isolation requires WetDryAudioEngine")
            
            recordingMixer.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, time in
                // Note: This records the full mix, not isolated wet signal
                _ = self?.wetRecorder?.writeAudioBuffer(buffer)
            }
        }
    }
    
    private func installDryTap(audioEngineService: AudioEngineService, url: URL, bufferSize: AVAudioFrameCount, format: AVAudioFormat) async throws {
        logger.info("📍 Installing dry tap for direct input")
        
        dryRecorder = NonBlockingAudioRecorder(
            recordingURL: url,
            format: format,
            bufferSize: bufferSize
        )
        
        dryRecorder?.startRecording()
        
        // Use dedicated wet/dry engine if available
        if let wetDryEngine = wetDryAudioEngine {
            let success = wetDryEngine.installDryTap(bufferSize: bufferSize) { [weak self] buffer, time in
                _ = self?.dryRecorder?.writeAudioBuffer(buffer)
            }
            
            if !success {
                throw RecordingError.audioEngineUnavailable
            }
        } else {
            // Fallback: Tap from input node (before any processing)
            guard let inputNode = audioEngineService.inputNode else {
                throw RecordingError.audioEngineUnavailable
            }
            
            logger.info("📍 Using input node tap for dry signal")
            
            inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, time in
                _ = self?.dryRecorder?.writeAudioBuffer(buffer)
            }
        }
    }
    
    private func removeRecordingTaps(audioEngineService: AudioEngineService) async throws -> (success: Bool, totalFrames: Int, droppedFrames: Int) {
        logger.info("🛑 Removing wet/dry recording taps")
        
        var totalFrames = 0
        var droppedFrames = 0
        var success = true
        
        // Remove taps from dedicated wet/dry engine if available
        if let wetDryEngine = wetDryAudioEngine {
            wetDryEngine.removeAllTaps()
        } else {
            // Remove taps from fallback nodes
            
            // Remove mix tap
            if mixRecorder != nil {
                if let recordingMixer = audioEngineService.getRecordingMixer() {
                    recordingMixer.removeTap(onBus: 0)
                }
            }
            
            // Remove wet tap (was on recording mixer in fallback)
            if wetRecorder != nil {
                if let recordingMixer = audioEngineService.getRecordingMixer() {
                    recordingMixer.removeTap(onBus: 0)
                }
            }
            
            // Remove dry tap (was on input node in fallback)
            if dryRecorder != nil {
                if let inputNode = audioEngineService.inputNode {
                    inputNode.removeTap(onBus: 0)
                }
            }
        }
        
        // Stop all recorders
        mixRecorder?.stopRecording()
        wetRecorder?.stopRecording()
        dryRecorder?.stopRecording()
        
        // Clear recorder references
        mixRecorder = nil
        wetRecorder = nil
        dryRecorder = nil
        
        return (success: success, totalFrames: totalFrames, droppedFrames: droppedFrames)
    }
    
    // MARK: - Helper Methods
    private func createRecordingURL(for type: String, timestamp: String, format: String) -> URL {
        let filename = "reverb_\(type)_\(timestamp).\(format)"
        return recordingDirectory.appendingPathComponent(filename)
    }
    
    private func generateTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: Date())
    }
    
    private func startRecordingTimer() {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let startTime = self.recordingStartTime else { return }
            
            DispatchQueue.main.async {
                self.recordingDuration = Date().timeIntervalSince(startTime)
            }
        }
    }
    
    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }
    
    private func getFileSize(for url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return attributes[.size] as? Int64 ?? 0
    }
    
    private func cleanup() {
        DispatchQueue.main.async {
            self.isRecording = false
            self.recordingDuration = 0
            self.recordingStartTime = nil
            self.currentMixURL = nil
            self.currentWetURL = nil
            self.currentDryURL = nil
        }
    }
    
    // MARK: - Error Types
    enum RecordingError: LocalizedError {
        case recordingInProgress
        case noActiveRecording
        case audioEngineUnavailable
        case fileSystemError(String)
        
        var errorDescription: String? {
            switch self {
            case .recordingInProgress:
                return "Enregistrement déjà en cours"
            case .noActiveRecording:
                return "Aucun enregistrement actif"
            case .audioEngineUnavailable:
                return "Moteur audio non disponible"
            case .fileSystemError(let message):
                return "Erreur fichier: \(message)"
            }
        }
    }
    
    // MARK: - Statistics
    func getRecordingStatistics() -> (totalRecordings: Int, wetDryRecordings: Int, totalSize: Int64) {
        do {
            let files = try FileManager.default.contentsOfDirectory(at: recordingDirectory, includingPropertiesForKeys: [.fileSizeKey])
            
            let wetDryRecordings = files.filter { url in
                let name = url.lastPathComponent
                return name.contains("_wet_") || name.contains("_dry_")
            }.count / 2 // Divide by 2 since wet/dry pairs count as one recording session
            
            let totalSize = files.compactMap { url -> Int64? in
                return (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
            }.reduce(0, +)
            
            return (totalRecordings: files.count, wetDryRecordings: wetDryRecordings, totalSize: totalSize)
        } catch {
            logger.error("❌ Error getting recording statistics: \(error.localizedDescription)")
            return (totalRecordings: 0, wetDryRecordings: 0, totalSize: 0)
        }
    }
    
    deinit {
        stopRecordingTimer()
        logger.info("🗑️ WetDryRecordingManager deinitialized")
    }
}

// MARK: - Extensions for UI Integration
extension WetDryRecordingManager {
    
    /// Get all recordings grouped by session (wet/dry pairs)
    func getRecordingSessions() -> [RecordingSession] {
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: recordingDirectory,
                includingPropertiesForKeys: [.creationDateKey, .fileSizeKey]
            )
            
            // Group files by timestamp
            var sessions: [String: RecordingSession] = [:]
            
            for file in files {
                let fileName = file.deletingPathExtension().lastPathComponent
                let components = fileName.components(separatedBy: "_")
                
                if components.count >= 3 {
                    let type = components[1] // mix, wet, or dry
                    let timestamp = components.dropFirst(2).joined(separator: "_")
                    
                    if sessions[timestamp] == nil {
                        sessions[timestamp] = RecordingSession(timestamp: timestamp)
                    }
                    
                    switch type {
                    case "mix":
                        sessions[timestamp]?.mixURL = file
                    case "wet":
                        sessions[timestamp]?.wetURL = file
                    case "dry":
                        sessions[timestamp]?.dryURL = file
                    default:
                        break
                    }
                }
            }
            
            return Array(sessions.values).sorted { $0.timestamp > $1.timestamp }
        } catch {
            logger.error("❌ Error loading recording sessions: \(error.localizedDescription)")
            return []
        }
    }
    
    struct RecordingSession {
        let timestamp: String
        var mixURL: URL?
        var wetURL: URL?
        var dryURL: URL?
        
        var hasWetDry: Bool {
            return wetURL != nil && dryURL != nil
        }
        
        var recordingMode: RecordingMode {
            let hasMix = mixURL != nil
            let hasWet = wetURL != nil
            let hasDry = dryURL != nil
            
            if hasMix && hasWet && hasDry {
                return .all
            } else if hasWet && hasDry {
                return .wetDrySeparate
            } else if hasWet {
                return .wetOnly
            } else if hasDry {
                return .dryOnly
            } else {
                return .mixOnly
            }
        }
        
        var displayName: String {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            
            if let date = formatter.date(from: timestamp) {
                formatter.dateStyle = .short
                formatter.timeStyle = .medium
                return formatter.string(from: date)
            }
            
            return timestamp
        }
    }
}