import Foundation
import AVFoundation
import Combine

/// Enhanced AudioManager that can optionally use C++ backend
/// Falls back to original implementation if C++ is not available
class AudioManagerCPP: ObservableObject {
    static let shared = AudioManagerCPP()
    
    // C++ Backend
    private var reverbBridge: ReverbBridge?
    private var audioIOBridge: AudioIOBridge?
    private var usingCppBackend: Bool = false
    
    // Fallback to original AudioManager
    private let originalAudioManager = AudioManager.shared
    
    // Published properties
    @Published var selectedReverbPreset: ReverbPreset = .vocalBooth
    @Published var currentAudioLevel: Float = 0.0
    @Published var isRecording: Bool = false
    @Published var lastRecordingFilename: String?
    @Published var isMonitoring: Bool = false
    @Published var cpuUsage: Double = 0.0
    
    // Custom reverb settings
    @Published var customReverbSettings = CustomReverbSettings.default
    
    private init() {
        setupCppBackend()
        
        // If C++ backend failed, use original manager
        if !usingCppBackend {
            print("🔄 Falling back to original Swift audio engine")
            setupOriginalManagerObservers()
        }
    }
    
    // MARK: - C++ Backend Setup
    
    private func setupCppBackend() {
        print("🎵 Attempting to initialize C++ audio backend...")
        
        do {
            // Try to create C++ bridges
            reverbBridge = ReverbBridge()
            
            guard let bridge = reverbBridge else {
                print("❌ Failed to create ReverbBridge")
                return
            }
            
            audioIOBridge = AudioIOBridge(reverbBridge: bridge)
            
            guard let iobridge = audioIOBridge else {
                print("❌ Failed to create AudioIOBridge")
                return
            }
            
            // Test initialization
            if iobridge.setupAudioEngine() {
                usingCppBackend = true
                setupCppObservers()
                print("✅ C++ audio backend initialized successfully!")
            } else {
                print("❌ C++ audio engine setup failed")
            }
            
        } catch {
            print("❌ C++ backend initialization error: \(error)")
        }
    }
    
