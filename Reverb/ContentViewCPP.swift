import SwiftUI
import AVFoundation

struct ContentViewCPP: View {
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
            CustomReverbView(audioManager: AudioManagerCPP.shared)
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 4) {
            HStack {
                Text("🎛️ Reverb Pro Enhanced")
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
            
            Text("Ultra-Simple Audio Engine")
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
                        .foregroundColor(.blue)
                        .fontWeight(.medium)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Quality")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                    Text("Professional")
                        .font(.caption2)
                        .foregroundColor(.green)
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
                
                // Backend Toggle
                Button(action: {
                    audioManager.toggleBackend()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: audioManager.usingCppBackend ? "cpu" : "swift")
                            .font(.caption)
                        Text(audioManager.usingCppBackend ? "C++" : "Swift")
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(audioManager.usingCppBackend ? Color.blue : Color.purple)
                    .cornerRadius(6)
                }
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
                    .onChange(of: micGain) { _, newValue in
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
                        .onChange(of: masterVolume) { _, newValue in
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
                    
                    Text("Enhanced monitoring active • \(audioManager.engineInfo)")
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
            Text("🎛️ Professional Reverb Modes")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(ReverbPreset.allCases, id: \.id) { preset in
                    Button(action: {
                        print("🎛️ UI (CPP): User clicked preset: \(preset.rawValue)")
                        print("📊 UI (CPP): Current monitoring state: \(audioManager.isMonitoring)")
                        print("📤 UI (CPP): Calling audioManager.updateReverbPreset(\(preset.rawValue))")
                        audioManager.updateReverbPreset(preset)
                        print("📨 UI (CPP): updateReverbPreset call completed")
                        
                        if preset == .custom {
                            showingCustomReverbView = true
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
                    .opacity(1.0)
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
                        .foregroundColor(audioManager.cpuUsage > 50 ? .orange : .green)
                        .monospacedDigit()
                }
                
                Spacer()
                
                VStack(alignment: .center, spacing: 4) {
                    Text("Backend")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                    Text(audioManager.engineInfo.contains("C++") ? "C++ FDN" : "Swift")
                        .font(.caption2)
                        .foregroundColor(audioManager.engineInfo.contains("C++") ? .blue : .purple)
                        .fontWeight(.bold)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Status")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                    Text(audioManager.canStartMonitoring ? "Ready" : "Busy")
                        .font(.caption2)
                        .foregroundColor(audioManager.canStartMonitoring ? .green : .orange)
                }
            }
            
            VStack(spacing: 4) {
                Button("Run Diagnostics") {
                    audioManager.diagnostic()
                }
                .font(.caption)
                .foregroundColor(accentColor)
                .frame(maxWidth: .infinity)
                .padding(8)
                .background(cardColor)
                .cornerRadius(6)
                
                Button("🔍 Test Audio Ultra-Simple") {
                    runUltraSimpleAudioTest()
                }
                .font(.caption)
                .foregroundColor(.orange)
                .frame(maxWidth: .infinity)
                .padding(8)
                .background(cardColor)
                .cornerRadius(6)
                
                Button("🎵 Test Direct macOS Audio") {
                    runDirectMacOSAudioTest()
                }
                .font(.caption)
                .foregroundColor(.green)
                .frame(maxWidth: .infinity)
                .padding(8)
                .background(cardColor)
                .cornerRadius(6)
                
            }
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
    
    private func runUltraSimpleAudioTest() {
        print("🔍 === TEST AUDIO ULTRA-SIMPLE ===")
        
        // Test des permissions microphone
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        print("1. Permissions microphone: \(status == .authorized ? "✅ AUTORISÉ" : "❌ REFUSÉ (\(status.rawValue))")")
        
        if status != .authorized {
            print("⚠️ PROBLÈME IDENTIFIÉ: Permissions microphone manquantes!")
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    print("Permissions accordées: \(granted)")
                }
            }
            return
        }
        
        // Test engine basique
        let testEngine = AVAudioEngine()
        let testInput = testEngine.inputNode
        let testOutput = testEngine.outputNode
        
        let inputFormat = testInput.inputFormat(forBus: 0)
        print("2. Format input: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount) canaux")
        
        if inputFormat.sampleRate == 0 {
            print("❌ PROBLÈME IDENTIFIÉ: Format input invalide!")
            return
        }
        
        do {
            // Connexion directe input->output (echo)
            testEngine.connect(testInput, to: testOutput, format: inputFormat)
            testEngine.prepare()
            try testEngine.start()
            
            print("✅ TEST RÉUSSI: Audio engine direct démarré!")
            print("👂 Vous devriez vous entendre en écho pendant 3 secondes...")
            
            // Arrêt après 3 secondes
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                testEngine.stop()
                print("🔍 Test terminé - si vous ne vous êtes pas entendu, le problème est au niveau matériel/système")
            }
            
        } catch {
            print("❌ PROBLÈME IDENTIFIÉ: \(error.localizedDescription)")
        }
    }
    
    private func runDirectMacOSAudioTest() {
        print("🎵 === TEST DIRECT macOS AUDIO ===")
        
        // Test permissions
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        print("1. Permissions: \(status == .authorized ? "✅ OK" : "❌ MANQUANT")")
        
        if status != .authorized {
            print("⚠️ Demande de permissions...")
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.runDirectMacOSAudioTest() // Retry after permission
                    } else {
                        print("❌ Permissions refusées")
                    }
                }
            }
            return
        }
        
        // Create a FORCED macOS audio test
        let testEngine = AVAudioEngine()
        let testInput = testEngine.inputNode
        let testOutput = testEngine.outputNode
        
        // Create mixer for volume control
        let testMixer = AVAudioMixerNode()
        testEngine.attach(testMixer)
        
        // Get input format
        let inputFormat = testInput.inputFormat(forBus: 0)
        print("2. Format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount) canaux")
        
        if inputFormat.sampleRate == 0 {
            print("❌ Format invalide!")
            return
        }
        
        do {
            // CRITICAL: Connect with explicit mixer for macOS
            testEngine.connect(testInput, to: testMixer, format: inputFormat)
            testEngine.connect(testMixer, to: testOutput, format: nil)
            
            // CRITICAL: Set mixer volume HIGH to force audio through
            testMixer.outputVolume = 2.0  // Double volume to force audio
            
            // CRITICAL: Set input volume high
            testInput.volume = 2.0
            
            print("3. ✅ Connexions: Input -> Mixer(vol=2.0) -> Output")
            
            testEngine.prepare()
            try testEngine.start()
            
            print("4. ✅ MOTEUR DÉMARRÉ - Volume FORCÉ x2")
            print("👂 ÉCOUTEZ MAINTENANT (10 secondes) - vous devriez vous entendre FORT!")
            
            // Stop after 10 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                testEngine.stop()
                print("🔍 Test terminé - si aucun son = problème système macOS")
            }
            
        } catch {
            print("❌ Erreur test direct: \(error.localizedDescription)")
        }
    }
}

#Preview {
    ContentViewCPP()
}