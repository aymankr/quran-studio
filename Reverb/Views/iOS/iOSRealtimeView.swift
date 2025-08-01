import SwiftUI
import AVFoundation

/// iOS-optimized real-time reverb interface with touch-friendly controls
@available(iOS 14.0, *)
struct iOSRealtimeView: View {
    @ObservedObject var audioManager: AudioManagerCPP
    
    // UI State
    @State private var showingPresetSelector = false
    @State private var showingCustomSettings = false
    @State private var selectedPreset: ReverbPreset = .studio
    @State private var wetDryMix: Float = 0.4
    @State private var inputGain: Float = 1.0
    @State private var outputGain: Float = 1.0
    
    // Touch interaction
    @State private var isDraggingWetDry = false
    @State private var isDraggingGain = false
    
    // Visual feedback
    @State private var audioLevelTimer: Timer?
    @State private var currentInputLevel: Float = 0.0
    @State private var currentOutputLevel: Float = 0.0
    
    private let cardColor = Color(red: 0.94, green: 0.94, blue: 0.96) // systemGray6 equivalent
    private let accentColor = Color.blue
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                // Audio status and levels
                audioStatusSection
                
                // Main reverb controls
                reverbControlsSection
                
                // Preset selection
                presetSelectionSection
                
                // Advanced controls (collapsible)
                advancedControlsSection
                
