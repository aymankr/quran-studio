import SwiftUI
import AVFoundation

struct WetDryRecordingView: View {
    @StateObject private var wetDryManager = WetDryRecordingManager()
    @ObservedObject var audioManager: AudioManagerCPP
    
    // UI State
    @State private var selectedMode: WetDryRecordingManager.RecordingMode = .mixOnly
    @State private var selectedFormat: String = "wav"
    @State private var showingRecordingSessions = false
    @State private var recordingSessions: [WetDryRecordingManager.RecordingSession] = []
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    
    // Colors
    private let cardColor = Color(red: 0.12, green: 0.12, blue: 0.18)
    private let accentColor = Color.blue
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            headerSection
            
            // Recording mode selection
            recordingModeSection
            
            // Format selection
            formatSelectionSection
            
            // Recording controls
            recordingControlsSection
            
            // Recording status
            if wetDryManager.isRecording {
                recordingStatusSection
            }
            
            // Sessions preview
            sessionsPreviewSection
        }
        .padding(16)
        .background(cardColor.opacity(0.8))
        .cornerRadius(12)
        .onAppear {
            setupWetDryManager()
            loadRecordingSessions()
        }
        .alert("Erreur d'enregistrement", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showingRecordingSessions) {
            WetDrySessionsView(
                sessions: recordingSessions,
                onSessionsChanged: { loadRecordingSessions() }
            )
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("🎛️ Enregistrement Wet/Dry")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Spacer()
                
                Button(action: {
                    showingRecordingSessions = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.fill")
                        Text("\(recordingSessions.count)")
                            .fontWeight(.medium)
                    }
                    .font(.caption)
                    .foregroundColor(accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(accentColor.opacity(0.1))
                    .cornerRadius(6)
                }
            }
            
            Text("Enregistrement séparé des signaux wet et dry pour post-production")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
        }
    }
    
    // MARK: - Recording Mode Section
    private var recordingModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("📡 Mode d'enregistrement")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
            
            VStack(spacing: 8) {
                ForEach(WetDryRecordingManager.RecordingMode.allCases, id: \.self) { mode in
                    recordingModeRow(mode: mode)
                }
            }
        }
    }
    
    @ViewBuilder
    private func recordingModeRow(mode: WetDryRecordingManager.RecordingMode) -> some View {
        Button(action: {
            if !wetDryManager.isRecording {
                selectedMode = mode
            }
        }) {
            HStack(spacing: 12) {
                // Selection indicator
                Image(systemName: selectedMode == mode ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundColor(selectedMode == mode ? accentColor : .white.opacity(0.6))
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(mode.displayName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        // File count indicator
                        HStack(spacing: 4) {
                            Image(systemName: "doc.fill")
                                .font(.caption2)
                            Text("\(mode.fileCount)")
                                .font(.caption2)
                                .fontWeight(.bold)
                        }
                        .foregroundColor(accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(accentColor.opacity(0.15))
                        .cornerRadius(4)
                    }
                    
                    Text(mode.description)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(2)
                }
                
                Spacer()
            }
            .padding(12)
            .background(
                selectedMode == mode ? 
                accentColor.opacity(0.1) : 
                cardColor.opacity(0.6)
            )
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        selectedMode == mode ? accentColor.opacity(0.5) : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .disabled(wetDryManager.isRecording)
        .opacity(wetDryManager.isRecording && selectedMode != mode ? 0.5 : 1.0)
    }
    
    // MARK: - Format Selection Section
    private var formatSelectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("💾 Format de fichier")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
            
            HStack(spacing: 8) {
                ForEach(["wav", "aac", "mp3"], id: \.self) { format in
                    Button(action: {
                        if !wetDryManager.isRecording {
                            selectedFormat = format
                        }
                    }) {
                        VStack(spacing: 4) {
                            Text(format.uppercased())
                                .font(.caption)
                                .fontWeight(.bold)
                            
                            Text(getFormatDescription(format))
                                .font(.caption2)
                                .multilineTextAlignment(.center)
                        }
                        .foregroundColor(selectedFormat == format ? .white : .white.opacity(0.7))
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity)
                        .background(selectedFormat == format ? accentColor : cardColor.opacity(0.6))
                        .cornerRadius(6)
                    }
                    .disabled(wetDryManager.isRecording)
                }
            }
        }
    }
    
    // MARK: - Recording Controls Section
    private var recordingControlsSection: some View {
        HStack(spacing: 12) {
            // Start/Stop button
            Button(action: {
                handleRecordingToggle()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: wetDryManager.isRecording ? "stop.circle.fill" : "record.circle")
                        .font(.title2)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(wetDryManager.isRecording ? "Arrêter" : "Démarrer")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        if !wetDryManager.isRecording {
                            Text(selectedMode.displayName)
                                .font(.caption2)
                                .opacity(0.8)
                        }
                    }
                }
                .foregroundColor(.white)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .background(wetDryManager.isRecording ? Color.red : accentColor)
                .cornerRadius(10)
            }
            .disabled(!canStartRecording)
            .opacity(canStartRecording ? 1.0 : 0.6)
        }
    }
    
    // MARK: - Recording Status Section
    private var recordingStatusSection: some View {
        VStack(spacing: 8) {
            HStack {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .scaleEffect(1.0)
                    .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: wetDryManager.isRecording)
                
                Text("🔴 Enregistrement \(selectedMode.displayName)...")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.red)
                
                Spacer()
                
                Text(formatDuration(wetDryManager.recordingDuration))
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .monospacedDigit()
            }
            
            // Progress indicators for multiple files
            if selectedMode.fileCount > 1 {
                HStack(spacing: 8) {
                    ForEach(getRecordingChannels(), id: \.self) { channel in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(getChannelColor(channel))
                                .frame(width: 6, height: 6)
                            
                            Text(channel.uppercased())
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(getChannelColor(channel).opacity(0.2))
                        .cornerRadius(6)
                    }
                    
                    Spacer()
                }
            }
        }
        .padding(12)
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
    }
    
    // MARK: - Sessions Preview Section
    private var sessionsPreviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("📂 Sessions récentes")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                
                Spacer()
                
                Button("Tout voir") {
                    showingRecordingSessions = true
                }
                .font(.caption)
                .foregroundColor(accentColor)
            }
            
            if recordingSessions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "waveform.path")
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.3))
                    
                    Text("Aucune session wet/dry")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(cardColor.opacity(0.4))
                .cornerRadius(8)
            } else {
                VStack(spacing: 4) {
                    ForEach(recordingSessions.prefix(2), id: \.timestamp) { session in
                        sessionPreviewRow(session: session)
                    }
                    
                    if recordingSessions.count > 2 {
                        Text("... et \(recordingSessions.count - 2) autre(s)")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.6))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(4)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func sessionPreviewRow(session: WetDryRecordingManager.RecordingSession) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.path")
                .font(.caption)
                .foregroundColor(accentColor)
                .frame(width: 16)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(session.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    Text(session.recordingMode.displayName)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                    
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.5))
                    
                    Text("\(session.recordingMode.fileCount) fichier(s)")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            
            Spacer()
            
            HStack(spacing: 4) {
                if session.mixURL != nil {
                    Circle()
                        .fill(Color.purple)
                        .frame(width: 6, height: 6)
                }
                if session.wetURL != nil {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 6, height: 6)
                }
                if session.dryURL != nil {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(cardColor.opacity(0.4))
        .cornerRadius(6)
    }
    
    // MARK: - Helper Methods
    private var canStartRecording: Bool {
        return !wetDryManager.isRecording && audioManager.isMonitoring
    }
    
    private func setupWetDryManager() {
        if let audioEngineService = audioManager.audioEngineService {
            wetDryManager.audioEngineService = audioEngineService
        }
    }
    
    private func handleRecordingToggle() {
        if wetDryManager.isRecording {
            Task {
                do {
                    let results = try await wetDryManager.stopRecording()
                    DispatchQueue.main.async {
                        self.loadRecordingSessions()
                        print("✅ Wet/Dry recording completed with \(results.count) file(s)")
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.errorMessage = error.localizedDescription
                        self.showingErrorAlert = true
                    }
                }
            }
        } else {
            Task {
                do {
                    let urls = try await wetDryManager.startRecording(mode: selectedMode, format: selectedFormat)
                    print("✅ Wet/Dry recording started with \(urls.count) file(s)")
                } catch {
                    DispatchQueue.main.async {
                        self.errorMessage = error.localizedDescription
                        self.showingErrorAlert = true
                    }
                }
            }
        }
    }
    
    private func loadRecordingSessions() {
        recordingSessions = wetDryManager.getRecordingSessions()
    }
    
    private func getFormatDescription(_ format: String) -> String {
        switch format {
        case "wav": return "Non compressé\nQualité studio"
        case "aac": return "Compressé\nBonne qualité"
        case "mp3": return "Compressé\nCompatible"
        default: return ""
        }
    }
    
    private func getRecordingChannels() -> [String] {
        switch selectedMode {
        case .mixOnly: return ["mix"]
        case .wetOnly: return ["wet"]
        case .dryOnly: return ["dry"]
        case .wetDrySeparate: return ["wet", "dry"]
        case .all: return ["mix", "wet", "dry"]
        }
    }
    
    private func getChannelColor(_ channel: String) -> Color {
        switch channel {
        case "mix": return .purple
        case "wet": return .blue
        case "dry": return .green
        default: return .gray
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Sessions List View
struct WetDrySessionsView: View {
    let sessions: [WetDryRecordingManager.RecordingSession]
    let onSessionsChanged: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var sessionToDelete: WetDryRecordingManager.RecordingSession?
    @State private var showDeleteAlert = false
    
    private let cardColor = Color(red: 0.12, green: 0.12, blue: 0.18)
    private let accentColor = Color.blue
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if sessions.isEmpty {
                    emptyStateView
                } else {
                    sessionsListView
                }
            }
            .navigationTitle("🎛️ Sessions Wet/Dry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Fermer") {
                        dismiss()
                    }
                }
            }
        }
        .alert("Supprimer la session", isPresented: $showDeleteAlert) {
            Button("Supprimer", role: .destructive) {
                deleteSelectedSession()
            }
            Button("Annuler", role: .cancel) {}
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.path")
                .font(.system(size: 60))
                .foregroundColor(.white.opacity(0.3))
            
            Text("Aucune session wet/dry")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundColor(.white)
            
            Text("Vos enregistrements wet/dry apparaîtront ici")
                .font(.body)
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var sessionsListView: some View {
        List {
            ForEach(sessions, id: \.timestamp) { session in
                sessionRowView(session: session)
                    .listRowBackground(cardColor.opacity(0.6))
            }
        }
        .listStyle(PlainListStyle())
    }
    
    @ViewBuilder
    private func sessionRowView(session: WetDryRecordingManager.RecordingSession) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.path")
                .font(.title3)
                .foregroundColor(accentColor)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(session.displayName)
                    .font(.headline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                
                HStack(spacing: 8) {
                    Text(session.recordingMode.displayName)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                    
                    Text("•")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                    
                    Text("\(session.recordingMode.fileCount) fichier(s)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
                
                // File indicators
                HStack(spacing: 8) {
                    if session.mixURL != nil {
                        fileIndicator(name: "MIX", color: .purple)
                    }
                    if session.wetURL != nil {
                        fileIndicator(name: "WET", color: .blue)
                    }
                    if session.dryURL != nil {
                        fileIndicator(name: "DRY", color: .green)
                    }
                }
            }
            
            Spacer()
            
            Button(action: {
                sessionToDelete = session
                showDeleteAlert = true
            }) {
                Image(systemName: "trash")
                    .font(.body)
                    .foregroundColor(.red)
            }
        }
        .padding(.vertical, 4)
    }
    
    @ViewBuilder
    private func fileIndicator(name: String, color: Color) -> some View {
        Text(name)
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color)
            .cornerRadius(4)
    }
    
    private func deleteSelectedSession() {
        guard let session = sessionToDelete else { return }
        
        // Delete all files in the session
        let urls = [session.mixURL, session.wetURL, session.dryURL].compactMap { $0 }
        
        for url in urls {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                print("❌ Error deleting file: \(error)")
            }
        }
        
        onSessionsChanged()
        sessionToDelete = nil
    }
}

#Preview {
    WetDryRecordingView(audioManager: AudioManagerCPP.shared)
        .preferredColorScheme(.dark)
}