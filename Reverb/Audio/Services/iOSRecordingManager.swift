import Foundation
import AVFoundation
import UIKit

/// iOS-specific recording manager with proper file permissions and document sharing
/// Handles iOS-specific constraints: sandboxed file access, UIDocumentInteraction, permissions
class iOSRecordingManager: NSObject, ObservableObject {
    
    // MARK: - Recording Configuration
    
    struct RecordingConfig {
        let sampleRate: Double = 48000.0
        let bufferSize: AVAudioFrameCount = 64
        let channels: UInt32 = 2
        let bitDepth: UInt32 = 32  // Float32
        
        // iOS-specific paths
        var documentsURL: URL {
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        }
        
        var temporaryURL: URL {
            FileManager.default.temporaryDirectory
        }
        
        var recordingsFolder: URL {
            documentsURL.appendingPathComponent("Recordings", isDirectory: true)
        }
        
        var tempRecordingsFolder: URL {
            temporaryURL.appendingPathComponent("TempRecordings", isDirectory: true)
        }
    }
    
    // MARK: - Recording State
    
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0.0
    @Published var availableRecordings: [RecordingInfo] = []
    @Published var recordingPermissionStatus: RecordingPermissionStatus = .notDetermined
    
    enum RecordingPermissionStatus {
        case notDetermined
        case denied
        case granted
        
        var description: String {
            switch self {
            case .notDetermined: return "Not Determined"
            case .denied: return "Denied"
            case .granted: return "Granted"
            }
        }
    }
    
    struct RecordingInfo {
        let id: UUID
        let filename: String
        let url: URL
        let duration: TimeInterval
        let fileSize: Int64
        let createdAt: Date
        let format: AudioFormat
        let isTemporary: Bool
        
        enum AudioFormat {
            case wav, caf, m4a
            
            var fileExtension: String {
                switch self {
                case .wav: return "wav"
                case .caf: return "caf"
                case .m4a: return "m4a"
                }
            }
            
            var mimeType: String {
                switch self {
                case .wav: return "audio/wav"
                case .caf: return "audio/x-caf"
                case .m4a: return "audio/mp4"
                }
            }
        }
    }
    
    // MARK: - Audio Components
    
    private let config = RecordingConfig()
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var recordingTimer: Timer?
    private var recordingStartTime: Date?
    
    // Tap-based recording
    private var installTapEnabled = false
    private var recordingTap: AVAudioNodeTap?
    
    // MARK: - File Management
    
