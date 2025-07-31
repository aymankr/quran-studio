import Foundation
import AVFoundation
import OSLog

#if os(iOS)
import UIKit
#endif

/// Cross-platform audio session manager optimized for iOS compatibility while maintaining macOS performance
/// Implements AD 480 RE level latency targets (64 samples) on iOS devices
class CrossPlatformAudioSession: ObservableObject {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Reverb", category: "AudioSession")
    
    // MARK: - Session State
    @Published var isConfigured = false
    @Published var currentSampleRate: Double = 48000
    @Published var currentBufferSize: Int = 64
    @Published var actualLatency: Double = 0.0
    @Published var audioRouteDescription: String = ""
    @Published var isBluetoothConnected = false
    
    // MARK: - Target Configuration
    private let targetSampleRate: Double = 48000 // Professional quality
    private let targetBufferSize: Int = 64       // AD 480 RE target latency
    private let fallbackBufferSize: Int = 128    // Fallback for less capable devices
    private let bluetoothBufferSize: Int = 256   // Bluetooth typically requires larger buffers
    
    // MARK: - Notification Observers
    #if os(iOS)
    private var routeChangeObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var mediaServicesLostObserver: NSObjectProtocol?
    private var mediaServicesResetObserver: NSObjectProtocol?
    #endif
    
    // MARK: - Initialization
    init() {
        logger.info("🎵 Initializing cross-platform audio session")
        setupNotificationObservers()
    }
    
    // MARK: - Audio Session Configuration
    func configureAudioSession() async throws {
        logger.info("🔧 Configuring audio session for optimal performance")
        
        #if os(iOS)
        try await configureiOSAudioSession()
        #elseif os(macOS)
        try await configuremacOSAudioSession()
        #endif
        
        // Update published properties
        await updateAudioSessionInfo()
        
        DispatchQueue.main.async {
            self.isConfigured = true
        }
        
        logger.info("✅ Audio session configured successfully")
    }
    
    #if os(iOS)
    private func configureiOSAudioSession() async throws {
        let session = AVAudioSession.sharedInstance()
        
        logger.info("📱 Configuring iOS AVAudioSession for professional audio")
        
        // Request microphone permission first
        let permissionGranted = await requestMicrophonePermission()
        guard permissionGranted else {
            throw AudioSessionError.microphonePermissionDenied
        }
        
        // Detect audio route and adjust configuration accordingly
        let isBluetoothRoute = detectBluetoothAudioRoute()
        let targetBufferFrames = isBluetoothRoute ? bluetoothBufferSize : targetBufferSize
        
        logger.info("🎧 Audio route detection - Bluetooth: \(isBluetoothRoute), Target buffer: \(targetBufferFrames) frames")
        
        do {
            // Configure category for simultaneous record and playback
            // PlayAndRecord allows microphone input + speaker/headphone output
            // DefaultToSpeaker ensures iPhone uses speaker instead of earpiece
            // AllowBluetooth enables Bluetooth audio devices
            // MixWithOthers allows background audio (optional)
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]
            )
            
            logger.info("✅ Audio category set to PlayAndRecord with DefaultToSpeaker")
            
            // Configure optimal sample rate (48kHz professional standard)
            try session.setPreferredSampleRate(targetSampleRate)
            logger.info("🎼 Preferred sample rate set to \(targetSampleRate) Hz")
            
            // Configure ultra-low latency buffer duration
            // Target: 64 frames at 48kHz = ~1.33ms latency (AD 480 RE level)
            let targetBufferDuration = Double(targetBufferFrames) / targetSampleRate
            try session.setPreferredIOBufferDuration(targetBufferDuration)
            logger.info("⚡ Preferred buffer duration set to \(String(format: "%.2f", targetBufferDuration * 1000))ms (\(targetBufferFrames) frames)")
            
            // Configure input settings for optimal quality
            try session.setPreferredInputNumberOfChannels(2) // Stereo input if available
            
