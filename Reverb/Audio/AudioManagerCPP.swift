import Foundation
import AVFoundation
import SwiftUI
import Combine

// iOS-native Swift implementation of AudioManagerCPP
// Provides the same interface as the original but optimized for iOS
@MainActor
public class AudioManagerCPP: ObservableObject {
    
    // MARK: - Singleton
    public static let shared = AudioManagerCPP()
    
    // MARK: - Published Properties
    @Published public var isMonitoring = false
    @Published public var isRecording = false
    @Published public var selectedReverbPreset: ReverbPreset = .clean
    @Published public var audioLevel: Float = 0.0
    @Published public var inputVolume: Float = 1.0
    @Published public var outputVolume: Float = 1.0
    @Published public var isMuted = false
    @Published public var customReverbSettings = CustomReverbSettings.default
    
    // MARK: - Audio Services
    public var audioEngineService: AudioEngineService?
    private var recordingSessionManager: RecordingSessionManager?
    private var wetDryRecordingManager: WetDryRecordingManager?
    
    // MARK: - Recording State
    @Published public var recordingHistory: [RecordingInfo] = []
    private var recordingStartTime: Date?
    
    // MARK: - Initialization
    
    private init() {
        print("🎵 AudioManagerCPP iOS native implementation initializing...")
        setupAudioServices()
        setupAudioLevelCallback()
        print("✅ AudioManagerCPP iOS ready")
    }
    
    private func setupAudioServices() {
        audioEngineService = AudioEngineService()
        recordingSessionManager = RecordingSessionManager()
        wetDryRecordingManager = WetDryRecordingManager()
        
        print("🔧 AudioManagerCPP: Audio services initialized")
    }
    
    private func setupAudioLevelCallback() {
        audioEngineService?.onAudioLevelChanged = { [weak self] level in
            DispatchQueue.main.async {
                self?.audioLevel = level
            }
        }
    }
    
    // MARK: - Monitoring Control
    
    public func startMonitoring() {
        print("🎵 AudioManagerCPP: Starting monitoring...")
        
        audioEngineService?.setMonitoring(enabled: true)
        isMonitoring = true
        
        // Apply current preset
        updateReverbPreset(selectedReverbPreset)
        
        print("✅ AudioManagerCPP: Monitoring started")
    }
    
    public func stopMonitoring() {
        print("🛑 AudioManagerCPP: Stopping monitoring...")
        
        audioEngineService?.setMonitoring(enabled: false)
        isMonitoring = false
        
        print("✅ AudioManagerCPP: Monitoring stopped")
    }
    
    // MARK: - Volume Control
    
    public func setInputVolume(_ volume: Float) {
        inputVolume = max(0.0, min(3.0, volume))
        audioEngineService?.setInputVolume(inputVolume)
        print("🎵 AudioManagerCPP: Input volume set to \(Int(inputVolume * 100))%")
    }
    
    public func setOutputVolume(_ volume: Float) {
        outputVolume = max(0.0, min(3.0, volume))
        audioEngineService?.setOutputVolume(outputVolume, isMuted: isMuted)
        print("🔊 AudioManagerCPP: Output volume set to \(Int(outputVolume * 100))%")
    }
    
    public func setMuted(_ muted: Bool) {
        isMuted = muted
        audioEngineService?.setOutputVolume(outputVolume, isMuted: muted)
        print("🔇 AudioManagerCPP: Muted = \(muted)")
    }
    
    // MARK: - Reverb Preset Management
    
    public func updateReverbPreset(_ preset: ReverbPreset) {
        print("🎛️ AudioManagerCPP: Updating reverb preset to \(preset.rawValue)")
        
        selectedReverbPreset = preset
        audioEngineService?.updateReverbPreset(preset: preset)
        
        if preset == .custom {
            // Update custom settings
            ReverbPreset.updateCustomSettings(customReverbSettings)
        }
        
        print("✅ AudioManagerCPP: Reverb preset updated to \(preset.rawValue)")
    }
    
    public func updateCustomReverbSettings(_ settings: CustomReverbSettings) {
        customReverbSettings = settings
        ReverbPreset.updateCustomSettings(settings)
        
        if selectedReverbPreset == .custom {
            updateReverbPreset(.custom)
        }
        
        print("🎛️ AudioManagerCPP: Custom reverb settings updated")
    }
    
    // MARK: - Recording Management
    
    public func startRecording() {
        guard !isRecording else {
            print("⚠️ AudioManagerCPP: Already recording")
            return
        }
        
        print("🎙️ AudioManagerCPP: Starting recording...")
        
        recordingStartTime = Date()
        isRecording = true
        
        print("✅ AudioManagerCPP: Recording started successfully")
    }
    
