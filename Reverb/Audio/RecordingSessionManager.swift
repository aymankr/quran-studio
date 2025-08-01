import Foundation
import AVFoundation
import OSLog

/// Enhanced recording session manager with file access permissions and advanced controls
class RecordingSessionManager: ObservableObject {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Reverb", category: "RecordingSession")
    
    // MARK: - Published Properties
    @Published var isRecordingActive: Bool = false
    @Published var currentRecordingURL: URL?
    @Published var recordingDuration: TimeInterval = 0
    @Published var recordingFormat: RecordingFormat = .wav
    @Published var recordingPermissionStatus: RecordingPermissionStatus = .notDetermined
    
    // MARK: - Private Properties
    private var recordingTimer: Timer?
    private var recordingStartTime: Date?
    weak var audioEngineService: AudioEngineService?
    private var currentRecordingDirectory: URL
    
    // MARK: - Types
    enum RecordingFormat: String, CaseIterable {
        case wav = "wav"
        case aac = "aac" 
        case mp3 = "mp3"
        
        var displayName: String {
            switch self {
            case .wav: return "WAV (Qualité studio)"
            case .aac: return "AAC (Équilibré)"
            case .mp3: return "MP3 (Compatible)"
            }
        }
        
        var fileExtension: String { rawValue }
    }
    
    enum RecordingPermissionStatus {
        case notDetermined
        case granted
        case denied
        case restricted
    }
    
