import Foundation
import SwiftUI
import AVFoundation

/// Manages dual operation modes: standalone app and AUv3 plugin
/// Handles state synchronization and context switching between modes
public class DualModeManager: ObservableObject {
    
    // MARK: - Operation Modes
    public enum OperationMode {
        case standalone     // Running as main iOS app
        case audioUnit     // Running as AUv3 plugin in host
    }
    
    // MARK: - Published Properties
    @Published public private(set) var currentMode: OperationMode = .standalone
    @Published public private(set) var isPluginActive = false
    @Published public private(set) var hostInfo: HostInfo?
    
    // MARK: - State Management
    public struct AppState {
        var wetDryMix: Float = 0.5
        var inputGain: Float = 1.0
        var outputGain: Float = 1.0
        var reverbDecay: Float = 0.7
        var reverbSize: Float = 0.5
        var dampingHF: Float = 0.3
        var dampingLF: Float = 0.1
        var currentPreset: Int = 2 // Studio
        var isRecording: Bool = false
        var recordingMode: RecordingMode = .mix
        
        enum RecordingMode {
            case mix, wet, dry, wetAndDry, all
        }
    }
    
    public struct HostInfo {
        let name: String
        let version: String
        let supportsAutomation: Bool
        let supportsMIDI: Bool
        let supportsPresets: Bool
        let maxBufferSize: Int
        let sampleRate: Double
    }
    
    // Current application state
    @Published public var appState = AppState()
    
    // MARK: - Core Audio Integration
    private var audioUnit: ReverbAudioUnit?
    private var audioManager: AudioManager?
    private var parameterController: ResponsiveParameterController?
    
    // MARK: - Initialization
    public init() {
        detectOperationMode()
        setupStateObservation()
    }
    
    // MARK: - Mode Detection and Switching
    
    private func detectOperationMode() {
        // Detect if running as AUv3 extension or standalone app
        if Bundle.main.bundleURL.pathExtension == "appex" {
            currentMode = .audioUnit
            print("🔌 Running in AUv3 plugin mode")
        } else {
            currentMode = .standalone
            print("📱 Running in standalone app mode")
        }
    }
    
    public func configureForStandaloneMode(audioManager: AudioManager, 
                                         parameterController: ResponsiveParameterController) {
        guard currentMode == .standalone else { return }
        
        self.audioManager = audioManager
        self.parameterController = parameterController
        
        // Sync state from standalone components
        syncStateFromStandalone()
        
        print("✅ Configured for standalone mode")
    }
    
    public func configureForAudioUnitMode(audioUnit: ReverbAudioUnit) {
        guard currentMode == .audioUnit else { return }
        
        self.audioUnit = audioUnit
        
        // Detect host information
        detectHostInformation()
        
        // Sync state from audio unit
        syncStateFromAudioUnit()
        
        isPluginActive = true
        
        print("🎛️ Configured for AUv3 plugin mode")
    }
    
    // MARK: - Host Detection
    
    private func detectHostInformation() {
        guard currentMode == .audioUnit else { return }
        
        // Detect host application information
        let hostBundle = Bundle.main
        let hostName = hostBundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Unknown Host"
        let hostVersion = hostBundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        
        // Detect host capabilities (simplified detection)
        let supportsAutomation = true // Most modern hosts support this
        let supportsMIDI = hostName.lowercased().contains("garage") || hostName.lowercased().contains("logic")
        let supportsPresets = true
        
        hostInfo = HostInfo(
            name: hostName,
            version: hostVersion,
            supportsAutomation: supportsAutomation,
            supportsMIDI: supportsMIDI,
            supportsPresets: supportsPresets,
            maxBufferSize: 512, // Default, will be updated
            sampleRate: 44100   // Default, will be updated
        )
        
        print("🎵 Detected host: \(hostName) v\(hostVersion)")
    }
    
    // MARK: - State Synchronization
    
