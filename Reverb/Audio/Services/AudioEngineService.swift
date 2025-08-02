import Foundation
import AVFoundation
import AudioToolbox

// MARK: - AudioEngineService using C++ ReverbBridge
public class AudioEngineService {
    // Logging control - disable verbose logging for cleaner console
    private let verboseLogging = false
    // Audio engine components
    private var audioEngine: AVAudioEngine?
    var inputNode: AVAudioInputNode?
    private var mainMixer: AVAudioMixerNode?
    
    // C++ Reverb system - using real C++ ReverbBridge
    private var reverbBridge: ReverbBridge?
    private var audioIOBridge: AudioIOBridge?
    
    // Audio chain components
    private var recordingMixer: AVAudioMixerNode?
    private var gainMixer: AVAudioMixerNode?
    
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
    
    // Volume controls
    private var inputVolume: Float = 1.0
    private var monitoringGain: Float = 1.2
    
    // Callbacks
    var onAudioLevelChanged: ((Float) -> Void)?
    
    init() {
        setupAudioSession()
        setupAudioEngine()
    }
    
    // MARK: - Audio Session Setup
    
    private func setupAudioSession() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            
            // Check if running on simulator to adjust settings
            #if targetEnvironment(simulator)
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setPreferredIOBufferDuration(0.05) // Larger buffer for simulator
            #else
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setPreferredIOBufferDuration(0.02) // 20ms for real device
            #endif
            
            // Safe audio settings
            try session.setPreferredSampleRate(48000)
            try session.setPreferredInputNumberOfChannels(1)
            try session.setActive(true)
            