    enum RecordingError: LocalizedError {
        case permissionDenied
        case audioEngineUnavailable
        case fileSystemError(String)
        case recordingInProgress
        case noActiveRecording
        
        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Permissions d'enregistrement refusées"
            case .audioEngineUnavailable:
                return "Moteur audio non disponible"
            case .fileSystemError(let message):
                return "Erreur fichier: \(message)"
            case .recordingInProgress:
                return "Enregistrement déjà en cours"
            case .noActiveRecording:
                return "Aucun enregistrement actif"
            }
        }
    }
    
    // MARK: - Initialization
    init(audioEngineService: AudioEngineService? = nil) {
        self.audioEngineService = audioEngineService
        
        // Setup recording directory with proper permissions
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.currentRecordingDirectory = documentsDir.appendingPathComponent("Recordings", isDirectory: true)
        
        setupRecordingDirectory()
        checkRecordingPermissions()
        
        logger.info("🎙️ RecordingSessionManager initialized")
    }
    
    // MARK: - Directory Setup
    private func setupRecordingDirectory() {
        do {
            if !FileManager.default.fileExists(atPath: currentRecordingDirectory.path) {
                try FileManager.default.createDirectory(
                    at: currentRecordingDirectory,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o755]
                )
                logger.info("✅ Created recording directory: \(self.currentRecordingDirectory.path)")
            }
            
            // Verify write permissions
            let testFile = currentRecordingDirectory.appendingPathComponent(".permissions_test")
            try "test".write(to: testFile, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(at: testFile)
            
            logger.info("✅ Recording directory permissions verified")
        } catch {
            logger.error("❌ Failed to setup recording directory: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Permission Management
    private func checkRecordingPermissions() {
        #if os(macOS)
        // macOS: Check microphone access
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            recordingPermissionStatus = .granted
        case .denied:
            recordingPermissionStatus = .denied
        case .undetermined:
            recordingPermissionStatus = .notDetermined
        @unknown default:
            recordingPermissionStatus = .notDetermined
        }
        #else
        // iOS: Use AVAudioSession
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            recordingPermissionStatus = .granted
        case .denied:
            recordingPermissionStatus = .denied
        case .undetermined:
            recordingPermissionStatus = .notDetermined
        @unknown default:
            recordingPermissionStatus = .notDetermined
        }
        #endif
        
        logger.info("🔐 Recording permission status: \(String(describing: self.recordingPermissionStatus))")
    }
    
    func requestRecordingPermissions() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.recordingPermissionStatus = .granted
                        continuation.resume()
                    } else {
                        self?.recordingPermissionStatus = .denied
                        continuation.resume(throwing: RecordingError.permissionDenied)
                    }
                }
            }
        }
    }
    
    // MARK: - Recording Control
    func startRecording(withFormat format: RecordingFormat = .wav) async throws -> URL {
        logger.info("🎙️ Starting recording session with format: \(format.rawValue)")
        
        // Validation checks
        guard !isRecordingActive else {
            throw RecordingError.recordingInProgress
        }
        
        if recordingPermissionStatus != .granted {
            try await requestRecordingPermissions()
        }
        
        guard let audioEngineService = audioEngineService else {
            throw RecordingError.audioEngineUnavailable
        }
        
        // Generate unique filename
        let filename = generateUniqueFilename(format: format)
        let recordingURL = currentRecordingDirectory.appendingPathComponent(filename)
        
        // Start recording via AudioEngineService
        let success = audioEngineService.installNonBlockingWetSignalRecordingTap(
            on: audioEngineService.getRecordingMixer()!,
            recordingURL: recordingURL
        )
        
        guard success else {
            throw RecordingError.audioEngineUnavailable
        }
        
        // Start recording and timer
        audioEngineService.startNonBlockingWetSignalRecording()
        startRecordingTimer()
        
        // Update state
        DispatchQueue.main.async {
            self.isRecordingActive = true
            self.currentRecordingURL = recordingURL
            self.recordingFormat = format
            self.recordingStartTime = Date()
        }
        
        logger.info("✅ Recording started: \(filename)")
        return recordingURL
    }
    
    func stopRecording() async throws -> (url: URL, duration: TimeInterval, fileSize: Int64) {
        logger.info("🛑 Stopping recording session")
        
        guard isRecordingActive, let recordingURL = currentRecordingURL else {
            throw RecordingError.noActiveRecording
        }
        
        guard let audioEngineService = audioEngineService else {
            throw RecordingError.audioEngineUnavailable
        }
        
        // Stop recording
        audioEngineService.stopNonBlockingWetSignalRecording()
        
        if let recordingMixer = audioEngineService.getRecordingMixer() {
            let stats = audioEngineService.removeNonBlockingWetSignalRecordingTap(from: recordingMixer)
            logger.info("📊 Recording stats - Success: \(stats.success), Frames: \(stats.totalFrames), Dropped: \(stats.droppedFrames)")
        }
        
        stopRecordingTimer()
        
        // Calculate final duration and file size
        let duration = recordingDuration
        
        // Wait for file to be finalized
        try await Task.sleep(nanoseconds: 300_000_000) // 300ms
        
        let fileSize = try getFileSize(for: recordingURL)
        
        // Update state
        DispatchQueue.main.async {
            self.isRecordingActive = false
            self.currentRecordingURL = nil
            self.recordingDuration = 0
            self.recordingStartTime = nil
        }
        
        logger.info("✅ Recording completed: \(recordingURL.lastPathComponent), Duration: \(String(format: "%.1f", duration))s, Size: \(fileSize) bytes")
        
        return (url: recordingURL, duration: duration, fileSize: fileSize)
    }
    
    func cancelRecording() async throws {
        logger.info("❌ Cancelling recording session")
        
        guard isRecordingActive, let recordingURL = currentRecordingURL else {
            throw RecordingError.noActiveRecording
        }
        
        // Stop recording
        if let audioEngineService = audioEngineService {
            audioEngineService.stopNonBlockingWetSignalRecording()
            
            if let recordingMixer = audioEngineService.getRecordingMixer() {
                _ = audioEngineService.removeNonBlockingWetSignalRecordingTap(from: recordingMixer)
            }
        }
        
        stopRecordingTimer()
        
        // Delete the incomplete file
        try? FileManager.default.removeItem(at: recordingURL)
        
        // Update state
        DispatchQueue.main.async {
            self.isRecordingActive = false
            self.currentRecordingURL = nil
            self.recordingDuration = 0
            self.recordingStartTime = nil
        }
        
        logger.info("✅ Recording cancelled and file deleted")
    }
    
    // MARK: - Timer Management
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
    
    // MARK: - File Management
    private func generateUniqueFilename(format: RecordingFormat) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        
        let counter = getNextFileCounter()
        return "reverb_recording_\(timestamp)_\(counter).\(format.fileExtension)"
    }
    
    private func getNextFileCounter() -> Int {
        do {
            let files = try FileManager.default.contentsOfDirectory(at: currentRecordingDirectory, includingPropertiesForKeys: nil)
            return files.count + 1
        } catch {
            return 1
        }
    }
    
    private func getFileSize(for url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return attributes[.size] as? Int64 ?? 0
    }
    
    func getAllRecordings() -> [URL] {
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: currentRecordingDirectory,
                includingPropertiesForKeys: [.creationDateKey, .fileSizeKey, .contentModificationDateKey]
            )
            
            return files
                .filter { url in
                    let ext = url.pathExtension.lowercased()
                    return ["wav", "aac", "mp3", "m4a"].contains(ext)
                }
                .sorted { url1, url2 in
                    let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                    let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                    return date1 > date2
                }
        } catch {
            logger.error("❌ Error loading recordings: \(error.localizedDescription)")
            return []
        }
    }
    
    func deleteRecording(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
        logger.info("✅ Recording deleted: \(url.lastPathComponent)")
    }
    
    func moveRecordingToTrash(at url: URL) throws {
        #if os(macOS)
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        #else
        try deleteRecording(at: url)
        #endif
        logger.info("✅ Recording moved to trash: \(url.lastPathComponent)")
    }
    
    // MARK: - Export & Sharing
    func exportRecording(at url: URL, to destinationURL: URL) throws {
        try FileManager.default.copyItem(at: url, to: destinationURL)
        logger.info("✅ Recording exported to: \(destinationURL.path)")
    }
    
    func getRecordingInfo(for url: URL) -> (duration: TimeInterval, fileSize: Int64, creationDate: Date)? {
        do {
            let asset = AVURLAsset(url: url)
            let duration = CMTimeGetSeconds(asset.duration)
            
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            let creationDate = attributes[.creationDate] as? Date ?? Date()
            
            let validDuration = duration.isFinite && duration > 0 ? duration : 0
            
            return (duration: validDuration, fileSize: fileSize, creationDate: creationDate)
        } catch {
            logger.error("❌ Error getting recording info: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Directory Access
    var recordingDirectoryURL: URL {
        return currentRecordingDirectory
    }
    
    func openRecordingDirectory() {
        #if os(macOS)
        NSWorkspace.shared.open(currentRecordingDirectory)
        #endif
    }
    
    func revealRecordingInFinder(at url: URL) {
        #if os(macOS)
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
        #endif
    }
    
    // MARK: - Cleanup
    deinit {
        stopRecordingTimer()
        logger.info("🗑️ RecordingSessionManager deinitialized")
    }
}

// MARK: - Extensions
extension RecordingSessionManager {
    
    /// Format file size for display
    func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    /// Format duration for display
    func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    /// Get recording statistics
    var recordingStatistics: (totalRecordings: Int, totalSize: Int64, totalDuration: TimeInterval) {
        let recordings = getAllRecordings()
        
        var totalSize: Int64 = 0
        var totalDuration: TimeInterval = 0
        
        for recording in recordings {
            if let info = getRecordingInfo(for: recording) {
                totalSize += info.fileSize
                totalDuration += info.duration
            }
        }
        
        return (totalRecordings: recordings.count, totalSize: totalSize, totalDuration: totalDuration)
    }
}