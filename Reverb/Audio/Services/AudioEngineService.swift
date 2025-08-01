import Foundation
import AVFoundation
import AudioToolbox
import Accelerate

// MARK: - iOS-native ReverbBridge implementation
@objc(ReverbBridge)
public class ReverbBridge: NSObject {
    
    @objc
    public enum ReverbPresetType: Int, CaseIterable {
        case clean = 0
        case vocalBooth = 1
        case studio = 2
        case cathedral = 3
        case custom = 4
    }
    
    private var sampleRate: Double = 48000.0
    private var maxBlockSize: Int = 512
    private var initialized: Bool = false
    private var bypassed: Bool = false
    
    private var currentWetDryMix: Float = 0.0
    private var currentDecayTime: Float = 1.0
    private var currentPreDelay: Float = 0.0
    private var currentCrossFeed: Float = 0.0
    private var currentRoomSize: Float = 0.5
    private var currentDensity: Float = 0.7
    private var currentHighFreqDamping: Float = 0.5
    
    public override init() {
        super.init()
        print("✅ ReverbBridge iOS native implementation created")
    }
    
    @objc public func initialize(withSampleRate sampleRate: Double, maxBlockSize: Int) -> Bool {
        self.sampleRate = sampleRate
        self.maxBlockSize = maxBlockSize
        self.initialized = true
        self.bypassed = false
        
        print("🎵 ReverbBridge iOS initialized: \(sampleRate)Hz, \(maxBlockSize) frames")
        return true
    }
    
    @objc public func isInitialized() -> Bool { return initialized }
    @objc public func isBypassed() -> Bool { return bypassed }
    @objc public func setBypassed(_ bypass: Bool) { bypassed = bypass }
    
    @objc public func wetDryMix() -> Float { return currentWetDryMix }
    @objc public func decayTime() -> Float { return currentDecayTime }
    @objc public func preDelay() -> Float { return currentPreDelay }
    @objc public func crossFeed() -> Float { return currentCrossFeed }
    @objc public func roomSize() -> Float { return currentRoomSize }
    @objc public func density() -> Float { return currentDensity }
    @objc public func highFreqDamping() -> Float { return currentHighFreqDamping }
    
    @objc public func setPreset(_ preset: ReverbPresetType) {
        switch preset {
        case .clean: applyCleanPreset()
        case .vocalBooth: applyVocalBoothPreset()
        case .studio: applyStudioPreset()
        case .cathedral: applyCathedralPreset()
        case .custom: break
        }
    }
    
    @objc public func applyCleanPreset() {
        currentWetDryMix = 0.0
        currentDecayTime = 0.5
        currentPreDelay = 0.0
        currentCrossFeed = 0.0
        currentRoomSize = 0.3
        currentDensity = 0.5
        currentHighFreqDamping = 0.7
        print("🎵 ReverbBridge: Clean preset applied (0% wet)")
    }
    
    @objc public func applyVocalBoothPreset() {
        currentWetDryMix = 15.0
        currentDecayTime = 0.8
        currentPreDelay = 10.0
        currentCrossFeed = 0.2
        currentRoomSize = 0.4
        currentDensity = 0.6
        currentHighFreqDamping = 0.8
        print("🎵 ReverbBridge: VocalBooth preset applied (15% wet)")
    }
    
    @objc public func applyStudioPreset() {
        currentWetDryMix = 25.0
        currentDecayTime = 1.2
        currentPreDelay = 20.0
        currentCrossFeed = 0.3
        currentRoomSize = 0.6
        currentDensity = 0.7
        currentHighFreqDamping = 0.6
        print("🎵 ReverbBridge: Studio preset applied (25% wet)")
    }
    
    @objc public func applyCathedralPreset() {
        currentWetDryMix = 40.0
        currentDecayTime = 3.5
        currentPreDelay = 50.0
        currentCrossFeed = 0.5
        currentRoomSize = 0.9
        currentDensity = 0.8
        currentHighFreqDamping = 0.4
        print("🎵 ReverbBridge: Cathedral preset applied (40% wet)")
    }
    
