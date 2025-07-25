import Foundation
import AVFoundation
import AudioToolbox

class AudioEngineService {
    // Audio engine components
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var mainMixer: AVAudioMixerNode?
    private var reverbNode: AVAudioUnitReverb?
    
    // CORRECTION: Chaîne simplifiée pour qualité optimale
    private var recordingMixer: AVAudioMixerNode?
    private var gainMixer: AVAudioMixerNode?          // Un seul étage de gain optimal
    private var cleanBypassMixer: AVAudioMixerNode?   // Bypass direct pour mode Clean
    
    // Advanced components for stereo effects
    private var stereoMixerL: AVAudioMixerNode?
    private var stereoMixerR: AVAudioMixerNode?
    private var delayNode: AVAudioUnitDelay?
    private var crossFeedEnabled = false
    
    // Engine state
    private var isEngineRunning = false
    private var setupAttempts = 0
    private let maxSetupAttempts = 3
    private var currentPreset: ReverbPreset = .clean
    
    // Format de connexion unifié
    private var connectionFormat: AVAudioFormat?
    
    // CORRECTION: Volumes optimaux pour qualité
    private var inputVolume: Float = 1.0    // Volume modéré par défaut
    private var monitoringGain: Float = 1.2 // Gain raisonnable
    
    // Callbacks
    var onAudioLevelChanged: ((Float) -> Void)?
    
    init() {
        setupAudioSession()
        setupAudioEngine()
    }
    
    // MARK: - Configuration optimisée
    
