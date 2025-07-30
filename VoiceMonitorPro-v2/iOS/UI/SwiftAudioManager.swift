import Foundation
import AVFoundation
import Combine

/// Updated AudioManager that uses the C++ backend via AudioIOBridge
/// This replaces your existing AudioManager.swift with C++ integration
class SwiftAudioManager: ObservableObject {
    static let shared = SwiftAudioManager()
    
    // C++ Bridge components
    private var reverbBridge: ReverbBridge?
    private var audioIOBridge: AudioIOBridge?
    
    // Published properties for SwiftUI
    @Published var selectedReverbPreset: ReverbPreset = .vocalBooth
    @Published var currentAudioLevel: Float = 0.0
    @Published var isRecording: Bool = false
    @Published var lastRecordingFilename: String?
    @Published var isMonitoring: Bool = false
    
    // Custom reverb settings (compatible with your existing UI)
    @Published var customReverbSettings = CustomReverbSettings.default
    
    // Volume control
    private var inputVolume: Float = 1.0
    private var outputVolume: Float = 1.4
    private var isMuted: Bool = false
    
    private init() {
        setupCppAudioEngine()
    }
    
    // MARK: - C++ Audio Engine Setup
    
    private func setupCppAudioEngine() {
        print("🎵 Initializing C++ audio engine")
        
        // Create C++ bridges
        reverbBridge = ReverbBridge()
        guard let reverbBridge = reverbBridge else {
            print("❌ Failed to create ReverbBridge")
            return
        }
        
        audioIOBridge = AudioIOBridge(reverbBridge: reverbBridge)
        guard let audioIOBridge = audioIOBridge else {
            print("❌ Failed to create AudioIOBridge")
            return
        }
        
        // Setup audio engine
        if audioIOBridge.setupAudioEngine() {
            print("✅ C++ audio engine initialized successfully")
            
            // Set up audio level monitoring
            audioIOBridge.setAudioLevelCallback { [weak self] level in
                DispatchQueue.main.async {
                    self?.currentAudioLevel = level
                }
            }
            
            // Apply initial settings
            updateReverbPreset(preset: selectedReverbPreset)
        } else {
            print("❌ Failed to setup C++ audio engine")
        }
    }
    
    // MARK: - Audio Control (compatible with existing UI)
    
    func startMonitoring() {
        guard let audioIOBridge = audioIOBridge else { return }
        
        audioIOBridge.setMonitoring(true)
        isMonitoring = audioIOBridge.isMonitoring()
        
        print("🎵 Monitoring started with C++ backend")
    }
    
    func stopMonitoring() {
        guard let audioIOBridge = audioIOBridge else { return }
        
        audioIOBridge.setMonitoring(false)
        isMonitoring = false
        currentAudioLevel = 0.0
        
        print("🔇 Monitoring stopped")
    }
    
    func setMonitoring(enabled: Bool) {
        if enabled {
            startMonitoring()
        } else {
            stopMonitoring()
        }
    }
    
    // MARK: - Reverb Preset Management
    
    func updateReverbPreset(preset: ReverbPreset) {
        guard let audioIOBridge = audioIOBridge else { return }
        
        selectedReverbPreset = preset
        
        let cppPreset: ReverbPresetType
        switch preset {
        case .clean:
            cppPreset = .clean
        case .vocalBooth:
            cppPreset = .vocalBooth
        case .studio:
            cppPreset = .studio
        case .cathedral:
            cppPreset = .cathedral
        case .custom:
            cppPreset = .custom
            // Apply custom settings
            applyCustomReverbSettings()
        }
        
        audioIOBridge.setReverbPreset(cppPreset)
        
        print("🎛️ Reverb preset changed to: \(preset.rawValue)")
    }
    
    private func applyCustomReverbSettings() {
        guard let audioIOBridge = audioIOBridge else { return }
        
        audioIOBridge.setWetDryMix(customReverbSettings.wetDryMix)
        audioIOBridge.setDecayTime(customReverbSettings.decayTime)
        audioIOBridge.setPreDelay(customReverbSettings.preDelay)
        audioIOBridge.setCrossFeed(customReverbSettings.crossFeed)
        audioIOBridge.setRoomSize(customReverbSettings.size)
        audioIOBridge.setDensity(customReverbSettings.density)
        audioIOBridge.setHighFreqDamping(customReverbSettings.highFrequencyDamping)
    }
    