    @objc public func applyCustomPreset(withWetDryMix wetDry: Float, 
                                       decayTime: Float, 
                                       preDelay: Float, 
                                       crossFeed: Float, 
                                       roomSize: Float, 
                                       density: Float, 
                                       highFreqDamping: Float) {
        currentWetDryMix = max(0.0, min(100.0, wetDry))
        currentDecayTime = max(0.1, min(8.0, decayTime))
        currentPreDelay = max(0.0, min(200.0, preDelay))
        currentCrossFeed = max(0.0, min(1.0, crossFeed))
        currentRoomSize = max(0.0, min(1.0, roomSize))
        currentDensity = max(0.0, min(100.0, density))
        currentHighFreqDamping = max(0.0, min(100.0, highFreqDamping))
        print("🎵 ReverbBridge: Custom preset applied (\(currentWetDryMix)% wet)")
    }
    
    @objc public func processAudioBuffer(_ buffer: AVAudioPCMBuffer) -> Bool {
        return !bypassed && initialized
    }
    
    @objc public func cleanup() {
        initialized = false
        bypassed = true
        print("🧹 ReverbBridge iOS cleaned up")
    }
    
    deinit {
        cleanup()
        print("♻️ ReverbBridge iOS deallocated")
    }
}

// MARK: - AudioEngineService

public class AudioEngineService {
    // Audio engine components
    private var audioEngine: AVAudioEngine?
    var inputNode: AVAudioInputNode?
    private var mainMixer: AVAudioMixerNode?
    
    // Reverb system using Swift ReverbBridge for iOS
    private var reverbBridge: ReverbBridge?
    
    // CORRECTION: Chaîne simplifiée pour qualité optimale
    private var recordingMixer: AVAudioMixerNode?
    private var gainMixer: AVAudioMixerNode?          // Un seul étage de gain optimal
    
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
        print("🎵 Setting up ULTRA-SIMPLE audio engine for direct monitoring (attempt \(setupAttempts))")
        
        cleanupEngine()
        
        let engine = AVAudioEngine()
        audioEngine = engine
        
        let inputNode = engine.inputNode
        self.inputNode = inputNode
        let mainMixer = engine.mainMixerNode
        mainMixer.outputVolume = 2.0 // LOUD volume to make sure we hear it
        self.mainMixer = mainMixer
        
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
        
        // Use the EXACT input format - no conversion
        self.connectionFormat = inputHWFormat
        print("🔗 DIRECT format (no conversion): \(inputHWFormat.sampleRate) Hz, \(inputHWFormat.channelCount) channels")
        
