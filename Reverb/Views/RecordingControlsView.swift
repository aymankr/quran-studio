import SwiftUI
import AVFoundation

struct RecordingControlsView: View {
    @StateObject private var recordingManager = RecordingSessionManager()
    @ObservedObject var audioManager: AudioManagerCPP
    
    // State management
    @State private var selectedFormat: RecordingSessionManager.RecordingFormat = .wav
    @State private var showingFormatPicker = false
    @State private var showingRecordingsList = false
    @State private var showingPermissionAlert = false
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    
    // Recording state
    @State private var recordings: [URL] = []
    @State private var recordingToDelete: URL?
    @State private var showDeleteAlert = false
    
    private let cardColor = Color(red: 0.12, green: 0.12, blue: 0.18)
    private let accentColor = Color.blue
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            headerSection
            
            // Recording controls
            recordingControlsSection
            
            // Recording status
            if recordingManager.isRecordingActive {
                recordingStatusSection
            }
            
            // Format selection
            formatSelectionSection
            
            // Recordings list
            recordingsListSection
        }
        .padding(16)
        .background(cardColor.opacity(0.8))
        .cornerRadius(12)
        .onAppear {
            setupRecordingManager()
            loadRecordings()
        }
        .alert("Permissions requises", isPresented: $showingPermissionAlert) {
            Button("Paramètres") {
                openSystemPreferences()
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("L'accès au microphone est requis pour l'enregistrement. Veuillez l'autoriser dans les Paramètres Système.")
        }
        .alert("Erreur d'enregistrement", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .alert("Supprimer l'enregistrement", isPresented: $showDeleteAlert) {
            Button("Supprimer", role: .destructive) {
                deleteSelectedRecording()
            }
            Button("Annuler", role: .cancel) {}
        }
        .sheet(isPresented: $showingRecordingsList) {
            RecordingsListView(
                recordings: recordings,
                recordingManager: recordingManager,
                onRecordingsChanged: { loadRecordings() }
            )
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("🎙️ Enregistrement Avancé")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text("Contrôles et gestion des sessions")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Spacer()
            
            // Permission status indicator
            permissionStatusIndicator
        }
    }
    
    private var permissionStatusIndicator: some View {
        HStack(spacing: 4) {
            Image(systemName: permissionStatusIcon)
                .font(.caption)
                .foregroundColor(permissionStatusColor)
            
            Text(permissionStatusText)
                .font(.caption2)
                .foregroundColor(permissionStatusColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(permissionStatusColor.opacity(0.1))
        .cornerRadius(6)
    }
    
    private var permissionStatusIcon: String {
        switch recordingManager.recordingPermissionStatus {
        case .granted: return "checkmark.circle.fill"
        case .denied: return "xmark.circle.fill"
        case .restricted: return "exclamationmark.triangle.fill"
        case .notDetermined: return "questionmark.circle.fill"
        }
    }
    
    private var permissionStatusColor: Color {
        switch recordingManager.recordingPermissionStatus {
        case .granted: return .green
        case .denied: return .red
        case .restricted: return .orange
        case .notDetermined: return .yellow
        }
    }
    
    private var permissionStatusText: String {
        switch recordingManager.recordingPermissionStatus {
        case .granted: return "Autorisé"
        case .denied: return "Refusé"
        case .restricted: return "Restreint"
        case .notDetermined: return "Non défini"
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
                    Image(systemName: recordingManager.isRecordingActive ? "stop.circle.fill" : "record.circle")
                        .font(.title2)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(recordingManager.isRecordingActive ? "Arrêter" : "Démarrer")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        if !recordingManager.isRecordingActive {
                            Text("Format: \(selectedFormat.displayName)")
                                .font(.caption2)
                                .opacity(0.8)
                        }
                    }
                }
                .foregroundColor(.white)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .background(recordingManager.isRecordingActive ? Color.red : accentColor)
                .cornerRadius(10)
            }
            .disabled(!canStartRecording)
            .opacity(canStartRecording ? 1.0 : 0.6)
            
            // Cancel button (only shown when recording)
            if recordingManager.isRecordingActive {
                Button(action: {
                    handleRecordingCancel()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .padding(12)
                        .background(Color.gray)
                        .cornerRadius(10)
                }
            }
            
            // Recordings list button
            Button(action: {
                showingRecordingsList = true
            }) {
                VStack(spacing: 4) {
                    Image(systemName: "list.bullet")
                        .font(.title3)
                    Text("\(recordings.count)")
                        .font(.caption2)
                        .fontWeight(.medium)
                }
                .foregroundColor(.white)
                .padding(12)
                .background(Color.gray.opacity(0.6))
                .cornerRadius(10)
            }
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
                    .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: recordingManager.isRecordingActive)
                
                Text("🔴 Enregistrement en cours...")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.red)
                
                Spacer()
                
                Text(formatDuration(recordingManager.recordingDuration))
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .monospacedDigit()
            }
            
            if let recordingURL = recordingManager.currentRecordingURL {
                HStack {
                    Text("📁")
                    Text(recordingURL.lastPathComponent)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    Spacer()
                    
                    Text("Format: \(recordingManager.recordingFormat.rawValue.uppercased())")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
        }
        .padding(12)
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
    }
    
    // MARK: - Format Selection Section
    private var formatSelectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("📼 Format d'enregistrement")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
            
            HStack(spacing: 8) {
                ForEach(RecordingSessionManager.RecordingFormat.allCases, id: \.self) { format in
                    Button(action: {
                        selectedFormat = format
                    }) {
                        VStack(spacing: 4) {
                            Text(format.rawValue.uppercased())
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
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(selectedFormat == format ? .white.opacity(0.3) : .clear, lineWidth: 1)
                        )
                    }
                    .disabled(recordingManager.isRecordingActive)
                }
            }
        }
    }
    
    // MARK: - Recordings List Section
    private var recordingsListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("📂 Enregistrements récents")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                
                Spacer()
                
                Button("Tout voir") {
                    showingRecordingsList = true
                }
                .font(.caption)
                .foregroundColor(accentColor)
            }
            
            if recordings.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "waveform.circle")
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.3))
                    
                    Text("Aucun enregistrement")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(cardColor.opacity(0.4))
                .cornerRadius(8)
            } else {
                VStack(spacing: 4) {
                    ForEach(recordings.prefix(3), id: \.self) { recording in
                        compactRecordingRow(recording: recording)
                    }
                    
                    if recordings.count > 3 {
                        Text("... et \(recordings.count - 3) autre(s)")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.6))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(4)
                    }
                }
            }
        }
    }
    
    // MARK: - Compact Recording Row
    @ViewBuilder
    private func compactRecordingRow(recording: URL) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.caption)
                .foregroundColor(accentColor)
                .frame(width: 16)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(getDisplayName(recording))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    if let info = recordingManager.getRecordingInfo(for: recording) {
                        Text(formatDuration(info.duration))
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.7))
                        
                        Text("•")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.5))
                        
                        Text(recordingManager.formatFileSize(info.fileSize))
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
            
            Spacer()
            
            Button(action: {
                recordingToDelete = recording
                showDeleteAlert = true
            }) {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundColor(.red.opacity(0.8))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(cardColor.opacity(0.4))
        .cornerRadius(6)
    }
    
    // MARK: - Helper Methods
    private var canStartRecording: Bool {
        return !recordingManager.isRecordingActive && 
               recordingManager.recordingPermissionStatus == .granted && 
               audioManager.isMonitoring
    }
    
    private func setupRecordingManager() {
        // Connect to AudioEngineService if available
        if let audioEngineService = audioManager.audioEngineService {
            recordingManager.audioEngineService = audioEngineService
        }
    }
    
    private func handleRecordingToggle() {
        if recordingManager.isRecordingActive {
            Task {
                do {
                    let result = try await recordingManager.stopRecording()
                    DispatchQueue.main.async {
                        self.loadRecordings()
                        print("✅ Recording completed: \(result.url.lastPathComponent)")
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.errorMessage = error.localizedDescription
                        self.showingErrorAlert = true
                    }
                }
            }
        } else {
            if recordingManager.recordingPermissionStatus != .granted {
                showingPermissionAlert = true
                return
            }
            
            Task {
                do {
                    let recordingURL = try await recordingManager.startRecording(withFormat: selectedFormat)
                    print("✅ Recording started: \(recordingURL.lastPathComponent)")
                } catch {
                    DispatchQueue.main.async {
                        self.errorMessage = error.localizedDescription
                        self.showingErrorAlert = true
                    }
                }
            }
        }
    }
    
    private func handleRecordingCancel() {
        Task {
            do {
                try await recordingManager.cancelRecording()
                print("✅ Recording cancelled")
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.showingErrorAlert = true
                }
            }
        }
    }
    
    private func loadRecordings() {
        recordings = recordingManager.getAllRecordings()
    }
    
    private func deleteSelectedRecording() {
        guard let recording = recordingToDelete else { return }
        
        do {
            try recordingManager.deleteRecording(at: recording)
            loadRecordings()
        } catch {
            errorMessage = error.localizedDescription
            showingErrorAlert = true
        }
        
        recordingToDelete = nil
    }
    
    private func openSystemPreferences() {
        #if os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }
    
    private func getFormatDescription(_ format: RecordingSessionManager.RecordingFormat) -> String {
        switch format {
        case .wav: return "Non compressé\nQualité studio"
        case .aac: return "Compressé\nBonne qualité"
        case .mp3: return "Compressé\nCompatible"
        }
    }
    
    private func getDisplayName(_ recording: URL) -> String {
        let name = recording.deletingPathExtension().lastPathComponent
        return name.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "reverb recording", with: "Reverb")
            .capitalized
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Recordings List View
struct RecordingsListView: View {
    let recordings: [URL]
    let recordingManager: RecordingSessionManager
    let onRecordingsChanged: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var recordingToDelete: URL?
    @State private var showDeleteAlert = false
    
    private let cardColor = Color(red: 0.12, green: 0.12, blue: 0.18)
    private let accentColor = Color.blue
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if recordings.isEmpty {
                    emptyStateView
                } else {
                    recordingsListView
                }
            }
            .navigationTitle("📂 Enregistrements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Fermer") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Dossier") {
                        recordingManager.openRecordingDirectory()
                    }
                }
            }
        }
        .alert("Supprimer l'enregistrement", isPresented: $showDeleteAlert) {
            Button("Supprimer", role: .destructive) {
                deleteSelectedRecording()
            }
            Button("Annuler", role: .cancel) {}
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 60))
                .foregroundColor(.white.opacity(0.3))
            
            Text("Aucun enregistrement")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundColor(.white)
            
            Text("Vos enregistrements apparaîtront ici")
                .font(.body)
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var recordingsListView: some View {
        List {
            ForEach(recordings, id: \.self) { recording in
                recordingRowView(recording: recording)
                    .listRowBackground(cardColor.opacity(0.6))
            }
        }
        .listStyle(PlainListStyle())
    }
    
    @ViewBuilder
    private func recordingRowView(recording: URL) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.title3)
                .foregroundColor(accentColor)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(getDisplayName(recording))
                    .font(.headline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                
                if let info = recordingManager.getRecordingInfo(for: recording) {
                    HStack(spacing: 8) {
                        Text(formatDuration(info.duration))
                        Text("•")
                        Text(recordingManager.formatFileSize(info.fileSize))
                        Text("•")
                        Text(recording.pathExtension.uppercased())
                    }
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                }
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                #if os(macOS)
                Button(action: {
                    recordingManager.revealRecordingInFinder(at: recording)
                }) {
                    Image(systemName: "folder")
                        .font(.body)
                        .foregroundColor(.blue)
                }
                #endif
                
                Button(action: {
                    recordingToDelete = recording
                    showDeleteAlert = true
                }) {
                    Image(systemName: "trash")
                        .font(.body)
                        .foregroundColor(.red)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func deleteSelectedRecording() {
        guard let recording = recordingToDelete else { return }
        
        do {
            try recordingManager.deleteRecording(at: recording)
            onRecordingsChanged()
        } catch {
            print("❌ Error deleting recording: \(error)")
        }
        
        recordingToDelete = nil
    }
    
    private func getDisplayName(_ recording: URL) -> String {
        let name = recording.deletingPathExtension().lastPathComponent
        return name.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "reverb recording", with: "Reverb")
            .capitalized
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    RecordingControlsView(audioManager: AudioManagerCPP.shared)
        .preferredColorScheme(.dark)
}