    private func setupAudioSession() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers]
            )
            try session.setActive(true)
            
            // CORRECTION: Configuration équilibrée pour qualité
            try session.setPreferredSampleRate(44100)
            try session.setPreferredIOBufferDuration(0.01) // Buffer plus stable
            try session.setPreferredInputNumberOfChannels(2)
            try session.setInputGain(0.8) // Gain système modéré
            
            print("✅ AVAudioSession configured for QUALITY monitoring")
        } catch {
            print("❌ Audio session configuration error: \(error.localizedDescription)")
        }
        #else
        print("🍎 macOS audio session ready for QUALITY amplification")
        requestMicrophonePermission()
        #endif
    }
    
    #if os(macOS)
    private func requestMicrophonePermission() {
        let micAccess = AVCaptureDevice.authorizationStatus(for: .audio)
        print("🎤 Microphone authorization status: \(micAccess.rawValue)")
        
        if micAccess == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    print("🎤 Microphone access granted: \(granted)")
                    if granted {
                        self.setupAudioEngine()
                    }
                }
            }
        }
    }
    #endif
    
    private func setupAudioEngine() {
        guard setupAttempts < maxSetupAttempts else {
            print("❌ Maximum setup attempts reached")
            return
        }
         
        setupAttempts += 1
        print("🎵 Setting up QUALITY-OPTIMIZED audio engine (attempt \(setupAttempts))")
        
        cleanupEngine()
        
        let engine = AVAudioEngine()
        audioEngine = engine
        
        let inputNode = engine.inputNode
        self.inputNode = inputNode
        let mainMixer = engine.mainMixerNode
        mainMixer.outputVolume = 1.4 // Gain modéré pour qualité
        self.mainMixer = mainMixer
        
        // CORRECTION: Chaîne simplifiée pour éviter la dégradation
        let gainMixer = AVAudioMixerNode()
        gainMixer.outputVolume = 1.3 // Gain équilibré
        self.gainMixer = gainMixer
        engine.attach(gainMixer)
        
        // NOUVEAU: Bypass direct pour mode Clean
        let cleanBypassMixer = AVAudioMixerNode()
        cleanBypassMixer.outputVolume = 1.2 // Gain léger pour bypass
        self.cleanBypassMixer = cleanBypassMixer
        engine.attach(cleanBypassMixer)
        
        // Configuration du reverb optimisée
        let reverb = AVAudioUnitReverb()
        reverb.loadFactoryPreset(.smallRoom)
        reverb.wetDryMix = 0 // Désactivé par défaut
        reverbNode = reverb
        engine.attach(reverb)
        
        // Recording mixer pour l'enregistrement
        let recordingMixer = AVAudioMixerNode()
        recordingMixer.outputVolume = 1.0 // Pas d'amplification excessive pour l'enregistrement
        self.recordingMixer = recordingMixer
        engine.attach(recordingMixer)
        
        // Configuration des effets stéréo
        let stereoMixerL = AVAudioMixerNode()
        let stereoMixerR = AVAudioMixerNode()
        let delayNode = AVAudioUnitDelay()
        
        engine.attach(stereoMixerL)
        engine.attach(stereoMixerR)
        engine.attach(delayNode)
        
        self.stereoMixerL = stereoMixerL
        self.stereoMixerR = stereoMixerR
        self.delayNode = delayNode
        
        delayNode.delayTime = 0.01
        delayNode.feedback = 0
        delayNode.wetDryMix = 100
        
        let inputHWFormat = inputNode.inputFormat(forBus: 0)
        print("🎤 Input format: \(inputHWFormat.sampleRate) Hz, \(inputHWFormat.channelCount) channels")
        
        guard inputHWFormat.sampleRate > 0 && inputHWFormat.channelCount > 0 else {
            print("❌ Invalid input format detected")
            if setupAttempts < maxSetupAttempts {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.setupAudioSession()
                    self.setupAudioEngine()
                }
            }
            return
        }
        
        let stereoFormat = AVAudioFormat(standardFormatWithSampleRate: inputHWFormat.sampleRate, channels: 2)!
        self.connectionFormat = stereoFormat
        print("🔗 QUALITY format: \(stereoFormat.sampleRate) Hz, \(stereoFormat.channelCount) channels")
        
        do {
            // CORRECTION CRITIQUE: Chaîne optimale pour qualité
            // Input → GainMixer → (Reverb OU CleanBypass) → RecordingMixer → MainMixer → Output
            
            try engine.connect(inputNode, to: gainMixer, format: stereoFormat)
            
            // Connexions conditionnelles selon le preset (sera configuré dans updateReverbPreset)
            try engine.connect(gainMixer, to: cleanBypassMixer, format: stereoFormat) // Connexion par défaut
            try engine.connect(cleanBypassMixer, to: recordingMixer, format: stereoFormat)
            try engine.connect(recordingMixer, to: mainMixer, format: stereoFormat)
            try engine.connect(mainMixer, to: engine.outputNode, format: nil)
            
            engine.prepare()
            print("🎵 QUALITY-OPTIMIZED audio engine configured successfully")
            print("📊 Theoretical gain: Input × Gain(1.3) × Main(1.4) = x1.8 (optimal)")
            setupAttempts = 0
        } catch {
            print("❌ Quality audio connection error: \(error.localizedDescription)")
            
            if setupAttempts < maxSetupAttempts {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.setupSimplifiedEngine()
                }
            }
        }
    }
    
    // MARK: - Accès au mixer d'enregistrement
    
    func getRecordingMixer() -> AVAudioMixerNode? {
        return recordingMixer
    }
    
    func getRecordingFormat() -> AVAudioFormat? {
        return connectionFormat
    }
    
    // MARK: - Input Volume Control OPTIMISÉ
    
    func setInputVolume(_ volume: Float) {
        // CORRECTION: Amplification raisonnable pour qualité
        let optimizedVolume = max(0.1, min(3.0, volume * 0.8)) // Range modéré 0.1-2.4
        inputVolume = optimizedVolume
        
        // Application équilibrée sur les composants
        inputNode?.volume = optimizedVolume
        gainMixer?.volume = max(1.0, optimizedVolume * 0.7) // Gain proportionnel modéré
        
        print("🎵 QUALITY input volume applied:")
        print("   - Raw volume: \(volume)")
        print("   - Optimized volume: \(optimizedVolume) (\(Int(optimizedVolume * 100))%)")
        print("   - Gain mixer: \(max(1.0, optimizedVolume * 0.7)) (\(Int(max(1.0, optimizedVolume * 0.7) * 100))%)")
    }
    
    func getInputVolume() -> Float {
        return inputVolume
    }
    
    // MARK: - Output Volume Control OPTIMISÉ
    
    func setOutputVolume(_ volume: Float, isMuted: Bool) {
        if isMuted {
            mainMixer?.outputVolume = 0.0
            return
        }
        
        // CORRECTION: Amplification équilibrée pour monitoring de qualité
        let optimizedOutput = max(0.0, min(2.5, volume * 0.9)) // Range modéré 0-2.25
        monitoringGain = optimizedOutput
        
        // Application sur le mixer principal
        mainMixer?.outputVolume = isEngineRunning ? optimizedOutput : 0.0
        
        print("🔊 QUALITY output volume applied:")
        print("   - Raw volume: \(volume)")
        print("   - Optimized output: \(optimizedOutput) (\(Int(optimizedOutput * 100))%)")
        print("   - Total theoretical gain: x\(String(format: "%.1f", optimizedOutput * max(1.0, inputVolume * 0.7)))")
    }
    
    // MARK: - Reverb Preset Management CORRIGÉ
    
    func updateReverbPreset(preset: ReverbPreset) {
        guard let engine = audioEngine,
              let reverb = reverbNode,
              let gainMixer = gainMixer,
              let cleanBypass = cleanBypassMixer,
              let recordingMixer = recordingMixer else {
            print("❌ Audio engine components not available")
            return
        }
        
        currentPreset = preset
        
        print("🎛️ Switching to preset: \(preset.rawValue)")
        
        do {
            // CORRECTION MAJEURE: Reconfiguration complète de la chaîne selon le preset
            
            // Déconnecter toutes les connexions existantes
            engine.disconnectNodeOutput(gainMixer)
            engine.disconnectNodeInput(recordingMixer)
            
            if preset == .clean {
                // MODE CLEAN: Bypass complet du reverb
                print("🎤 CLEAN MODE: Direct bypass without reverb")
                reverb.wetDryMix = 0 // Assurer que le reverb est totalement coupé
                reverb.bypass = true // Bypass complet
                
                // Connexion directe sans reverb
                try engine.connect(gainMixer, to: cleanBypass, format: connectionFormat)
                try engine.connect(cleanBypass, to: recordingMixer, format: connectionFormat)
                
            } else {
                // MODE REVERB: Passage par le reverb
                print("🎵 REVERB MODE: \(preset.rawValue)")
                reverb.bypass = false // Activer le reverb
                reverb.loadFactoryPreset(preset.preset)
                
                let targetWetDryMix = max(0, min(100, preset.wetDryMix))
                reverb.wetDryMix = targetWetDryMix
                
                // Connexion via reverb
                try engine.connect(gainMixer, to: reverb, format: connectionFormat)
                try engine.connect(reverb, to: recordingMixer, format: connectionFormat)
                
                applyAdvancedParameters(to: reverb, preset: preset)
            }
            
            print("✅ Preset '\(preset.rawValue)' applied successfully")
            
        } catch {
            print("❌ Error switching preset: \(error.localizedDescription)")
            
            // Fallback: restaurer connexion de base
            do {
                try engine.connect(gainMixer, to: cleanBypass, format: connectionFormat)
                try engine.connect(cleanBypass, to: recordingMixer, format: connectionFormat)
                reverb.wetDryMix = 0
                reverb.bypass = true
            } catch {
                print("❌ Fallback connection failed: \(error)")
            }
        }
    }
    
    // MARK: - Installation du tap optimisé pour qualité
    
    private func installAudioTap(inputNode: AVAudioInputNode, bufferSize: UInt32) {
        inputNode.removeTap(onBus: 0)
        Thread.sleep(forTimeInterval: 0.01)
        
        guard let tapFormat = connectionFormat else {
            print("❌ No connection format available for tap")
            return
        }
        
        print("🎤 Installing QUALITY-OPTIMIZED tap with format: \(tapFormat)")
        
        do {
            // CORRECTION: Buffer plus grand pour éviter les saccades
            let qualityBufferSize = max(bufferSize, 2048)
            
            inputNode.installTap(onBus: 0, bufferSize: qualityBufferSize, format: tapFormat) { [weak self] buffer, time in
                guard let self = self else { return }
                
                guard let channelData = buffer.floatChannelData else {
                    return
                }
                
                let frameLength = Int(buffer.frameLength)
                guard frameLength > 0 else { return }
                
                let channelCount = Int(buffer.format.channelCount)
                var totalLevel: Float = 0
                
                for channel in 0..<channelCount {
                    let channelPtr = channelData[channel]
                    var sum: Float = 0
                    var maxValue: Float = 0
                    
                    let stride = max(1, frameLength / 32) // Échantillonnage plus précis
                    var sampleCount = 0
                    
                    for i in Swift.stride(from: 0, to: frameLength, by: stride) {
                        let sample = abs(channelPtr[i])
                        sum += sample
                        maxValue = max(maxValue, sample)
                        sampleCount += 1
                    }
                    
                    let avgLevel = sum / Float(max(sampleCount, 1))
                    let channelLevel = max(avgLevel, maxValue * 0.6)
                    totalLevel += channelLevel
                }
                
                let finalLevel = totalLevel / Float(channelCount)
                
                // CORRECTION: Niveau affiché réaliste et stable
                let displayLevel = min(1.0, max(0, finalLevel * self.getOptimalGainFactor()))
                
                if displayLevel > 0.001 && Int.random(in: 0...500) == 0 {
                    print("🎵 Quality Audio: level=\(displayLevel), preset=\(self.currentPreset.rawValue)")
                }
                
                DispatchQueue.main.async {
                    self.onAudioLevelChanged?(displayLevel)
                }
            }
            print("✅ Quality-optimized audio tap installed successfully")
        } catch {
            print("❌ Failed to install quality audio tap: \(error)")
        }
    }
    
    // NOUVEAU: Calcul du gain optimal pour qualité
    private func getOptimalGainFactor() -> Float {
        let inputGain = max(1.0, inputVolume)
        let gainMixerLevel = max(1.0, (gainMixer?.volume ?? 1.0))
        let mainMixerLevel = max(1.0, (mainMixer?.outputVolume ?? 1.0))
        
        // Gain total équilibré pour qualité
        return min(6.0, inputGain * gainMixerLevel * mainMixerLevel)
    }
    
    // MARK: - Monitoring Control avec qualité optimisée
    
    func setMonitoring(enabled: Bool) {
        if enabled {
            startMonitoring()
        } else {
            stopMonitoring()
        }
    }
    
    private func startMonitoring() {
        guard let engine = audioEngine else {
            print("❌ Audio engine not available")
            return
        }
        
        if engine.isRunning {
            engine.stop()
            print("🔄 Engine stopped for quality restart")
            Thread.sleep(forTimeInterval: 0.1)
        }
        
        let success = startEngine()
        
        if success {
            // Application des volumes optimaux
            mainMixer?.outputVolume = 1.4
            recordingMixer?.outputVolume = 1.0
            gainMixer?.volume = 1.3
            cleanBypassMixer?.volume = 1.2
            
            setInputVolume(inputVolume)
            
            // S'assurer que le preset actuel est appliqué correctement
            updateReverbPreset(preset: currentPreset)
            
            print("🎵 QUALITY monitoring started successfully")
            print("📊 Optimal gain: x\(getOptimalGainFactor())")
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.verifyAudioFlow()
            }
        } else {
            print("❌ Failed to start quality monitoring")
        }
    }
    
    private func stopMonitoring() {
        stopEngine()
        print("🔇 Quality monitoring disabled")
    }
    
    private func verifyAudioFlow() {
        guard let engine = audioEngine,
              let reverb = reverbNode,
              let mixer = mainMixer,
              let recMixer = recordingMixer,
              let gainMix = gainMixer,
              let cleanMix = cleanBypassMixer else {
            return
        }
        
        print("🔍 QUALITY AUDIO FLOW VERIFICATION:")
        print("- Engine running: \(engine.isRunning)")
        print("- Current preset: \(currentPreset.rawValue)")
        print("- Reverb bypass: \(reverb.bypass)")
        print("- Reverb wetDryMix: \(reverb.wetDryMix)")
        print("- Input volume: \(inputNode?.volume ?? 0) (\(Int((inputNode?.volume ?? 0) * 100))%)")
        print("- Gain mixer: \(gainMix.volume) (\(Int(gainMix.volume * 100))%)")
        print("- Clean bypass: \(cleanMix.volume) (\(Int(cleanMix.volume * 100))%)")
        print("- Main mixer: \(mixer.outputVolume) (\(Int(mixer.outputVolume * 100))%)")
        print("- Recording mixer: \(recMixer.outputVolume) (\(Int(recMixer.outputVolume * 100))%)")
        print("- OPTIMAL TOTAL GAIN: x\(getOptimalGainFactor())")
        print("- Connection format: \(connectionFormat?.description ?? "none")")
    }
    
    // MARK: - Engine Control optimisé
    
    func startEngine() -> Bool {
        guard let engine = audioEngine, !isEngineRunning else {
            return isEngineRunning
        }
        
        do {
            #if os(iOS)
            try AVAudioSession.sharedInstance().setActive(true)
            #endif
            
            print("🎵 Starting QUALITY-OPTIMIZED audio engine...")
            
            try engine.start()
            isEngineRunning = true
            
            Thread.sleep(forTimeInterval: 0.1)
            
            // Application des volumes optimaux
            if let mixer = mainMixer {
                mixer.outputVolume = 1.4
            }
            
            if let recMixer = recordingMixer {
                recMixer.outputVolume = 1.0
            }
            
            if let gainMix = gainMixer {
                gainMix.volume = 1.3
            }
            
            if let cleanMix = cleanBypassMixer {
                cleanMix.volume = 1.2
            }
            
            if let inputNode = self.inputNode {
                installAudioTap(inputNode: inputNode, bufferSize: 2048) // Buffer plus stable
            }
            
            print("🎵 Quality-optimized engine started successfully")
            return true
            
        } catch {
            let nsError = error as NSError
            print("❌ Quality engine start error: \(error.localizedDescription)")
            print("   Error code: \(nsError.code)")
            
            isEngineRunning = false
            return false
        }
    }
    
    func stopEngine() {
        if let engine = audioEngine, engine.isRunning {
            if let inputNode = self.inputNode {
                inputNode.removeTap(onBus: 0)
            }
            engine.stop()
            isEngineRunning = false
            print("🛑 Quality audio engine stopped")
        }
        setupAttempts = 0
    }
    
    private func cleanupEngine() {
        if let oldEngine = audioEngine, oldEngine.isRunning {
            if let inputNode = self.inputNode {
                inputNode.removeTap(onBus: 0)
            }
            oldEngine.stop()
        }
        isEngineRunning = false
    }
    
    // MARK: - Configuration simplifiée en fallback
    
    private func setupSimplifiedEngine() {
        print("⚠️ Using simplified QUALITY configuration...")
        
        cleanupEngine()
        
        let engine = AVAudioEngine()
        audioEngine = engine
        
        let inputNode = engine.inputNode
        self.inputNode = inputNode
        let mainMixer = engine.mainMixerNode
        mainMixer.outputVolume = 1.5 // Amplification modérée même en mode simple
        self.mainMixer = mainMixer
        
        let recordingMixer = AVAudioMixerNode()
        recordingMixer.outputVolume = 1.0
        self.recordingMixer = recordingMixer
        engine.attach(recordingMixer)
        
        let inputFormat = inputNode.inputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 && inputFormat.channelCount > 0 else {
            print("❌ Cannot proceed with invalid format in simplified setup")
            return
        }
        
        self.connectionFormat = inputFormat
        
        do {
            try engine.connect(inputNode, to: recordingMixer, format: inputFormat)
            try engine.connect(recordingMixer, to: mainMixer, format: inputFormat)
            try engine.connect(mainMixer, to: engine.outputNode, format: nil)
            
            engine.prepare()
            print("✅ Simplified QUALITY configuration successful")
            setupAttempts = 0
        } catch {
            print("❌ Simplified quality configuration failed: \(error)")
        }
    }
    
    // MARK: - Advanced Parameters (reste identique)
    // Dans AudioEngineService.swift, améliorer applyAdvancedParameters pour plus de réactivité

    private func applyAdvancedParameters(to reverb: AVAudioUnitReverb, preset: ReverbPreset) {
        let audioUnit = reverb.audioUnit
        
        // Paramètres Audio Unit
        let kDecayTimeParameter: AudioUnitParameterID = 7
        let kHFDampingParameter: AudioUnitParameterID = 9
        let kRoomSizeParameter: AudioUnitParameterID = 1000
        let kDensityParameter: AudioUnitParameterID = 10
        let kPreDelayParameter: AudioUnitParameterID = 5
        
        if preset == .custom {
            // AMÉLIORATION: Application séquentielle pour éviter les conflits
            let customSettings = ReverbPreset.customSettings
            
            // Application par priorité (wetDryMix en premier pour effet immédiat)
            reverb.wetDryMix = customSettings.wetDryMix
            
            // Puis les autres paramètres
            let decayTime = max(0.1, min(8.0, customSettings.decayTime))
            safeSetParameter(audioUnit: audioUnit, paramID: kDecayTimeParameter, value: decayTime)
            
            safeSetParameter(audioUnit: audioUnit, paramID: kPreDelayParameter,
                          value: max(0, min(0.5, customSettings.preDelay / 1000.0)))
            
            safeSetParameter(audioUnit: audioUnit, paramID: kRoomSizeParameter,
                          value: max(0, min(1, customSettings.size)))
            
            safeSetParameter(audioUnit: audioUnit, paramID: kDensityParameter,
                          value: max(0, min(1, customSettings.density / 100.0)))
            
            safeSetParameter(audioUnit: audioUnit, paramID: kHFDampingParameter,
                          value: max(0, min(1, customSettings.highFrequencyDamping / 100.0)))
            
            print("🎛️ LIVE: Custom parameters applied - wetDry:\(customSettings.wetDryMix)%, decay:\(decayTime)s")
            
        } else {
            // Paramètres prédéfinis
            let decayTime = max(0.1, min(5.0, preset.decayTime))
            safeSetParameter(audioUnit: audioUnit, paramID: kDecayTimeParameter, value: decayTime)
            
            safeSetParameter(audioUnit: audioUnit, paramID: kHFDampingParameter,
                           value: max(0, min(1, preset.highFrequencyDamping / 100.0)))
        }
    }
    
    private func safeSetParameter(audioUnit: AudioUnit?, paramID: AudioUnitParameterID, value: Float) {
        guard let audioUnit = audioUnit else { return }
        
        let clampedValue = max(-100, min(100, value))
        
        let status = AudioUnitSetParameter(
            audioUnit,
            paramID,
            kAudioUnitScope_Global,
            0,
            clampedValue,
            0
        )
        
        if status != noErr {
            print("⚠️ Parameter ID \(paramID) not available (error \(status))")
        }
    }
    
    func updateCrossFeed(enabled: Bool, value: Float) {
        crossFeedEnabled = enabled
    }
    
    func diagnosticMonitoring() {
        print("🔍 === DIAGNOSTIC QUALITÉ OPTIMISÉE ===")
        
        guard let engine = audioEngine else {
            print("❌ No audio engine")
            return
        }
        
        print("🎵 Quality-Optimized Engine Status:")
        print("   - Engine running: \(engine.isRunning)")
        print("   - Current preset: \(currentPreset.rawValue)")
        print("   - Reverb bypass: \(reverbNode?.bypass ?? true)")
        print("   - Reverb wetDryMix: \(reverbNode?.wetDryMix ?? 0)")
        print("   - Input volume: \(inputNode?.volume ?? 0) (\(Int((inputNode?.volume ?? 0) * 100))%)")
        print("   - Gain mixer: \(gainMixer?.volume ?? 0) (\(Int((gainMixer?.volume ?? 0) * 100))%)")
        print("   - Clean bypass: \(cleanBypassMixer?.volume ?? 0) (\(Int((cleanBypassMixer?.volume ?? 0) * 100))%)")
        print("   - Main mixer: \(mainMixer?.outputVolume ?? 0) (\(Int((mainMixer?.outputVolume ?? 0) * 100))%)")
        print("   - Recording mixer: \(recordingMixer?.outputVolume ?? 0) (\(Int((recordingMixer?.outputVolume ?? 0) * 100))%)")
        print("   - OPTIMAL TOTAL GAIN: x\(getOptimalGainFactor())")
        print("   - Connection format: \(connectionFormat?.description ?? "none")")
        
        #if os(macOS)
        let micAccess = AVCaptureDevice.authorizationStatus(for: .audio)
        print("   - Microphone access: \(micAccess == .authorized ? "✅" : "❌")")
        #endif
        
        print("=== FIN DIAGNOSTIC QUALITÉ ===")
    }
    
    deinit {
        cleanupEngine()
        
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            print("Error deactivating audio session: \(error)")
        }
        #endif
    }
}
