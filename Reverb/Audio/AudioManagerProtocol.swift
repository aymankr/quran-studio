import Foundation
import AVFoundation

protocol AudioManagerProtocol: ObservableObject {
    var isMonitoring: Bool { get }
    var isRecording: Bool { get }
    var selectedReverbPreset: ReverbPreset { get }
    var currentAudioLevel: Float { get }
    var canStartMonitoring: Bool { get }
    var lastRecordingFilename: String? { get }
    var engineInfo: String { get }
    var currentPresetDescription: String { get }
    var cpuUsage: Double { get }
    
    func startMonitoring()
    func stopMonitoring()
    func toggleRecording()
    func updateReverbPreset(_ preset: ReverbPreset)
    func setInputVolume(_ volume: Float)
    func setOutputVolume(_ volume: Float, isMuted: Bool)
    func diagnostic()
}