    private func setupStateObservation() {
        // Observe app state changes to sync with active mode
        $appState
            .sink { [weak self] newState in
                self?.syncStateToActiveMode(newState)
            }
            .store(in: &cancellables)
    }
    
    private func syncStateFromStandalone() {
        guard let parameterController = parameterController else { return }
        
        appState.wetDryMix = parameterController.wetDryMix
        appState.inputGain = parameterController.inputGain
        appState.outputGain = parameterController.outputGain
        appState.reverbDecay = parameterController.reverbDecay
        appState.reverbSize = parameterController.reverbSize
        appState.dampingHF = parameterController.dampingHF
        appState.dampingLF = parameterController.dampingLF
    }
    
    private func syncStateFromAudioUnit() {
        guard let audioUnit = audioUnit,
              let parameterTree = audioUnit.parameterTree else { return }
        
        appState.wetDryMix = parameterTree.parameter(withAddress: 0)?.value ?? 0.5
        appState.inputGain = parameterTree.parameter(withAddress: 1)?.value ?? 1.0
        appState.outputGain = parameterTree.parameter(withAddress: 2)?.value ?? 1.0
        appState.reverbDecay = parameterTree.parameter(withAddress: 3)?.value ?? 0.7
        appState.reverbSize = parameterTree.parameter(withAddress: 4)?.value ?? 0.5
        appState.dampingHF = parameterTree.parameter(withAddress: 5)?.value ?? 0.3
        appState.dampingLF = parameterTree.parameter(withAddress: 6)?.value ?? 0.1
        
        if let currentPreset = audioUnit.currentPreset {
            appState.currentPreset = currentPreset.number
        }
    }
    
    private func syncStateToActiveMode(_ state: AppState) {
        switch currentMode {
        case .standalone:
            syncStateToStandalone(state)
        case .audioUnit:
            syncStateToAudioUnit(state)
        }
    }
    
    private func syncStateToStandalone(_ state: AppState) {
        guard let parameterController = parameterController else { return }
        
        // Update parameter controller (this will trigger audio updates)
        parameterController.wetDryMix = state.wetDryMix
        parameterController.inputGain = state.inputGain
        parameterController.outputGain = state.outputGain
        parameterController.reverbDecay = state.reverbDecay
        parameterController.reverbSize = state.reverbSize
        parameterController.dampingHF = state.dampingHF
        parameterController.dampingLF = state.dampingLF
    }
    
    private func syncStateToAudioUnit(_ state: AppState) {
        guard let audioUnit = audioUnit,
              let parameterTree = audioUnit.parameterTree else { return }
        
        // Update audio unit parameters
        parameterTree.parameter(withAddress: 0)?.setValue(state.wetDryMix, originator: nil)
        parameterTree.parameter(withAddress: 1)?.setValue(state.inputGain, originator: nil)
        parameterTree.parameter(withAddress: 2)?.setValue(state.outputGain, originator: nil)
        parameterTree.parameter(withAddress: 3)?.setValue(state.reverbDecay, originator: nil)
        parameterTree.parameter(withAddress: 4)?.setValue(state.reverbSize, originator: nil)
        parameterTree.parameter(withAddress: 5)?.setValue(state.dampingHF, originator: nil)
        parameterTree.parameter(withAddress: 6)?.setValue(state.dampingLF, originator: nil)
        
        // Update preset if changed
        if audioUnit.currentPreset?.number != state.currentPreset {
            audioUnit.currentPreset = audioUnit.factoryPresets[state.currentPreset]
        }
    }
    
    // MARK: - Public Interface Methods
    
    /// Update parameter value with automatic mode handling
    public func updateParameter(_ parameter: ParameterType, value: Float) {
        switch parameter {
        case .wetDryMix:
            appState.wetDryMix = value
        case .inputGain:
            appState.inputGain = value
        case .outputGain:
            appState.outputGain = value
        case .reverbDecay:
            appState.reverbDecay = value
        case .reverbSize:
            appState.reverbSize = value
        case .dampingHF:
            appState.dampingHF = value
        case .dampingLF:
            appState.dampingLF = value
        }
    }
    
