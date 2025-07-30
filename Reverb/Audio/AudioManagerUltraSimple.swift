import Foundation
import AVFoundation
import Combine

/// AudioManager ULTRA-SIMPLE qui copie exactement le code du test qui fonctionne
class AudioManagerUltraSimple: ObservableObject {
    static let shared = AudioManagerUltraSimple()
    
    // Published properties
    @Published var selectedReverbPreset: ReverbPreset = .clean
    @Published var currentAudioLevel: Float = 0.0
    @Published var isRecording: Bool = false
    @Published var lastRecordingFilename: String?
    @Published var isMonitoring: Bool = false
    @Published var cpuUsage: Double = 0.0
    @Published var customReverbSettings = CustomReverbSettings.default
    
    // Audio engine ultra-simple
    private var audioEngine: AVAudioEngine?
    private var reverbUnit: AVAudioUnitReverb?
    private var isEngineRunning = false
    
    private init() {
        print("🔥 ULTRA-SIMPLE AudioManager initializing...")
    }
    
    // MARK: - Monitoring Control (copie exacte du test qui fonctionne)
    
    func startMonitoring() {
        print("🎵 === ULTRA-SIMPLE MONITORING START ===")
        
        // Test des permissions microphone (exactement comme le test qui fonctionne)
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        print("1. Permissions microphone: \(status == .authorized ? "✅ AUTORISÉ" : "❌ REFUSÉ (\(status.rawValue))")")
        
        if status != .authorized {
            print("⚠️ PROBLÈME IDENTIFIÉ: Permissions microphone manquantes!")
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    print("Permissions accordées: \(granted)")
                    if granted {
                        self.startMonitoring()
                    }
                }
            }
            return
        }
        
        // COPIE EXACTE du test ultra-simple qui fonctionne
        let testEngine = AVAudioEngine()
        let testInput = testEngine.inputNode
        let testOutput = testEngine.outputNode
        
        let inputFormat = testInput.inputFormat(forBus: 0)
        print("2. Format input: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount) canaux")
        
        if inputFormat.sampleRate == 0 {
            print("❌ PROBLÈME IDENTIFIÉ: Format input invalide!")
            return
        }
        
        // Créer une unité de reverb pour les effets
        let reverbUnit = AVAudioUnitReverb()
        reverbUnit.wetDryMix = getCurrentWetDryMix()
        loadCurrentPreset(reverbUnit)
        testEngine.attach(reverbUnit)
        
        do {
            // Connexion: Input -> Reverb -> Output (exactement comme le test)
            testEngine.connect(testInput, to: reverbUnit, format: inputFormat)
            testEngine.connect(reverbUnit, to: testOutput, format: nil)
            testEngine.prepare()
            try testEngine.start()
            
            // Stocker les références
            self.audioEngine = testEngine
            self.reverbUnit = reverbUnit
            self.isEngineRunning = true
            self.isMonitoring = true
            
            // Installer le tap pour le niveau audio
            installAudioLevelTap(on: reverbUnit, format: inputFormat)
            
            print("✅ ULTRA-SIMPLE ENGINE DÉMARRÉ!")
            print("🎯 Connexion: Microphone -> Reverb -> Speakers")
            print("👂 Vous devriez vous entendre MAINTENANT!")
            
        } catch {
            print("❌ ERREUR ULTRA-SIMPLE: \(error.localizedDescription)")
            isMonitoring = false
        }
    }
    
    func stopMonitoring() {
        print("🔇 ULTRA-SIMPLE MONITORING STOP")
        
        if let engine = audioEngine, engine.isRunning {
            reverbUnit?.removeTap(onBus: 0)
            engine.stop()
        }
        
        audioEngine = nil
        reverbUnit = nil
        isEngineRunning = false
        isMonitoring = false
        currentAudioLevel = 0.0
        
        print("🛑 ULTRA-SIMPLE engine arrêté")
    }
    
    // MARK: - Reverb Control
    
    func updateReverbPreset(_ preset: ReverbPreset) {
        print("🎛️ ULTRA-SIMPLE: Changing preset to \(preset.rawValue)")
        selectedReverbPreset = preset
        
        guard let reverb = reverbUnit else {
            print("❌ No reverb unit available")
            return
        }
        
        // Appliquer les paramètres de reverb
        reverb.wetDryMix = getCurrentWetDryMix()
        loadCurrentPreset(reverb)
        
        print("✅ ULTRA-SIMPLE: Preset applied - wetDry: \(reverb.wetDryMix)%")
    }
    
    private func getCurrentWetDryMix() -> Float {
        switch selectedReverbPreset {
        case .clean: return 0.0
        case .vocalBooth: return 18.0
        case .studio: return 40.0
        case .cathedral: return 65.0
        case .custom: return customReverbSettings.wetDryMix
        }
    }
    
    private func loadCurrentPreset(_ reverb: AVAudioUnitReverb) {
        switch selectedReverbPreset {
        case .clean, .vocalBooth:
            reverb.loadFactoryPreset(.smallRoom)
        case .studio:
            reverb.loadFactoryPreset(.mediumRoom)
        case .cathedral:
            reverb.loadFactoryPreset(.cathedral)
        case .custom:
            reverb.loadFactoryPreset(.mediumRoom)
        }
        
        // Re-appliquer le wetDryMix après le preset (les presets le réinitialisent)
        reverb.wetDryMix = getCurrentWetDryMix()
    }
    
    // MARK: - Audio Level Monitoring
    
    private func installAudioLevelTap(on node: AVAudioNode, format: AVAudioFormat) {
        node.removeTap(onBus: 0)
        
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, time in
            guard let self = self else { return }
            
            guard let channelData = buffer.floatChannelData else { return }
            
            let frameLength = Int(buffer.frameLength)
            let channelCount = Int(buffer.format.channelCount)
            
            guard frameLength > 0 && channelCount > 0 else { return }
            
            var totalLevel: Float = 0
            
            for channel in 0..<channelCount {
                let channelPtr = channelData[channel]
                var sum: Float = 0
                
                for i in 0..<frameLength {
                    sum += abs(channelPtr[i])
                }
                
                totalLevel += sum / Float(frameLength)
            }
            
            let averageLevel = totalLevel / Float(channelCount)
            let displayLevel = min(1.0, max(0.0, averageLevel * 5.0)) // Amplifier pour l'affichage
            
            DispatchQueue.main.async {
                self.currentAudioLevel = displayLevel
            }
        }
        
        print("✅ ULTRA-SIMPLE: Audio level tap installed")
    }
    
    // MARK: - Volume Control
    
    func setInputVolume(_ volume: Float) {
        // L'input volume sera géré par l'input node si nécessaire
        if let engine = audioEngine {
            engine.inputNode.volume = max(1.0, volume)
            print("🎵 ULTRA-SIMPLE: Input volume set to \(volume)")
        }
    }
    
    func getInputVolume() -> Float {
        return audioEngine?.inputNode.volume ?? 1.0
    }
    
    func setOutputVolume(_ volume: Float, isMuted: Bool) {
        // Pour l'ultra-simple, on contrôle via le wetDryMix de la reverb
        if let reverb = reverbUnit {
            if isMuted {
                reverb.wetDryMix = 0.0
            } else {
                reverb.wetDryMix = getCurrentWetDryMix()
            }
        }
        print("🔊 ULTRA-SIMPLE: Output volume set to \(volume), muted: \(isMuted)")
    }
    
    // MARK: - Recording (stub for now)
    
    func startRecording(completion: @escaping (Bool) -> Void) {
        print("🎙️ ULTRA-SIMPLE: Recording not implemented yet")
        completion(false)
    }
    
    func stopRecording(completion: @escaping (Bool, String?, TimeInterval) -> Void) {
        print("🛑 ULTRA-SIMPLE: Recording not implemented yet")
        completion(false, nil, 0)
    }
    
    func toggleRecording() {
        print("🔄 ULTRA-SIMPLE: Recording toggle not implemented yet")
    }
    
    // MARK: - Custom Settings
    
    func updateCustomReverbSettings(_ settings: CustomReverbSettings) {
        customReverbSettings = settings
        if selectedReverbPreset == .custom {
            reverbUnit?.wetDryMix = settings.wetDryMix
        }
    }
    
    func updateCustomReverbLive(_ settings: CustomReverbSettings) {
        updateCustomReverbSettings(settings)
    }
    
    // MARK: - Info Properties
    
    var currentPresetDescription: String {
        switch selectedReverbPreset {
        case .clean: return "Pure signal (Ultra-Simple)"
        case .vocalBooth: return "Vocal booth environment (Ultra-Simple)"
        case .studio: return "Professional studio (Ultra-Simple)"
        case .cathedral: return "Spacious cathedral (Ultra-Simple)"
        case .custom: return "Custom parameters (Ultra-Simple)"
        }
    }
    
    var canStartRecording: Bool {
        return isMonitoring && !isRecording
    }
    
    var canStartMonitoring: Bool {
        return !isMonitoring
    }
    
    var engineInfo: String {
        return "Ultra-Simple AVAudioEngine"
    }
    
    func diagnostic() {
        print("🔍 === ULTRA-SIMPLE DIAGNOSTIC ===")
        print("- Selected preset: \(selectedReverbPreset.rawValue)")
        print("- Monitoring active: \(isMonitoring)")
        print("- Recording active: \(isRecording)")
        print("- Current audio level: \(currentAudioLevel)")
        print("- Engine running: \(isEngineRunning)")
        print("- Audio engine: \(audioEngine != nil ? "✅" : "❌")")
        print("- Reverb unit: \(reverbUnit != nil ? "✅" : "❌")")
        if let reverb = reverbUnit {
            print("- Reverb wetDryMix: \(reverb.wetDryMix)%")
        }
        print("=== END ULTRA-SIMPLE DIAGNOSTIC ===")
    }
}