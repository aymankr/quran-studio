import SwiftUI
import AVFoundation
import UserNotifications

/// iOS onboarding flow with permission requests and audio session setup
@available(iOS 14.0, *)
struct iOSOnboardingView: View {
    @ObservedObject var permissionManager: iOSPermissionManager
    @ObservedObject var audioSession: CrossPlatformAudioSession
    let onComplete: () -> Void
    
    @State private var currentStep: OnboardingStep = .welcome
    @State private var isRequestingPermissions = false
    @State private var permissionError: String?
    @State private var audioTestInProgress = false
    
    enum OnboardingStep: Int, CaseIterable {
        case welcome = 0
        case permissions = 1
        case audioSetup = 2
        case audioTest = 3
        case complete = 4
        
        var title: String {
            switch self {
            case .welcome: return "Bienvenue dans Reverb"
            case .permissions: return "Permissions"
            case .audioSetup: return "Configuration Audio"
            case .audioTest: return "Test Audio"
            case .complete: return "Prêt à utiliser"
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Progress indicator
                progressIndicator
                
                // Main content
                TabView(selection: $currentStep) {
                    welcomeStep
                        .tag(OnboardingStep.welcome)
                    
                    permissionsStep
                        .tag(OnboardingStep.permissions)
                    
                    audioSetupStep
                        .tag(OnboardingStep.audioSetup)
                    
                    audioTestStep
                        .tag(OnboardingStep.audioTest)
                    
                    completeStep
                        .tag(OnboardingStep.complete)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: currentStep)
                
                // Navigation buttons
                navigationButtons
            }
            .background(Color(.systemBackground))
            .navigationTitle(currentStep.title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(currentStep == .welcome)
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear {
            permissionManager.checkPermissions()
        }
        .alert("Erreur de permissions", isPresented: .constant(permissionError != nil)) {
            Button("OK") {
                permissionError = nil
            }
            Button("Paramètres") {
                openiOSSettings()
            }
        } message: {
            if let error = permissionError {
                Text(error)
            }
        }
    }
    
    // MARK: - Progress Indicator
    private var progressIndicator: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingStep.allCases, id: \.self) { step in
                Circle()
                    .fill(step.rawValue <= currentStep.rawValue ? Color.blue : Color.gray.opacity(0.3))
                    .frame(width: 8, height: 8)
                    .scaleEffect(step == currentStep ? 1.2 : 1.0)
                    .animation(.spring(response: 0.3), value: currentStep)
            }
        }
        .padding(.vertical, 16)
    }
    
    // MARK: - Welcome Step
    private var welcomeStep: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // App icon and title
            VStack(spacing: 16) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                
                Text("Reverb")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Traitement audio professionnel en temps réel")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Features list
            VStack(alignment: .leading, spacing: 16) {
                featureRow(
                    icon: "waveform",
                    title: "Reverb Temps Réel",
                    description: "Traitement audio sans latence"
                )
                
                featureRow(
                    icon: "slider.horizontal.2.rectangle",
                    title: "Enregistrement Wet/Dry",
                    description: "Capture séparée des signaux"
                )
                
                featureRow(
                    icon: "bolt",
                    title: "Traitement Offline",
                    description: "Plus rapide que temps réel"
                )
                
                featureRow(
                    icon: "list.number",
                    title: "Traitement Batch",
                    description: "Multiples fichiers en série"
                )
            }
            
            Spacer()
        }
        .padding(.horizontal, 24)
    }
    
    @ViewBuilder
    private func featureRow(icon: String, title: String, description: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Permissions Step
    private var permissionsStep: some View {
        VStack(spacing: 32) {
            Spacer()
            
            VStack(spacing: 16) {
                Image(systemName: "mic.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                
                Text("Permissions Requises")
                    .font(.title)
                    .fontWeight(.semibold)
                
                Text("Reverb a besoin d'accéder au microphone pour le traitement audio en temps réel.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Permission status
            VStack(spacing: 16) {
                permissionStatusRow(
                    icon: "mic.fill",
                    title: "Microphone",
                    status: permissionManager.microphonePermission,
                    description: "Requis pour l'enregistrement et le traitement"
                )
                
                permissionStatusRow(
                    icon: "bell.fill",
                    title: "Notifications",
                    status: permissionManager.notificationPermission,
                    description: "Optionnel - pour les alertes de traitement"
                )
            }
            
            Spacer()
            
            // Request permissions button
            if permissionManager.microphonePermission != .granted {
                Button(action: {
                    requestPermissions()
                }) {
                    HStack {
                        if isRequestingPermissions {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.white)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                        }
                        
                        Text("Autoriser les Permissions")
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .cornerRadius(12)
                }
                .disabled(isRequestingPermissions)
            }
        }
        .padding(.horizontal, 24)
    }
    
    @ViewBuilder
    private func permissionStatusRow(
        icon: String,
        title: String,
        status: iOSPermissionManager.PermissionStatus,
        description: String
    ) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Circle()
                            .fill(status.color)
                            .frame(width: 8, height: 8)
                        
                        Text(status.description)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(status.color)
                    }
                }
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
    
    // MARK: - Audio Setup Step
    private var audioSetupStep: some View {
        VStack(spacing: 32) {
            Spacer()
            
            VStack(spacing: 16) {
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                
                Text("Configuration Audio")
                    .font(.title)
                    .fontWeight(.semibold)
                
                Text("Configuration de l'audio session pour des performances optimales avec une latence ultra-faible.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Audio session info
            VStack(spacing: 16) {
                audioSessionInfoRow(
                    title: "Fréquence d'échantillonnage",
                    value: "\(Int(audioSession.currentSampleRate)) Hz",
                    target: "48000 Hz",
                    isOptimal: abs(audioSession.currentSampleRate - 48000) < 100
                )
                
                audioSessionInfoRow(
                    title: "Taille du buffer",
                    value: "\(audioSession.currentBufferSize) frames",
                    target: "64 frames",
                    isOptimal: audioSession.currentBufferSize <= 128
                )
                
                audioSessionInfoRow(
                    title: "Latence estimée",
                    value: String(format: "%.1f ms", audioSession.actualLatency),
                    target: "< 3 ms",
                    isOptimal: audioSession.actualLatency < 3.0
                )
            }
            
            Spacer()
            
            // Configure button
            if !audioSession.isConfigured {
                Button(action: {
                    configureAudioSession()
                }) {
                    HStack {
                        Image(systemName: "gear.circle.fill")
                        Text("Configurer l'Audio Session")
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .cornerRadius(12)
                }
            }
        }
        .padding(.horizontal, 24)
    }
    
    @ViewBuilder
    private func audioSessionInfoRow(
        title: String,
        value: String,
        target: String,
        isOptimal: Bool
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.medium)
                
                Text("Cible: \(target)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: isOptimal ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(isOptimal ? .green : .orange)
                    
                    Text(value)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(isOptimal ? .green : .orange)
                        .monospacedDigit()
                }
            }
        }
        .padding(16)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
    
    // MARK: - Audio Test Step
    private var audioTestStep: some View {
        VStack(spacing: 32) {
            Spacer()
            
            VStack(spacing: 16) {
                Image(systemName: audioTestInProgress ? "waveform" : "play.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                    .symbolEffect(.pulse, isActive: audioTestInProgress)
                
                Text("Test Audio")
                    .font(.title)
                    .fontWeight(.semibold)
                
                Text(audioTestInProgress ? 
                     "Test en cours... Parlez dans le microphone pour vérifier le fonctionnement." :
                     "Testez la configuration audio pour vous assurer que tout fonctionne correctement."
                )
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Test controls
            VStack(spacing: 20) {
                Button(action: {
                    toggleAudioTest()
                }) {
                    HStack {
                        Image(systemName: audioTestInProgress ? "stop.circle.fill" : "play.circle.fill")
                        Text(audioTestInProgress ? "Arrêter le Test" : "Démarrer le Test")
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    .background(audioTestInProgress ? Color.red : Color.blue)
                    .cornerRadius(12)
                }
                
                if audioSession.isConfigured {
                    Text("✅ Configuration audio validée")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 24)
    }
    
    // MARK: - Complete Step
    private var completeStep: some View {
        VStack(spacing: 32) {
            Spacer()
            
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.green)
                
                Text("Tout est Prêt!")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Reverb est configuré et prêt à utiliser. Vous pouvez maintenant profiter du traitement audio professionnel.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Summary
            VStack(spacing: 12) {
                summaryRow(title: "Microphone", status: "Configuré", isValid: true)
                summaryRow(title: "Audio Session", status: "Optimisée", isValid: audioSession.isConfigured)
                summaryRow(title: "Latence", status: audioSession.getLatencyDescription(), isValid: audioSession.isLowLatencyCapable())
            }
            
            Spacer()
            
            Button(action: {
                onComplete()
            }) {
                HStack {
                    Image(systemName: "arrow.right.circle.fill")
                    Text("Commencer à Utiliser Reverb")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(Color.blue)
                .cornerRadius(12)
            }
        }
        .padding(.horizontal, 24)
    }
    
    @ViewBuilder
    private func summaryRow(title: String, status: String, isValid: Bool) -> some View {
        HStack {
            Image(systemName: isValid ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundColor(isValid ? .green : .orange)
            
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
            
            Spacer()
            
            Text(status)
                .font(.subheadline)
                .foregroundColor(isValid ? .green : .orange)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .cornerRadius(6)
    }
    
    // MARK: - Navigation Buttons
    private var navigationButtons: some View {
        HStack(spacing: 16) {
            if currentStep != .welcome {
                Button("Précédent") {
                    withAnimation {
                        if let previousStep = OnboardingStep(rawValue: currentStep.rawValue - 1) {
                            currentStep = previousStep
                        }
                    }
                }
                .font(.subheadline)
                .foregroundColor(.blue)
            }
            
            Spacer()
            
            if currentStep != .complete {
                Button(currentStep == .welcome ? "Commencer" : "Suivant") {
                    withAnimation {
                        if let nextStep = OnboardingStep(rawValue: currentStep.rawValue + 1) {
                            currentStep = nextStep
                        }
                    }
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(Color.blue)
                .cornerRadius(8)
                .disabled(!canProceedToNextStep())
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
    }
    
    // MARK: - Helper Methods
    private func canProceedToNextStep() -> Bool {
        switch currentStep {
        case .welcome:
            return true
        case .permissions:
            return permissionManager.microphonePermission == .granted
        case .audioSetup:
            return audioSession.isConfigured
        case .audioTest:
            return true
        case .complete:
            return true
        }
    }
    
    private func requestPermissions() {
        isRequestingPermissions = true
        
        Task {
            let micGranted = await permissionManager.requestMicrophonePermission()
            
            DispatchQueue.main.async {
                self.isRequestingPermissions = false
                
                if !micGranted {
                    self.permissionError = "L'accès au microphone est requis pour utiliser Reverb."
                }
            }
        }
    }
    
    private func configureAudioSession() {
        Task {
            do {
                try await audioSession.configureAudioSession()
            } catch {
                DispatchQueue.main.async {
                    self.permissionError = error.localizedDescription
                }
            }
        }
    }
    
    private func toggleAudioTest() {
        audioTestInProgress.toggle()
        
        if audioTestInProgress {
            // Start audio test
            // This would typically start the audio engine for testing
        } else {
            // Stop audio test
        }
        
        // Provide haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }
    
    private func openiOSSettings() {
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
    }
}

#if DEBUG
#Preview {
    iOSOnboardingView(
        permissionManager: iOSPermissionManager(),
        audioSession: CrossPlatformAudioSession()
    ) {
        print("Onboarding complete")
    }
    .preferredColorScheme(.dark)
}
#endif