    public enum ParameterType {
        case wetDryMix, inputGain, outputGain
        case reverbDecay, reverbSize
        case dampingHF, dampingLF
    }
    
    /// Load preset with mode-appropriate handling
    public func loadPreset(_ preset: ReverbPreset) {
        appState.currentPreset = preset.rawValue
        
        // Update parameter values based on preset
        switch preset {
        case .clean:
            updateMultipleParameters(wetDry: 0.2, decay: 0.3, size: 0.2, dampingHF: 0.7, dampingLF: 0.1)
        case .vocalBooth:
            updateMultipleParameters(wetDry: 0.3, decay: 0.4, size: 0.3, dampingHF: 0.6, dampingLF: 0.2)
        case .studio:
            updateMultipleParameters(wetDry: 0.4, decay: 0.6, size: 0.5, dampingHF: 0.4, dampingLF: 0.1)
        case .cathedral:
            updateMultipleParameters(wetDry: 0.6, decay: 0.9, size: 0.8, dampingHF: 0.2, dampingLF: 0.0)
        case .custom:
            // Keep current values
            break
        }
    }
    
    private func updateMultipleParameters(wetDry: Float, decay: Float, size: Float, 
                                        dampingHF: Float, dampingLF: Float) {
        appState.wetDryMix = wetDry
        appState.reverbDecay = decay
        appState.reverbSize = size
        appState.dampingHF = dampingHF
        appState.dampingLF = dampingLF
    }
    
    // MARK: - Recording Management (Standalone Only)
    
    public func startRecording(mode: AppState.RecordingMode) {
        guard currentMode == .standalone else {
            print("⚠️ Recording only available in standalone mode")
            return
        }
        
        appState.isRecording = true
        appState.recordingMode = mode
        
        // Delegate to audio manager
        audioManager?.startRecording()
    }
    
    public func stopRecording() {
        guard currentMode == .standalone else { return }
        
        appState.isRecording = false
        audioManager?.stopRecording()
    }
    
    // MARK: - Mode-Specific Capabilities
    
    public var availableFeatures: [Feature] {
        switch currentMode {
        case .standalone:
            return [.recording, .offlineProcessing, .presets, .automation]
        case .audioUnit:
            return [.presets, .automation, .hostIntegration]
        }
    }
    
    public enum Feature {
        case recording          // Audio recording capabilities
        case offlineProcessing  // Batch processing
        case presets           // Preset management
        case automation        // Parameter automation
        case hostIntegration   // DAW host integration
    }
    
    public func isFeatureAvailable(_ feature: Feature) -> Bool {
        return availableFeatures.contains(feature)
    }
    
    // MARK: - Cleanup
    private var cancellables = Set<AnyCancellable>()
    
    deinit {
        cancellables.removeAll()
    }
}

// MARK: - Preset Enumeration

public enum ReverbPreset: Int, CaseIterable {
    case clean = 0
    case vocalBooth = 1
    case studio = 2
    case cathedral = 3
    case custom = 4
    
    public var name: String {
        switch self {
        case .clean: return "Clean"
        case .vocalBooth: return "Vocal Booth"
        case .studio: return "Studio"
        case .cathedral: return "Cathedral"
        case .custom: return "Custom"
        }
    }
}

// MARK: - Feature Detection Extension

extension DualModeManager.Feature: Equatable {
    public static func == (lhs: DualModeManager.Feature, rhs: DualModeManager.Feature) -> Bool {
        switch (lhs, rhs) {
        case (.recording, .recording),
             (.offlineProcessing, .offlineProcessing),
             (.presets, .presets),
             (.automation, .automation),
             (.hostIntegration, .hostIntegration):
            return true
        default:
            return false
        }
    }
}

// MARK: - Import Missing Dependencies

import Combine