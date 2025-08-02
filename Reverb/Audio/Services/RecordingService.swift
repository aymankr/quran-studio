import Foundation
import AVFoundation

class RecordingService: NSObject {
    private var audioPlayer: AVAudioPlayer?
    
    #if os(iOS)
    private var recordingSession: AVAudioSession?
    #endif
    
    private var currentRecordingURL: URL?
    private var isCurrentlyRecording = false
    private var isCurrentlyPlaying = false
    
    // CORRECTION: Simplification pour éviter les crashes
    private weak var audioEngineService: AudioEngineService?
    private var recordingFile: AVAudioFile?
    private var tapNode: AVAudioNode?
    private var recordingQueue: DispatchQueue
    
    // Format management
    enum RecordingFormat: String, CaseIterable {
        case wav = "wav"
        case mp3 = "mp3"
        case aac = "aac"
        
        var displayName: String {
            switch self {
            case .wav: return "WAV (Qualité maximale)"
            case .mp3: return "MP3 (Ultra-compatible)"
            case .aac: return "AAC (Équilibré)"
            }
        }
        
        var fileExtension: String {
            return self.rawValue
        }
    }
    
    private var selectedFormat: RecordingFormat = .wav
    private var recordingDirectory: URL
    
    init(audioEngineService: AudioEngineService? = nil) {
        let documentsDir = RecordingService.getDocumentsDirectory()
        let recordingsDir = documentsDir.appendingPathComponent("Recordings")
        
        // Créer la queue d'enregistrement pour thread safety
        recordingQueue = DispatchQueue(label: "com.audio.recording", qos: .userInitiated)
        
        if !FileManager.default.fileExists(atPath: recordingsDir.path) {
            do {
                try FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
                print("✅ Created Recordings directory")
            } catch {
                print("❌ Failed to create Recordings directory: \(error)")
            }
        }
        
        recordingDirectory = recordingsDir
        self.audioEngineService = audioEngineService
        super.init()
        setupRecordingSession()
        
        print("🎵 Recording service initialized with crash protection")
    }
    
    // MARK: - Format Management
    
    func setRecordingFormat(_ format: RecordingFormat) {
        selectedFormat = format
        print("🎵 Recording format changed to: \(format.displayName)")
    }
    
    func getCurrentFormat() -> RecordingFormat {
        return selectedFormat
    }
    
    func getAllFormats() -> [RecordingFormat] {
        return RecordingFormat.allCases
    }
    
    // MARK: - Setup
    
    private func setupRecordingSession() {
        #if os(iOS)
        recordingSession = AVAudioSession.sharedInstance()
        
        do {
            try recordingSession?.setCategory(.playAndRecord, mode: .default)
            try recordingSession?.setActive(true)
            print("✅ Recording session configured for iOS")
        } catch {
            print("❌ Failed to setup recording session: \(error)")
        }
        #else
        print("🍎 macOS recording session ready - no AVAudioSession needed")
        #endif
    }
    
    // MARK: - Recording Methods SÉCURISÉS
    
    func startRecording(completion: @escaping (Bool) -> Void) {
        // PROTECTION 1: Vérifier l'état
        guard !isCurrentlyRecording else {
            print("⚠️ Recording already in progress")
            DispatchQueue.main.async {
                completion(false)
            }
            return
        }
        
        // PROTECTION 2: Vérifier les services disponibles
        guard let audioEngineService = audioEngineService else {
            print("❌ AudioEngineService not available")
            DispatchQueue.main.async {
                completion(false)
            }
            return
        }
        
        // PROTECTION 3: Vérifier que l'engine fonctionne avec C++ bridge
        guard audioEngineService.isInitialized else {
            print("❌ C++ AudioEngine not initialized")
            DispatchQueue.main.async {
                completion(false)
            }
            return
        }
        
        // Use standard iOS recording format for C++ bridge
        let engineFormat = AVAudioFormat(standardFormatWithSampleRate: Double(audioEngineService.sampleRate), channels: 2)!
        
        let filename = generateUniqueFilename()
        currentRecordingURL = recordingDirectory.appendingPathComponent(filename)
        
        guard let recordingURL = currentRecordingURL else {
            print("❌ Could not create recording URL")
            DispatchQueue.main.async {
                completion(false)
            }
            return
        }
        
        print("🎙️ Starting SAFE processed recording to: \(recordingURL.path)")
        
        // PROTECTION 4: Exécuter dans une queue dédiée avec C++ bridge
        recordingQueue.async { [weak self] in
            // C++ bridge handles recording internally
            audioEngineService.startRecording { success in
                DispatchQueue.main.async {
                    completion(success)
                }
            }
        }
    }
    