            print("✅ C++ AudioEngineService: Audio session configured for stable performance")
        } catch {
            print("⚠️ C++ AudioEngineService: Audio session setup warning: \(error)")
            // Continue anyway - app can still function
        }
        #endif
    }
    
    // MARK: - Engine Setup
    
    private func setupAudioEngine() {
        if verboseLogging { print("🎵 C++ AudioEngineService: Setting up audio engine with C++ bridge") }
        
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            print("❌ C++ AudioEngineService: Failed to create audio engine")
            return
        }
        
        inputNode = audioEngine.inputNode
        mainMixer = audioEngine.mainMixerNode
        
        // Initialize C++ bridges
        reverbBridge = ReverbBridge()
        
        guard let reverbBridge = reverbBridge else {
            print("❌ C++ AudioEngineService: Failed to create ReverbBridge")
            return
        }
        
        audioIOBridge = AudioIOBridge(reverbBridge: reverbBridge)
        
        // Setup audio format
        guard let inputNode = inputNode else {
            print("❌ C++ AudioEngineService: Input node not available")
            return
        }
        
        let inputFormat = inputNode.inputFormat(forBus: 0)
        connectionFormat = AVAudioFormat(standardFormatWithSampleRate: inputFormat.sampleRate, channels: 2)
        
        guard let connectionFormat = connectionFormat else {
            print("❌ C++ AudioEngineService: Failed to create connection format")
            return
        }
        
        // Initialize C++ engine with conservative block size for stability
        #if targetEnvironment(simulator)
        let blockSize = 1024 // Larger buffer for simulator
        #else
        let blockSize = 512  // Smaller buffer for real device
        #endif
        let success = reverbBridge.initialize(withSampleRate: inputFormat.sampleRate, maxBlockSize: Int32(blockSize))
        if !success {
            print("❌ C++ AudioEngineService: Failed to initialize ReverbBridge")
            return
        }
        
        // Setup C++ AudioIOBridge
        if !audioIOBridge!.setupAudioEngine() {
            print("❌ C++ AudioEngineService: Failed to setup AudioIOBridge")
            return
        }
        
        print("✅ C++ AudioEngineService: Audio engine setup complete with C++ bridges")
    }
    
    // MARK: - Engine Control
    
    func startMonitoring() -> Bool {
        guard let audioIOBridge = audioIOBridge else {
            print("❌ C++ AudioEngineService: AudioIOBridge not available")
            return false
        }
        
        if verboseLogging { print("🎵 C++ AudioEngineService: Starting monitoring with C++ engine") }
        audioIOBridge.setMonitoring(true)
        isEngineRunning = audioIOBridge.isEngineRunning()
        
        if isEngineRunning {
            print("✅ C++ AudioEngineService: Monitoring started successfully")
        } else {
            print("❌ C++ AudioEngineService: Failed to start monitoring")
        }
        
        return isEngineRunning
    }
    
    func stopMonitoring() {
        guard let audioIOBridge = audioIOBridge else {
            print("❌ C++ AudioEngineService: AudioIOBridge not available")
            return
        }
        
        print("🛑 C++ AudioEngineService: Stopping monitoring")
        audioIOBridge.setMonitoring(false)
        isEngineRunning = false
    }
    
    func resetEngine() {
        guard let audioIOBridge = audioIOBridge else {
            print("❌ C++ AudioEngineService: AudioIOBridge not available")
            return
        }
        
        print("🔄 C++ AudioEngineService: Resetting engine")
        audioIOBridge.resetEngine()
    }
    
    // MARK: - Reverb Control
    
    func setReverbPreset(_ preset: ReverbPreset) {
        guard let reverbBridge = reverbBridge, let audioIOBridge = audioIOBridge else {
            print("❌ C++ AudioEngineService: Bridges not available")
            return
        }
        
        print("🎛️ C++ AudioEngineService: Setting reverb preset: \(preset)")
        currentPreset = preset
        
        // Map Swift preset to C++ preset using integer values
        let cppPreset: Int32
        switch preset {
        case .clean:
            cppPreset = 0
        case .vocalBooth:
            cppPreset = 1
        case .studio:
            cppPreset = 2
        case .cathedral:
            cppPreset = 3
        case .custom:
            cppPreset = 4
        }
        
        // Apply preset to both bridges using raw values
        reverbBridge.setPreset(ReverbPresetType(rawValue: Int(cppPreset))!)
        audioIOBridge.setReverbPreset(ReverbPresetType(rawValue: Int(cppPreset))!)
        
        print("✅ C++ AudioEngineService: Reverb preset applied: \(preset)")
    }
    
    func setWetDryMix(_ wetDryMix: Float) {
        guard let reverbBridge = reverbBridge, let audioIOBridge = audioIOBridge else {
            print("❌ C++ AudioEngineService: Bridges not available")
            return
        }
        
        reverbBridge.setWetDryMix(wetDryMix)
        audioIOBridge.setWetDryMix(wetDryMix)
        print("🎛️ C++ AudioEngineService: WetDryMix set to \(wetDryMix)")
    }
    
    func setDecayTime(_ decayTime: Float) {
        guard let reverbBridge = reverbBridge, let audioIOBridge = audioIOBridge else {
            print("❌ C++ AudioEngineService: Bridges not available")
            return
        }
        
        reverbBridge.setDecayTime(decayTime)
        audioIOBridge.setDecayTime(decayTime)
        print("🎛️ C++ AudioEngineService: DecayTime set to \(decayTime)")
    }
    
    func setPreDelay(_ preDelay: Float) {
        guard let reverbBridge = reverbBridge, let audioIOBridge = audioIOBridge else {
            print("❌ C++ AudioEngineService: Bridges not available")
            return
        }
        
        reverbBridge.setPreDelay(preDelay)
        audioIOBridge.setPreDelay(preDelay)
        print("🎛️ C++ AudioEngineService: PreDelay set to \(preDelay)")
    }
    
    func setCrossFeed(_ crossFeed: Float) {
        guard let reverbBridge = reverbBridge, let audioIOBridge = audioIOBridge else {
            print("❌ C++ AudioEngineService: Bridges not available")
            return
        }
        
        reverbBridge.setCrossFeed(crossFeed)
        audioIOBridge.setCrossFeed(crossFeed)
        print("🎛️ C++ AudioEngineService: CrossFeed set to \(crossFeed)")
    }
    
    func setRoomSize(_ roomSize: Float) {
        guard let reverbBridge = reverbBridge, let audioIOBridge = audioIOBridge else {
            print("❌ C++ AudioEngineService: Bridges not available")
            return
        }
        
        reverbBridge.setRoomSize(roomSize)
        audioIOBridge.setRoomSize(roomSize)
        print("🎛️ C++ AudioEngineService: RoomSize set to \(roomSize)")
    }
    
    func setDensity(_ density: Float) {
        guard let reverbBridge = reverbBridge, let audioIOBridge = audioIOBridge else {
            print("❌ C++ AudioEngineService: Bridges not available")
            return
        }
        
        reverbBridge.setDensity(density)
        audioIOBridge.setDensity(density)
        print("🎛️ C++ AudioEngineService: Density set to \(density)")
    }
    
    func setHighFreqDamping(_ damping: Float) {
        guard let reverbBridge = reverbBridge, let audioIOBridge = audioIOBridge else {
            print("❌ C++ AudioEngineService: Bridges not available")
            return
        }
        
        reverbBridge.setHighFreqDamping(damping)
        audioIOBridge.setHighFreqDamping(damping)
        print("🎛️ C++ AudioEngineService: HighFreqDamping set to \(damping)")
    }
    
    func setBypass(_ bypass: Bool) {
        guard let reverbBridge = reverbBridge, let audioIOBridge = audioIOBridge else {
            print("❌ C++ AudioEngineService: Bridges not available")
            return
        }
        
        reverbBridge.setBypass(bypass)
        audioIOBridge.setBypass(bypass)
        print("🎛️ C++ AudioEngineService: Bypass set to \(bypass)")
    }
    
    // MARK: - Volume Control
    
    func setInputVolume(_ volume: Float) {
        guard let audioIOBridge = audioIOBridge else {
            print("❌ C++ AudioEngineService: AudioIOBridge not available")
            return
        }
        
        inputVolume = volume
        audioIOBridge.setInputVolume(volume)
        if verboseLogging { print("🎵 C++ AudioEngineService: Input volume set to \(volume)") }
    }
    
    func setOutputVolume(_ volume: Float, isMuted: Bool) {
        guard let audioIOBridge = audioIOBridge else {
            print("❌ C++ AudioEngineService: AudioIOBridge not available")
            return
        }
        
        audioIOBridge.setOutputVolume(volume, isMuted: isMuted)
        print("🔊 C++ AudioEngineService: Output volume set to \(volume), muted: \(isMuted)")
    }
    
    // MARK: - Audio Level Monitoring
    
    func setAudioLevelCallback(_ callback: @escaping (Float) -> Void) {
        guard let audioIOBridge = audioIOBridge else {
            print("❌ C++ AudioEngineService: AudioIOBridge not available")
            return
        }
        
        onAudioLevelChanged = callback
        audioIOBridge.setAudioLevelCallback { level in
            DispatchQueue.main.async {
                callback(level)
            }
        }
        print("✅ C++ AudioEngineService: Audio level callback set")
    }
    
    // MARK: - Recording Support
    
    func startRecording(completion: @escaping (Bool) -> Void) {
        guard let audioIOBridge = audioIOBridge else {
            print("❌ C++ AudioEngineService: AudioIOBridge not available")
            completion(false)
            return
        }
        
        print("🎙️ C++ AudioEngineService: Starting recording")
        audioIOBridge.startRecording { success in
            print("✅ C++ AudioEngineService: Recording start result: \(success)")
            completion(success)
        }
    }
    
    func stopRecording(completion: @escaping (Bool, String?, TimeInterval) -> Void) {
        guard let audioIOBridge = audioIOBridge else {
            print("❌ C++ AudioEngineService: AudioIOBridge not available")
            completion(false, nil, 0.0)
            return
        }
        
        print("🛑 C++ AudioEngineService: Stopping recording")
        audioIOBridge.stopRecording { success, filename, duration in
            print("✅ C++ AudioEngineService: Recording stop result: \(success), file: \(filename ?? "none"), duration: \(duration)")
            completion(success, filename, duration)
        }
    }
    
    // MARK: - State Queries
    
    var currentReverbPreset: ReverbPreset {
        return currentPreset
    }
    
    var engineRunning: Bool {
        return audioIOBridge?.isEngineRunning() ?? false
    }
    
    var isInitialized: Bool {
        return reverbBridge?.isInitialized() ?? false
    }
    
    var cpuUsage: Double {
        return reverbBridge?.cpuUsage() ?? 0.0
    }
    
    var sampleRate: Float {
        return audioIOBridge?.sampleRate() ?? 44100.0
    }
    
    var bufferSize: UInt32 {
        return audioIOBridge?.bufferSize() ?? 512
    }
    
    // MARK: - Diagnostics
    
    func printDiagnostics() {
        if verboseLogging {
            print("🔍 === C++ AUDIO ENGINE DIAGNOSTICS ===")
            print("Engine running: \(engineRunning)")
            print("C++ bridges initialized: \(isInitialized)")
            print("Current preset: \(currentPreset)")
            print("Sample rate: \(sampleRate) Hz")
            print("Buffer size: \(bufferSize) frames")
            print("CPU usage: \(cpuUsage)%")
            print("Input volume: \(inputVolume)")
            print("=== END C++ DIAGNOSTICS ===")
            
            audioIOBridge?.printDiagnostics()
        }
    }
    
    // MARK: - Temporary Compatibility Methods
    
    func getRecordingMixerPlaceholder() -> AVAudioMixerNode? {
        // C++ bridge handles recording internally - no direct mixer access needed
        return nil
    }
}