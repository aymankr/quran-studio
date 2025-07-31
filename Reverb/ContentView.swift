import SwiftUI
import AVFoundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct ContentView: View {
    @StateObject private var audioManager = AudioManagerCPP.shared
    @StateObject private var recordingHistory = RecordingHistory()
    
    // États locaux
    @State private var isMonitoring = false
    @State private var masterVolume: Float = 1.5
    @State private var micGain: Float = 1.2
    @State private var isMuted = false
    @State private var selectedReverbPreset: ReverbPreset = .vocalBooth
    @State private var recordings: [URL] = []
    @State private var recordingToDelete: URL?
    @State private var showDeleteAlert = false
    
    // States spécifiques macOS
    @State private var windowWidth: CGFloat = 800
    
    // Player local
    @StateObject private var audioPlayer = LocalAudioPlayer()
    
    // Couleurs du thème
    private let backgroundColor = Color(red: 0.08, green: 0.08, blue: 0.13)
    private let cardColor = Color(red: 0.12, green: 0.12, blue: 0.18)
    private let accentColor = Color.blue
    @State private var showingCustomReverbView = false

    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()
            
            GeometryReader { geometry in
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: adaptiveSpacing) {
                        headerSection
                        
                        if isCompactLayout {
                            compactLayout
                        } else {
                            expandedLayout
                        }
                        
                        Color.clear.frame(height: 20)
                    }
                    .padding(.horizontal, adaptivePadding)
                    .padding(.top, 5)
                }
                .onAppear {
                    windowWidth = geometry.size.width
                }
                .onChange(of: geometry.size.width) { newWidth in
                    windowWidth = newWidth
                }
            }
        }
        .onAppear {
            setupAudio()
            loadRecordings()
        }
        .alert("Supprimer l'enregistrement", isPresented: $showDeleteAlert) {
            Button("Supprimer", role: .destructive) {
                deleteSelectedRecording()
            }
            Button("Annuler", role: .cancel) { }
        }
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 500)
        .background(WindowAccessor { window in
            window?.title = "Reverb Studio - Enregistrement Audio"
            window?.titlebarAppearsTransparent = true
            window?.titleVisibility = .hidden
        })
        #endif
    }
    
    // MARK: - Layout Properties
    
    private var isCompactLayout: Bool {
        #if os(iOS)
        return true
        #else
        return windowWidth < 800
        #endif
    }
    
    private var adaptiveSpacing: CGFloat {
        #if os(macOS)
        return isCompactLayout ? 12 : 16
        #else
        return 16
        #endif
    }
    
    private var adaptivePadding: CGFloat {
        #if os(macOS)
        return isCompactLayout ? 16 : 24
        #else
        return 16
        #endif
    }
    
    // MARK: - LAYOUTS
    
    @ViewBuilder
    private var compactLayout: some View {
        audioLevelSection
        volumeControlsSection
        monitoringSection
        reverbPresetsSection
        
        if isMonitoring {
            recordingSection
            
            // Advanced recording controls (TODO: Add RecordingControlsView to Xcode project)
            // RecordingControlsView(audioManager: audioManager)
        }
        
        recordingsListSection
    }
    
    @ViewBuilder
    private var expandedLayout: some View {
        audioLevelSection
        
        HStack(alignment: .top, spacing: 20) {
            VStack(spacing: 16) {
                volumeControlsSection
                monitoringSection
                
                if isMonitoring {
                    recordingSection
                    
                    // Advanced recording controls (TODO: Add RecordingControlsView to Xcode project)
                    // RecordingControlsView(audioManager: audioManager)
                }
            }
            .frame(maxWidth: 350)
            
            VStack(spacing: 16) {
                reverbPresetsSection
                recordingsListSection
            }
            .frame(maxWidth: 400)
        }
    }
    
    // MARK: - HEADER SECTION
    
    private var headerSection: some View {
        VStack(spacing: 4) {
            HStack {
                Text("🎙️ Reverb Studio")
                    .font(.system(size: adaptiveTitleSize, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Spacer()
                
                #if os(macOS)
                HStack(spacing: 4) {
                    Image(systemName: "laptopcomputer")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                    Text("macOS")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                }
                #endif
            }
            
            Text("Enregistrement avec réverbération optimisée")
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(.vertical, 8)
    }
    
    private var adaptiveTitleSize: CGFloat {
        #if os(macOS)
        return isCompactLayout ? 20 : 26
        #else
        return 24
        #endif
    }
    
    // MARK: - NIVEAU AUDIO
    
    private var audioLevelSection: some View {
        VStack(spacing: 6) {
            Text("Niveau Audio")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white)
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 10)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(
                            gradient: Gradient(colors: [.green, .yellow, .red]),
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: geometry.size.width * CGFloat(audioManager.currentAudioLevel), height: 10)
                        .animation(.easeInOut(duration: 0.1), value: audioManager.currentAudioLevel)
                }
            }
            .frame(height: 10)
            
            Text("\(Int(audioManager.currentAudioLevel * 100))%")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.8))
                .monospacedDigit()
        }
        .padding(12)
        .background(cardColor)
        .cornerRadius(10)
    }
    
    // MARK: - CONTRÔLES VOLUME
    
    private var volumeControlsSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("🎵 Contrôles Audio Optimisés")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                #if os(macOS)
                Spacer()
                Text("Double-clic pour réinitialiser")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
                #endif
            }
            
            // GAIN MICROPHONE
            VStack(spacing: 6) {
                HStack {
                    Image(systemName: "mic.fill")
                        .foregroundColor(.green)
                    Text("Gain Microphone")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                    Spacer()
                    Text("\(Int(micGain * 100))%" + getGainLabel(micGain))
                        .foregroundColor(getGainColor(micGain))
                        .font(.caption)
                        .monospacedDigit()
                }
                
                HStack {
                    Slider(value: $micGain, in: 0.2...3.0, step: 0.1)
                        .accentColor(.green)
                        .onChange(of: micGain) { newValue in
                            audioManager.setInputVolume(newValue)
                            print("🎵 Quality Gain micro: \(Int(newValue * 100))%")
                        }
                        #if os(macOS)
                        .onTapGesture(count: 2) {
                            micGain = 1.2
                        }
                        #endif
                }
                
                HStack {
                    Text("20%")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    Spacer()
                    Text("DOUX")
                        .font(.caption2)
                        .foregroundColor(.green)
                    Spacer()
                    Text("OPTIMAL")
                        .font(.caption2)
                        .foregroundColor(.blue)
                    Spacer()
                    Text("FORT")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    Spacer()
                    Text("300%")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
                
                qualityIndicator(for: micGain, type: .microphone)
            }
            .padding(10)
            .background(cardColor.opacity(0.7))
            .cornerRadius(8)
            
            // VOLUME MONITORING
            VStack(spacing: 6) {
                HStack {
                    Image(systemName: isMuted ? "speaker.slash" : "speaker.wave.3")
                        .foregroundColor(isMuted ? .red : accentColor)
                    Text("Volume Monitoring")
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
                    #if os(macOS)
                    .buttonStyle(PlainButtonStyle())
                    .onHover { hovering in
                        if hovering { NSCursor.pointingHand.set() }
                    }
                    #endif
                }
                
                if !isMuted {
                    Slider(value: $masterVolume, in: 0...2.5, step: 0.05)
                        .accentColor(accentColor)
                        .onChange(of: masterVolume) { newValue in
                            audioManager.setOutputVolume(newValue, isMuted: isMuted)
                            print("🔊 Quality Volume: \(Int(newValue * 100))%")
                        }
                        #if os(macOS)
                        .onTapGesture(count: 2) {
                            masterVolume = 1.5
                        }
                        #endif
                    
                    HStack {
                        Text("Silence")
                            .font(.caption2)
                            .foregroundColor(.gray)
                        Spacer()
                        Text("DOUX")
                            .font(.caption2)
                            .foregroundColor(.green)
                        Spacer()
                        Text("OPTIMAL")
                            .font(.caption2)
                            .foregroundColor(.blue)
                        Spacer()
                        Text("FORT")
                            .font(.caption2)
                            .foregroundColor(.orange)
                        Spacer()
                        Text("250%")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                    
                    Text("\(Int(masterVolume * 100))%" + getVolumeQualityLabel(masterVolume))
                        .foregroundColor(getVolumeQualityColor(masterVolume))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                    
                    qualityIndicator(for: masterVolume, type: .volume)
                } else {
                    Text("🔇 SILENCIEUX")
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(4)
                }
            }
            .padding(10)
            .background(cardColor)
            .cornerRadius(8)
            .opacity(isMuted ? 0.7 : 1.0)
            
            // Indicateur de qualité totale
            if isMonitoring {
                HStack {
                    Text("🎵 GAIN TOTAL OPTIMAL:")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.8))
                    
                    Spacer()
                    
                    let totalGain = micGain * masterVolume * 1.3
                    Text("x\(String(format: "%.1f", totalGain))")
                        .font(.caption2)
                        .foregroundColor(totalGain > 4.0 ? .orange : .green)
                        .fontWeight(.bold)
                        .monospacedDigit()
                    
                    Text(totalGain > 4.0 ? "(Élevé)" : "(Optimal)")
                        .font(.caption2)
                        .foregroundColor(totalGain > 4.0 ? .orange : .green)
                }
                .padding(8)
                .background((micGain * masterVolume * 1.3) > 4.0 ? Color.orange.opacity(0.1) : Color.green.opacity(0.1))
                .cornerRadius(6)
            }
        }
    }
    
    // MARK: - MONITORING SECTION
    
    private var monitoringSection: some View {
        VStack(spacing: 8) {
            Button(action: {
                toggleMonitoring()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: isMonitoring ? "stop.circle.fill" : "play.circle.fill")
                        .font(.title2)
                    Text(isMonitoring ? "🔴 Arrêter Monitoring" : "▶️ Démarrer Monitoring")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(isMonitoring ? Color.red : accentColor)
                .cornerRadius(10)
            }
            #if os(macOS)
            .buttonStyle(PlainButtonStyle())
            .onHover { hovering in
                if hovering { NSCursor.pointingHand.set() }
            }
            .keyboardShortcut(isMonitoring ? "s" : "p", modifiers: .command)
            #endif
            
            if isMonitoring {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                        .scaleEffect(1.0)
                        .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: isMonitoring)
                    
                    Text("Monitoring actif • Volumes ajustables en temps réel")
                        .font(.caption2)
                        .foregroundColor(.green)
                        .fontWeight(.medium)
                    
                    #if os(macOS)
                    Spacer()
                    Text("⌘P/⌘S pour contrôler")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.5))
                    #endif
                }
                .padding(.horizontal, 4)
            }
        }
    }
    
    // MARK: - PRESETS REVERB
    
    private var reverbPresetsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("🎛️ Modes de Réverbération")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: adaptiveColumnCount)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(ReverbPreset.allCases, id: \.id) { preset in
                    Button(action: {
                        print("🎛️ UI: User selected preset: \(preset.rawValue)")
                        if isMonitoring {
                            print("✅ UI: Monitoring is active, applying preset")
                            selectedReverbPreset = preset
                            print("📤 UI: Calling audioManager.updateReverbPreset(\(preset.rawValue))")
                            audioManager.updateReverbPreset(preset)
                            print("📨 UI: updateReverbPreset call completed")
                            
                            // NOUVEAU: Présenter CustomReverbView si preset custom
                            if preset == .custom {
                                showingCustomReverbView = true
                            }
                        } else {
                            print("⚠️ UI: Monitoring is NOT active, preset selection ignored")
                        }
                    }) {
                        VStack(spacing: 4) {
                            Text(getPresetEmoji(preset))
                                .font(adaptivePresetEmojiSize)
                            
                            Text(getPresetName(preset))
                                .font(.caption)
                                .fontWeight(.medium)
                                .multilineTextAlignment(.center)
                        }
                        .foregroundColor(selectedReverbPreset == preset ? .white : .white.opacity(0.7))
                        .frame(maxWidth: .infinity, minHeight: adaptivePresetHeight)
                        .background(
                            selectedReverbPreset == preset ?
                            accentColor : cardColor.opacity(0.8)
                        )
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(selectedReverbPreset == preset ? .white.opacity(0.3) : .clear, lineWidth: 1)
                        )
                        .scaleEffect(selectedReverbPreset == preset ? 1.05 : 1.0)
                        .animation(.easeInOut(duration: 0.15), value: selectedReverbPreset == preset)
                    }
                    .disabled(!isMonitoring)
                    .opacity(isMonitoring ? 1.0 : 0.5)
                    #if os(macOS)
                    .buttonStyle(PlainButtonStyle())
                    .onHover { hovering in
                        if isMonitoring && hovering { NSCursor.pointingHand.set() }
                    }
                    #endif
                }
            }
            
            // NOUVEAU: Bouton direct pour Custom quand monitoring inactif
            if !isMonitoring && selectedReverbPreset == .custom {
                Button(action: {
                    showingCustomReverbView = true
                }) {
                    HStack {
                        Image(systemName: "slider.horizontal.3")
                        Text("Configurer les paramètres personnalisés")
                            .font(.caption)
                    }
                    .foregroundColor(accentColor)
                    .padding(8)
                    .background(cardColor.opacity(0.6))
                    .cornerRadius(6)
                }
                #if os(macOS)
                .buttonStyle(PlainButtonStyle())
                #endif
            }
            
            if isMonitoring {
                HStack {
                    Text("Effet: \(selectedReverbPreset.rawValue) - \(getPresetDescription(selectedReverbPreset))")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.8))
                    
                    // NOUVEAU: Bouton pour accéder aux réglages Custom pendant monitoring
                    if selectedReverbPreset == .custom {
                        Spacer()
                        Button("Régler") {
                            showingCustomReverbView = true
                        }
                        .font(.caption2)
                        .foregroundColor(accentColor)
                        #if os(macOS)
                        .buttonStyle(PlainButtonStyle())
                        #endif
                    }
                }
                .padding(8)
                .background(cardColor.opacity(0.5))
                .cornerRadius(6)
            }
        }
        // NOUVEAU: Présentation de CustomReverbView
        .sheet(isPresented: $showingCustomReverbView) {
            CustomReverbView(audioManager: audioManager)
        }
    }

    
    private var adaptiveColumnCount: Int {
        #if os(macOS)
        return isCompactLayout ? 3 : 5
        #else
        return 3
        #endif
    }
    
    private var adaptivePresetEmojiSize: Font {
        #if os(macOS)
        return isCompactLayout ? .title3 : .title2
        #else
        return .title2
        #endif
    }
    
    private var adaptivePresetHeight: CGFloat {
        #if os(macOS)
        return isCompactLayout ? 50 : 65
        #else
        return 60
        #endif
    }
    
    // MARK: - SECTION ENREGISTREMENT
    
    private var recordingSection: some View {
        VStack(spacing: 10) {
            Text("🎙️ Enregistrement")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            HStack(spacing: 12) {
                Button(action: {
                    handleRecordingToggle()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: audioManager.isRecording ? "stop.circle.fill" : "record.circle")
                            .font(.title3)
                        Text(audioManager.isRecording ? "🔴 Arrêter" : "⏺️ Enregistrer")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(audioManager.isRecording ? Color.red : Color.orange)
                    .cornerRadius(8)
                }
                #if os(macOS)
                .buttonStyle(PlainButtonStyle())
                .keyboardShortcut("r", modifiers: .command)
                #endif
                
                Button(action: {
                    loadRecordings()
                }) {
                    VStack(spacing: 2) {
                        Image(systemName: "list.bullet")
                            .font(.body)
                        Text("\(recordings.count)")
                            .font(.caption2)
                    }
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Color.gray.opacity(0.6))
                    .cornerRadius(8)
                }
                #if os(macOS)
                .buttonStyle(PlainButtonStyle())
                #endif
            }
            
            if audioManager.isRecording {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 6, height: 6)
                        .scaleEffect(1.0)
                        .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: audioManager.isRecording)
                    
                    Text("🔴 Enregistrement avec \(selectedReverbPreset.rawValue)...")
                        .font(.caption)
                        .foregroundColor(.red)
                        .fontWeight(.medium)
                    
                    #if os(macOS)
                    Spacer()
                    Text("⌘R pour arrêter")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.5))
                    #endif
                }
            } else if let filename = audioManager.lastRecordingFilename {
                Text("✅ Dernier: \(filename)")
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
    
    // MARK: - LISTE ENREGISTREMENTS
    
    private var recordingsListSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("📂 Enregistrements (\(recordings.count))")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Spacer()
                
                Button("🔄") {
                    loadRecordings()
                }
                .foregroundColor(accentColor)
                #if os(macOS)
                .buttonStyle(PlainButtonStyle())
                #endif
            }
            
            if recordings.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "waveform.circle")
                        .font(.system(size: 30))
                        .foregroundColor(.white.opacity(0.3))
                    Text("Aucun enregistrement")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                    
                    #if os(macOS)
                    Text("Les fichiers sont sauvés dans ~/Documents/Recordings")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.4))
                        .multilineTextAlignment(.center)
                    #endif
                }
                .frame(maxWidth: .infinity)
                .padding(20)
                .background(cardColor.opacity(0.5))
                .cornerRadius(8)
            } else {
                LazyVStack(spacing: 6) {
                    ForEach(recordings.prefix(adaptiveRecordingCount), id: \.self) { recording in
                        recordingRowView(recording: recording)
                    }
                    
                    if recordings.count > adaptiveRecordingCount {
                        Text("... et \(recordings.count - adaptiveRecordingCount) autre(s)")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.6))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(8)
                    }
                }
            }
        }
        .padding(12)
        .background(cardColor.opacity(0.3))
        .cornerRadius(10)
    }
    
    private var adaptiveRecordingCount: Int {
        #if os(macOS)
        return isCompactLayout ? 4 : 8
        #else
        return 5
        #endif
    }
    
    // MARK: - ROW ENREGISTREMENT
    
    @ViewBuilder
    private func recordingRowView(recording: URL) -> some View {
        HStack(spacing: 10) {
            Button(action: {
                togglePlayback(recording: recording)
            }) {
                Image(systemName: getPlayButtonIcon(recording: recording))
                    .font(.title3)
                    .foregroundColor(isCurrentlyPlaying(recording) ? .red : accentColor)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(cardColor))
            }
            #if os(macOS)
            .buttonStyle(PlainButtonStyle())
            .onHover { hovering in
                if hovering { NSCursor.pointingHand.set() }
            }
            #endif
            
            VStack(alignment: .leading, spacing: 2) {
                Text(getDisplayName(recording))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    Text(getRecordingDuration(recording))
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                    
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.5))
                    
                    Text(getFileSize(recording))
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                    
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.5))
                    
                    Text(recording.pathExtension.uppercased())
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.5))
                    
                    #if os(macOS)
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.5))
                    
                    Text(getCreationDate(recording))
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.5))
                    #endif
                }
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                #if os(macOS)
                Button(action: {
                    revealInFinder(recording)
                }) {
                    Image(systemName: "folder")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Afficher dans le Finder")
                #endif
                
                Button(action: {
                    shareRecording(recording)
                }) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.caption)
                        .foregroundColor(accentColor)
                }
                #if os(macOS)
                .buttonStyle(PlainButtonStyle())
                .help("Partager")
                #endif
                
                Button(action: {
                    recordingToDelete = recording
                    showDeleteAlert = true
                }) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundColor(.red.opacity(0.8))
                }
                #if os(macOS)
                .buttonStyle(PlainButtonStyle())
                .help("Supprimer")
                #endif
            }
        }
        .padding(8)
        .background(cardColor.opacity(0.6))
        .cornerRadius(6)
        #if os(macOS)
        .contextMenu {
            Button("Lire/Pause") {
                togglePlayback(recording: recording)
            }
            
            Button("Afficher dans le Finder") {
                revealInFinder(recording)
            }
            
            Button("Partager") {
                shareRecording(recording)
            }
            
            Divider()
            
            Button("Supprimer", role: .destructive) {
                recordingToDelete = recording
                showDeleteAlert = true
            }
        }
        #endif
    }
    
    // MARK: - HELPER FUNCTIONS
    
    private func setupAudio() {
        // AudioManagerCPP doesn't need prepareAudio() - it initializes automatically
        audioManager.setInputVolume(micGain)
        audioManager.setOutputVolume(masterVolume, isMuted: isMuted)
    }
    
    private func toggleMonitoring() {
        isMonitoring.toggle()
        if isMonitoring {
            audioManager.startMonitoring()
            audioManager.updateReverbPreset(selectedReverbPreset)
            audioManager.setInputVolume(micGain)
            audioManager.setOutputVolume(masterVolume, isMuted: isMuted)
        } else {
            audioManager.stopMonitoring()
        }
    }
    
    private func handleRecordingToggle() {
        if audioManager.isRecording {
            audioManager.stopRecording { success, filename, duration in
                if success {
                    recordingHistory.addSession(preset: selectedReverbPreset.rawValue, duration: duration)
                    loadRecordings()
                }
            }
        } else {
            audioManager.startRecording { success in
                if !success {
                    print("❌ Échec de l'enregistrement")
                }
            }
        }
    }
    
    private func loadRecordings() {
        let documentsPath: URL
        
        #if os(macOS)
        documentsPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
        #else
        documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        #endif
        
        let recordingsPath = documentsPath.appendingPathComponent("Recordings")
        
        if !FileManager.default.fileExists(atPath: recordingsPath.path) {
            do {
                try FileManager.default.createDirectory(at: recordingsPath, withIntermediateDirectories: true)
                print("✅ Created Recordings directory at: \(recordingsPath.path)")
            } catch {
                print("❌ Failed to create directory: \(error)")
                return
            }
        }
        
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: recordingsPath,
                includingPropertiesForKeys: [.creationDateKey]
            )
            
            recordings = files.filter { url in
                ["wav", "mp3", "aac", "m4a"].contains(url.pathExtension.lowercased())
            }.sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                return date1 > date2
            }
            
            print("📂 Loaded \(recordings.count) recordings from: \(recordingsPath.path)")
        } catch {
            recordings = []
            print("❌ Error loading recordings: \(error)")
        }
    }
    
    private func togglePlayback(recording: URL) {
        if isCurrentlyPlaying(recording) {
            audioPlayer.pausePlayback()
        } else {
            audioPlayer.playRecording(at: recording)
        }
    }
    
    private func isCurrentlyPlaying(_ recording: URL) -> Bool {
        return audioPlayer.isPlaying && audioPlayer.currentRecordingURL == recording
    }
    
    private func getPlayButtonIcon(recording: URL) -> String {
        return isCurrentlyPlaying(recording) ? "pause.circle.fill" : "play.circle.fill"
    }
    
    private func shareRecording(_ recording: URL) {
        #if os(iOS)
        let activityController = UIActivityViewController(activityItems: [recording], applicationActivities: nil)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootViewController = window.rootViewController {
            rootViewController.present(activityController, animated: true)
        }
        #elseif os(macOS)
        let sharingService = NSSharingServicePicker(items: [recording])
        
        if let window = NSApplication.shared.mainWindow,
           let contentView = window.contentView {
            let rect = NSRect(x: contentView.bounds.midX - 10, y: contentView.bounds.midY - 10, width: 20, height: 20)
            sharingService.show(relativeTo: rect, of: contentView, preferredEdge: .minY)
        }
        #endif
    }
    
    #if os(macOS)
    private func revealInFinder(_ recording: URL) {
        NSWorkspace.shared.selectFile(recording.path, inFileViewerRootedAtPath: "")
    }
    #endif
    
    private func deleteSelectedRecording() {
        guard let recording = recordingToDelete else { return }
        
        do {
            try FileManager.default.removeItem(at: recording)
            loadRecordings()
            print("✅ Recording deleted: \(recording.lastPathComponent)")
        } catch {
            print("❌ Erreur suppression: \(error)")
        }
        
        recordingToDelete = nil
    }
    
    // MARK: - Helper Functions pour styling
    
    @ViewBuilder
    private func qualityIndicator(for value: Float, type: QualityType) -> some View {
        let (message, color, background) = getQualityInfo(value: value, type: type)
        
        if !message.isEmpty {
            Text(message)
                .font(.caption2)
                .foregroundColor(color)
                .padding(4)
                .background(background)
                .cornerRadius(4)
        }
    }
    
    private enum QualityType {
        case microphone, volume
    }
    
    private func getQualityInfo(value: Float, type: QualityType) -> (String, Color, Color) {
        switch type {
        case .microphone:
            if value > 2.5 {
                return ("⚠️ GAIN ÉLEVÉ - Vérifier la qualité", .orange, Color.orange.opacity(0.2))
            } else if value > 1.5 {
                return ("✅ GAIN OPTIMAL - Bonne qualité", .blue, Color.clear)
            } else {
                return ("🎵 GAIN DOUX - Qualité maximale", .green, Color.clear)
            }
        case .volume:
            if value > 2.0 {
                return ("⚠️ VOLUME ÉLEVÉ - Surveiller la qualité", .orange, Color.orange.opacity(0.2))
            } else if value > 1.2 {
                return ("✅ VOLUME OPTIMAL - Parfait équilibre", .blue, Color.clear)
            } else {
                return ("🎵 VOLUME DOUX - Qualité premium", .green, Color.clear)
            }
        }
    }
    
    private func getGainLabel(_ gain: Float) -> String {
        if gain > 2.5 { return " (Élevé)" }
        else if gain > 1.5 { return " (Optimal)" }
        else { return " (Doux)" }
    }
    
    private func getGainColor(_ gain: Float) -> Color {
        if gain > 2.5 { return .orange }
        else if gain > 1.5 { return .blue }
        else { return .green }
    }
    
    private func getVolumeQualityLabel(_ volume: Float) -> String {
        if volume > 2.0 { return " (Fort)" }
        else if volume > 1.2 { return " (Optimal)" }
        else { return " (Doux)" }
    }
    
    private func getVolumeQualityColor(_ volume: Float) -> Color {
        if volume > 2.0 { return .orange }
        else if volume > 1.2 { return .blue }
        else { return .green }
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
    
    private func getPresetDescription(_ preset: ReverbPreset) -> String {
        switch preset {
        case .clean: return "Aucun effet"
        case .vocalBooth: return "Ambiance feutrée"
        case .studio: return "Équilibre professionnel"
        case .cathedral: return "Écho spacieux"
        case .custom: return "Paramètres personnalisés"
        }
    }
    
    private func getDisplayName(_ recording: URL) -> String {
        let name = recording.deletingPathExtension().lastPathComponent
        return name.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "safe reverb", with: "Reverb")
            .capitalized
    }
    
    private func getRecordingDuration(_ recording: URL) -> String {
        let asset = AVURLAsset(url: recording)
        let duration = CMTimeGetSeconds(asset.duration)
        
        if duration > 0 {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            return String(format: "%d:%02d", minutes, seconds)
        }
        return "0:00"
    }
    
    private func getFileSize(_ recording: URL) -> String {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: recording.path)
            let bytes = attributes[.size] as? Int64 ?? 0
            
            if bytes < 1024 * 1024 {
                return "\(bytes / 1024) KB"
            } else {
                return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
            }
        } catch {
            return "? KB"
        }
    }
    
    #if os(macOS)
    private func getCreationDate(_ recording: URL) -> String {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: recording.path)
            if let date = attributes[.creationDate] as? Date {
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                formatter.timeStyle = .short
                return formatter.string(from: date)
            }
        } catch {}
        return ""
    }
    #endif
}

