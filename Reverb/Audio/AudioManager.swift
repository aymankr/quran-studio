import Foundation
import AVFoundation
import Combine

class AudioManager: ObservableObject {
    static let shared = AudioManager()
    
    // Audio services
    private(set) var audioEngineService: AudioEngineService?
    private var recordingService: RecordingService?
    
    // Published properties
    @Published var selectedReverbPreset: ReverbPreset = .vocalBooth
    @Published var currentAudioLevel: Float = 0.0
    @Published var isRecording: Bool = false
    @Published var lastRecordingFilename: String?
    
    // Custom reverb settings
    @Published var customReverbSettings = CustomReverbSettings.default
    
    // Recording state
    private var currentRecordingPreset: String = ""
    private var recordingStartTime: Date?
    
    // Monitoring state
    private var isMonitoringActive = false
    
    // Preset description
    var currentPresetDescription: String {
        switch selectedReverbPreset {
        case .clean:
            return "Signal audio pur sans traitement"
        case .vocalBooth:
            return "Ambiance feutrée pour la voix parlée"
        case .studio:
            return "Son équilibré pour l'enregistrement"
        case .cathedral:
            return "Réverbération spacieuse et noble"
        case .custom:
            return "Paramètres personnalisables"
        }
    }
    
    private init() {
        setupServices()
    }
    
    private func setupServices() {
        audioEngineService = AudioEngineService()
        audioEngineService?.onAudioLevelChanged = { [weak self] level in
            DispatchQueue.main.async {
                self?.currentAudioLevel = level
            }
        }
        
        // CORRECTION: Passer l'audioEngineService au RecordingService
        recordingService = RecordingService(audioEngineService: audioEngineService)
        
        print("✅ Audio services initialized with engine connection")
    }
    
    // MARK: - Public Methods
    
    func prepareAudio() {
        if audioEngineService == nil {
            setupServices()
        }
        print("🔧 Audio services prepared")
    }
    
    func startMonitoring() {
        guard !isMonitoringActive else {
            print("⚠️ Monitoring already active")
            return
        }
        
        audioEngineService?.setMonitoring(enabled: true)
        audioEngineService?.updateReverbPreset(preset: selectedReverbPreset)
        isMonitoringActive = true
        
        print("✅ Monitoring started with preset: \(selectedReverbPreset.rawValue)")
    }
    
    func stopMonitoring() {
        guard isMonitoringActive else {
            print("⚠️ Monitoring not active")
            return
        }
        
        audioEngineService?.setMonitoring(enabled: false)
        isMonitoringActive = false
        
        if isRecording {
            // Arrêter l'enregistrement si en cours
            stopRecording { _, _, _ in }
        }
        
        print("🔇 Monitoring stopped")
    }
    
    func updateReverbPreset(_ preset: ReverbPreset) {
        selectedReverbPreset = preset
        
        if preset == .custom {
            ReverbPreset.updateCustomSettings(customReverbSettings)
        }
        
        audioEngineService?.updateReverbPreset(preset: preset)
        
        print("🎛️ Reverb preset updated to: \(preset.rawValue)")
    }
    
    // MARK: - Input Volume Control
    
    func setInputVolume(_ volume: Float) {
        audioEngineService?.setInputVolume(volume)
    }
    
    func getInputVolume() -> Float {
        return audioEngineService?.getInputVolume() ?? 0.7
    }
    
    // MARK: - Recording Methods (restent identiques)
    
    func startRecording(completion: @escaping (Bool) -> Void) {
        guard let recordingService = recordingService else {
            print("❌ Recording service not available")
            completion(false)
            return
        }
        
        guard !isRecording else {
            print("⚠️ Recording already in progress")
            completion(false)
            return
        }
        
        guard isMonitoringActive else {
            print("⚠️ Cannot record without active monitoring")
            completion(false)
            return
        }
        
        currentRecordingPreset = selectedReverbPreset.rawValue
        recordingStartTime = Date()
        
        print("🎙️ Starting recording with processed signal (reverb: \(currentRecordingPreset))")
        
        recordingService.startRecording { [weak self] success in
            DispatchQueue.main.async {
                if success {
                    self?.isRecording = true
                    print("✅ Recording started with processed audio (preset: \(self?.currentRecordingPreset ?? "unknown"))")
                } else {
                    print("❌ Failed to start recording")
                    self?.recordingStartTime = nil
                }
                completion(success)
            }
        }
    }
    
    func stopRecording(completion: @escaping (Bool, String?, TimeInterval) -> Void) {
        guard let recordingService = recordingService else {
            print("❌ Recording service not available")
            completion(false, nil, 0)
            return
        }
        
        guard isRecording else {
            print("⚠️ No active recording to stop")
            completion(false, nil, 0)
            return
        }
        
        // Calculer la durée
        let duration = recordingStartTime?.timeIntervalSinceNow.magnitude ?? 0
        
        recordingService.stopRecording { [weak self] success, filename in
            DispatchQueue.main.async {
                self?.isRecording = false
                self?.recordingStartTime = nil
                
                if success {
                    self?.lastRecordingFilename = filename
                    print("✅ Processed recording stopped successfully: \(filename ?? "unknown"), duration: \(duration)s")
                } else {
                    print("❌ Recording stop failed")
                    self?.lastRecordingFilename = self?.generateFallbackFilename()
                }
                
                completion(success, filename, duration)
            }
        }
    }
    