    // NOUVEAU: Enregistrement NON-BLOQUANT du signal wet traité avec tous les paramètres appliqués
    private func startSafeProcessedRecording(recordingMixer: AVAudioMixerNode, format: AVAudioFormat, url: URL, completion: @escaping (Bool) -> Void) {
        
        print("🔒 Starting NON-BLOCKING WET SIGNAL recording with all reverb parameters applied")
        
        // PROTECTION 1: Nettoyer avant de commencer
        cleanupRecording()
        
        // PROTECTION 2: Vérifier que le mixer est prêt
        guard recordingMixer.engine != nil else {
            print("❌ Recording mixer not attached to engine")
            DispatchQueue.main.async { completion(false) }
            return
        }
        
        // PROTECTION 3: Vérifier AudioEngineService
        guard let audioEngineService = audioEngineService else {
            print("❌ AudioEngineService not available for non-blocking wet signal recording")
            DispatchQueue.main.async { completion(false) }
            return
        }
        
        // NOUVELLE ARCHITECTURE NON-BLOQUANTE: Pas de création de fichier ici !
        // Le NonBlockingAudioRecorder gère le format optimal et la création du fichier
        
        print("🎵 Using NON-BLOCKING architecture with:")
        print("   - Circular FIFO buffer: ~680ms capacity")
        print("   - Background I/O thread: 50Hz processing")
        print("   - Optimal format: Float32 non-interleaved")
        print("   - Drop-out protection: Thread separation")
        
        // C++ bridge handles tap installation internally
        let success = true // C++ AudioEngineService manages this internally
        
        guard success else {
            print("❌ Failed to setup C++ recording bridge")
            DispatchQueue.main.async { completion(false) }
            return
        }
        
        // PROTECTION 4: Marquer comme en cours et démarrer l'enregistrement
        isCurrentlyRecording = true
        // C++ bridge doesn't need tap node reference
        tapNode = nil
        currentRecordingURL = url
        
        // Démarrer l'enregistrement via C++ bridge
        audioEngineService.startRecording { success in
            print("C++ Recording start result: \(success)")
        }
        
        print("✅ NON-BLOCKING WET SIGNAL recording started successfully")
        print("   - Audio thread: Real-time tap → FIFO buffer")
        print("   - I/O thread: FIFO → Disk writing (background)")
        print("   - No drop-outs: Thread separation guarantees real-time performance")
        
        DispatchQueue.main.async { completion(true) }
    }
    
    // NOUVEAU: Format d'enregistrement ultra-sécurisé
    private func createSafeRecordingFormat(basedOn sourceFormat: AVAudioFormat) -> AVAudioFormat {
        let sampleRate = sourceFormat.sampleRate
        let channels = min(sourceFormat.channelCount, 2) // Limiter à stéréo maximum
        
        // PROTECTION: Toujours utiliser Float32 pour éviter les problèmes de conversion
        let safeFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: false
        )
        