    private func setupCppObservers() {
        // Set up audio level monitoring for C++ backend
        audioIOBridge?.setAudioLevelCallback { [weak self] level in
            DispatchQueue.main.async {
                self?.currentAudioLevel = level
            }
        }
        
        // Performance monitoring
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let bridge = self.reverbBridge else { return }
            
            DispatchQueue.main.async {
                self.cpuUsage = bridge.cpuUsage()
            }
        }
    }
    
    private func setupOriginalManagerObservers() {
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
        
        // Monitor state from original manager
        isMonitoring = originalAudioManager.isMonitoring
    }
    
    // MARK: - Public Interface (unified for both backends)
    
    func startMonitoring() {
        if usingCppBackend {
            audioIOBridge?.setMonitoring(true)
            isMonitoring = audioIOBridge?.isMonitoring() ?? false
            print("🎵 C++ monitoring started")
        } else {
            originalAudioManager.startMonitoring()
            isMonitoring = originalAudioManager.isMonitoring
            print("🎵 Swift monitoring started")
        }
    }
    
    func stopMonitoring() {
        if usingCppBackend {
            audioIOBridge?.setMonitoring(false)
            isMonitoring = false
            currentAudioLevel = 0.0
            print("🔇 C++ monitoring stopped")
        } else {
            originalAudioManager.stopMonitoring()
            isMonitoring = originalAudioManager.isMonitoring
            print("🔇 Swift monitoring stopped")
        }
    }
    
    func updateReverbPreset(_ preset: ReverbPreset) {
        selectedReverbPreset = preset
        
        if usingCppBackend {
            // Map to C++ presets
            let cppPreset: Int
            switch preset {
            case .clean: cppPreset = 0
            case .vocalBooth: cppPreset = 1
            case .studio: cppPreset = 2
            case .cathedral: cppPreset = 3
            case .custom: cppPreset = 4
            }
            reverbBridge?.setPreset(cppPreset)
            
            if preset == .custom {
                applyCppCustomSettings()
            }
            
            print("🎛️ C++ reverb preset: \(preset.rawValue)")
        } else {
            originalAudioManager.updateReverbPreset(preset)
            print("🎛️ Swift reverb preset: \(preset.rawValue)")
        }
    }
    
    private func applyCppCustomSettings() {
        guard let bridge = reverbBridge else { return }
        
        bridge.setWetDryMix(customReverbSettings.wetDryMix)
        bridge.setDecayTime(customReverbSettings.decayTime)
        bridge.setPreDelay(customReverbSettings.preDelay)
        bridge.setCrossFeed(customReverbSettings.crossFeed)
        bridge.setRoomSize(customReverbSettings.size)
        bridge.setDensity(customReverbSettings.density)
        bridge.setHighFreqDamping(customReverbSettings.highFrequencyDamping)
        
        print("🎛️ C++ custom settings applied - wetDry:\(customReverbSettings.wetDryMix)%, decay:\(customReverbSettings.decayTime)s")
    }
    
    func setInputVolume(_ volume: Float) {
        if usingCppBackend {
            audioIOBridge?.setInputVolume(volume)
            print("🎵 C++ input volume: \(volume)")
        } else {
            originalAudioManager.setInputVolume(volume)
        }
    }
    
    func getInputVolume() -> Float {
        if usingCppBackend {
            return audioIOBridge?.inputVolume() ?? 1.0
        } else {
            return originalAudioManager.getInputVolume()
        }
    }
    
    func setOutputVolume(_ volume: Float, isMuted: Bool) {
        if usingCppBackend {
            audioIOBridge?.setOutputVolume(volume, isMuted: isMuted)
            print("🔊 C++ output volume: \(volume), muted: \(isMuted)")
        } else {
            originalAudioManager.setOutputVolume(volume, isMuted: isMuted)
        }
    }
    
    // MARK: - Recording Support
    
    func startRecording(completion: @escaping (Bool) -> Void) {
        if usingCppBackend {
            // Use C++ recording pipeline
            audioIOBridge?.startRecording { [weak self] success in
                DispatchQueue.main.async {
                    self?.isRecording = success
                    completion(success)
                }
            }
        } else {
            originalAudioManager.startRecording(completion: completion)
        }
    }
    
    func stopRecording(completion: @escaping (Bool, String?, TimeInterval) -> Void) {
        if usingCppBackend {
            audioIOBridge?.stopRecording { [weak self] success, filename, duration in
                DispatchQueue.main.async {
                    self?.isRecording = false
                    self?.lastRecordingFilename = filename
                    completion(success, filename, duration)
                }
            }
        } else {
            originalAudioManager.stopRecording(completion: completion)
        }
    }
    
    func toggleRecording() {
        if isRecording {
            stopRecording { _, _, _ in }
        } else {
            startRecording { _ in }
        }
    }
    
    // MARK: - Custom Settings
    
    func updateCustomReverbSettings(_ settings: CustomReverbSettings) {
        customReverbSettings = settings
        
        if usingCppBackend && selectedReverbPreset == .custom {
            applyCppCustomSettings()
        } else {
            originalAudioManager.updateCustomReverbSettings(settings)
        }
    }
    
    func updateCustomReverbLive(_ settings: CustomReverbSettings) {
        // Mise à jour immédiate sans validation excessive
        customReverbSettings = settings
        ReverbPreset.updateCustomSettings(settings)
        
        // Application directe si en mode custom et monitoring actif
        if selectedReverbPreset == .custom && isMonitoring {
            if usingCppBackend {
                applyCppCustomSettings()
            } else {
                originalAudioManager.updateReverbPreset(.custom)
            }
            print("🎛️ LIVE UPDATE: Custom reverb applied in real-time")
        }
    }
    
    // MARK: - Diagnostics & Info
    
    var currentPresetDescription: String {
        if usingCppBackend {
            switch selectedReverbPreset {
            case .clean: return "Pure signal (C++ backend)"
            case .vocalBooth: return "Vocal booth environment (C++ FDN)"
            case .studio: return "Professional studio (C++ FDN)"
            case .cathedral: return "Spacious cathedral (C++ FDN)"
            case .custom: return "Custom parameters (C++ FDN)"
            }
        } else {
            return originalAudioManager.currentPresetDescription
        }
    }
    
    var canStartRecording: Bool {
        return isMonitoring && !isRecording
    }
    
    var canStartMonitoring: Bool {
        if usingCppBackend {
            return (audioIOBridge?.isInitialized() ?? false) && !isMonitoring
        } else {
            return originalAudioManager.canStartMonitoring
        }
    }
    
    var engineInfo: String {
        if usingCppBackend {
            return "Professional C++ FDN Engine"
        } else {
            return "Swift AVAudioUnitReverb Engine"
        }
    }
    
    // MARK: - Advanced C++ Features
    
    func getCppEngineStats() -> [String: Any]? {
        guard usingCppBackend, let bridge = reverbBridge else { return nil }
        
        return [
            "cpu_usage": bridge.cpuUsage(),
            "wet_dry_mix": bridge.wetDryMix(),
            "decay_time": bridge.decayTime(),
            "room_size": bridge.roomSize(),
            "density": bridge.density(),
            "is_initialized": bridge.isInitialized(),
            "sample_rate": audioIOBridge?.sampleRate() ?? 0,
            "buffer_size": audioIOBridge?.bufferSize() ?? 0
        ]
    }
    
    func resetCppEngine() {
        guard usingCppBackend else { return }
        
        reverbBridge?.reset()
        print("🔄 C++ reverb engine reset")
    }
    
    func optimizeCppEngine() {
        guard usingCppBackend else { return }
        
        audioIOBridge?.optimizeForLowLatency()
        print("⚡ C++ engine optimized for low latency")
    }
    
    func diagnostic() {
        print("🔍 === ENHANCED AUDIO MANAGER DIAGNOSTIC ===")
        print("- Backend: \(usingCppBackend ? "C++ FDN Engine" : "Swift AVAudioEngine")")
        print("- Selected preset: \(selectedReverbPreset.rawValue)")
        print("- Monitoring active: \(isMonitoring)")
        print("- Recording active: \(isRecording)")
        print("- Current audio level: \(currentAudioLevel)")
        
        if usingCppBackend {
            print("- CPU usage: \(cpuUsage)%")
            print("- C++ reverb bridge: \(reverbBridge != nil ? "✅" : "❌")")
            print("- Audio I/O bridge: \(audioIOBridge != nil ? "✅" : "❌")")
            
            if let bridge = reverbBridge {
                print("- Engine initialized: \(bridge.isInitialized())")
                print("- Engine wet/dry mix: \(bridge.wetDryMix())%")
                print("- Engine decay time: \(bridge.decayTime())s")
                print("- Engine room size: \(bridge.roomSize())")
                print("- Engine density: \(bridge.density())%")
            }
            
            if let ioBridge = audioIOBridge {
                print("- Audio I/O initialized: \(ioBridge.isInitialized())")
                print("- Sample rate: \(ioBridge.sampleRate()) Hz")
                print("- Buffer size: \(ioBridge.bufferSize()) frames")
                print("- Input volume: \(ioBridge.inputVolume())")
            }
        } else {
            originalAudioManager.diagnostic()
        }
        
        print("=== END ENHANCED DIAGNOSTIC ===")
    }
}

// MARK: - C++ Backend Extensions

extension AudioManagerCPP {
    
    /// Force switch to C++ backend (for testing)
    func forceCppBackend() {
        guard !usingCppBackend else { return }
        setupCppBackend()
    }
    
    /// Force switch to Swift backend
    func forceSwiftBackend() {
        guard usingCppBackend else { return }
        
        // Cleanup C++ backend
        audioIOBridge?.setMonitoring(false)
        reverbBridge = nil
        audioIOBridge = nil
        usingCppBackend = false
        
        // Setup Swift backend
        setupOriginalManagerObservers()
        print("🔄 Switched to Swift backend")
    }
    
    /// Get current backend type
    var currentBackend: String {
        return usingCppBackend ? "C++ FDN Engine" : "Swift AVAudioEngine"
    }
    
    /// Check if C++ backend is available
    var isCppBackendAvailable: Bool {
        return reverbBridge != nil && audioIOBridge != nil
    }
}
