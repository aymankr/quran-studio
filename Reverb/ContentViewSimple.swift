import SwiftUI
import AVFoundation

struct ContentViewSimple: View {
    @StateObject private var audioManager = AudioManagerCPP.shared
    
    // Local state for UI
    @State private var masterVolume: Float = 1.4
    @State private var micGain: Float = 1.0
    @State private var isMuted = false
    @State private var showingCustomReverbView = false
    
    // Theme colors
    private let backgroundColor = Color(red: 0.08, green: 0.08, blue: 0.13)
    private let cardColor = Color(red: 0.12, green: 0.12, blue: 0.18)
    private let accentColor = Color.blue
    
    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()
            
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 16) {
                    headerSection
                    engineInfoSection
                    audioLevelSection
                    volumeControlsSection
                    monitoringSection
                    reverbPresetsSection
                    
                    if audioManager.isMonitoring {
                        recordingSection
                    }
                    
                    performanceSection
                    
                    Color.clear.frame(height: 20)
                }
                .padding(.horizontal, 16)
                .padding(.top, 5)
            }
        }
        .onAppear {
            setupAudio()
        }
        .sheet(isPresented: $showingCustomReverbView) {
            // CORRECTION : Passer AudioManager.shared au lieu de audioManager
            CustomReverbView(audioManager: AudioManagerCPP.shared)
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 4) {
            HStack {
                Text("🎛️ Reverb Pro")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("v2.0")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                    
                    Text("Ready")
                        .font(.caption2)
                        .foregroundColor(.green)
                        .fontWeight(.bold)
                }
            }
            
            Text("Enhanced Audio Engine")
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Engine Info Section
    
    private var engineInfoSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("🚀 Engine Status")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                Spacer()
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Backend")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                    Text(audioManager.engineInfo)
                        .font(.caption2)
                        .foregroundColor(audioManager.engineInfo.contains("C++") ? .green : .purple)
                        .fontWeight(.medium)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Quality")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                    Text(audioManager.engineInfo.contains("C++") ? "Professional" : "Standard")
                        .font(.caption2)
                        .foregroundColor(audioManager.engineInfo.contains("C++") ? .green : .blue)
                        .fontWeight(.bold)
                }
            }
        }
        .padding(12)
        .background(cardColor.opacity(0.6))
        .cornerRadius(10)
    }
    
    // MARK: - Audio Level Section
    
    private var audioLevelSection: some View {
        VStack(spacing: 6) {
            Text("Audio Level")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white)
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 12)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(
                            gradient: Gradient(colors: [.green, .yellow, .red]),
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: geometry.size.width * CGFloat(audioManager.currentAudioLevel), height: 12)
                        .animation(.easeInOut(duration: 0.1), value: audioManager.currentAudioLevel)
                }
            }
            .frame(height: 12)
            
            Text("\(Int(audioManager.currentAudioLevel * 100))%")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.8))
                .monospacedDigit()
        }
        .padding(12)
        .background(cardColor)
        .cornerRadius(10)
    }
    
    // MARK: - Volume Controls Section
    
    private var volumeControlsSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("🎵 Audio Controls")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                Spacer()
            }
            
            // Microphone Gain
            VStack(spacing: 6) {
                HStack {
                    Image(systemName: "mic.fill")
                        .foregroundColor(.green)
                    Text("Microphone Gain")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                    Spacer()
                    Text("\(Int(micGain * 100))%")
                        .foregroundColor(.green)
                        .font(.caption)
                        .monospacedDigit()
                }
                
                Slider(value: $micGain, in: 0.2...3.0, step: 0.1)
                    .accentColor(.green)
                    .onChange(of: micGain) { newValue in
                        audioManager.setInputVolume(newValue)
                    }
            }
            .padding(10)
            .background(cardColor.opacity(0.7))
            .cornerRadius(8)
            
            // Output Volume
            VStack(spacing: 6) {
                HStack {
                    Image(systemName: isMuted ? "speaker.slash" : "speaker.wave.3")
                        .foregroundColor(isMuted ? .red : accentColor)
                    Text("Output Volume")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                    Spacer()
                    
                    Button(action: {
                        isMuted.toggle()
                        audioManager.setOutputVolume(masterVolume, isMuted: isMuted)
                    }) {
                        Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.3.fill")
                            .foregroundColor(isMuted ? .red : accentColor)
                            .font(.body)
                    }
                }
                
                if !isMuted {
                    Slider(value: $masterVolume, in: 0...2.5, step: 0.05)
                        .accentColor(accentColor)
                        .onChange(of: masterVolume) { newValue in
                            audioManager.setOutputVolume(newValue, isMuted: isMuted)
                        }
                    
                    Text("\(Int(masterVolume * 100))%")
                        .foregroundColor(accentColor)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                } else {
                    Text("🔇 MUTED")
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(4)
                }
            }
            .padding(10)
            .background(cardColor)
            .cornerRadius(8)
            .opacity(isMuted ? 0.7 : 1.0)
        }
    }
    
    // MARK: - Monitoring Section
    
    private var monitoringSection: some View {
        VStack(spacing: 8) {
            Button(action: {
                toggleMonitoring()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: audioManager.isMonitoring ? "stop.circle.fill" : "play.circle.fill")
                        .font(.title2)
                    Text(audioManager.isMonitoring ? "🔴 Stop Monitoring" : "▶️ Start Monitoring")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(audioManager.isMonitoring ? Color.red : accentColor)
                .cornerRadius(10)
            }
            
            if audioManager.isMonitoring {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                        .scaleEffect(1.0)
                        .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: audioManager.isMonitoring)
                    
                    Text("\(audioManager.currentBackend) monitoring active")
                        .font(.caption2)
                        .foregroundColor(.green)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 4)
            }
        }
    }
    
    // MARK: - Reverb Presets Section
    
    private var reverbPresetsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("🎛️ Reverb Modes")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(ReverbPreset.allCases, id: \.id) { preset in
                    Button(action: {
                        if audioManager.isMonitoring || preset == .custom {
                            audioManager.updateReverbPreset(preset)
                            
                            if preset == .custom {
                                showingCustomReverbView = true
                            }
                        }
                    }) {
                        VStack(spacing: 4) {
                            Text(getPresetEmoji(preset))
                                .font(.title2)
                            
                            Text(getPresetName(preset))
                                .font(.caption)
                                .fontWeight(.medium)
                                .multilineTextAlignment(.center)
                        }
                        .foregroundColor(audioManager.selectedReverbPreset == preset ? .white : .white.opacity(0.7))
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .background(
                            audioManager.selectedReverbPreset == preset ?
                            accentColor : cardColor.opacity(0.8)
                        )
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(audioManager.selectedReverbPreset == preset ? .white.opacity(0.3) : .clear, lineWidth: 1)
                        )
                        .scaleEffect(audioManager.selectedReverbPreset == preset ? 1.05 : 1.0)
                        .animation(.easeInOut(duration: 0.15), value: audioManager.selectedReverbPreset == preset)
                    }
                    .disabled(!audioManager.isMonitoring && preset != .custom)
                    .opacity((audioManager.isMonitoring || preset == .custom) ? 1.0 : 0.5)
                }
            }
            
            if audioManager.isMonitoring {
                HStack {
                    Text("Active: \(audioManager.selectedReverbPreset.rawValue)")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.8))
                    
                    Spacer()
                    
                    Text(audioManager.currentPresetDescription)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(8)
                .background(cardColor.opacity(0.5))
                .cornerRadius(6)
            }
        }
    }
    
    // MARK: - Recording Section
    
    private var recordingSection: some View {
        VStack(spacing: 10) {
            Text("🎙️ Recording")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            Button(action: {
                audioManager.toggleRecording()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: audioManager.isRecording ? "stop.circle.fill" : "record.circle")
                        .font(.title3)
                    Text(audioManager.isRecording ? "🔴 Stop Recording" : "⏺️ Start Recording")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .foregroundColor(.white)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(audioManager.isRecording ? Color.red : Color.orange)
                .cornerRadius(8)
            }
            
            if audioManager.isRecording {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 6, height: 6)
                        .scaleEffect(1.0)
                        .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: audioManager.isRecording)
                    
                    Text("🔴 Recording with \(audioManager.selectedReverbPreset.rawValue) preset...")
                        .font(.caption)
                        .foregroundColor(.red)
                        .fontWeight(.medium)
                }
            } else if let filename = audioManager.lastRecordingFilename {
                Text("✅ Last: \(filename)")
                    .font(.caption2)
                    .foregroundColor(.green)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(12)
        .background(cardColor.opacity(0.8))
        .cornerRadius(10)
    }
    
    // MARK: - Performance Section
    
    private var performanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("⚡ Performance & Diagnostics")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CPU Usage")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                    Text("\(String(format: "%.1f", audioManager.cpuUsage))%")
                        .font(.caption2)
                        .foregroundColor(.green)
                        .monospacedDigit()
                }
                
                Spacer()
                
                VStack(alignment: .center, spacing: 4) {
                    Text("Backend")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                    Text(audioManager.currentBackend.contains("C++") ? "C++" : "Swift")
                        .font(.caption2)
                        .foregroundColor(audioManager.currentBackend.contains("C++") ? .green : .purple)
                        .fontWeight(.bold)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Status")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                    Text("Ready")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }
            
            Button("Run Diagnostics") {
                audioManager.diagnostic()
            }
            .font(.caption)
            .foregroundColor(accentColor)
            .frame(maxWidth: .infinity)
            .padding(8)
            .background(cardColor)
            .cornerRadius(6)
        }
        .padding(12)
        .background(cardColor.opacity(0.6))
        .cornerRadius(10)
    }
    
    // MARK: - Helper Functions
    
    private func setupAudio() {
        audioManager.setInputVolume(micGain)
        audioManager.setOutputVolume(masterVolume, isMuted: isMuted)
    }
    
    private func toggleMonitoring() {
        if audioManager.isMonitoring {
            audioManager.stopMonitoring()
        } else {
            audioManager.startMonitoring()
        }
    }
    
    private func getPresetEmoji(_ preset: ReverbPreset) -> String {
        switch preset {
        case .clean: return "🎤"
        case .vocalBooth: return "🎙️"
        case .studio: return "🎧"
        case .cathedral: return "⛪"
        case .custom: return "🎛️"
        }
    }
    
    private func getPresetName(_ preset: ReverbPreset) -> String {
        switch preset {
        case .clean: return "Clean"
        case .vocalBooth: return "Vocal\nBooth"
        case .studio: return "Studio"
        case .cathedral: return "Cathedral"
        case .custom: return "Custom"
        }
    }
}

#Preview {
    ContentViewSimple()
}