                // Recording controls
                recordingControlsSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .background(Color(.systemBackground))
        .onAppear {
            setupAudioLevelMonitoring()
        }
        .onDisappear {
            stopAudioLevelMonitoring()
        }
        .sheet(isPresented: $showingPresetSelector) {
            // TODO: Add iOSPresetSelectorView to Xcode project
            VStack {
                Text("Preset Selector - Coming Soon")
                Text("Selected: \(selectedPreset.rawValue)")
                Button("Close") {
                    showingPresetSelector = false
                }
            }
            .padding()
        }
        .sheet(isPresented: $showingCustomSettings) {
            // TODO: Add iOSCustomReverbView to Xcode project
            VStack {
                Text("Custom Reverb Controls - Coming Soon")
                Button("Close") {
                    showingCustomSettings = false
                }
            }
            .padding()
        }
    }
    
    // MARK: - Audio Status Section
    private var audioStatusSection: some View {
        VStack(spacing: 12) {
            // Audio engine status
            HStack {
                Circle()
                    .fill(audioManager.isEngineRunning ? .green : .red)
                    .frame(width: 12, height: 12)
                
                Text(audioManager.isEngineRunning ? "Audio Engine Actif" : "Audio Engine Arrêté")
                    .font(.headline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Button(action: toggleAudioEngine) {
                    Image(systemName: audioManager.isEngineRunning ? "stop.circle.fill" : "play.circle.fill")
                        .font(.title2)
                        .foregroundColor(audioManager.isEngineRunning ? .red : .green)
                }
            }
            
            // Audio level meters
            audioLevelMeters
        }
        .padding(16)
        .background(cardColor)
        .cornerRadius(12)
    }
    
    private var audioLevelMeters: some View {
        VStack(spacing: 8) {
            // Input level
            HStack {
                Text("IN")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                    .frame(width: 24, alignment: .leading)
                
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 6)
                        
                        RoundedRectangle(cornerRadius: 3)
                            .fill(LinearGradient(
                                colors: [.green, .yellow, .red],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                            .frame(width: geometry.size.width * CGFloat(currentInputLevel), height: 6)
                            .animation(.easeInOut(duration: 0.1), value: currentInputLevel)
                    }
                }
                .frame(height: 6)
                
                Text(String(format: "%.0f", currentInputLevel * 100))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .frame(width: 24, alignment: .trailing)
                    .monospacedDigit()
            }
            
            // Output level
            HStack {
                Text("OUT")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                    .frame(width: 24, alignment: .leading)
                
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 6)
                        
                        RoundedRectangle(cornerRadius: 3)
                            .fill(LinearGradient(
                                colors: [.green, .yellow, .red],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                            .frame(width: geometry.size.width * CGFloat(currentOutputLevel), height: 6)
                            .animation(.easeInOut(duration: 0.1), value: currentOutputLevel)
                    }
                }
                .frame(height: 6)
                
                Text(String(format: "%.0f", currentOutputLevel * 100))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .frame(width: 24, alignment: .trailing)
                    .monospacedDigit()
            }
        }
    }
    
    // MARK: - Reverb Controls Section
    private var reverbControlsSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("🎛️ Contrôles Reverb")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Avancés") {
                    showingCustomSettings = true
                }
                .font(.caption)
                .foregroundColor(accentColor)
            }
            
            // Wet/Dry Mix - Large touch-friendly control
            VStack(spacing: 8) {
                HStack {
                    Text("Mix Wet/Dry")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Text("\(Int(wetDryMix * 100))%")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(accentColor)
                        .monospacedDigit()
                }
                
                // Custom touch-optimized slider
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Track
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 16)
                        
                        // Fill
                        RoundedRectangle(cornerRadius: 8)
                            .fill(LinearGradient(
                                colors: [.green, accentColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                            .frame(width: geometry.size.width * CGFloat(wetDryMix), height: 16)
                        
                        // Thumb
                        Circle()
                            .fill(Color.white)
                            .shadow(radius: 2)
                            .frame(width: 24, height: 24)
                            .offset(x: (geometry.size.width - 24) * CGFloat(wetDryMix))
                            .scaleEffect(isDraggingWetDry ? 1.2 : 1.0)
                            .animation(.spring(response: 0.3), value: isDraggingWetDry)
                    }
                }
                .frame(height: 24)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDraggingWetDry = true
                            let newValue = Float(max(0, min(1, value.location.x / UIScreen.main.bounds.width * 0.9)))
                            wetDryMix = newValue
                            // Apply to audio manager
                            // audioManager.setWetDryMix(newValue)
                        }
                        .onEnded { _ in
                            isDraggingWetDry = false
                            // Provide haptic feedback
                            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                            impactFeedback.impactOccurred()
                        }
                )
                
                // Wet/Dry labels
                HStack {
                    Text("Dry")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("Wet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(16)
        .background(cardColor)
        .cornerRadius(12)
    }
    
    // MARK: - Preset Selection Section
    private var presetSelectionSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("🎯 Presets")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Tout voir") {
                    showingPresetSelector = true
                }
                .font(.caption)
                .foregroundColor(accentColor)
            }
            
            // Quick preset buttons
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach([ReverbPreset.clean, .vocalBooth, .studio], id: \.self) { preset in
                    presetButton(preset)
                }
            }
        }
        .padding(16)
        .background(cardColor)
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private func presetButton(_ preset: ReverbPreset) -> some View {
        Button(action: {
            selectPreset(preset)
        }) {
            VStack(spacing: 6) {
                Text(getPresetEmoji(preset))
                    .font(.title2)
                
                Text(getPresetName(preset))
                    .font(.caption)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
            }
            .foregroundColor(selectedPreset == preset ? .white : .primary)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(selectedPreset == preset ? accentColor : Color.gray.opacity(0.2))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Advanced Controls Section
    private var advancedControlsSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("⚙️ Contrôles Avancés")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            
            VStack(spacing: 16) {
                // Input Gain
                gainControl(
                    title: "Gain d'entrée",
                    value: $inputGain,
                    range: 0...2,
                    unit: "dB",
                    color: .green
                )
                
                // Output Gain
                gainControl(
                    title: "Gain de sortie",
                    value: $outputGain,
                    range: 0...2,
                    unit: "dB",
                    color: .blue
                )
            }
        }
        .padding(16)
        .background(cardColor)
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private func gainControl(
        title: String,
        value: Binding<Float>,
        range: ClosedRange<Float>,
        unit: String,
        color: Color
    ) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text(String(format: "%.1f %@", value.wrappedValue, unit))
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(color)
                    .monospacedDigit()
            }
            
            Slider(value: value, in: range)
                .accentColor(color)
        }
    }
    
    // MARK: - Recording Controls Section
    private var recordingControlsSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("🎙️ Enregistrement")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            
            HStack(spacing: 12) {
                Button(action: {
                    // Start recording
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "record.circle")
                            .font(.title3)
                        Text("Démarrer")
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 20)
                    .background(Color.red)
                    .cornerRadius(8)
                }
                
                Button(action: {
                    // Stop recording
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "stop.circle")
                            .font(.title3)
                        Text("Arrêter")
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 20)
                    .background(Color.gray)
                    .cornerRadius(8)
                }
            }
        }
        .padding(16)
        .background(cardColor)
        .cornerRadius(12)
    }
    
    // MARK: - Helper Methods
    private func toggleAudioEngine() {
        if audioManager.isEngineRunning {
            audioManager.stopAudioEngine()
        } else {
            audioManager.startAudioEngine()
        }
        
        // Provide haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.impactOccurred()
    }
    
    private func selectPreset(_ preset: ReverbPreset) {
        selectedPreset = preset
        // audioManager.setReverbPreset(preset)
        
        // Provide haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
    
    private func setupAudioLevelMonitoring() {
        audioLevelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            // Update audio levels
            // These would come from the audio manager's level monitoring
            currentInputLevel = Float.random(in: 0...0.8) // Simulated
            currentOutputLevel = Float.random(in: 0...0.6) // Simulated
        }
    }
    
    private func stopAudioLevelMonitoring() {
        audioLevelTimer?.invalidate()
        audioLevelTimer = nil
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
        case .vocalBooth: return "Booth"
        case .studio: return "Studio"
        case .cathedral: return "Cathedral"
        case .custom: return "Custom"
        }
    }
}

#if DEBUG
#Preview {
    iOSRealtimeView(audioManager: AudioManagerCPP.shared)
        .preferredColorScheme(.dark)
}
#endif