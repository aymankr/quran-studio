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
        
        // PROTECTION 3: Vérifier que l'engine fonctionne
        guard let recordingMixer = audioEngineService.getRecordingMixer(),
              let engineFormat = audioEngineService.getRecordingFormat() else {
            print("❌ AudioEngine components not ready")
            DispatchQueue.main.async {
                completion(false)
            }
            return
        }
        
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
        
        // PROTECTION 4: Exécuter dans une queue dédiée
        recordingQueue.async { [weak self] in
            self?.startSafeProcessedRecording(
                recordingMixer: recordingMixer,
                format: engineFormat,
                url: recordingURL,
                completion: completion
            )
        }
    }
    
    // NOUVEAU: Enregistrement sécurisé avec protection contre les crashes
    private func startSafeProcessedRecording(recordingMixer: AVAudioMixerNode, format: AVAudioFormat, url: URL, completion: @escaping (Bool) -> Void) {
        
        print("🔒 Starting SAFE processed audio recording")
        
        // PROTECTION 1: Nettoyer avant de commencer
        cleanupRecording()
        
        do {
            // PROTECTION 2: Créer un format simple et compatible
            let recordingFormat = createSafeRecordingFormat(basedOn: format)
            
            print("📊 Safe recording format: \(recordingFormat.sampleRate) Hz, \(recordingFormat.channelCount) channels")
            print("🎵 Format type: \(recordingFormat.commonFormat.rawValue)")
            
            // PROTECTION 3: Créer le fichier avec try-catch robuste
            recordingFile = try AVAudioFile(forWriting: url, settings: recordingFormat.settings)
            
            guard let audioFile = recordingFile else {
                print("❌ Could not create audio file")
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            print("✅ Safe audio file created")
            
            // PROTECTION 4: Vérifier que le mixer est prêt avant d'installer le tap
            guard recordingMixer.engine != nil else {
                print("❌ Recording mixer not attached to engine")
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            // PROTECTION 5: Installer le tap avec gestion d'erreur complète
            do {
                recordingMixer.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, time in
                    // PROTECTION 6: Vérifications dans le tap
                    guard let self = self,
                          self.isCurrentlyRecording,
                          let audioFile = self.recordingFile else {
                        return
                    }
                    
                    // PROTECTION 7: Écriture thread-safe
                    do {
                        try audioFile.write(from: buffer)
                        
                        // Debug périodique
                        if Int.random(in: 0...1000) == 0 {
                            print("🔄 Safe recording: \(buffer.frameLength) frames")
                        }
                    } catch {
                        print("⚠️ Buffer write error (non-fatal): \(error)")
                        // Ne pas crasher pour une erreur d'écriture
                    }
                }
                
                // PROTECTION 8: Marquer comme en cours seulement si tout a réussi
                isCurrentlyRecording = true
                tapNode = recordingMixer
                
                print("✅ Safe processed recording started successfully")
                DispatchQueue.main.async { completion(true) }
                
            } catch {
                print("❌ Failed to install safe tap: \(error)")
                cleanupRecording()
                DispatchQueue.main.async { completion(false) }
            }
            
        } catch {
            print("❌ Safe recording setup failed: \(error.localizedDescription)")
            cleanupRecording()
            DispatchQueue.main.async { completion(false) }
        }
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
    
    // NOUVEAU: Arrêt sécurisé
    private func stopSafeRecording(filename: String?, completion: @escaping (Bool, String?) -> Void) {
        
        // PROTECTION 1: Arrêter le tap de manière sécurisée
        if let tapNode = tapNode as? AVAudioMixerNode {
            do {
                tapNode.removeTap(onBus: 0)
                print("✅ Tap removed safely")
            } catch {
                print("⚠️ Error removing tap (non-fatal): \(error)")
            }
            self.tapNode = nil
        }
        
        // PROTECTION 2: Finaliser le fichier de manière sécurisée
        if let audioFile = recordingFile {
            recordingFile = nil // Finalise automatiquement
            print("💾 Audio file finalized safely")
        }
        
        // PROTECTION 3: Attendre la finalisation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.verifySafeRecording(filename: filename, completion: completion)
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
        // PROTECTION: Nettoyage dans l'ordre correct
        if let tapNode = tapNode as? AVAudioMixerNode {
            do {
                tapNode.removeTap(onBus: 0)
            } catch {
                print("⚠️ Tap cleanup error (ignored): \(error)")
            }
            self.tapNode = nil
        }
        
        recordingFile = nil
        print("🧹 Safe cleanup completed")
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