    func toggleRecording() {
        if isRecording {
            stopRecording { success, filename, duration in
                print("Recording toggled off: success=\(success), duration=\(duration)s")
            }
        } else {
            startRecording { success in
                print("Recording toggled on: success=\(success)")
            }
        }
    }
    
    private func generateFallbackFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return "recording_\(currentRecordingPreset)_\(formatter.string(from: Date())).m4a"
    }
    
    // MARK: - Custom Reverb Management (reste identique)
    
    func updateCustomReverbSettings(_ settings: CustomReverbSettings) {
        customReverbSettings = settings
        ReverbPreset.updateCustomSettings(settings)
        
        if selectedReverbPreset == .custom {
            audioEngineService?.updateReverbPreset(preset: .custom)
        }
        
        print("🎛️ Custom reverb settings updated")
    }
    
    func resetCustomReverbSettings() {
        customReverbSettings = CustomReverbSettings.default
        ReverbPreset.updateCustomSettings(customReverbSettings)
        
        if selectedReverbPreset == .custom {
            audioEngineService?.updateReverbPreset(preset: .custom)
        }
        
        print("🔄 Custom reverb settings reset to default")
    }
    
    // MARK: - Audio Control Methods (restent identiques)
    
    func setOutputVolume(_ volume: Float, isMuted: Bool) {
        audioEngineService?.setOutputVolume(volume, isMuted: isMuted)
    }
    
    func diagnostic() {
        print("🔍 === AUDIO MANAGER DIAGNOSTIC ===")
        print("- Selected preset: \(selectedReverbPreset.rawValue)")
        print("- Monitoring active: \(isMonitoringActive)")
        print("- Recording active: \(isRecording)")
        print("- Current audio level: \(currentAudioLevel)")
        print("- Audio engine service: \(audioEngineService != nil ? "✅" : "❌")")
        print("- Recording service: \(recordingService != nil ? "✅" : "❌")")
        
        audioEngineService?.diagnosticMonitoring()
        print("=== END AUDIO MANAGER DIAGNOSTIC ===")
    }
    
    // MARK: - Recording Info Methods (restent identiques)
    
    func getCurrentRecordingInfo() -> (preset: String, isActive: Bool, duration: TimeInterval) {
        let duration = recordingStartTime?.timeIntervalSinceNow.magnitude ?? 0
        return (currentRecordingPreset, isRecording, duration)
    }
    
    func getRecordingDuration() -> TimeInterval {
        guard let startTime = recordingStartTime, isRecording else { return 0 }
        return Date().timeIntervalSince(startTime)
    }
    
    // MARK: - State Properties (restent identiques)
    
    var isMonitoring: Bool {
        return isMonitoringActive
    }
    
    var canStartRecording: Bool {
        return isMonitoringActive && !isRecording
    }
    
    var canStartMonitoring: Bool {
        return audioEngineService != nil && !isMonitoringActive
    }
    
    // MARK: - Custom Settings Integration (reste identique)
    
    func updateCustomSetting(
        size: Float? = nil,
        decayTime: Float? = nil,
        preDelay: Float? = nil,
        crossFeed: Float? = nil,
        wetDryMix: Float? = nil,
        density: Float? = nil,
        highFrequencyDamping: Float? = nil,
        applyImmediately: Bool = true
    ) {
        var settings = customReverbSettings
        
        if let size = size { settings.size = size }
        if let decayTime = decayTime { settings.decayTime = decayTime }
        if let preDelay = preDelay { settings.preDelay = preDelay }
        if let crossFeed = crossFeed { settings.crossFeed = crossFeed }
        if let wetDryMix = wetDryMix { settings.wetDryMix = wetDryMix }
        if let density = density { settings.density = density }
        if let highFrequencyDamping = highFrequencyDamping { settings.highFrequencyDamping = highFrequencyDamping }
        
        customReverbSettings = settings
        
        if applyImmediately {
            updateCustomReverbSettings(settings)
        }
    }
    // Dans AudioManager.swift, ajouter une méthode pour les mises à jour live

    func updateCustomReverbLive(_ settings: CustomReverbSettings) {
        // Mise à jour immédiate sans validation excessive
        customReverbSettings = settings
        ReverbPreset.updateCustomSettings(settings)
        
        // Application directe si en mode custom et monitoring actif
        if selectedReverbPreset == .custom && isMonitoringActive {
            audioEngineService?.updateReverbPreset(preset: .custom)
            print("🎛️ LIVE UPDATE: Custom reverb applied in real-time")
        }
    }

}
