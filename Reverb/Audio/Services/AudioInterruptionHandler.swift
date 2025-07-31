import Foundation
import AVFoundation
import UIKit
import CallKit

/// Handles audio interruptions on iOS (phone calls, Siri, FaceTime, etc.)
/// Manages graceful recording pause/resume and user notifications
class AudioInterruptionHandler: NSObject, ObservableObject {
    
    // MARK: - Interruption Types
    
    enum InterruptionType {
        case phoneCall           // Incoming/outgoing phone call
        case siri               // Siri activation
        case faceTime           // FaceTime call
        case systemAlert        // System alert with audio
        case bluetoothConnection // Bluetooth device connection/disconnection
        case routeChange        // Audio route change (headphones, speaker)
        case backgroundApp      // App backgrounded during recording
        case unknown(reason: String) // Other interruption
        
        var description: String {
            switch self {
            case .phoneCall: return "Phone Call"
            case .siri: return "Siri"
            case .faceTime: return "FaceTime"
            case .systemAlert: return "System Alert"
            case .bluetoothConnection: return "Bluetooth Connection"
            case .routeChange: return "Audio Route Change"
            case .backgroundApp: return "App Backgrounded"
            case .unknown(let reason): return "Unknown (\(reason))"
            }
        }
        
        var allowsRecordingResume: Bool {
            switch self {
            case .phoneCall, .faceTime: return false // Cannot resume during calls
            case .siri, .systemAlert: return true   // Can resume after
            case .bluetoothConnection, .routeChange: return true
            case .backgroundApp: return true
            case .unknown: return true // Default to allowing resume
            }
        }
        
        var requiresUserConfirmation: Bool {
            switch self {
            case .phoneCall, .faceTime: return true // Important interruptions
            case .siri, .systemAlert: return false  // Automatic resume OK
            case .bluetoothConnection, .routeChange: return false
            case .backgroundApp: return false
            case .unknown: return true // Err on side of caution
            }
        }
    }
    
    // MARK: - Interruption State
    
    @Published var isInterrupted = false
    @Published var currentInterruption: InterruptionType?
    @Published var interruptionStartTime: Date?
    @Published var canResumeRecording = false
    @Published var userConfirmationRequired = false
    
    // State before interruption
    private var wasRecordingBeforeInterruption = false
    private var audioSessionWasActive = false
    private var previousAudioSessionCategory: AVAudioSession.Category?
    private var previousAudioSessionMode: AVAudioSession.Mode?
    
    // MARK: - Delegates and Callbacks
    
    weak var recordingManager: iOSRecordingManager?
    
    // Interruption callbacks
    var onInterruptionBegan: ((InterruptionType) -> Void)?
    var onInterruptionEnded: ((InterruptionType, Bool) -> Void)? // Type, canResume
    var onRecordingPaused: (() -> Void)?
    var onRecordingResumed: (() -> Void)?
    
    // MARK: - Notification Observers
    
    private var notificationObservers: [NSObjectProtocol] = []
    
    // MARK: - Call Detection
    