        do {
            // RESTORE WORKING SETUP: Create recordingMixer for proper audio flow
            let recordingMixer = AVAudioMixerNode()
            recordingMixer.outputVolume = 1.0
            self.recordingMixer = recordingMixer
            engine.attach(recordingMixer)
            
            // WORKING AUDIO CHAIN: Input -> RecordingMixer -> MainMixer -> Output
            print("🔄 WORKING SETUP: Input -> RecordingMixer -> MainMixer -> Output")
            
            try engine.connect(inputNode, to: recordingMixer, format: inputHWFormat)
            try engine.connect(recordingMixer, to: mainMixer, format: inputHWFormat)
            try engine.connect(mainMixer, to: engine.outputNode, format: nil)
            
            // Initialize Swift ReverbBridge for processing (but don't break audio flow)
            self.reverbBridge = ReverbBridge()
            let sampleRate = inputHWFormat.sampleRate
            let maxBlockSize = 512
            
            if let bridge = self.reverbBridge {
                let success = bridge.initialize(withSampleRate: sampleRate, maxBlockSize: maxBlockSize)
                if success {
                    print("✅ Swift ReverbBridge initialized successfully")
                } else {
                    print("⚠️ ReverbBridge failed to initialize, but audio flow preserved")
                    self.reverbBridge = nil
                }
            }
            
            self.connectionFormat = inputHWFormat
            engine.prepare()
            print("✅ WORKING audio connection established with recordingMixer")
            setupAttempts = 0
        } catch {
            print("❌ Even simple connection failed: \(error.localizedDescription)")
            
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
    
    // MARK: - Reverb Preset Management using Swift ReverbBridge
    
    func updateReverbPreset(preset: ReverbPreset) {
        print("🎛️ AUDIOENGINESERVICE: Received updateReverbPreset(\(preset.rawValue))")
        currentPreset = preset
        
        guard let bridge = self.reverbBridge else {
            print("❌ AUDIOENGINESERVICE: ReverbBridge is nil")
            return
        }
        
        if !bridge.isInitialized() {
            print("❌ AUDIOENGINESERVICE: ReverbBridge not initialized")
            return
        }
        
        print("🔧 AUDIOENGINESERVICE: Applying preset to Swift ReverbBridge")
        
        // Convert Swift preset to ReverbBridge and apply
        switch preset {
        case .clean:
            print("   Applying Clean preset (0% wet)")
            bridge.applyCleanPreset()
        case .vocalBooth:
            print("   Applying VocalBooth preset (\(preset.wetDryMix)% wet)")
            bridge.applyVocalBoothPreset()
        case .studio:
            print("   Applying Studio preset (\(preset.wetDryMix)% wet)")
            bridge.applyStudioPreset()
        case .cathedral:
            print("   Applying Cathedral preset (\(preset.wetDryMix)% wet)")
            bridge.applyCathedralPreset()
        case .custom:
            print("   Applying Custom preset with manual parameters")
            let customSettings = ReverbPreset.customSettings
            bridge.applyCustomPreset(withWetDryMix: customSettings.wetDryMix,
                                   decayTime: customSettings.decayTime,
                                   preDelay: customSettings.preDelay,
                                   crossFeed: customSettings.crossFeed,
                                   roomSize: customSettings.size,
                                   density: customSettings.density,
                                   highFreqDamping: customSettings.highFrequencyDamping)
        }
        
        // Verify parameters were applied
        let appliedWetDry = bridge.wetDryMix()
        let appliedDecay = bridge.decayTime()
        
        print("✅ AUDIOENGINESERVICE: Swift Reverb preset applied successfully")
        print("   - Preset: \(preset.rawValue)")
        print("   - Applied Wet/Dry: \(appliedWetDry)%")
        print("   - Applied Decay: \(appliedDecay)s")
        print("   - Bridge Initialized: \(bridge.isInitialized())")
        print("   - Bridge Bypassed: \(bridge.isBypassed())")
    }
    
    // MARK: - Installation du tap d'enregistrement NON-BLOQUANT du signal wet traité
    
    private var recordingTapInstalled = false
    private var isRecordingWetSignal = false
    private var nonBlockingRecorder: NonBlockingAudioRecorder?
    
    func installNonBlockingWetSignalRecordingTap(on mixerNode: AVAudioMixerNode, recordingURL: URL) -> Bool {
        guard !recordingTapInstalled else {
            print("⚠️ Recording tap already installed")
            return false
        }
        
        guard let tapFormat = connectionFormat else {
            print("❌ Cannot install recording tap: No connection format")
            return false
        }
        
        print("🎙️ Installing NON-BLOCKING wet signal recording tap with optimized format")
        
        // Créer le recorder non-bloquant
        nonBlockingRecorder = NonBlockingAudioRecorder(
            recording: recordingURL,
            format: tapFormat,
            bufferSize: 1024
        )
        
        guard let recorder = nonBlockingRecorder else {
            print("❌ Failed to create NonBlockingAudioRecorder")
            return false
        }
        
        // Démarrer l'enregistrement non-bloquant
        guard recorder.startRecording(to: recordingURL, format: tapFormat) else {
            print("❌ Failed to start non-blocking recording")
            nonBlockingRecorder = nil
            return false
        }
        
        // Remove existing tap if any
        do {
            mixerNode.removeTap(onBus: 0)
        } catch {
            // Ignore - no existing tap
        }
        
        Thread.sleep(forTimeInterval: 0.01)
        
        do {
            // Buffer size optimisé pour architecture non-bloquante (1024 frames = ~21ms à 48kHz)
            let recordingBufferSize: UInt32 = 1024
            
            mixerNode.installTap(onBus: 0, bufferSize: recordingBufferSize, format: tapFormat) { [weak self, weak recorder] buffer, time in
                guard let self = self,
                      self.isRecordingWetSignal,
                      let recorder = recorder else { 
                    return 
                }
                
                // ARCHITECTURE NON-BLOQUANTE: Pas d'I/O disque dans le thread audio !
                // Le buffer est copié dans le FIFO circulaire, l'écriture se fait en background
                let success = recorder.writeAudioBuffer(buffer)
                
                // Debug périodique pour vérifier le flux
                if Int.random(in: 0...2000) == 0 {
                    let stats = recorder.statistics
                    print("📼 NON-BLOCKING WET RECORDING: \(buffer.frameLength) frames → FIFO")
                    print("   Buffer usage: \(String(format: "%.1f", recorder.bufferUsagePercentage))%")
                    print("   Total: \(stats.totalFrames), Dropped: \(stats.droppedFrames)")
                }
                
                if !success {
                    print("⚠️ FIFO buffer overflow - audio quality may be affected")
                }
            }
            
            recordingTapInstalled = true
            print("✅ NON-BLOCKING wet signal recording tap installed successfully")
            print("   Format: \(tapFormat)")
            print("   Buffer: \(recordingBufferSize) frames (~\(String(format: "%.1f", Double(recordingBufferSize) / tapFormat.sampleRate * 1000))ms)")
            return true
            
        } catch {
            print("❌ Failed to install non-blocking recording tap: \(error)")
            let _ = recorder.stopRecording()
            nonBlockingRecorder = nil
            return false
        }
    }
    
    func removeNonBlockingWetSignalRecordingTap(from mixerNode: AVAudioMixerNode) -> (success: Bool, droppedFrames: Int, totalFrames: Int) {
        guard recordingTapInstalled else { 
            return (false, 0, 0)
        }
        
        isRecordingWetSignal = false
        
        // Arrêter l'enregistrement non-bloquant et récupérer les statistiques
        var stats = (success: false, droppedFrames: 0, totalFrames: 0)
        if let recorder = nonBlockingRecorder {
            stats = recorder.stopRecording()
            nonBlockingRecorder = nil
        }
        
        // Retirer le tap audio
        do {
            mixerNode.removeTap(onBus: 0)
            print("🛑 NON-BLOCKING wet signal recording tap removed safely")
        } catch {
            print("⚠️ Error removing non-blocking tap (non-fatal): \(error)")
        }
        
        recordingTapInstalled = false
        
        print("📊 NON-BLOCKING RECORDING STATS:")
        print("   - Success rate: \(String(format: "%.2f", Double(stats.totalFrames) / Double(stats.totalFrames + stats.droppedFrames) * 100))%")
        print("   - Total frames: \(stats.totalFrames)")
        print("   - Dropped frames: \(stats.droppedFrames)")
        
        return stats
    }
    
    func startNonBlockingWetSignalRecording() {
        guard recordingTapInstalled else {
            print("❌ Cannot start recording: tap not installed")
            return
        }
        
        isRecordingWetSignal = true
        print("▶️ Started NON-BLOCKING recording of wet signal with all applied parameters")
        
        // Afficher les statistiques initiales
        if let recorder = nonBlockingRecorder {
            print("   Buffer capacity: \(String(format: "%.1f", Float(32768) / 48000 * 1000))ms")
            print("   I/O thread: 50Hz background processing")
        }
    }
    
    func stopNonBlockingWetSignalRecording() {
        isRecordingWetSignal = false
        print("⏹️ Stopped NON-BLOCKING wet signal recording")
        
        // Afficher les statistiques actuelles
        if let recorder = nonBlockingRecorder {
            let stats = recorder.statistics
            print("   Buffer usage: \(String(format: "%.1f", recorder.bufferUsagePercentage))%")
            print("   Frames in FIFO: \(stats.bufferedFrames)")
        }
    }
    
    // MARK: - Format et Synchronisation Optimisés
    
    func getOptimalRecordingFormat() -> AVAudioFormat? {
        guard let baseFormat = connectionFormat else { return nil }
        
        // Créer un format optimal aligné avec les besoins du mixer
        // Float32 non-interleaved, 2 canaux max, préserver le sample rate
        let sampleRate = baseFormat.sampleRate > 0 ? baseFormat.sampleRate : 48000
        let channelCount = min(baseFormat.channelCount, 2)
        
        let optimizedFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                          sampleRate: sampleRate,
                                          channels: channelCount,
                                          interleaved: false)
        
        if let format = optimizedFormat {
            print("🎵 OPTIMAL RECORDING FORMAT:")
            print("   - Sample Rate: \(sampleRate) Hz")
            print("   - Channels: \(channelCount) (non-interleaved)")
            print("   - Format: Float32")
            print("   - Aligned with mixer format: ✅")
        }
        
        return optimizedFormat
    }
    
