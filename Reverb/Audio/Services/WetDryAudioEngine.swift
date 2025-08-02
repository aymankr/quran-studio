import Foundation
import AVFoundation
import OSLog

/// Enhanced audio engine with separate wet/dry signal paths for professional recording
/// Implements AD 480 style wet/dry separation with individual tap points
class WetDryAudioEngine: ObservableObject {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Reverb", category: "WetDryAudioEngine")
    
    // MARK: - Audio Engine Components
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var outputNode: AVAudioOutputNode?
    
    // MARK: - Audio Processing Nodes
    private var inputGainNode: AVAudioMixerNode?
    private var drySignalNode: AVAudioMixerNode?      // Clean dry signal
    private var wetSignalNode: AVAudioMixerNode?      // Reverb-processed wet signal
    private var wetDryMixerNode: AVAudioMixerNode?    // Final wet/dry mix
    private var recordingMixerNode: AVAudioMixerNode? // For recording tap
    private var outputMixerNode: AVAudioMixerNode?    // Final output
    
    // MARK: - Reverb Processing
    private var reverbUnit: AVAudioUnitReverb?
    private var reverbBridge: ReverbBridge?
    
    // MARK: - Audio Formats
    private var connectionFormat: AVAudioFormat?
    private let targetSampleRate: Double = 48000
    private let targetChannels: AVAudioChannelCount = 2
    
    // MARK: - State Management
    @Published var isEngineRunning = false
    @Published var isMonitoring = false
    @Published var wetDryMix: Float = 0.5 // 0.0 = full dry, 1.0 = full wet
    @Published var inputGain: Float = 1.0
    @Published var outputVolume: Float = 1.0
    
    // MARK: - Tap Management
    private var dryTapInstalled = false
    private var wetTapInstalled = false
    private var mixTapInstalled = false
    
    // MARK: - Initialization
    init() {
        setupAudioSession()
        logger.info("🎛️ WetDryAudioEngine initialized")
    }
    
    // MARK: - Audio Session Setup
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
            try session.setPreferredSampleRate(targetSampleRate)
            try session.setPreferredIOBufferDuration(0.01)
            try session.setPreferredInputNumberOfChannels(Int(targetChannels))
            