    private let callObserver = CXCallObserver()
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupInterruptionHandling()
    }
    
    deinit {
        removeNotificationObservers()
    }
    
    private func setupInterruptionHandling() {
        setupAudioSessionNotifications()
        setupApplicationNotifications()
        setupCallDetection()
        
        print("✅ Audio interruption handling configured")
    }
    
    // MARK: - Audio Session Notifications
    
    private func setupAudioSessionNotifications() {
        let audioSession = AVAudioSession.sharedInstance()
        
        // Audio interruption notifications
        let interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: audioSession,
            queue: .main
        ) { [weak self] notification in
            self?.handleAudioInterruption(notification)
        }
        notificationObservers.append(interruptionObserver)
        
        // Audio route change notifications  
        let routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: audioSession,
            queue: .main
        ) { [weak self] notification in
            self?.handleAudioRouteChange(notification)
        }
        notificationObservers.append(routeChangeObserver)
        
        // Media services were reset
        let mediaServicesResetObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: audioSession,
            queue: .main
        ) { [weak self] notification in
            self?.handleMediaServicesReset(notification)
        }
        notificationObservers.append(mediaServicesResetObserver)
    }
    
    private func setupApplicationNotifications() {
        // App lifecycle notifications
        let backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAppBackgrounded()
        }
        notificationObservers.append(backgroundObserver)
        
        let foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAppForegrounded()
        }
        notificationObservers.append(foregroundObserver)
        
        // Memory warning
        let memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMemoryWarning()
        }
        notificationObservers.append(memoryWarningObserver)
    }
    
    private func setupCallDetection() {
        callObserver.setDelegate(self, queue: DispatchQueue.main)
    }
    
    // MARK: - Interruption Handlers
    
    private func handleAudioInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let interruptionType = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch interruptionType {
        case .began:
            handleInterruptionBegan(notification)
        case .ended:
            handleInterruptionEnded(notification)
        @unknown default:
            print("⚠️ Unknown audio interruption type")
        }
    }
    
    private func handleInterruptionBegan(_ notification: Notification) {
        print("🔇 Audio interruption began")
        
        // Determine interruption type
        let interruptionType = determineInterruptionType(from: notification)
        
        // Save current state
        wasRecordingBeforeInterruption = recordingManager?.isRecording ?? false
        audioSessionWasActive = AVAudioSession.sharedInstance().isOtherAudioPlaying
        previousAudioSessionCategory = AVAudioSession.sharedInstance().category
        previousAudioSessionMode = AVAudioSession.sharedInstance().mode
        
        // Update state
        currentInterruption = interruptionType
        isInterrupted = true
        interruptionStartTime = Date()
        canResumeRecording = interruptionType.allowsRecordingResume
        userConfirmationRequired = interruptionType.requiresUserConfirmation
        
        // Pause recording if active
        if wasRecordingBeforeInterruption {
            pauseRecordingForInterruption()
        }
        
        // Notify delegates
        onInterruptionBegan?(interruptionType)
        
        // Show user notification if needed
        if interruptionType.requiresUserConfirmation {
            showInterruptionNotification(interruptionType)
        }
        
        print("📱 Interruption: \(interruptionType.description)")
    }
    
    private func handleInterruptionEnded(_ notification: Notification) {
        print("🔊 Audio interruption ended")
        
        guard let currentInterruption = currentInterruption else { return }
        
        // Check interruption options
        let shouldResume = checkShouldResumeAfterInterruption(notification)
        
        // Update state
        isInterrupted = false
        canResumeRecording = shouldResume && currentInterruption.allowsRecordingResume
        
        // Handle recording resumption
        if wasRecordingBeforeInterruption && canResumeRecording {
            if currentInterruption.requiresUserConfirmation {
                promptUserForRecordingResumption()
            } else {
                resumeRecordingAfterInterruption()
            }
        }
        
        // Notify delegates
        onInterruptionEnded?(currentInterruption, canResumeRecording)
        
        // Clear interruption state
        self.currentInterruption = nil
        interruptionStartTime = nil
        wasRecordingBeforeInterruption = false
        
        print("✅ Interruption ended: \(currentInterruption.description)")
    }
    
    private func handleAudioRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        print("🎧 Audio route changed: \(reason)")
        
        switch reason {
        case .newDeviceAvailable:
            handleNewAudioDeviceAvailable(notification)
        case .oldDeviceUnavailable:
            handleAudioDeviceRemoved(notification)
        case .categoryChange:
            handleAudioCategoryChange(notification)
        case .override:
            handleAudioRouteOverride(notification)
        default:
            break
        }
    }
    
    private func handleMediaServicesReset(_ notification: Notification) {
        print("🔄 Media services were reset")
        
        // This is a serious interruption - stop recording and notify user
        let interruptionType = InterruptionType.unknown(reason: "Media services reset")
        
        if recordingManager?.isRecording == true {
            currentInterruption = interruptionType
            isInterrupted = true
            pauseRecordingForInterruption()
            
            // Show critical error to user
            showCriticalInterruptionAlert("Audio system was reset. Recording has been stopped.")
        }
    }
    
    private func handleAppBackgrounded() {
        print("📱 App entered background")
        
        // Check if recording and handle appropriately
        if recordingManager?.isRecording == true {
            let interruptionType = InterruptionType.backgroundApp
            
            // iOS allows background recording with proper configuration
            // But we should inform the user and potentially pause
            currentInterruption = interruptionType
            wasRecordingBeforeInterruption = true
            
            // Show local notification
            showBackgroundRecordingNotification()
        }
    }
    
    private func handleAppForegrounded() {
        print("📱 App entered foreground")
        
        // If we were interrupted by backgrounding, check if we should resume
        if currentInterruption == .backgroundApp {
            currentInterruption = nil
            
            // Recording might have continued in background
            // Just update UI state
        }
    }
    
    private func handleMemoryWarning() {
        print("⚠️ Memory warning received")
        
        // If recording, consider stopping to free memory
        if recordingManager?.isRecording == true {
            let interruptionType = InterruptionType.unknown(reason: "Low memory")
            
            currentInterruption = interruptionType
            isInterrupted = true
            pauseRecordingForInterruption()
            
            showInterruptionAlert(
                title: "Low Memory",
                message: "Recording has been paused due to low memory. Please close other apps and try again."
            )
        }
    }
    
    // MARK: - Audio Device Handling
    
    private func handleNewAudioDeviceAvailable(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let routeDescription = userInfo[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription else {
            return
        }
        
        let currentRoute = AVAudioSession.sharedInstance().currentRoute
        print("🎧 New audio device: \(currentRoute.outputs.first?.portName ?? "Unknown")")
        
        // Check if this affects recording quality
        if recordingManager?.isRecording == true {
            validateAudioRouteForRecording(currentRoute)
        }
    }
    
    private func handleAudioDeviceRemoved(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let routeDescription = userInfo[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription else {
            return
        }
        
        print("🎧 Audio device removed")
        
        // If recording with external device and it was removed, pause recording
        if recordingManager?.isRecording == true {
            let previousInputs = routeDescription.inputs
            let currentInputs = AVAudioSession.sharedInstance().currentRoute.inputs
            
            if previousInputs.count > currentInputs.count {
                // External microphone was likely removed
                let interruptionType = InterruptionType.routeChange
                
                currentInterruption = interruptionType
                isInterrupted = true
                pauseRecordingForInterruption()
                
                showInterruptionAlert(
                    title: "Microphone Disconnected",
                    message: "External microphone was disconnected. Recording has been paused."
                )
            }
        }
    }
    
    private func handleAudioCategoryChange(_ notification: Notification) {
        print("🔧 Audio category changed")
        
        // Verify category is still appropriate for recording
        let currentCategory = AVAudioSession.sharedInstance().category
        
        if recordingManager?.isRecording == true && currentCategory != .playAndRecord {
            print("⚠️ Audio category changed from playAndRecord during recording")
            
            // Try to restore appropriate category
            do {
                try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default)
            } catch {
                print("❌ Failed to restore recording category: \(error)")
                
                // Pause recording if we can't restore proper category
                let interruptionType = InterruptionType.unknown(reason: "Audio category changed")
                currentInterruption = interruptionType
                isInterrupted = true
                pauseRecordingForInterruption()
            }
        }
    }
    
    private func handleAudioRouteOverride(_ notification: Notification) {
        print("🔄 Audio route override")
        // Handle route override (e.g., force to speaker)
    }
    
    // MARK: - Recording Control
    
    private func pauseRecordingForInterruption() {
        Task {
            await recordingManager?.stopRecording()
            
            DispatchQueue.main.async {
                self.onRecordingPaused?()
            }
        }
        
        print("⏸️ Recording paused due to interruption")
    }
    
    private func resumeRecordingAfterInterruption() {
        guard canResumeRecording else { return }
        
        // Restore audio session
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            if let previousCategory = previousAudioSessionCategory {
                try audioSession.setCategory(previousCategory, mode: previousAudioSessionMode ?? .default)
            }
            
            try audioSession.setActive(true)
            
            // Resume recording
            Task {
                await recordingManager?.startRecording()
                
                DispatchQueue.main.async {
                    self.onRecordingResumed?()
                }
            }
            
            print("▶️ Recording resumed after interruption")
            
        } catch {
            print("❌ Failed to resume recording: \(error)")
            
            showInterruptionAlert(
                title: "Cannot Resume Recording",
                message: "Failed to resume recording after interruption: \(error.localizedDescription)"
            )
        }
    }
    
    // MARK: - User Interaction
    
    private func promptUserForRecordingResumption() {
        guard let interruptionType = currentInterruption else { return }
        
        let alert = UIAlertController(
            title: "Resume Recording?",
            message: "Recording was paused due to \(interruptionType.description). Would you like to resume?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Resume", style: .default) { [weak self] _ in
            self?.resumeRecordingAfterInterruption()
        })
        
        alert.addAction(UIAlertAction(title: "Stop Recording", style: .cancel) { [weak self] _ in
            self?.wasRecordingBeforeInterruption = false
            self?.canResumeRecording = false
        })
        
        presentAlert(alert)
    }
    
    private func showInterruptionNotification(_ interruptionType: InterruptionType) {
        // Show local notification for background interruptions
        let content = UNMutableNotificationContent()
        content.title = "Recording Interrupted"
        content.body = "Recording was paused due to \(interruptionType.description)"
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "recording-interruption",
            content: content,
            trigger: nil // Immediate
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Failed to show interruption notification: \(error)")
            }
        }
    }
    
    private func showBackgroundRecordingNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Recording in Background"
        content.body = "Reverb is continuing to record in the background"
        content.sound = nil // Silent notification
        
        let request = UNNotificationRequest(
            identifier: "background-recording",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    private func showInterruptionAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        presentAlert(alert)
    }
    
    private func showCriticalInterruptionAlert(_ message: String) {
        let alert = UIAlertController(
            title: "Critical Audio Error",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        presentAlert(alert)
    }
    
    private func presentAlert(_ alert: UIAlertController) {
        DispatchQueue.main.async {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let rootViewController = window.rootViewController {
                rootViewController.present(alert, animated: true)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func determineInterruptionType(from notification: Notification) -> InterruptionType {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionInterruptionReasonKey] as? UInt else {
            return .unknown(reason: "No interruption reason")
        }
        
        if #available(iOS 14.5, *) {
            if let reason = AVAudioSession.InterruptionReason(rawValue: reasonValue) {
                switch reason {
                case .default:
                    return .unknown(reason: "Default interruption")
                case .appWasSuspended:
                    return .backgroundApp
                case .builtInMicMuted:
                    return .systemAlert
                @unknown default:
                    return .unknown(reason: "Unknown reason \(reasonValue)")
                }
            }
        }
        
        // Fallback for older iOS versions
        return .unknown(reason: "Reason code \(reasonValue)")
    }
    
    private func checkShouldResumeAfterInterruption(_ notification: Notification) -> Bool {
        guard let userInfo = notification.userInfo else { return false }
        
        if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            return options.contains(.shouldResume)
        }
        
        return false
    }
    
    private func validateAudioRouteForRecording(_ route: AVAudioSessionRouteDescription) {
        let inputs = route.inputs
        
        if inputs.isEmpty {
            print("⚠️ No audio input available")
            
            let interruptionType = InterruptionType.routeChange
            currentInterruption = interruptionType
            isInterrupted = true
            pauseRecordingForInterruption()
            
            showInterruptionAlert(
                title: "No Microphone",
                message: "No microphone is available for recording."
            )
        } else {
            let inputSource = inputs.first!
            print("🎤 Recording with: \(inputSource.portName) (\(inputSource.portType.rawValue))")
        }
    }
    
    private func removeNotificationObservers() {
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers.removeAll()
    }
    
    // MARK: - Public Interface
    
    func setRecordingManager(_ manager: iOSRecordingManager) {
        recordingManager = manager
    }
    
    func forceStopRecording() {
        wasRecordingBeforeInterruption = false
        canResumeRecording = false
        
        Task {
            await recordingManager?.stopRecording()
        }
    }
}

// MARK: - CXCallObserverDelegate

extension AudioInterruptionHandler: CXCallObserverDelegate {
    
    func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        if call.hasEnded {
            print("📞 Call ended")
            
            // If we were interrupted by a call, check if we can resume
            if currentInterruption == .phoneCall && wasRecordingBeforeInterruption {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.promptUserForRecordingResumption()
                }
            }
        } else if call.isOutgoing || call.hasConnected {
            print("📞 Call started")
            
            // Pause recording for phone call
            if recordingManager?.isRecording == true {
                currentInterruption = .phoneCall
                isInterrupted = true
                interruptionStartTime = Date()
                wasRecordingBeforeInterruption = true
                canResumeRecording = false // Cannot resume during call
                userConfirmationRequired = true
                
                pauseRecordingForInterruption()
                
                showInterruptionNotification(.phoneCall)
            }
        }
    }
}