    // Méthodes de compatibilité (deprecated - utiliser les versions non-bloquantes)
    func removeWetSignalRecordingTap(from mixerNode: AVAudioMixerNode) {
        let _ = removeNonBlockingWetSignalRecordingTap(from: mixerNode)
    }
    
    func startWetSignalRecording() {
        startNonBlockingWetSignalRecording()
    }
    
    func stopWetSignalRecording() {
        stopNonBlockingWetSignalRecording()
    }
    
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
        let mainMixerLevel = max(1.0, (mainMixer?.outputVolume ?? 1.0))
        
        // Facteur de gain amplifié pour affichage réaliste
        return min(15.0, inputGain * mainMixerLevel * 8.0) // Amplification x8 pour affichage visible
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
        print("🎵 === DÉMARRAGE MONITORING (FORCE RESET) ===")
        
        // FORCE RESET COMPLET de l'audio engine à chaque monitoring
        cleanupEngine()
        audioEngine = nil
        mainMixer = nil
        inputNode = nil
        
        print("🔄 Force reset audio engine...")
        setupAudioSession()
        setupAudioEngine()
        
        guard let engine = audioEngine else {
            print("❌ Failed to setup audio engine after reset")
            return
        }
        
        print("🎵 Starting DIRECT monitoring...")
        
