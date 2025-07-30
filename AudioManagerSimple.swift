import Foundation
import AVFoundation
import Combine

/// Simple wrapper around original AudioManager for testing
/// Use this if you want to test without C++ backend first
class AudioManagerSimple: ObservableObject {
    static let shared = AudioManagerSimple()
    
    // Just delegate to original AudioManager
    private let originalAudioManager = AudioManager.shared
    
    // Published properties that mirror the original
    @Published var selectedReverbPreset: ReverbPreset = .vocalBooth
    @Published var currentAudioLevel: Float = 0.0
    @Published var isRecording: Bool = false
    @Published var lastRecordingFilename: String?
    @Published var isMonitoring: Bool = false
    @Published var customReverbSettings = CustomReverbSettings.default
    
    // Performance info (fake for now)
    @Published var cpuUsage: Double = 15.0
    @Published var engineInfo: String = "Swift AVAudioEngine (Original)"
    
    private init() {
        setupObservers()
    }
    
    private func setupObservers() {
        // Mirror original manager's published properties
        originalAudioManager.$selectedReverbPreset
            .assign(to: &$selectedReverbPreset)
        
        originalAudioManager.$currentAudioLevel
            .assign(to: &$currentAudioLevel)
        
        originalAudioManager.$isRecording
            .assign(to: &$isRecording)
        
        originalAudioManager.$lastRecordingFilename
            .assign(to: &$lastRecordingFilename)
        
        originalAudioManager.$customReverbSettings
            .assign(to: &$customReverbSettings)
        
        // Monitor state
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.isMonitoring = self.originalAudioManager.isMonitoring
                // Simulate some CPU usage
                self.cpuUsage = Double.random(in: 10...25)
            }
        }
    }
    
    // MARK: - Public Interface (just delegate everything)
    
    func startMonitoring() {
        originalAudioManager.startMonitoring()
        isMonitoring = originalAudioManager.isMonitoring
    }
    
    func stopMonitoring() {
        originalAudioManager.stopMonitoring()
        isMonitoring = originalAudioManager.isMonitoring
    }
    
    func updateReverbPreset(_ preset: ReverbPreset) {
        originalAudioManager.updateReverbPreset(preset)
        selectedReverbPreset = preset
    }
    
    func setInputVolume(_ volume: Float) {
        originalAudioManager.setInputVolume(volume)
    }
    
    func getInputVolume() -> Float {
        return originalAudioManager.getInputVolume()
    }
    
    func setOutputVolume(_ volume: Float, isMuted: Bool) {
        originalAudioManager.setOutputVolume(volume, isMuted: isMuted)
    }
    
    func startRecording(completion: @escaping (Bool) -> Void) {
        originalAudioManager.startRecording(completion: completion)
    }
    
    func stopRecording(completion: @escaping (Bool, String?, TimeInterval) -> Void) {
        originalAudioManager.stopRecording(completion: completion)
    }
    
    func toggleRecording() {
        originalAudioManager.toggleRecording()
    }
    
    func updateCustomReverbSettings(_ settings: CustomReverbSettings) {
        originalAudioManager.updateCustomReverbSettings(settings)
        customReverbSettings = settings
    }
    
    // MARK: - Properties
    
    var currentPresetDescription: String {
        return originalAudioManager.currentPresetDescription + " (Simple Mode)"
    }
    
    var canStartRecording: Bool {
        return originalAudioManager.canStartRecording
    }
    
    var canStartMonitoring: Bool {
        return originalAudioManager.canStartMonitoring
    }
    
    func diagnostic() {
        print("🔍 === SIMPLE AUDIO MANAGER ===")
        print("- Mode: Delegating to original AudioManager")
        print("- Engine: Swift AVAudioEngine")
        print("- Backend: Original implementation")
        originalAudioManager.diagnostic()
        print("=== END SIMPLE DIAGNOSTIC ===")
    }
}