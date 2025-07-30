import SwiftUI
import AVFoundation

struct ContentView: View {
    @EnvironmentObject private var audioManager: SwiftAudioManager
    
    // États locaux
    @State private var isMonitoring = false
    @State private var masterVolume: Float = 1.5
    @State private var micGain: Float = 1.2
    @State private var isMuted = false
    @State private var selectedReverbPreset: ReverbPreset = .vocalBooth
    
    // Couleurs du thème
    private let backgroundColor = Color(red: 0.08, green: 0.08, blue: 0.13)
    private let cardColor = Color(red: 0.12, green: 0.12, blue: 0.18)
    private let accentColor = Color(red: 0.3, green: 0.7, blue: 1.0)
    
    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Header
                headerView
                
                // Audio Level Display
                audioLevelView
                
                // Preset Selection
                presetSelectionView
                
                // Volume Controls
                volumeControlsView
                
                // Monitor Control
                monitorControlView
                
                // Performance Info
                performanceInfoView
                
                Spacer()
            }
            .padding()
        }
        .onAppear {
            setupInitialState()
        }
    }
    
    // MARK: - Views
    
    private var headerView: some View {
        VStack {
            Text("VoiceMonitor Pro v2.0")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text("Architecture C++ Professionnelle")
                .font(.subheadline)
                .foregroundColor(.gray)
        }
    }
    
    private var audioLevelView: some View {
        VStack {
            Text("Niveau Audio")
                .font(.headline)
                .foregroundColor(.white)
            
            // Audio level meter
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 20)
                    
                    Rectangle()
                        .fill(LinearGradient(
                            gradient: Gradient(colors: [.green, .yellow, .red]),
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: geometry.size.width * CGFloat(audioManager.currentAudioLevel), height: 20)
                        .animation(.easeInOut(duration: 0.1), value: audioManager.currentAudioLevel)
                }
                .cornerRadius(10)
            }
            .frame(height: 20)
            
            Text(String(format: "%.2f", audioManager.currentAudioLevel))
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding()
        .background(cardColor)
        .cornerRadius(15)
    }
    
    private var presetSelectionView: some View {
        VStack {
            Text("Préréglages de Réverbération")
                .font(.headline)
                .foregroundColor(.white)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 10) {
                ForEach(ReverbPreset.allCases, id: \.self) { preset in
                    Button(action: {
                        selectedReverbPreset = preset
                        audioManager.updateReverbPreset(preset: preset)
                    }) {
                        VStack {
                            Text(preset.rawValue)
                                .font(.headline)
                                .foregroundColor(selectedReverbPreset == preset ? backgroundColor : .white)
                            
                            Text(preset.description)
                                .font(.caption)
                                .foregroundColor(selectedReverbPreset == preset ? backgroundColor : .gray)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, minHeight: 80)
                        .background(selectedReverbPreset == preset ? accentColor : cardColor)
                        .cornerRadius(12)
                    }
                }
            }
        }
        .padding()
        .background(cardColor)
        .cornerRadius(15)
    }
    
    private var volumeControlsView: some View {
        VStack {
            Text("Contrôles de Volume")
                .font(.headline)
                .foregroundColor(.white)
            
            // Microphone Gain
            VStack {
                HStack {
                    Text("Gain Micro")
                        .foregroundColor(.white)
                    Spacer()
                    Text(String(format: "%.1fx", micGain))
                        .foregroundColor(.gray)
                }
                
                Slider(value: $micGain, in: 0.1...3.0, step: 0.1) { _ in
                    audioManager.setInputVolume(micGain)
                }
                .accentColor(accentColor)
            }
            
            Divider()
                .background(Color.gray)
            
            // Master Volume
            VStack {
                HStack {
                    Text("Volume Maître")
                        .foregroundColor(.white)
                    Spacer()
                    Text(String(format: "%.1fx", masterVolume))
                        .foregroundColor(.gray)
                }
                
                HStack {
                    Slider(value: $masterVolume, in: 0.0...2.5, step: 0.1) { _ in
                        audioManager.setOutputVolume(masterVolume, isMuted: isMuted)
                    }
                    .accentColor(accentColor)
                    
                    Button(action: {
                        isMuted.toggle()
                        audioManager.setOutputVolume(masterVolume, isMuted: isMuted)
                    }) {
                        Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.2.fill")
                            .font(.title2)
                            .foregroundColor(isMuted ? .red : accentColor)
                    }
                }
            }
        }
        .padding()
        .background(cardColor)
        .cornerRadius(15)
    }
    
    private var monitorControlView: some View {
        VStack {
            Button(action: {
                isMonitoring.toggle()
                audioManager.setMonitoring(enabled: isMonitoring)
            }) {
                HStack {
                    Image(systemName: isMonitoring ? "stop.circle.fill" : "play.circle.fill")
                        .font(.title)
                    
                    Text(isMonitoring ? "Arrêter le Monitoring" : "Démarrer le Monitoring")
                        .font(.headline)
                }
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(isMonitoring ? Color.red : accentColor)
                .cornerRadius(12)
            }
            .disabled(!audioManager.isInitialized())
            
            if !audioManager.isInitialized() {
                Text("Initialisation du moteur audio C++...")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }
    
    private var performanceInfoView: some View {
        VStack {
            Text("Performance")
                .font(.headline)
                .foregroundColor(.white)
            
            HStack {
                VStack {
                    Text("CPU")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text(String(format: "%.1f%%", audioManager.getCpuUsage()))
                        .font(.headline)
                        .foregroundColor(audioManager.getCpuUsage() > 50 ? .red : .green)
                }
                
                Spacer()
                
                VStack {
                    Text("Engine")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text(audioManager.isEngineRunning() ? "✅" : "❌")
                        .font(.headline)
                }
                
                Spacer()
                
                VStack {
                    Text("Preset")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text(selectedReverbPreset.rawValue)
                        .font(.caption)
                        .foregroundColor(.white)
                }
            }
            
            Button("Diagnostics") {
                audioManager.printDiagnostics()
            }
            .font(.caption)
            .foregroundColor(accentColor)
        }
        .padding()
        .background(cardColor)
        .cornerRadius(15)
    }
    
    // MARK: - Setup
    
    private func setupInitialState() {
        selectedReverbPreset = audioManager.selectedReverbPreset
        isMonitoring = audioManager.isMonitoring
        micGain = audioManager.getInputVolume()
        
        // Sync with audio manager
        audioManager.updateReverbPreset(preset: selectedReverbPreset)
        audioManager.setInputVolume(micGain)
        audioManager.setOutputVolume(masterVolume, isMuted: isMuted)
    }
}

// MARK: - Preview

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(SwiftAudioManager.shared)
    }
}