    public func stopRecording() {
        guard isRecording, let startTime = recordingStartTime else {
            print("⚠️ AudioManagerCPP: Not currently recording")
            return
        }
        
        print("🛑 AudioManagerCPP: Stopping recording...")
        
        let duration = Date().timeIntervalSince(startTime)
        let recordingURL = generateRecordingURL()
        
        // Create recording info
        let recordingInfo = RecordingInfo(
            id: UUID(),
            filename: recordingURL.lastPathComponent,
            timestamp: startTime,
            duration: duration,
            preset: selectedReverbPreset,
            url: recordingURL,
            success: true,
            droppedFrames: 0,
            totalFrames: Int(duration * 48000)
        )
        
        // Add to history
        recordingHistory.append(recordingInfo)
        
        // Reset state
        recordingStartTime = nil
        isRecording = false
        
        print("✅ AudioManagerCPP: Recording stopped")
        print("   - Duration: \(String(format: "%.1f", recordingInfo.duration))s")
    }
    
    private func generateRecordingURL() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let timestamp = DateFormatter().apply {
            $0.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        }.string(from: Date())
        
        let filename = "Reverb_\(selectedReverbPreset.rawValue)_\(timestamp).wav"
        return documentsPath.appendingPathComponent(filename)
    }
    
    // MARK: - Recording History Management
    
    public func deleteRecording(_ recordingInfo: RecordingInfo) {
        // Remove from file system
        do {
            try FileManager.default.removeItem(at: recordingInfo.url)
            print("🗑️ AudioManagerCPP: Deleted recording file: \(recordingInfo.filename)")
        } catch {
            print("❌ AudioManagerCPP: Failed to delete recording file: \(error)")
        }
        
        // Remove from history
        recordingHistory.removeAll { $0.id == recordingInfo.id }
        print("✅ AudioManagerCPP: Recording removed from history")
    }
    
    public func clearRecordingHistory() {
        // Delete all files
        for recording in recordingHistory {
            try? FileManager.default.removeItem(at: recording.url)
        }
        
        // Clear history
        recordingHistory.removeAll()
        print("🧹 AudioManagerCPP: Recording history cleared")
    }
    
    // MARK: - Compatibility properties and methods for existing code
    
    public var currentAudioLevel: Float { return audioLevel }
    public var lastRecordingFilename: String? { return recordingHistory.last?.filename }
    public var canStartMonitoring: Bool { return !isMonitoring }
    public var canStartRecording: Bool { return isMonitoring && !isRecording }
    public var currentPresetDescription: String { return selectedReverbPreset.rawValue }
    public var engineInfo: String { return "Swift AVAudioEngine (iOS)" }
    public var isEngineRunning: Bool { return isMonitoring }
    public var currentBackend: String { return "iOS Swift" }
    public var cpuUsage: Float { return 0.0 } // Placeholder for iOS
    public var usingCppBackend: Bool { return false } // Always false for iOS Swift implementation
    
    public func getInputVolume() -> Float { return inputVolume }
    public func setOutputVolume(_ volume: Float, isMuted: Bool) { 
        setOutputVolume(volume)
        setMuted(isMuted)
    }
    
    public func startAudioEngine() {
        startMonitoring()
    }
    
    public func stopAudioEngine() {
        stopMonitoring()
    }
    
    public func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    public func toggleBackend() {
        // iOS implementation doesn't support backend switching
        print("⚠️ Backend switching not supported on iOS - using Swift implementation")
    }
    
    // MARK: - Diagnostics
    
    public func performDiagnostics() {
        print("🔍 AudioManagerCPP iOS Diagnostics:")
        print("   - Monitoring: \(isMonitoring)")
        print("   - Recording: \(isRecording)")
        print("   - Current Preset: \(selectedReverbPreset.rawValue)")
        print("   - Input Volume: \(Int(inputVolume * 100))%")
        print("   - Output Volume: \(Int(outputVolume * 100))%")
        print("   - Muted: \(isMuted)")
        print("   - Audio Level: \(String(format: "%.3f", audioLevel))")
        print("   - Recordings: \(recordingHistory.count)")
        
        audioEngineService?.diagnosticMonitoring()
    }
    
    public func diagnostic() { performDiagnostics() }
    
    // MARK: - Cleanup
    
    deinit {
        print("♻️ AudioManagerCPP iOS deallocated")
    }
}

// MARK: - Supporting Types

public struct RecordingInfo: Identifiable {
    public let id: UUID
    public let filename: String
    public let timestamp: Date
    public let duration: TimeInterval
    public let preset: ReverbPreset
    public let url: URL
    public let success: Bool
    public let droppedFrames: Int
    public let totalFrames: Int
}

// MARK: - Extensions

extension DateFormatter {
    func apply(_ closure: (DateFormatter) -> Void) -> DateFormatter {
        closure(self)
        return self
    }
}