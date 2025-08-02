import Foundation
import AVFoundation
import Combine

/// iOS-compatible SwiftAudioManager that delegates to AudioManagerCPP
/// Provides compatibility while using the iOS-optimized implementation
@MainActor
class SwiftAudioManager: ObservableObject {
    static let shared = SwiftAudioManager()
    
    // Delegate to the main audio manager
    private let audioManager = AudioManagerCPP.shared
    
    // Published properties that mirror AudioManagerCPP
    @Published var selectedReverbPreset: ReverbPreset = .vocalBooth
    @Published var currentAudioLevel: Float = 0.0
    @Published var isRecording: Bool = false
    @Published var lastRecordingFilename: String?
    @Published var isMonitoring: Bool = false
    @Published var inputVolume: Float = 1.0
    @Published var outputVolume: Float = 1.0
    @Published var isMuted: Bool = false
    @Published var customReverbSettings = CustomReverbSettings.default
    
    private init() {
        print("🎵 SwiftAudioManager iOS compatibility layer initialized")
        
        // Sync state with main audio manager
        syncWithAudioManager()
    }
    
    private func syncWithAudioManager() {
        selectedReverbPreset = audioManager.selectedReverbPreset
        currentAudioLevel = audioManager.audioLevel
        isRecording = audioManager.isRecording
        isMonitoring = audioManager.isMonitoring
        inputVolume = audioManager.inputVolume
        outputVolume = audioManager.outputVolume
        isMuted = audioManager.isMuted
        customReverbSettings = audioManager.customReverbSettings
    }
    
    // MARK: - Delegation methods
    
    func startMonitoring() {
        audioManager.startMonitoring()
        syncWithAudioManager()
    }
    
    func stopMonitoring() {
        audioManager.stopMonitoring()
        syncWithAudioManager()
    }
    
    func setMonitoring(enabled: Bool) {
        if enabled {
            startMonitoring()
        } else {
            stopMonitoring()
        }
    }
    
    func updateReverbPreset(preset: ReverbPreset) {
        audioManager.updateReverbPreset(preset)
        syncWithAudioManager()
    }
    
    func setInputVolume(_ volume: Float) {
        audioManager.setInputVolume(volume)
        syncWithAudioManager()
    }
    
    func getInputVolume() -> Float {
        return audioManager.getInputVolume()
    }
    
    func setOutputVolume(_ volume: Float, isMuted: Bool) {
        audioManager.setOutputVolume(volume, isMuted: isMuted)
        syncWithAudioManager()
    }
    
    func printDiagnostics() {
        print("🔍 SwiftAudioManager Compatibility Layer:")
        audioManager.performDiagnostics()
    }
    
    // MARK: - Placeholder methods for compatibility
    
    func updateCustomReverbSettings(_ settings: CustomReverbSettings) {
        audioManager.updateCustomReverbSettings(settings)
        syncWithAudioManager()
    }
    
    func setWetDryMix(_ value: Float) {
        customReverbSettings.wetDryMix = value
        updateCustomReverbSettings(customReverbSettings)
    }
    
    func setDecayTime(_ value: Float) {
        customReverbSettings.decayTime = value
        updateCustomReverbSettings(customReverbSettings)
    }
    
    func setPreDelay(_ value: Float) {
        customReverbSettings.preDelay = value
        updateCustomReverbSettings(customReverbSettings)
    }
    
    func setCrossFeed(_ value: Float) {
        customReverbSettings.crossFeed = value
        updateCustomReverbSettings(customReverbSettings)
    }
    
    func setRoomSize(_ value: Float) {
        customReverbSettings.size = value
        updateCustomReverbSettings(customReverbSettings)
    }
    
    func setDensity(_ value: Float) {
        customReverbSettings.density = value
        updateCustomReverbSettings(customReverbSettings)
    }
    
    func setHighFreqDamping(_ value: Float) {
        customReverbSettings.highFrequencyDamping = value
        updateCustomReverbSettings(customReverbSettings)
    }
    
    // MARK: - Recording Support (delegates to AudioManagerCPP)
    
    func getRecordingMixer() -> AVAudioMixerNode? {
        // AudioEngineService using C++ doesn't expose mixers directly
        // Return nil for now - recording is handled internally by C++ bridge
        return nil
    }
    
    func getRecordingFormat() -> AVAudioFormat? {
        // Use standard iOS recording format for now
        return AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)
    }
    
    // MARK: - Performance Monitoring (placeholders)
    
    func getCpuUsage() -> Double {
        return Double(audioManager.cpuUsage)
    }
    
    func isEngineRunning() -> Bool {
        return audioManager.isEngineRunning
    }
    
    func isInitialized() -> Bool {
        return audioManager.audioEngineService != nil
    }
    
    // MARK: - Preset Description (for UI compatibility)
    
    var currentPresetDescription: String {
        return audioManager.currentPresetDescription
    }
}

// MARK: - Extensions for ReverbPreset compatibility

extension ReverbPreset {
    func toCppPresetType() -> Int {
        // Map to integer values that match the C++ enum
        switch self {
        case .clean: return 0
        case .vocalBooth: return 1
        case .studio: return 2
        case .cathedral: return 3
        case .custom: return 4
        }
    }
}