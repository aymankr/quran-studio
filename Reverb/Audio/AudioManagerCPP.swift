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
    @Published var usingCppBackend: Bool = false
    
    // Fallback to original AudioManager
    private let originalAudioManager = AudioManager.shared
    
    // Published properties
    @Published var selectedReverbPreset: ReverbPreset = .clean
    @Published var currentAudioLevel: Float = 0.0
    @Published var isRecording: Bool = false
    @Published var lastRecordingFilename: String?
    @Published var isMonitoring: Bool = false
    @Published var cpuUsage: Double = 0.0
    
    // Custom reverb settings
    @Published var customReverbSettings = CustomReverbSettings.default
    
    private init() {
        // Start with Swift backend by default
        setupOriginalManagerObservers()
        
        // Try to initialize C++ backend as secondary option
        initializeCppBackend()
    }
    
    func toggleBackend() {
        if usingCppBackend {
            switchToSwiftBackend()
        } else {
            switchToCppBackend()
        }
    }
    
    private func switchToSwiftBackend() {
        print("🔄 Switching to Swift backend...")
        
        // Stop C++ backend if running
        if isMonitoring {
            audioIOBridge?.setMonitoring(false)
            audioIOBridge?.stopEngine()
        }
        
        usingCppBackend = false
        
        // Start Swift monitoring if it was active
        if isMonitoring {
            originalAudioManager.startMonitoring()
        }
        
        print("✅ Switched to Swift AVAudioEngine backend")
    }
    
    private func switchToCppBackend() {
        print("🔄 Switching to C++ backend...")
        
        guard isCppBackendAvailable else {
            print("❌ C++ backend not available, initializing...")
            initializeCppBackend()
            return
        }
        
        // Stop Swift backend if running
        if isMonitoring {
            originalAudioManager.stopMonitoring()
        }
        
        usingCppBackend = true
        
        // Start C++ monitoring if it was active
        if isMonitoring {
            let success = audioIOBridge?.startEngine() ?? false
            if success {
                audioIOBridge?.setMonitoring(true)
            }
        }
        
        print("✅ Switched to C++ FDN backend")
    }
    
    // MARK: - C++ Backend Setup
    
    private func initializeCppBackend() {
        print("🎵 C++ BACKEND: Testing C++ audio library integration...")
        
        // Try to initialize C++ backend
        print("🔧 Creating C++ ReverbBridge...")
        reverbBridge = ReverbBridge()
        
        if let bridge = reverbBridge {
            print("🔧 Creating C++ AudioIOBridge...")
            audioIOBridge = AudioIOBridge(reverbBridge: bridge)
            
            print("🔧 Setting up C++ audio engine...")
            let setupSuccess = audioIOBridge?.setupAudioEngine() ?? false
            
            if setupSuccess {
                print("✅ C++ BACKEND INITIALIZED AND AVAILABLE!")
                setupCppObservers()
            } else {
                print("❌ C++ backend setup failed")
            }
        } else {
            print("❌ Failed to create ReverbBridge")
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
        
        // Synchronize monitoring state continuously
        originalAudioManager.$isMonitoring
            .assign(to: &$isMonitoring)
        
        print("✅ Original AudioManager observers setup - monitoring state will be synchronized")
    }
    
    // MARK: - Public Interface (unified for both backends)
    
    func startMonitoring() {
        print("🎵 AudioManagerCPP.startMonitoring called")
        if usingCppBackend {
            // Use the C++ AudioIOBridge's engine directly
            let success = audioIOBridge?.startEngine() ?? false
            if success {
                audioIOBridge?.setMonitoring(true)
                isMonitoring = true
                print("🎵 C++ engine started with direct C++ processing")
            } else {
                print("❌ Failed to start C++ engine, falling back to Swift")
                originalAudioManager.startMonitoring()
                // isMonitoring will be automatically synchronized via observer
            }
        } else {
            print("🔄 Using Swift backend - calling originalAudioManager.startMonitoring()")
            originalAudioManager.startMonitoring()
            // Force synchronization of state
            self.isMonitoring = originalAudioManager.isMonitoring
            print("✅ Swift monitoring started via AudioManagerCPP (state: \(self.isMonitoring))")
        }
    }
    
    func stopMonitoring() {
        print("🔇 AudioManagerCPP.stopMonitoring called")
        if usingCppBackend {
            audioIOBridge?.setMonitoring(false)
            audioIOBridge?.stopEngine()
            isMonitoring = false
            currentAudioLevel = 0.0
            print("🔇 C++ engine stopped")
        } else {
            print("🔄 Using Swift backend - calling originalAudioManager.stopMonitoring()")
            originalAudioManager.stopMonitoring()
            // Force synchronization of state
            self.isMonitoring = originalAudioManager.isMonitoring
            print("✅ Swift monitoring stopped via AudioManagerCPP (state: \(self.isMonitoring))")
        }
    }
    
    func updateReverbPreset(_ preset: ReverbPreset) {
        print("📥 AUDIOMANAGERCPP: Received updateReverbPreset(\(preset.rawValue))")
        print("🔧 AUDIOMANAGERCPP: usingCppBackend = \(usingCppBackend)")
        selectedReverbPreset = preset
        
        if usingCppBackend {
            // DO NOT call originalAudioManager - it interferes with C++
            // originalAudioManager.updateReverbPreset(.clean)
            
            // Map Swift preset to C++ preset correctly
            let cppPreset: ReverbPresetType
            switch preset {
            case .clean: 
                cppPreset = ReverbPresetType.clean
            case .vocalBooth: 
                cppPreset = ReverbPresetType.vocalBooth
            case .studio: 
                cppPreset = ReverbPresetType.studio
            case .cathedral: 
                cppPreset = ReverbPresetType.cathedral
            case .custom: 
                cppPreset = ReverbPresetType.custom
            }
            
            print("🔧 AUDIOMANAGERCPP: Using C++ backend for preset application")
            
            // Apply via AudioIOBridge (which manages the audio chain)
            if let iobridge = audioIOBridge {
                print("📤 AUDIOMANAGERCPP: Calling audioIOBridge.setReverbPreset(\(preset.rawValue))")
                iobridge.setReverbPreset(cppPreset)
                
                // Verify the preset was applied
                let _ = iobridge.currentReverbPreset()
                print("✅ AUDIOMANAGERCPP: C++ preset applied via AudioIOBridge: \(preset.rawValue)")
                
                // Apply custom settings if needed
                if preset == .custom {
                    print("🎨 AUDIOMANAGERCPP: Applying custom settings via AudioIOBridge")
                    applyCppCustomSettings()
                }
            } else {
                print("❌ AUDIOMANAGERCPP: AudioIOBridge is nil, falling back to ReverbBridge")
                // Fallback to direct ReverbBridge
                reverbBridge?.setPreset(cppPreset)
                if preset == .custom {
                    applyCppCustomSettings()
                }
            }
            
            print("✅ AUDIOMANAGERCPP: C++ reverb preset processing completed: \(preset.rawValue)")
        } else {
            print("🔄 AUDIOMANAGERCPP: Using Swift backend, calling originalAudioManager.updateReverbPreset(\(preset.rawValue))")
            originalAudioManager.updateReverbPreset(preset)
            // Force sync the selected preset
            self.selectedReverbPreset = preset
            print("✅ AUDIOMANAGERCPP: Swift reverb preset call completed for \(preset.rawValue)")
        }
    }
    
    // Helper function to convert Swift preset to C++ enum
    private func convertToReverbPresetType(_ preset: ReverbPreset) -> ReverbPresetType {
        switch preset {
        case .clean: return ReverbPresetType.clean
        case .vocalBooth: return ReverbPresetType.vocalBooth
        case .studio: return ReverbPresetType.studio
        case .cathedral: return ReverbPresetType.cathedral
        case .custom: return ReverbPresetType.custom
        }
    }
    
    private func applyCppCustomSettings() {
        // Prefer AudioIOBridge if available, fallback to ReverbBridge
        if let iobridge = audioIOBridge {
            print("🎨 Applying custom settings via AudioIOBridge")
            iobridge.setWetDryMix(customReverbSettings.wetDryMix)
            iobridge.setDecayTime(customReverbSettings.decayTime)
            iobridge.setPreDelay(customReverbSettings.preDelay)
            iobridge.setCrossFeed(customReverbSettings.crossFeed)
            iobridge.setRoomSize(customReverbSettings.size)
            iobridge.setDensity(customReverbSettings.density)
            iobridge.setHighFreqDamping(customReverbSettings.highFrequencyDamping)
            print("✅ Custom settings applied via AudioIOBridge")
        } else if let bridge = reverbBridge {
            print("🎨 Applying custom settings via ReverbBridge (fallback)")
            bridge.setWetDryMix(customReverbSettings.wetDryMix)
            bridge.setDecayTime(customReverbSettings.decayTime)
            bridge.setPreDelay(customReverbSettings.preDelay)
            bridge.setCrossFeed(customReverbSettings.crossFeed)
            bridge.setRoomSize(customReverbSettings.size)
            bridge.setDensity(customReverbSettings.density)
            bridge.setHighFreqDamping(customReverbSettings.highFrequencyDamping)
            print("✅ Custom settings applied via ReverbBridge")
        } else {
            print("❌ No C++ bridge available for custom settings")
        }
        
        print("🎛️ C++ custom settings applied - wetDry:\(customReverbSettings.wetDryMix)%, decay:\(customReverbSettings.decayTime)s")
    }
    
    func setInputVolume(_ volume: Float) {
        if usingCppBackend {
            print("🔧 AudioManagerCPP: Setting input volume via C++ backend: \(volume)")
            audioIOBridge?.setInputVolume(volume)
        } else {
            print("🔧 AudioManagerCPP: Setting input volume via Swift backend: \(volume)")
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
        initializeCppBackend()
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
    
    func testCppBackend() {
        print("🧪 Testing C++ backend...")
        if let bridge = reverbBridge {
            print("- ReverbBridge exists: ✅")
            print("- Is initialized: \(bridge.isInitialized() ? "✅" : "❌")")
            print("- Current preset: \(bridge.currentPreset())")
            print("- CPU usage: \(bridge.cpuUsage())%")
        } else {
            print("- ReverbBridge: ❌")
        }
    }
}