    // MARK: - Custom Reverb Parameters
    
    func updateCustomReverbSettings(_ settings: CustomReverbSettings) {
        customReverbSettings = settings
        ReverbPreset.updateCustomSettings(settings)
        
        if selectedReverbPreset == .custom {
            applyCustomReverbSettings()
        }
    }
    
    // Individual parameter updates for real-time control
    func setWetDryMix(_ value: Float) {
        customReverbSettings.wetDryMix = value
        audioIOBridge?.setWetDryMix(value)
    }
    
    func setDecayTime(_ value: Float) {
        customReverbSettings.decayTime = value
        audioIOBridge?.setDecayTime(value)
    }
    
    func setPreDelay(_ value: Float) {
        customReverbSettings.preDelay = value
        audioIOBridge?.setPreDelay(value)
    }
    
    func setCrossFeed(_ value: Float) {
        customReverbSettings.crossFeed = value
        audioIOBridge?.setCrossFeed(value)
    }
    
    func setRoomSize(_ value: Float) {
        customReverbSettings.size = value
        audioIOBridge?.setRoomSize(value)
    }
    
    func setDensity(_ value: Float) {
        customReverbSettings.density = value
        audioIOBridge?.setDensity(value)
    }
    
    func setHighFreqDamping(_ value: Float) {
        customReverbSettings.highFrequencyDamping = value
        audioIOBridge?.setHighFreqDamping(value)
    }
    
    // MARK: - Volume Control
    
    func setInputVolume(_ volume: Float) {
        inputVolume = volume
        audioIOBridge?.setInputVolume(volume)
    }
    
    func getInputVolume() -> Float {
        return audioIOBridge?.inputVolume() ?? inputVolume
    }
    
    func setOutputVolume(_ volume: Float, isMuted: Bool) {
        outputVolume = volume
        self.isMuted = isMuted
        audioIOBridge?.setOutputVolume(volume, isMuted: isMuted)
    }
    
    // MARK: - Recording Support (for compatibility)
    
    func getRecordingMixer() -> AVAudioMixerNode? {
        return audioIOBridge?.getRecordingMixer()
    }
    
    func getRecordingFormat() -> AVAudioFormat? {
        return audioIOBridge?.getRecordingFormat()
    }
    
    // MARK: - Performance Monitoring
    
    func getCpuUsage() -> Double {
        return audioIOBridge?.cpuUsage() ?? 0.0
    }
    
    func isEngineRunning() -> Bool {
        return audioIOBridge?.isEngineRunning() ?? false
    }
    
    func isInitialized() -> Bool {
        return audioIOBridge?.isInitialized() ?? false
    }
    
    // MARK: - Diagnostics
    
    func printDiagnostics() {
        print("🔍 === SWIFT AUDIO MANAGER DIAGNOSTICS ===")
        print("Selected preset: \(selectedReverbPreset.rawValue)")
        print("Is monitoring: \(isMonitoring)")
        print("Audio level: \(currentAudioLevel)")
        print("CPU usage: \(getCpuUsage())%")
        print("Engine running: \(isEngineRunning())")
        print("Initialized: \(isInitialized())")
        
        // Print C++ diagnostics
        audioIOBridge?.printDiagnostics()
        
        print("=== END SWIFT DIAGNOSTICS ===")
    }
    
    // MARK: - Preset Description (for UI compatibility)
    
    var currentPresetDescription: String {
        return selectedReverbPreset.description
    }
    
    // MARK: - Cleanup
    
    deinit {
        stopMonitoring()
    }
}

// MARK: - Bridge to Objective-C types

extension ReverbPreset {
    func toCppPresetType() -> ReverbPresetType {
        switch self {
        case .clean: return .clean
        case .vocalBooth: return .vocalBooth
        case .studio: return .studio
        case .cathedral: return .cathedral
        case .custom: return .custom
        }
    }
}