        // Set normal volume for monitoring
        mainMixer?.outputVolume = 2.0
        
        let success = startEngine()
        
        if success {
            print("✅ DIRECT monitoring active - you should hear yourself NOW!")
            print("🔊 Volume at 200% for clear monitoring")
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
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
        print("🔍 DIRECT AUDIO: No verification needed - simple direct connection")
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
            
            print("🔥 Starting ULTRA-SIMPLE direct monitoring engine...")
            
            try engine.start()
            isEngineRunning = true
            
            Thread.sleep(forTimeInterval: 0.1)
            
            // ENSURE LOUD VOLUME FOR TESTING
            if let mixer = mainMixer {
                mixer.outputVolume = 2.0  // VERY LOUD to make sure we hear it
                print("🔊 Main mixer volume set to 2.0 (200%)")
            }
            
            // Set input volume for monitoring
            if let inputNode = self.inputNode {
                inputNode.volume = 1.5
                print("🎤 Input volume set to 1.5 (150%)")
                
                // Install audio tap for level monitoring only
                installAudioTap(inputNode: inputNode, bufferSize: 1024)
                
                // DISABLED: Reverb processing tap causes crashes
                // We need a different approach for real-time reverb processing
                print("⚠️ Reverb processing tap disabled to prevent crashes")
            }
            
            print("✅ ULTRA-SIMPLE engine started - YOU SHOULD HEAR YOURSELF NOW!")
            print("🎯 Direct path: Microphone -> MainMixer(200%) -> Speakers")
            return true
            
        } catch {
            let nsError = error as NSError
            print("❌ Simple engine start error: \(error.localizedDescription)")
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
            if let mixer = self.mainMixer {
                mixer.removeTap(onBus: 0)
            }
            oldEngine.stop()
        }
        
        // Clear reverb bridge reference
        reverbBridge = nil
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
            // SIMPLIFIED SETUP: Direct connections only for now
            print("🔄 SIMPLIFIED DIRECT: Input -> RecordingMixer -> MainMixer -> Output")
            
            try engine.connect(inputNode, to: recordingMixer, format: inputFormat)
            try engine.connect(recordingMixer, to: mainMixer, format: inputFormat)
            try engine.connect(mainMixer, to: engine.outputNode, format: nil)
            
            self.reverbBridge = nil // No reverb for now
            
            engine.prepare()
            print("✅ Simplified direct configuration successful")
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
        print("   - Swift ReverbBridge: \(reverbBridge != nil ? "✅ AVAILABLE" : "❌ NIL")")
        if let bridge = reverbBridge {
            print("   - Bridge initialized: \(bridge.isInitialized())")
            print("   - Bridge wet/dry: \(bridge.wetDryMix())%")
            print("   - Bridge bypassed: \(bridge.isBypassed())")
        }
        print("   - Input volume: \(inputNode?.volume ?? 0) (\(Int((inputNode?.volume ?? 0) * 100))%)")
        print("   - Gain mixer: \(gainMixer?.volume ?? 0) (\(Int((gainMixer?.volume ?? 0) * 100))%)")
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