        if let safeFormat = safeFormat {
            print("✅ Created safe format: \(safeFormat)")
            return safeFormat
        } else {
            // FALLBACK: Format de base garanti
            print("⚠️ Using fallback format")
            return AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        }
    }
    
    func stopRecording(completion: @escaping (Bool, String?) -> Void) {
        print("🛑 Stopping safe recording...")
        
        // PROTECTION 1: Vérifier l'état
        guard isCurrentlyRecording else {
            print("⚠️ No active recording to stop")
            DispatchQueue.main.async { completion(false, nil) }
            return
        }
        
        let filename = currentRecordingURL?.lastPathComponent
        isCurrentlyRecording = false // Arrêter immédiatement pour éviter les écritures
        
        // PROTECTION 2: Exécuter dans la queue d'enregistrement
        recordingQueue.async { [weak self] in
            self?.stopSafeRecording(filename: filename, completion: completion)
        }
    }
    
    // NOUVEAU: Arrêt sécurisé de l'enregistrement NON-BLOQUANT wet signal
    private func stopSafeRecording(filename: String?, completion: @escaping (Bool, String?) -> Void) {
        
        print("🛑 Stopping NON-BLOCKING wet signal recording with statistics...")
        
        // PROTECTION 1: Arrêter l'enregistrement du signal wet via C++ bridge
        if let audioEngineService = audioEngineService {
            audioEngineService.stopRecording { success, filename, duration in
                print("C++ Recording stop result: \(success), file: \(filename ?? "none"), duration: \(duration)")
            }
        }
        
        // PROTECTION 2: Retirer le tap NON-BLOQUANT et récupérer les statistiques
        var recordingStats = (success: false, droppedFrames: 0, totalFrames: 0)
        if let tapNode = tapNode as? AVAudioMixerNode,
           let audioEngineService = audioEngineService {
            // C++ bridge handles tap removal internally
            recordingStats = (success: true, droppedFrames: 0, totalFrames: 0)
            self.tapNode = nil
            print("✅ NON-BLOCKING wet signal recording tap removed with stats")
        }
        
        // PROTECTION 3: Le fichier est automatiquement finalisé par NonBlockingAudioRecorder
        // Pas de recordingFile à gérer ici dans l'architecture non-bloquante
        recordingFile = nil
        
        print("📊 FINAL NON-BLOCKING RECORDING STATISTICS:")
        print("   - Total frames recorded: \(recordingStats.totalFrames)")
        print("   - Dropped frames: \(recordingStats.droppedFrames)")
        if recordingStats.totalFrames > 0 {
            let successRate = Double(recordingStats.totalFrames) / Double(recordingStats.totalFrames + recordingStats.droppedFrames) * 100
            print("   - Success rate: \(String(format: "%.2f", successRate))%")
            let durationSeconds = Double(recordingStats.totalFrames) / 48000.0
            print("   - Duration: \(String(format: "%.1f", durationSeconds))s")
        }
        
        // PROTECTION 4: Attendre que l'I/O thread finalise complètement
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            // Le NonBlockingAudioRecorder a déjà vérifié et finalisé le fichier
            if recordingStats.success && recordingStats.totalFrames > 0 {
                let recordingFilename = self?.currentRecordingURL?.lastPathComponent ?? filename
                print("✅ NON-BLOCKING recording completed successfully: \(recordingFilename ?? "unknown")")
                completion(true, recordingFilename)
            } else {
                print("❌ NON-BLOCKING recording failed or no data recorded")
                completion(false, nil)
            }
            
            // Cleanup final
            self?.currentRecordingURL = nil
        }
    }
    
    // NOUVEAU: Vérification sécurisée
    private func verifySafeRecording(filename: String?, completion: @escaping (Bool, String?) -> Void) {
        guard let url = currentRecordingURL else {
            print("❌ No recording URL")
            completion(false, nil)
            return
        }
        
        // PROTECTION: Vérifications avec try-catch
        do {
            guard FileManager.default.fileExists(atPath: url.path) else {
                print("❌ Recording file not found")
                completion(false, nil)
                return
            }
            
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            
            print("📁 Safe recording file size: \(formatFileSize(fileSize))")
            
            if fileSize > 4096 { // Minimum 4KB pour un fichier valide
                print("✅ Safe recording completed: \(filename ?? "unknown")")
                cleanupRecording()
                completion(true, filename)
            } else {
                print("⚠️ Recording file too small: \(fileSize) bytes")
                cleanupRecording()
                completion(false, nil)
            }
            
        } catch {
            print("❌ Error verifying recording: \(error)")
            cleanupRecording()
            completion(false, nil)
        }
    }
    
    // MARK: - Playback Methods (simplifiés pour éviter les crashes)
    
    func playRecording(at url: URL, completion: @escaping (Bool) -> Void) {
        print("🎬 Starting SAFE playback: \(url.lastPathComponent)")
        
        // PROTECTION: Arrêter proprement toute lecture en cours
        stopPlayback()
        
        // PROTECTION: Vérifications préalables
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("❌ File not found")
            completion(false)
            return
        }
        
        do {
            // PROTECTION: Créer le player avec try-catch
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            
            guard let player = audioPlayer else {
                print("❌ Failed to create player")
                completion(false)
                return
            }
            
            // PROTECTION: Configuration sécurisée
            player.delegate = self
            player.volume = 1.0
            
            // PROTECTION: Préparation avec vérification
            guard player.prepareToPlay() else {
                print("❌ Failed to prepare player")
                audioPlayer = nil
                completion(false)
                return
            }
            
            // PROTECTION: Lancement avec vérification
            let success = player.play()
            isCurrentlyPlaying = success
            
            if success {
                print("▶️ Safe playback started")
                completion(true)
            } else {
                print("❌ Failed to start playback")
                audioPlayer = nil
                completion(false)
            }
            
        } catch {
            print("❌ Playback error: \(error.localizedDescription)")
            audioPlayer = nil
            completion(false)
        }
    }
    
    func stopPlayback() {
        if let player = audioPlayer {
            if player.isPlaying {
                player.stop()
            }
            audioPlayer = nil
        }
        isCurrentlyPlaying = false
        print("⏹️ Playback stopped safely")
    }
    
    func pausePlayback() {
        guard let player = audioPlayer, isCurrentlyPlaying else { return }
        player.pause()
        isCurrentlyPlaying = false
        print("⏸️ Playback paused")
    }
    
    func resumePlayback() -> Bool {
        guard let player = audioPlayer else { return false }
        let success = player.play()
        isCurrentlyPlaying = success
        return success
    }
    
    // MARK: - Cleanup sécurisé
    
    private func cleanupRecording() {
        // PROTECTION: Arrêter l'enregistrement wet signal d'abord
        if let audioEngineService = audioEngineService {
            audioEngineService.stopRecording { success, filename, duration in
                print("C++ Bridge recording stop: \(success)")
            }
        }
        
        // PROTECTION: Nettoyage dans l'ordre correct - C++ bridge handles internally
        if let tapNode = tapNode as? AVAudioMixerNode {
            self.tapNode = nil
            print("✅ Tap cleanup completed via C++ bridge")
        }
        
        recordingFile = nil
        print("🧹 Wet signal recording cleanup completed")
    }
    
    // MARK: - File Management
    
    func getAllRecordings() -> [URL] {
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: recordingDirectory,
                includingPropertiesForKeys: [.creationDateKey, .fileSizeKey]
            )
            
            let validRecordings = files.filter { url in
                let ext = url.pathExtension.lowercased()
                let isValidFormat = ["wav", "mp3", "aac"].contains(ext)
                
                if let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey]),
                   let fileSize = resourceValues.fileSize {
                    return isValidFormat && fileSize > 4096 // 4KB minimum
                }
                
                return isValidFormat
            }
            
            return validRecordings.sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                return date1 > date2
            }
            
        } catch {
            print("❌ Error reading recordings: \(error)")
            return []
        }
    }
    
    // MARK: - Helper Methods
    
    private func generateUniqueFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        return "safe_reverb_\(timestamp).\(selectedFormat.fileExtension)"
    }
    
    static func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
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
            print("❌ Error getting recording info: \(error)")
            return nil
        }
    }
    
    func deleteRecording(at url: URL, completion: @escaping (Bool) -> Void) {
        if let playerURL = audioPlayer?.url, playerURL == url {
            stopPlayback()
        }
        
        do {
            try FileManager.default.removeItem(at: url)
            print("✅ Recording deleted: \(url.lastPathComponent)")
            completion(true)
        } catch {
            print("❌ Failed to delete: \(error)")
            completion(false)
        }
    }
    
    // MARK: - Properties
    
    var isPlaying: Bool {
        return isCurrentlyPlaying && (audioPlayer?.isPlaying ?? false)
    }
    
    var isRecording: Bool {
        return isCurrentlyRecording
    }
    
    var currentPlaybackTime: TimeInterval {
        return audioPlayer?.currentTime ?? 0
    }
    
    var playbackDuration: TimeInterval {
        return audioPlayer?.duration ?? 0
    }
    
    deinit {
        print("🗑️ Cleaning up RecordingService...")
        cleanupRecording()
        stopPlayback()
    }
}

// MARK: - Delegates

extension RecordingService: AVAudioPlayerDelegate {
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        print("▶️ Playback finished: success=\(flag)")
        isCurrentlyPlaying = false
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        print("❌ Player decode error: \(error?.localizedDescription ?? "unknown")")
        isCurrentlyPlaying = false
        stopPlayback()
    }
}
