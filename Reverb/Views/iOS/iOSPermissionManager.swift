import Foundation
import AVFoundation
import UIKit

/// iOS Permission manager for microphone and audio access
@available(iOS 14.0, *)
class iOSPermissionManager: ObservableObject {
    
    @Published var microphonePermissionStatus: AVAudioSession.RecordPermission = .undetermined
    @Published var hasRequestedPermission = false
    
    init() {
        checkCurrentPermissions()
    }
    
    func checkCurrentPermissions() {
        microphonePermissionStatus = AVAudioSession.sharedInstance().recordPermission
    }
    
    func requestMicrophonePermission() async {
        guard microphonePermissionStatus == .undetermined else { return }
        
        hasRequestedPermission = true
        
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async {
                    self.microphonePermissionStatus = granted ? .granted : .denied
                    continuation.resume()
                }
            }
        }
    }
    
    var permissionDescription: String {
        switch microphonePermissionStatus {
        case .granted:
            return "Microphone access granted"
        case .denied:
            return "Microphone access denied"
        case .undetermined:
            return "Microphone permission not requested"
        @unknown default:
            return "Unknown permission status"
        }
    }
    
    var canRecord: Bool {
        return microphonePermissionStatus == .granted
    }
    
    func openSettings() {
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
    }
}