            logger.info("✅ iOS audio session configured for wet/dry processing")
        } catch {
            logger.error("❌ Audio session configuration error: \(error.localizedDescription)")
        }
        #else
        logger.info("🍎 macOS audio session ready for wet/dry processing")
        requestMicrophonePermission()
        #endif
    }
    
    #if os(macOS)
    private func requestMicrophonePermission() {
        let micAccess = AVCaptureDevice.authorizationStatus(for: .audio)
        
        if micAccess == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.setupAudioEngine()
                    }
                }
            }
        } else if micAccess == .authorized {
            setupAudioEngine()
        }
    }
    #endif
    
    // MARK: - Audio Engine Setup
    func setupAudioEngine() {
        logger.info("🎛️ Setting up wet/dry separation audio engine")
        
        cleanupEngine()
        
        let engine = AVAudioEngine()
        audioEngine = engine
        
        let inputNode = engine.inputNode
        self.inputNode = inputNode
        self.outputNode = engine.outputNode
        
        let inputFormat = inputNode.inputFormat(forBus: 0)
        logger.info("🎤 Input format: \(inputFormat.sampleRate) Hz, \(inputFormat.channelCount) channels")
        
        // Create optimal format for processing
        guard let processingFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: inputFormat.sampleRate,
            channels: min(inputFormat.channelCount, targetChannels),
            interleaved: false
        ) else {
            logger.error("❌ Failed to create processing format")
            return
        }
        
        self.connectionFormat = processingFormat
        
        do {
            try setupWetDryAudioGraph(engine: engine, inputNode: inputNode, format: processingFormat)
            engine.prepare()
            logger.info("✅ Wet/dry separation audio engine ready")
        } catch {
            logger.error("❌ Failed to setup wet/dry audio engine: \(error.localizedDescription)")
        }
    }
    
    private func setupWetDryAudioGraph(engine: AVAudioEngine, inputNode: AVAudioInputNode, format: AVAudioFormat) throws {
        
        // Create all audio nodes
        let inputGain = AVAudioMixerNode()
        let drySignal = AVAudioMixerNode()
        let wetSignal = AVAudioMixerNode()
        let wetDryMixer = AVAudioMixerNode()
        let recordingMixer = AVAudioMixerNode()
        let outputMixer = AVAudioMixerNode()
        
        // Create reverb unit
        let reverb = AVAudioUnitReverb()
        reverb.loadFactoryPreset(.cathedral)
        reverb.wetDryMix = 100 // 100% wet since we'll mix manually
        
        // Store references
        self.inputGainNode = inputGain
        self.drySignalNode = drySignal
        self.wetSignalNode = wetSignal
        self.wetDryMixerNode = wetDryMixer
        self.recordingMixerNode = recordingMixer
        self.outputMixerNode = outputMixer
        self.reverbUnit = reverb
        
        // Attach all nodes to engine
        engine.attach(inputGain)
        engine.attach(drySignal)
        engine.attach(wetSignal)
        engine.attach(reverb)
        engine.attach(wetDryMixer)
        engine.attach(recordingMixer)
        engine.attach(outputMixer)
        
        // Set initial volumes
        inputGain.outputVolume = self.inputGain
        drySignal.outputVolume = 1.0
        wetSignal.outputVolume = 1.0
        wetDryMixer.outputVolume = 1.0
        recordingMixer.outputVolume = 1.0
        outputMixer.outputVolume = self.outputVolume
        
        /*
         WET/DRY SEPARATION AUDIO GRAPH:
         
         Input → InputGain → ┬─→ DrySignal ─┬─→ WetDryMixer → RecordingMixer → OutputMixer → Output
                             │              │
                             └─→ Reverb → WetSignal ─┘
         
         Tap Points:
         - Dry Tap: on DrySignal node (pure dry signal)
         - Wet Tap: on WetSignal node (pure wet signal)  
         - Mix Tap: on RecordingMixer node (wet/dry mixed signal)
         */
        
        logger.info("🔗 Connecting wet/dry separation audio graph...")
        
        // Main signal path
        try engine.connect(inputNode, to: inputGain, format: format)
        
        // Dry path: Input → InputGain → DrySignal → WetDryMixer
        try engine.connect(inputGain, to: drySignal, format: format)
        try engine.connect(drySignal, to: wetDryMixer, format: format)
        
        // Wet path: Input → InputGain → Reverb → WetSignal → WetDryMixer
        try engine.connect(inputGain, to: reverb, format: format)
        try engine.connect(reverb, to: wetSignal, format: format)
        try engine.connect(wetSignal, to: wetDryMixer, format: format)
        
        // Final path: WetDryMixer → RecordingMixer → OutputMixer → Output
        try engine.connect(wetDryMixer, to: recordingMixer, format: format)
        try engine.connect(recordingMixer, to: outputMixer, format: format)
        try engine.connect(outputMixer, to: engine.outputNode, format: nil)
        
        // Initialize C++ reverb bridge for advanced processing
        initializeReverbBridge(sampleRate: format.sampleRate)
        
        // Set initial wet/dry balance
        updateWetDryMix()
        
        logger.info("✅ Wet/dry separation audio graph connected")
    }
    
    private func initializeReverbBridge(sampleRate: Double) {
        reverbBridge = ReverbBridge()
        
        if let bridge = reverbBridge {
            let success = bridge.initialize(withSampleRate: sampleRate, maxBlockSize: 512)
            if success {
                logger.info("✅ C++ ReverbBridge initialized for wet/dry processing")
            } else {
                logger.warning("⚠️ ReverbBridge failed to initialize, using AVAudioUnitReverb")
                reverbBridge = nil
            }
        }
    }
    
    // MARK: - Engine Control
    func startEngine() -> Bool {
        guard let engine = audioEngine, !engine.isRunning else {
            logger.warning("⚠️ Engine already running or not initialized")
            return false
        }
        
        do {
            try engine.start()
            DispatchQueue.main.async {
                self.isEngineRunning = true
            }
            logger.info("✅ Wet/dry audio engine started")
            return true
        } catch {
            logger.error("❌ Failed to start wet/dry audio engine: \(error.localizedDescription)")
            return false
        }
    }
    
    func stopEngine() {
        guard let engine = audioEngine, engine.isRunning else { return }
        
        engine.stop()
        DispatchQueue.main.async {
            self.isEngineRunning = false
            self.isMonitoring = false
        }
        
        logger.info("🛑 Wet/dry audio engine stopped")
    }
    
    func startMonitoring() -> Bool {
        guard startEngine() else { return false }
        
        DispatchQueue.main.async {
            self.isMonitoring = true
        }
        
        logger.info("🎧 Wet/dry monitoring started")
        return true
    }
    
    func stopMonitoring() {
        stopEngine()
        logger.info("🔇 Wet/dry monitoring stopped")
    }
    
    // MARK: - Wet/Dry Mix Control
    func setWetDryMix(_ mix: Float) {
        wetDryMix = max(0.0, min(1.0, mix)) // Clamp to 0.0-1.0
        updateWetDryMix()
    }
    
    private func updateWetDryMix() {
        guard let drySignal = drySignalNode,
              let wetSignal = wetSignalNode else { return }
        
        // AD 480 style wet/dry mixing:
        // - Dry signal volume decreases as wet increases
        // - Wet signal volume increases with wet/dry mix
        // - Equal power crossfade for smooth transitions
        
        let wetLevel = wetDryMix
        let dryLevel = 1.0 - wetDryMix
        
        // Apply equal power crossfade (cosine/sine curves)
        let wetVolume = sin(wetLevel * .pi / 2)
        let dryVolume = cos(wetLevel * .pi / 2)
        
        drySignal.outputVolume = dryVolume
        wetSignal.outputVolume = wetVolume
        
        logger.debug("🎛️ Wet/Dry mix updated - Dry: \(String(format: "%.2f", dryVolume)), Wet: \(String(format: "%.2f", wetVolume))")
    }
    
    // MARK: - Volume Control
    func setInputGain(_ gain: Float) {
        inputGain = max(0.0, min(3.0, gain))
        inputGainNode?.outputVolume = self.inputGain
    }
    
    func setOutputVolume(_ volume: Float) {
        outputVolume = max(0.0, min(3.0, volume))
        outputMixerNode?.outputVolume = self.outputVolume
    }
    
    // MARK: - Tap Installation for Recording
    func installDryTap(bufferSize: AVAudioFrameCount = 1024, tapHandler: @escaping AVAudioNodeTapBlock) -> Bool {
        guard let dryNode = drySignalNode,
              let format = connectionFormat,
              !dryTapInstalled else {
            logger.warning("⚠️ Dry tap already installed or node not available")
            return false
        }
        
        dryNode.installTap(onBus: 0, bufferSize: bufferSize, format: format, block: tapHandler)
        dryTapInstalled = true
        
        logger.info("📍 Dry signal tap installed")
        return true
    }
    
    func installWetTap(bufferSize: AVAudioFrameCount = 1024, tapHandler: @escaping AVAudioNodeTapBlock) -> Bool {
        guard let wetNode = wetSignalNode,
              let format = connectionFormat,
              !wetTapInstalled else {
            logger.warning("⚠️ Wet tap already installed or node not available")
            return false
        }
        
        wetNode.installTap(onBus: 0, bufferSize: bufferSize, format: format, block: tapHandler)
        wetTapInstalled = true
        
        logger.info("📍 Wet signal tap installed")
        return true
    }
    
    func installMixTap(bufferSize: AVAudioFrameCount = 1024, tapHandler: @escaping AVAudioNodeTapBlock) -> Bool {
        guard let mixNode = recordingMixerNode,
              let format = connectionFormat,
              !mixTapInstalled else {
            logger.warning("⚠️ Mix tap already installed or node not available")
            return false
        }
        
        mixNode.installTap(onBus: 0, bufferSize: bufferSize, format: format, block: tapHandler)
        mixTapInstalled = true
        
        logger.info("📍 Mix signal tap installed")
        return true
    }
    
    // MARK: - Tap Removal
    func removeDryTap() {
        guard let dryNode = drySignalNode, dryTapInstalled else { return }
        
        dryNode.removeTap(onBus: 0)
        dryTapInstalled = false
        
        logger.info("🗑️ Dry signal tap removed")
    }
    
    func removeWetTap() {
        guard let wetNode = wetSignalNode, wetTapInstalled else { return }
        
        wetNode.removeTap(onBus: 0)
        wetTapInstalled = false
        
        logger.info("🗑️ Wet signal tap removed")
    }
    
    func removeMixTap() {
        guard let mixNode = recordingMixerNode, mixTapInstalled else { return }
        
        mixNode.removeTap(onBus: 0)
        mixTapInstalled = false
        
        logger.info("🗑️ Mix signal tap removed")
    }
    
    func removeAllTaps() {
        removeDryTap()
        removeWetTap()
        removeMixTap()
        
        logger.info("🗑️ All signal taps removed")
    }
    
    // MARK: - Reverb Preset Management
    func applyReverbPreset(_ preset: ReverbPreset) {
        // Apply to AVAudioUnitReverb
        if let reverb = reverbUnit {
            switch preset {
            case .clean:
                reverb.wetDryMix = 0
            case .vocalBooth:
                reverb.loadFactoryPreset(.smallRoom)
                reverb.wetDryMix = 100
            case .studio:
                reverb.loadFactoryPreset(.mediumRoom)
                reverb.wetDryMix = 100
            case .cathedral:
                reverb.loadFactoryPreset(.cathedral)
                reverb.wetDryMix = 100
            case .custom:
                // Custom settings handled separately
                reverb.wetDryMix = 100
            }
        }
        
        // Apply to C++ ReverbBridge if available
        if let bridge = reverbBridge {
            let cppPreset: Int32
            switch preset {
            case .clean: cppPreset = 0
            case .vocalBooth: cppPreset = 1
            case .studio: cppPreset = 2
            case .cathedral: cppPreset = 3
            case .custom: cppPreset = 4
            }
            
            bridge.setPreset(ReverbPresetType(rawValue: Int(cppPreset))!)
        }
        
        logger.info("🎛️ Applied reverb preset: \(preset.rawValue)")
    }
    
    // MARK: - Diagnostics
    func getEngineStatus() -> [String: Any] {
        return [
            "engine_running": isEngineRunning,
            "monitoring": isMonitoring,
            "wet_dry_mix": wetDryMix,
            "input_gain": inputGain,
            "output_volume": outputVolume,
            "dry_tap_installed": dryTapInstalled,
            "wet_tap_installed": wetTapInstalled,
            "mix_tap_installed": mixTapInstalled,
            "sample_rate": connectionFormat?.sampleRate ?? 0,
            "channels": connectionFormat?.channelCount ?? 0,
            "reverb_bridge_available": reverbBridge != nil
        ]
    }
    
    func printDiagnostics() {
        logger.info("🔍 === WET/DRY AUDIO ENGINE DIAGNOSTICS ===")
        let status = getEngineStatus()
        
        for (key, value) in status {
            logger.info("- \(key): \(String(describing: value))")
        }
        
        logger.info("=== END DIAGNOSTICS ===")
    }
    
    // MARK: - Cleanup
    private func cleanupEngine() {
        removeAllTaps()
        
        if let engine = audioEngine, engine.isRunning {
            engine.stop()
        }
        
        audioEngine = nil
        inputNode = nil
        outputNode = nil
        inputGainNode = nil
        drySignalNode = nil
        wetSignalNode = nil
        wetDryMixerNode = nil
        recordingMixerNode = nil
        outputMixerNode = nil
        reverbUnit = nil
        reverbBridge = nil
        
        DispatchQueue.main.async {
            self.isEngineRunning = false
            self.isMonitoring = false
        }
        
        logger.info("🧹 Wet/dry audio engine cleaned up")
    }
    
    deinit {
        cleanupEngine()
        logger.info("🗑️ WetDryAudioEngine deinitialized")
    }
}

// MARK: - Extensions
extension WetDryAudioEngine {
    
    /// Get the current wet/dry mix as a percentage string
    var wetDryMixPercentage: String {
        return String(format: "%.0f%% Wet / %.0f%% Dry", wetDryMix * 100, (1.0 - wetDryMix) * 100)
    }
    
    /// Check if the engine is ready for recording
    var isReadyForRecording: Bool {
        return isEngineRunning && isMonitoring && connectionFormat != nil
    }
    
    /// Get the optimal recording format
    var recordingFormat: AVAudioFormat? {
        return connectionFormat
    }
}