import SwiftUI
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

/// iOS-optimized main interface for Reverb application
/// Adapts the desktop interface for touch interactions and mobile constraints
@available(iOS 15.0, *)
struct iOSMainView: View {
    @StateObject private var audioManager = AudioManagerCPP.shared
    @StateObject private var audioSession = CrossPlatformAudioSession()
    @StateObject private var permissionManager = iOSPermissionManager()
    
    // Navigation state
    @State private var selectedTab: MainTab = .realtime
    @State private var showingSettings = false
    @State private var showingSessionInfo = false
    @State private var showingOnboarding = false
    
    // Audio session state
    @State private var sessionConfigured = false
    @State private var audioSessionError: String?
    
    enum MainTab: String, CaseIterable {
        case realtime = "realtime"
        case wetDry = "wetdry"
        case offline = "offline"
        case batch = "batch"
        
        var title: String {
            switch self {
            case .realtime: return "Temps Réel"
            case .wetDry: return "Wet/Dry"
            case .offline: return "Offline"
            case .batch: return "Batch"
            }
        }
        
        var icon: String {
            switch self {
            case .realtime: return "waveform"
            case .wetDry: return "slider.horizontal.2.rectangle"
            case .offline: return "bolt"
            case .batch: return "list.number"
            }
        }
    }
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // Status bar with session info
                    sessionStatusBar
                    
                    // Main content
                    TabView(selection: $selectedTab) {
                        // Real-time processing
                        iOSRealtimeView(audioManager: audioManager)
                            .tabItem {
                                Image(systemName: MainTab.realtime.icon)
                                Text(MainTab.realtime.title)
                            }
                            .tag(MainTab.realtime)
                        
                        // Wet/Dry recording
                        iOSWetDryView(audioManager: audioManager)
                            .tabItem {
                                Image(systemName: MainTab.wetDry.icon)
                                Text(MainTab.wetDry.title)
                            }
                            .tag(MainTab.wetDry)
                        
                        // Offline processing
                        iOSOfflineView(audioManager: audioManager)
                            .tabItem {
                                Image(systemName: MainTab.offline.icon)
                                Text(MainTab.offline.title)
                            }
                            .tag(MainTab.offline)
                        
                        // Batch processing
                        iOSBatchView(audioManager: audioManager)  
                            .tabItem {
                                Image(systemName: MainTab.batch.icon)
                                Text(MainTab.batch.title)
                            }
                            .tag(MainTab.batch)
                    }
                    .accentColor(.blue)
                }
            }
            .navigationTitle("Reverb")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(false)
            .navigationBarItems(
                leading: Button(action: {
                    showingSessionInfo = true
                }) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(audioSession.isConfigured ? .green : .red)
                            .frame(width: 8, height: 8)
                        
                        Text(audioSession.getLatencyDescription())
                            .font(.caption2)
                            .foregroundColor(.primary)
                    }
                },
                trailing: Button(action: {
                    showingSettings = true
                }) {
                    Image(systemName: "gear")
                }
            )
        }
        .navigationViewStyle(StackNavigationViewStyle()) // Force single view on iPhone
        .sheet(isPresented: $showingSettings) {
            // TODO: Add iOSSettingsView to Xcode project
            Text("Settings - Coming Soon")
                .padding()
        }
        .sheet(isPresented: $showingSessionInfo) {
            // iOSAudioSessionInfoView(audioSession: audioSession) // TODO: Add to Xcode project
            Text("Audio Session Info - Coming Soon")
                .padding()
        }
        .sheet(isPresented: $showingOnboarding) {
            iOSOnboardingView(
                permissionManager: permissionManager,
                audioSession: audioSession
            ) {
                showingOnboarding = false
                Task {
                    await configureAudioSession()
                }
            }
        }
        .onAppear {
            setupiOSApp()
        }
        .alert("Erreur Audio Session", isPresented: .constant(audioSessionError != nil)) {
            Button("OK") {
                audioSessionError = nil
            }
            Button("Paramètres") {
                openiOSSettings()
            }
        } message: {
            if let error = audioSessionError {
                Text(error)
            }
        }
    }
    
    // MARK: - Session Status Bar
    private var sessionStatusBar: some View {
        HStack(spacing: 12) {
            // Connection status
            HStack(spacing: 4) {
                Circle()
                    .fill(audioSession.isConfigured ? .green : .red)
                    .frame(width: 6, height: 6)
                
                Text(audioSession.isConfigured ? "Connecté" : "Déconnecté")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Sample rate and buffer info
            if audioSession.isConfigured {
                HStack(spacing: 8) {
                    Text("\(Int(audioSession.currentSampleRate/1000))kHz")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                    
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.5))
                    
                    Text("\(audioSession.currentBufferSize)f")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                    
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.5))
                    
                    Text(audioSession.getLatencyDescription())
                        .font(.caption2)
                        .foregroundColor(audioSession.isLowLatencyCapable() ? .green : .orange)
                }
            }
            
            // Bluetooth indicator
            if audioSession.isBluetoothConnected {
                Image(systemName: "bluetooth")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(.systemGray6))
        .onTapGesture {
            showingSessionInfo = true
        }
    }
    
    // MARK: - Setup Methods
    private func setupiOSApp() {
        // Check if this is first launch
        let hasLaunchedBefore = UserDefaults.standard.bool(forKey: "HasLaunchedBefore")
        
        if !hasLaunchedBefore {
            showingOnboarding = true
            UserDefaults.standard.set(true, forKey: "HasLaunchedBefore")
        } else {
            Task {
                await configureAudioSession()
            }
        }
        
        // Configure audio session notifications
        setupAudioSessionNotifications()
    }
    
    private func configureAudioSession() async {
        do {
            try await audioSession.configureAudioSession()
            sessionConfigured = true
            
            // Print diagnostics for development
            audioSession.printDiagnostics()
            
        } catch {
            audioSessionError = error.localizedDescription
            sessionConfigured = false
        }
    }
    
    private func setupAudioSessionNotifications() {
        // Additional iOS-specific audio session monitoring
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task {
                await configureAudioSession()
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            // Optionally deactivate audio session when app goes to background
            // audioSession.deactivateAudioSession()
        }
    }
    
    private func openiOSSettings() {
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
    }
}

