import Foundation
import AVFoundation
import Combine

class AudioManager: ObservableObject {
    static let shared = AudioManager()
    
    // WORKING ARCHITECTURE: Multi-stage mixer pipeline (like successful repo)
    private var audioEngine: AVAudioEngine?
    private var reverbUnit: AVAudioUnitReverb?
    private var isEngineRunning = false
    
    // Multi-stage mixer architecture (essential for proper audio flow)
    private var gainMixer: AVAudioMixerNode?
    private var cleanBypassMixer: AVAudioMixerNode?
    private var recordingMixer: AVAudioMixerNode?
    private var mainMixer: AVAudioMixerNode?
    
    // Connection format (critical for consistency)
    private var connectionFormat: AVAudioFormat?
    
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
    @Published var isMonitoring = false
    
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
        print("🎵 WORKING REPO AudioManager: Ready for multi-stage mixer architecture")
        print("✅ Initialization complete - ready for advanced audio routing")
    }
    
    // MARK: - Public Methods
    
    func prepareAudio() {
        // No preparation needed for ultra-simple approach
        print("🔧 ULTRA-SIMPLE: Audio ready")
    }
    
    
    func startMonitoring() {
        guard !isMonitoring else {
            print("⚠️ Monitoring already active")
            return
        }
        
        print("🎵 === WORKING REPO ARCHITECTURE: Multi-Stage Mixer Pipeline ===")
        
        // Check microphone permissions
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        print("1. Microphone permissions: \(status == .authorized ? "✅ AUTHORIZED" : "❌ DENIED")")
        
        if status != .authorized {
            print("⚠️ Requesting microphone permissions...")
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.startMonitoring()
                    } else {
                        print("❌ Permissions denied")
                    }
                }
            }
            return
        }
        
        setupWorkingAudioEngine()
    }
    
    private func setupWorkingAudioEngine() {
        // Create engine and get nodes
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let outputNode = engine.outputNode
        
        // Get input format and create stereo format (critical from working repo)
        let inputFormat = inputNode.inputFormat(forBus: 0)
        print("2. Input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount) channels")
        
        guard inputFormat.sampleRate > 0 else {
            print("❌ Invalid input format!")
            return
        }
        
        // CRITICAL: Create stereo format for consistency (from working repo)
        guard let stereoFormat = AVAudioFormat(standardFormatWithSampleRate: inputFormat.sampleRate, channels: 2) else {
            print("❌ Could not create stereo format!")
            return
        }
        self.connectionFormat = stereoFormat
        
        // Create all mixer nodes (working repo architecture)
        let gainMixer = AVAudioMixerNode()
        let cleanBypassMixer = AVAudioMixerNode()
        let recordingMixer = AVAudioMixerNode()
        let mainMixer = engine.mainMixerNode
        
        // Create reverb unit
        let reverb = AVAudioUnitReverb()
        loadCurrentPreset(reverb)
        reverb.wetDryMix = getCurrentWetDryMix()
        reverb.bypass = false
        
        // Attach all nodes
        engine.attach(gainMixer)
        engine.attach(cleanBypassMixer)
        engine.attach(recordingMixer)
        engine.attach(reverb)
        
        do {
            // WORKING REPO CHAIN: Input → GainMixer → (CleanBypass OR Reverb) → RecordingMixer → MainMixer → Output
            try engine.connect(inputNode, to: gainMixer, format: stereoFormat)
            
            // Route based on preset (critical from working repo)
            if selectedReverbPreset == .clean {
                print("3. 🎤 CLEAN MODE: Input → Gain → CleanBypass → Recording → Main → Output")
                try engine.connect(gainMixer, to: cleanBypassMixer, format: stereoFormat)
                try engine.connect(cleanBypassMixer, to: recordingMixer, format: stereoFormat)
            } else {
                print("3. 🎛️ REVERB MODE: Input → Gain → Reverb → Recording → Main → Output")
                try engine.connect(gainMixer, to: reverb, format: stereoFormat)
                try engine.connect(reverb, to: recordingMixer, format: stereoFormat)
            }
            
            try engine.connect(recordingMixer, to: mainMixer, format: stereoFormat)
            // MainMixer to output is already connected by default
            
            // WORKING REPO VOLUMES: Balanced, not extreme
            gainMixer.volume = 1.3
            cleanBypassMixer.volume = 1.2
            recordingMixer.outputVolume = 1.0
            mainMixer.outputVolume = 1.4
            
            print("4. ✅ BALANCED VOLUMES: Gain=1.3, Clean=1.2, Recording=1.0, Main=1.4")
            print("🎛️ Preset: \(selectedReverbPreset.rawValue), wetDry: \(reverb.wetDryMix)%")
            
            engine.prepare()
            try engine.start()
            
            // Store references
            self.audioEngine = engine
            self.reverbUnit = reverb
            self.gainMixer = gainMixer
            self.cleanBypassMixer = cleanBypassMixer
            self.recordingMixer = recordingMixer
            self.mainMixer = mainMixer
            self.isEngineRunning = true
            self.isMonitoring = true
            
            // Install audio level monitoring on the appropriate node
            let monitorNode = selectedReverbPreset == .clean ? cleanBypassMixer : reverb
            installAudioLevelTap(on: monitorNode, format: stereoFormat)
            
            print("5. ✅ WORKING REPO MONITORING ACTIVE!")
            print("👂 You should hear yourself NOW with proper audio routing!")
            
        } catch {
            print("❌ Working repo setup error: \(error.localizedDescription)")
            isMonitoring = false
        }
    }
    
    func stopMonitoring() {
        guard isMonitoring else {
            print("⚠️ Monitoring not active")
            return
        }
        
        print("🔇 ULTRA-SIMPLE MONITORING STOP")
        
        if let engine = audioEngine, engine.isRunning {
            reverbUnit?.removeTap(onBus: 0)
            engine.stop()
        }
        
        audioEngine = nil
        reverbUnit = nil
        gainMixer = nil
        cleanBypassMixer = nil
        recordingMixer = nil
        mainMixer = nil
        connectionFormat = nil
        isEngineRunning = false
        isMonitoring = false
        currentAudioLevel = 0.0
        
        print("🛑 ULTRA-SIMPLE engine stopped")
    }
    
    func updateReverbPreset(_ preset: ReverbPreset) {
        print("📥 WORKING REPO PRESET CHANGE: \(preset.rawValue)")
        selectedReverbPreset = preset
        
        guard let engine = audioEngine,
              let gainMix = gainMixer,
              let recordingMix = recordingMixer,
              let format = connectionFormat else {
            print("❌ Engine not properly initialized for preset change")
            return
        }
        
        // CRITICAL: Dynamic routing like working repo
        do {
            print("🔄 DYNAMIC ROUTING: Disconnecting and reconnecting nodes...")
            
            // Disconnect existing connections
            engine.disconnectNodeOutput(gainMix)
            engine.disconnectNodeInput(recordingMix)
            
            if preset == .clean {
                print("🎤 SWITCHING TO CLEAN MODE: Bypassing reverb entirely")
                
                guard let cleanBypass = cleanBypassMixer else {
                    print("❌ Clean bypass mixer not available")
                    return
                }
                
                // Route through clean bypass (no reverb)
                try engine.connect(gainMix, to: cleanBypass, format: format)
                try engine.connect(cleanBypass, to: recordingMix, format: format)
                
                print("✅ CLEAN ROUTING: Gain → CleanBypass → Recording")
                
            } else {
                print("🎛️ SWITCHING TO REVERB MODE: \(preset.rawValue)")
                
                guard let reverb = reverbUnit else {
                    print("❌ Reverb unit not available")
                    return
                }
                
                // Apply preset parameters
                loadCurrentPreset(reverb)
                reverb.wetDryMix = getCurrentWetDryMix()
                reverb.bypass = false
                
                // Route through reverb
                try engine.connect(gainMix, to: reverb, format: format)
                try engine.connect(reverb, to: recordingMix, format: format)
                
                print("✅ REVERB ROUTING: Gain → Reverb(wetDry=\(reverb.wetDryMix)%) → Recording")
            }
            
            // Update audio level monitoring on the new active node
            let monitorNode = preset == .clean ? cleanBypassMixer : reverbUnit
            if let monitor = monitorNode {
                monitor.removeTap(onBus: 0)
                installAudioLevelTap(on: monitor, format: format)
            }
            
            print("✅ PRESET CHANGE COMPLETE: \(preset.rawValue)")
            
        } catch {
            print("❌ Preset routing error: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Input Volume Control
    
    func setInputVolume(_ volume: Float) {
        // WORKING REPO: Control via gain mixer (first stage)
        if let gain = gainMixer {
            // Scale volume appropriately (working repo uses balanced values)
            gain.volume = max(0.5, min(2.0, volume * 1.3))
            print("🎵 WORKING REPO: Input volume via gain mixer: \(gain.volume)")
        } else {
            print("❌ No gain mixer available for input volume control")
        }
    }
    
    func getInputVolume() -> Float {
        // Return normalized volume from gain mixer
        if let gain = gainMixer {
            return gain.volume / 1.3
        }
        return 1.0
    }
    
    func setOutputVolume(_ volume: Float, isMuted: Bool) {
        // WORKING REPO: Control via main mixer (final stage)
        if let main = mainMixer {
            if isMuted {
                main.outputVolume = 0.0
            } else {
                // Balanced scaling like working repo
                main.outputVolume = max(0.8, min(2.0, volume * 1.4))
            }
            print("🔊 WORKING REPO: Main mixer volume: \(main.outputVolume), muted: \(isMuted)")
        } else {
            print("❌ No main mixer available for output volume control")
        }
    }
    
    // MARK: - Ultra-Simple Helper Functions
    
    private func getCurrentWetDryMix() -> Float {
        // AVAudioUnitReverb.wetDryMix expects values from 0.0 to 100.0
        // where 0 = 100% dry (original), 100 = 100% wet (effect)
        switch selectedReverbPreset {
        case .clean: return 0.0    // Pure dry signal (no reverb)
        case .vocalBooth: return 25.0  // Subtle reverb
        case .studio: return 50.0      // Balanced mix
        case .cathedral: return 75.0   // Heavy reverb
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
        
        // Re-apply wetDryMix after preset (presets reset this value)
        reverb.wetDryMix = getCurrentWetDryMix()
    }
    
    private func installAudioLevelTap(on node: AVAudioNode, format: AVAudioFormat) {
        node.removeTap(onBus: 0)
        
        // Use nil format to let AVAudioEngine determine the correct format
        node.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, time in
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
            let displayLevel = min(1.0, max(0.0, averageLevel * 5.0)) // Amplify for display
            
            DispatchQueue.main.async {
                self.currentAudioLevel = displayLevel
            }
        }
        
        print("✅ ULTRA-SIMPLE: Audio level tap installed")
    }
    
    // MARK: - Recording Methods (simplified stubs for now)
    
    func startRecording(completion: @escaping (Bool) -> Void) {
        print("🎙️ ULTRA-SIMPLE: Recording not implemented yet")
        completion(false)
    }
    
    func stopRecording(completion: @escaping (Bool, String?, TimeInterval) -> Void) {
        print("🛑 ULTRA-SIMPLE: Recording not implemented yet")
        completion(false, nil, 0)
    }
    
    func startRecording() {
        guard !isRecording else {
            print("⚠️ Recording already in progress")
            return
        }
        
        guard isMonitoring else {
            print("❌ Cannot start recording: monitoring not active")
            return
        }
        
        print("🎙️ Starting WET SIGNAL recording with current reverb preset: \(selectedReverbPreset.rawValue)")
        
        currentRecordingPreset = selectedReverbPreset.rawValue
        recordingStartTime = Date()
        
        // TODO: Intégrer avec AudioEngineService ou AudioIOBridge pour démarrer l'enregistrement
        // En attendant, simuler le démarrage
        DispatchQueue.main.async {
            self.isRecording = true
        }
        
        print("✅ WET SIGNAL recording started with preset: \(currentRecordingPreset)")
    }
    
    func stopRecording() {
        guard isRecording else {
            print("⚠️ No active recording to stop")
            return
        }
        
        print("🛑 Stopping WET SIGNAL recording...")
        
        let duration = recordingStartTime?.timeIntervalSinceNow ?? 0
        let recordingInfo = "Preset: \(currentRecordingPreset), Duration: \(String(format: "%.1f", abs(duration)))s"
        
        // TODO: Intégrer avec AudioEngineService ou AudioIOBridge pour arrêter l'enregistrement
        // En attendant, simuler l'arrêt
        DispatchQueue.main.async {
            self.isRecording = false
            // Générer un nom de fichier temporaire
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            let timestamp = formatter.string(from: Date())
            self.lastRecordingFilename = "wet_reverb_\(timestamp).wav"
        }
        
        print("✅ WET SIGNAL recording completed: \(recordingInfo)")
    }
    
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
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