            // Optimize for low latency processing
            if #available(iOS 14.5, *) {
                try session.setPrefersNoInterruptionsFromSystemAlerts(true)
            }
            
            // Activate the session
            try session.setActive(true)
            logger.info("🔴 AVAudioSession activated")
            
            // Verify actual configuration achieved
            let actualSampleRate = session.sampleRate
            let actualBufferDuration = session.ioBufferDuration
            let actualBufferFrames = Int(actualBufferDuration * actualSampleRate)
            let actualLatencyMs = actualBufferDuration * 1000
            
            logger.info("📊 ACTUAL iOS AUDIO CONFIGURATION:")
            logger.info("   - Sample Rate: \(actualSampleRate) Hz (target: \(targetSampleRate) Hz)")
            logger.info("   - Buffer Duration: \(String(format: "%.2f", actualBufferDuration * 1000))ms")
            logger.info("   - Buffer Size: \(actualBufferFrames) frames (target: \(targetBufferFrames) frames)")
            logger.info("   - Input Channels: \(session.inputNumberOfChannels)")
            logger.info("   - Output Channels: \(session.outputNumberOfChannels)")
            logger.info("   - Route: \(session.currentRoute.outputs.first?.portName ?? "Unknown")")
            
            // Update state
            DispatchQueue.main.async {
                self.currentSampleRate = actualSampleRate
                self.currentBufferSize = actualBufferFrames
                self.actualLatency = actualLatencyMs
                self.isBluetoothConnected = isBluetoothRoute
                self.audioRouteDescription = self.describeCurrentRoute()
            }
            
            // Validate latency achievement
            if actualBufferFrames <= 128 {
                logger.info("🎯 EXCELLENT: Achieved ultra-low latency (\(actualBufferFrames) frames)")
            } else if actualBufferFrames <= 256 {
                logger.info("✅ GOOD: Achieved low latency (\(actualBufferFrames) frames)")
            } else {
                logger.warning("⚠️ WARNING: Higher latency than ideal (\(actualBufferFrames) frames)")
            }
            
        } catch {
            logger.error("❌ iOS audio session configuration failed: \(error.localizedDescription)")
            throw AudioSessionError.configurationFailed(error.localizedDescription)
        }
    }
    
    private func requestMicrophonePermission() async -> Bool {
        return await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                self.logger.info("🎤 Microphone permission: \(granted ? "GRANTED" : "DENIED")")
                continuation.resume(returning: granted)
            }
        }
    }
    
    private func detectBluetoothAudioRoute() -> Bool {
        let session = AVAudioSession.sharedInstance()
        let currentRoute = session.currentRoute
        
        for output in currentRoute.outputs {
            switch output.portType {
            case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
                logger.info("🔵 Bluetooth audio detected: \(output.portName)")
                return true
            default:
                continue
            }
        }
        
        for input in currentRoute.inputs {
            switch input.portType {
            case .bluetoothHFP:
                logger.info("🔵 Bluetooth input detected: \(input.portName)")
                return true
            default:
                continue
            }
        }
        
        return false
    }
    
    private func describeCurrentRoute() -> String {
        let session = AVAudioSession.sharedInstance()
        let route = session.currentRoute
        
        let inputs = route.inputs.map { "\($0.portName) (\($0.portType.rawValue))" }.joined(separator: ", ")
        let outputs = route.outputs.map { "\($0.portName) (\($0.portType.rawValue))" }.joined(separator: ", ")
        
        return "In: [\(inputs)] Out: [\(outputs)]"
    }
    #endif
    
    #if os(macOS)
    private func configuremacOSAudioSession() async throws {
        logger.info("💻 Configuring macOS audio session")
        
        // Request microphone permission
        let permissionGranted = await requestmacOSMicrophonePermission()
        guard permissionGranted else {
            throw AudioSessionError.microphonePermissionDenied
        }
        
        // macOS uses default audio devices - less configuration needed
        // But we can still optimize for our use case
        
        DispatchQueue.main.async {
            self.currentSampleRate = 48000 // Default assumption
            self.currentBufferSize = 64    // Default assumption
            self.actualLatency = 1.33      // ~64 frames at 48kHz
            self.audioRouteDescription = "macOS Default Audio"
            self.isBluetoothConnected = false
        }
        
        logger.info("✅ macOS audio session ready")
    }
    
    private func requestmacOSMicrophonePermission() async -> Bool {
        return await withCheckedContinuation { continuation in
            let status = AVCaptureDevice.authorizationStatus(for: .audio)
            
            switch status {
            case .authorized:
                continuation.resume(returning: true)
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            case .denied, .restricted:
                continuation.resume(returning: false)
            @unknown default:
                continuation.resume(returning: false)
            }
        }
    }
    #endif
    
    // MARK: - Notification Observers
    private func setupNotificationObservers() {
        #if os(iOS)
        let notificationCenter = NotificationCenter.default
        
        // Audio route changes (headphones plugged/unplugged, Bluetooth connect/disconnect)
        routeChangeObserver = notificationCenter.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleRouteChange(notification)
        }
        
        // Audio interruptions (phone calls, other apps)
        interruptionObserver = notificationCenter.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleInterruption(notification)
        }
        
        // Media services lost/reset (rare but critical)
        mediaServicesLostObserver = notificationCenter.addObserver(
            forName: AVAudioSession.mediaServicesWereLostNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMediaServicesLost()
        }
        
        mediaServicesResetObserver = notificationCenter.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMediaServicesReset()
        }
        
        logger.info("🔔 iOS audio session notifications configured")
        #endif
    }
    
    #if os(iOS)
    private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        logger.info("🔄 Audio route changed: \(reason)")
        
        switch reason {
        case .newDeviceAvailable:
            logger.info("📱 New audio device available")
        case .oldDeviceUnavailable:
            logger.info("📱 Audio device removed")
        case .categoryChange:
            logger.info("📱 Audio category changed")
        case .override:
            logger.info("📱 Audio route override")
        case .wakeFromSleep:
            logger.info("📱 Wake from sleep")
        case .noSuitableRouteForCategory:
            logger.warning("⚠️ No suitable route for category")
        case .routeConfigurationChange:
            logger.info("📱 Route configuration changed")
        @unknown default:
            logger.info("📱 Unknown route change reason")
        }
        
        // Update audio session info
        Task {
            await self.updateAudioSessionInfo()
        }
        
        // Potentially reconfigure session for optimal performance
        Task {
            do {
                try await self.reconfigureForOptimalPerformance()
            } catch {
                self.logger.error("❌ Failed to reconfigure after route change: \(error.localizedDescription)")
            }
        }
    }
    
    private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            logger.info("🔴 Audio interruption began")
            // Audio processing will be automatically stopped
            
        case .ended:
            logger.info("🟢 Audio interruption ended")
            
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    logger.info("🔄 Resuming audio after interruption")
                    // Audio can be resumed - the engine will handle this
                }
            }
            
        @unknown default:
            logger.info("📱 Unknown interruption type")
        }
    }
    
    private func handleMediaServicesLost() {
        logger.error("💀 Media services lost - audio system needs reset")
        
        DispatchQueue.main.async {
            self.isConfigured = false
        }
    }
    
    private func handleMediaServicesReset() {
        logger.info("🔄 Media services reset - reconfiguring audio session")
        
        Task {
            do {
                try await self.configureAudioSession()
            } catch {
                self.logger.error("❌ Failed to reconfigure after media services reset: \(error.localizedDescription)")
            }
        }
    }
    
    private func reconfigureForOptimalPerformance() async throws {
        logger.info("🔧 Reconfiguring for optimal performance after route change")
        
        let wasBluetoothConnected = isBluetoothConnected
        let isBluetoothNowConnected = detectBluetoothAudioRoute()
        
        // If Bluetooth status changed, we might need different buffer settings
        if wasBluetoothConnected != isBluetoothNowConnected {
            logger.info("🔵 Bluetooth connection status changed: \(isBluetoothNowConnected)")
            
            let newTargetBufferFrames = isBluetoothNowConnected ? bluetoothBufferSize : targetBufferSize
            let newBufferDuration = Double(newTargetBufferFrames) / currentSampleRate
            
            do {
                try AVAudioSession.sharedInstance().setPreferredIOBufferDuration(newBufferDuration)
                logger.info("⚡ Updated buffer duration for new route: \(String(format: "%.2f", newBufferDuration * 1000))ms")
            } catch {
                logger.warning("⚠️ Could not update buffer duration: \(error.localizedDescription)")
            }
        }
        
        await updateAudioSessionInfo()
    }
    #endif
    
    private func updateAudioSessionInfo() async {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        
        DispatchQueue.main.async {
            self.currentSampleRate = session.sampleRate
            self.currentBufferSize = Int(session.ioBufferDuration * session.sampleRate)
            self.actualLatency = session.ioBufferDuration * 1000
            self.audioRouteDescription = self.describeCurrentRoute()
            self.isBluetoothConnected = self.detectBluetoothAudioRoute()
        }
        #endif
    }
    
    // MARK: - Public Interface
    func deactivateAudioSession() {
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setActive(false)
            logger.info("🔴 AVAudioSession deactivated")
        } catch {
            logger.error("❌ Failed to deactivate audio session: \(error.localizedDescription)")
        }
        #endif
        
        DispatchQueue.main.async {
            self.isConfigured = false
        }
    }
    
    func getOptimalBufferSize() -> Int {
        #if os(iOS)
        return isBluetoothConnected ? bluetoothBufferSize : targetBufferSize
        #else
        return targetBufferSize
        #endif
    }
    
    func isLowLatencyCapable() -> Bool {
        return currentBufferSize <= 128
    }
    
    func getLatencyDescription() -> String {
        let latencyMs = actualLatency
        
        if latencyMs <= 2.0 {
            return "🎯 Ultra-faible (\(String(format: "%.1f", latencyMs))ms)"
        } else if latencyMs <= 5.0 {
            return "✅ Faible (\(String(format: "%.1f", latencyMs))ms)"
        } else if latencyMs <= 10.0 {
            return "⚠️ Modérée (\(String(format: "%.1f", latencyMs))ms)"
        } else {
            return "❌ Élevée (\(String(format: "%.1f", latencyMs))ms)"
        }
    }
    
    // MARK: - Diagnostics
    func printDiagnostics() {
        logger.info("🔍 === CROSS-PLATFORM AUDIO SESSION DIAGNOSTICS ===")
        logger.info("Platform: \(getCurrentPlatform())")
        logger.info("Configured: \(isConfigured)")
        logger.info("Sample Rate: \(currentSampleRate) Hz")
        logger.info("Buffer Size: \(currentBufferSize) frames")
        logger.info("Latency: \(String(format: "%.2f", actualLatency))ms")
        logger.info("Route: \(audioRouteDescription)")
        logger.info("Bluetooth: \(isBluetoothConnected)")
        logger.info("Low Latency Capable: \(isLowLatencyCapable())")
        logger.info("Optimal Buffer Size: \(getOptimalBufferSize()) frames")
        logger.info("=== END DIAGNOSTICS ===")
    }
    
    private func getCurrentPlatform() -> String {
        #if os(iOS)
        return "iOS \(UIDevice.current.systemVersion)"
        #elseif os(macOS)
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        #else
        return "Unknown"
        #endif
    }
    
    // MARK: - Error Types
    enum AudioSessionError: LocalizedError {
        case microphonePermissionDenied
        case configurationFailed(String)
        case unsupportedPlatform
        
        var errorDescription: String? {
            switch self {
            case .microphonePermissionDenied:
                return "Permission d'accès au microphone refusée"
            case .configurationFailed(let message):
                return "Échec de configuration audio: \(message)"
            case .unsupportedPlatform:
                return "Plateforme non supportée"
            }
        }
    }
    
    deinit {
        #if os(iOS)
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = mediaServicesLostObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = mediaServicesResetObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        #endif
        
        logger.info("🗑️ CrossPlatformAudioSession deinitialized")
    }
}