// MARK: - iOS Permission Manager
class iOSPermissionManager: ObservableObject {
    @Published var microphonePermission: PermissionStatus = .notDetermined
    @Published var notificationPermission: PermissionStatus = .notDetermined
    
    enum PermissionStatus {
        case notDetermined
        case granted
        case denied
        case restricted
        
        var description: String {
            switch self {
            case .notDetermined: return "Non déterminé"
            case .granted: return "Accordé"
            case .denied: return "Refusé"
            case .restricted: return "Restreint"
            }
        }
        
        var color: Color {
            switch self {
            case .granted: return .green
            case .denied, .restricted: return .red
            case .notDetermined: return .orange
            }
        }
    }
    
    func checkPermissions() {
        checkMicrophonePermission()
        checkNotificationPermission()
    }
    
    func requestMicrophonePermission() async -> Bool {
        return await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async {
                    self.microphonePermission = granted ? .granted : .denied
                }
                continuation.resume(returning: granted)
            }
        }
    }
    
    private func checkMicrophonePermission() {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            microphonePermission = .granted
        case .denied:
            microphonePermission = .denied
        case .undetermined:
            microphonePermission = .notDetermined
        @unknown default:
            microphonePermission = .notDetermined
        }
    }
    
    private func checkNotificationPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .authorized, .provisional:
                    self.notificationPermission = .granted
                case .denied:
                    self.notificationPermission = .denied
                case .notDetermined:
                    self.notificationPermission = .notDetermined
                @unknown default:
                    self.notificationPermission = .notDetermined
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    iOSMainView()
        .preferredColorScheme(.dark)
}
#endif