    private let fileManager = FileManager.default
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupRecordingDirectories()
        checkRecordingPermissions()
        loadExistingRecordings()
    }
    
    private func setupRecordingDirectories() {
        // Create recordings directory in Documents
        do {
            try fileManager.createDirectory(
                at: config.recordingsFolder,
                withIntermediateDirectories: true,
                attributes: nil
            )
            
            try fileManager.createDirectory(
                at: config.tempRecordingsFolder,
                withIntermediateDirectories: true,
                attributes: nil
            )
            
            print("✅ Created recording directories:")
            print("   Documents/Recordings: \(config.recordingsFolder.path)")
            print("   Temp/TempRecordings: \(config.tempRecordingsFolder.path)")
            
        } catch {
            print("❌ Failed to create recording directories: \(error)")
        }
    }
    
    // MARK: - Permissions Management
    
    private func checkRecordingPermissions() {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .denied:
            recordingPermissionStatus = .denied
        case .granted:
            recordingPermissionStatus = .granted
        case .undetermined:
            recordingPermissionStatus = .notDetermined
        @unknown default:
            recordingPermissionStatus = .notDetermined
        }
    }
    
    func requestRecordingPermission() async -> Bool {
        let granted = await AVAudioSession.sharedInstance().requestRecordPermission()
        
        DispatchQueue.main.async {
            self.recordingPermissionStatus = granted ? .granted : .denied
        }
        
        return granted
    }
    
    // MARK: - Recording Operations
    
    func startRecording(format: RecordingInfo.AudioFormat = .wav, temporary: Bool = false) async {
        guard recordingPermissionStatus == .granted else {
            print("❌ Recording permission not granted")
            return
        }
        
        guard !isRecording else {
            print("⚠️ Already recording")
            return
        }
        
        do {
            try await setupAudioSession()
            try setupAudioEngine()
            try await startRecordingProcess(format: format, temporary: temporary)
            
            DispatchQueue.main.async {
                self.isRecording = true
                self.recordingStartTime = Date()
                self.startRecordingTimer()
            }
            
            print("✅ Started recording (format: \(format), temp: \(temporary))")
            
        } catch {
            print("❌ Failed to start recording: \(error)")
        }
    }
    
    func stopRecording() async -> RecordingInfo? {
        guard isRecording else {
            print("⚠️ Not currently recording")
            return nil
        }
        
        // Stop recording timer
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        // Remove audio engine tap
        if let tap = recordingTap {
            audioEngine?.inputNode.removeTap(tap)
            recordingTap = nil
        }
        
        // Stop audio engine
        audioEngine?.stop()
        
        // Close audio file
        audioFile = nil
        
        let duration = recordingStartTime?.timeIntervalSinceNow.magnitude ?? 0.0
        
        DispatchQueue.main.async {
            self.isRecording = false
            self.recordingDuration = 0.0
        }
        
        // Create recording info for the completed recording
        // This would be populated with actual file information
        let recordingInfo = createRecordingInfo(duration: duration)
        
        // Refresh recordings list
        loadExistingRecordings()
        
        print("✅ Stopped recording (duration: \(String(format: "%.2f", duration))s)")
        
        return recordingInfo
    }
    
    private func setupAudioSession() async throws {
        let audioSession = AVAudioSession.sharedInstance()
        
        try audioSession.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.defaultToSpeaker, .allowBluetoothA2DP]
        )
        
        // Configure for professional audio recording
        try audioSession.setPreferredSampleRate(config.sampleRate)
        try audioSession.setPreferredIOBufferDuration(Double(config.bufferSize) / config.sampleRate)
        
        try audioSession.setActive(true)
        
        print("✅ Audio session configured: \(audioSession.sampleRate)Hz, \(audioSession.ioBufferDuration * 1000)ms buffer")
    }
    
    private func setupAudioEngine() throws {
        audioEngine = AVAudioEngine()
        
        guard let engine = audioEngine else {
            throw RecordingError.audioEngineSetupFailed
        }
        
        // Configure input format to match our requirements
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        print("✅ Audio engine configured:")
        print("   Input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount) channels")
        print("   Processing format: \(config.sampleRate)Hz, \(config.channels) channels")
    }
    
    private func startRecordingProcess(format: RecordingInfo.AudioFormat, temporary: Bool) async throws {
        guard let engine = audioEngine else {
            throw RecordingError.audioEngineNotConfigured
        }
        
        // Generate unique filename
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let filename = "Recording_\(timestamp).\(format.fileExtension)"
        
        // Choose directory based on temporary flag
        let recordingURL = temporary ? 
            config.tempRecordingsFolder.appendingPathComponent(filename) :
            config.recordingsFolder.appendingPathComponent(filename)
        
        // Create audio file with specified format
        try createAudioFile(at: recordingURL, format: format)
        
        // Install recording tap on input node
        try installRecordingTap(on: engine.inputNode)
        
        // Start audio engine
        try engine.start()
        
        print("✅ Recording to: \(recordingURL.path)")
    }
    
    private func createAudioFile(at url: URL, format: RecordingInfo.AudioFormat) throws {
        let audioFormat: AVAudioFormat
        
        switch format {
        case .wav:
            // WAV format with Float32 samples
            guard let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: config.sampleRate,
                channels: config.channels,
                interleaved: false
            ) else {
                throw RecordingError.invalidAudioFormat
            }
            audioFormat = format
            
        case .caf:
            // Core Audio Format with Float32 samples
            guard let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: config.sampleRate,
                channels: config.channels,
                interleaved: false
            ) else {
                throw RecordingError.invalidAudioFormat
            }
            audioFormat = format
            
        case .m4a:
            // Compressed AAC format
            guard let format = AVAudioFormat(
                standardFormatWithSampleRate: config.sampleRate,
                channels: config.channels
            ) else {
                throw RecordingError.invalidAudioFormat
            }
            audioFormat = format
        }
        
        audioFile = try AVAudioFile(forWriting: url, settings: audioFormat.settings)
    }
    
    private func installRecordingTap(on inputNode: AVAudioInputNode) throws {
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        // Create recording tap
        inputNode.installTap(
            onBus: 0,
            bufferSize: config.bufferSize,
            format: inputFormat
        ) { [weak self] buffer, when in
            // Write buffer to audio file
            do {
                try self?.audioFile?.write(from: buffer)
            } catch {
                print("❌ Failed to write audio buffer: \(error)")
            }
        }
        
        installTapEnabled = true
    }
    
    private func startRecordingTimer() {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self,
                  let startTime = self.recordingStartTime else { return }
            
            self.recordingDuration = Date().timeIntervalSince(startTime)
        }
    }
    
    private func createRecordingInfo(duration: TimeInterval) -> RecordingInfo {
        // This is a placeholder - in real implementation, would use actual file info
        return RecordingInfo(
            id: UUID(),
            filename: "Recording_\(Date()).wav",
            url: config.recordingsFolder.appendingPathComponent("temp.wav"),
            duration: duration,
            fileSize: Int64(duration * config.sampleRate * Double(config.channels) * 4), // Approximate
            createdAt: Date(),
            format: .wav,
            isTemporary: false
        )
    }
    
    // MARK: - File Management
    
    private func loadExistingRecordings() {
        var recordings: [RecordingInfo] = []
        
        // Load from Documents/Recordings
        recordings.append(contentsOf: loadRecordingsFromDirectory(config.recordingsFolder, temporary: false))
        
        // Load from Temp/TempRecordings
        recordings.append(contentsOf: loadRecordingsFromDirectory(config.tempRecordingsFolder, temporary: true))
        
        // Sort by creation date (newest first)
        recordings.sort { $0.createdAt > $1.createdAt }
        
        DispatchQueue.main.async {
            self.availableRecordings = recordings
        }
    }
    
    private func loadRecordingsFromDirectory(_ directory: URL, temporary: Bool) -> [RecordingInfo] {
        var recordings: [RecordingInfo] = []
        
        do {
            let fileURLs = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey],
                options: .skipsHiddenFiles
            )
            
            for fileURL in fileURLs {
                if let recordingInfo = createRecordingInfo(from: fileURL, temporary: temporary) {
                    recordings.append(recordingInfo)
                }
            }
            
        } catch {
            print("❌ Failed to load recordings from \(directory.path): \(error)")
        }
        
        return recordings
    }
    
    private func createRecordingInfo(from url: URL, temporary: Bool) -> RecordingInfo? {
        do {
            let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
            
            let fileSize = resourceValues.fileSize ?? 0
            let createdAt = resourceValues.creationDate ?? Date()
            
            // Determine audio format from file extension
            let format: RecordingInfo.AudioFormat
            switch url.pathExtension.lowercased() {
            case "wav":
                format = .wav
            case "caf":
                format = .caf
            case "m4a":
                format = .m4a
            default:
                return nil // Unsupported format
            }
            
            // Estimate duration from file size (approximate)
            let bytesPerSecond = config.sampleRate * Double(config.channels) * 4 // Float32
            let duration = Double(fileSize) / bytesPerSecond
            
            return RecordingInfo(
                id: UUID(),
                filename: url.lastPathComponent,
                url: url,
                duration: duration,
                fileSize: Int64(fileSize),
                createdAt: createdAt,
                format: format,
                isTemporary: temporary
            )
            
        } catch {
            print("❌ Failed to get file info for \(url.path): \(error)")
            return nil
        }
    }
    
    // MARK: - File Operations
    
    func deleteRecording(_ recording: RecordingInfo) {
        do {
            try fileManager.removeItem(at: recording.url)
            loadExistingRecordings() // Refresh list
            print("✅ Deleted recording: \(recording.filename)")
        } catch {
            print("❌ Failed to delete recording: \(error)")
        }
    }
    
    func moveRecordingToPermanent(_ recording: RecordingInfo) {
        guard recording.isTemporary else {
            print("⚠️ Recording is already permanent")
            return
        }
        
        let permanentURL = config.recordingsFolder.appendingPathComponent(recording.filename)
        
        do {
            try fileManager.moveItem(at: recording.url, to: permanentURL)
            loadExistingRecordings() // Refresh list
            print("✅ Moved recording to permanent storage: \(recording.filename)")
        } catch {
            print("❌ Failed to move recording: \(error)")
        }
    }
    
    // MARK: - Document Sharing
    
    func shareRecording(_ recording: RecordingInfo, from viewController: UIViewController) {
        let documentInteractionController = UIDocumentInteractionController(url: recording.url)
        documentInteractionController.delegate = self
        documentInteractionController.name = recording.filename
        documentInteractionController.uti = recording.format.mimeType
        
        // Present sharing options
        if !documentInteractionController.presentOptionsMenu(from: viewController.view.bounds, in: viewController.view, animated: true) {
            // Fallback to activity view controller
            presentActivityViewController(for: recording, from: viewController)
        }
    }
    
    private func presentActivityViewController(for recording: RecordingInfo, from viewController: UIViewController) {
        let activityViewController = UIActivityViewController(
            activityItems: [recording.url],
            applicationActivities: nil
        )
        
        // Configure for iPad
        if let popover = activityViewController.popoverPresentationController {
            popover.sourceView = viewController.view
            popover.sourceRect = CGRect(x: viewController.view.bounds.midX, y: viewController.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        viewController.present(activityViewController, animated: true)
    }
    
    // MARK: - Cleanup
    
    func cleanupTemporaryRecordings() {
        do {
            let fileURLs = try fileManager.contentsOfDirectory(
                at: config.tempRecordingsFolder,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
            
            for fileURL in fileURLs {
                try fileManager.removeItem(at: fileURL)
            }
            
            loadExistingRecordings() // Refresh list
            print("✅ Cleaned up \(fileURLs.count) temporary recordings")
            
        } catch {
            print("❌ Failed to cleanup temporary recordings: \(error)")
        }
    }
    
    // MARK: - Error Types
    
    enum RecordingError: Error, LocalizedError {
        case audioEngineSetupFailed
        case audioEngineNotConfigured
        case invalidAudioFormat
        case recordingPermissionDenied
        case fileCreationFailed
        case diskSpaceInsufficient
        
        var errorDescription: String? {
            switch self {
            case .audioEngineSetupFailed:
                return "Failed to setup audio engine"
            case .audioEngineNotConfigured:
                return "Audio engine not configured"
            case .invalidAudioFormat:
                return "Invalid audio format"
            case .recordingPermissionDenied:
                return "Recording permission denied"
            case .fileCreationFailed:
                return "Failed to create recording file"
            case .diskSpaceInsufficient:
                return "Insufficient disk space"
            }
        }
    }
}

// MARK: - UIDocumentInteractionControllerDelegate

extension iOSRecordingManager: UIDocumentInteractionControllerDelegate {
    
    func documentInteractionControllerViewControllerForPreview(_ controller: UIDocumentInteractionController) -> UIViewController {
        // Return the root view controller for document preview
        return UIApplication.shared.windows.first?.rootViewController ?? UIViewController()
    }
    
    func documentInteractionControllerDidEndPreview(_ controller: UIDocumentInteractionController) {
        print("✅ Document preview ended")
    }
}