// MARK: - CLASSE AUDIO PLAYER LOCAL

class LocalAudioPlayer: NSObject, ObservableObject {
    @Published var isPlaying = false
    @Published var currentRecordingURL: URL?
    
    private var audioPlayer: AVAudioPlayer?
    
    func playRecording(at url: URL) {
        stopPlayback()
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            
            let success = audioPlayer?.play() ?? false
            if success {
                isPlaying = true
                currentRecordingURL = url
                print("▶️ Lecture: \(url.lastPathComponent)")
            }
        } catch {
            print("❌ Erreur lecture: \(error)")
        }
    }
    
    func pausePlayback() {
        audioPlayer?.pause()
        isPlaying = false
        print("⏸️ Lecture en pause")
    }
    
    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        currentRecordingURL = nil
    }
    
    func resumePlayback() -> Bool {
        guard let player = audioPlayer else { return false }
        let success = player.play()
        isPlaying = success
        return success
    }
}

// MARK: - EXTENSION DELEGATE

extension LocalAudioPlayer: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.currentRecordingURL = nil
            print("✅ Lecture terminée")
        }
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.currentRecordingURL = nil
            print("❌ Erreur lecture: \(error?.localizedDescription ?? "unknown")")
        }
    }
}

// MARK: - WINDOW ACCESSOR POUR macOS

#if os(macOS)
struct WindowAccessor: NSViewRepresentable {
    let callback: (NSWindow?) -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            self.callback(view.window)
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif

#Preview {
    ContentView()
}
