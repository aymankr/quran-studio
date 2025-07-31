import SwiftUI

/// Compact iOS views for WetDry, Offline, and Batch processing
/// Optimized for mobile screen constraints and touch interactions
@available(iOS 14.0, *)

// MARK: - iOS Wet/Dry View
struct iOSWetDryView: View {
    @ObservedObject var audioManager: AudioManagerCPP
    @State private var selectedMode: WetDryMode = .mixOnly
    @State private var isRecording = false
    @State private var recordingDuration: TimeInterval = 0
    @State private var recordingTimer: Timer?
    
    enum WetDryMode: String, CaseIterable {
        case mixOnly = "mix"
        case wetOnly = "wet"
        case dryOnly = "dry"
        case wetDrySeparate = "wetdry"
        case all = "all"
        
        var title: String {
            switch self {
            case .mixOnly: return "Mix Seul"
            case .wetOnly: return "Wet Seul"
            case .dryOnly: return "Dry Seul"
            case .wetDrySeparate: return "Wet + Dry"
            case .all: return "Tout (3 fichiers)"
            }
        }
        
        var icon: String {
            switch self {
            case .mixOnly: return "waveform.circle"
            case .wetOnly: return "drop.circle"
            case .dryOnly: return "circle"
            case .wetDrySeparate: return "rectangle.split.2x1"
            case .all: return "rectangle.split.3x1"
            }
        }
        
        var description: String {
            switch self {
            case .mixOnly: return "Signal mixé wet/dry"
            case .wetOnly: return "Signal reverb uniquement"
            case .dryOnly: return "Signal direct uniquement"
            case .wetDrySeparate: return "Fichiers séparés wet/dry"
            case .all: return "Mix + Wet + Dry séparés"
            }
        }
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                // Recording status
                recordingStatusSection
                
                // Mode selection
                modeSelectionSection
                
                // Recording controls
                recordingControlsSection
                
                // Recent recordings
                recentRecordingsSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .background(Color(.systemBackground))
    }
    
    private var recordingStatusSection: some View {
        VStack(spacing: 12) {
            HStack {
                Circle()
                    .fill(isRecording ? .red : .gray)
                    .frame(width: 12, height: 12)
                    .scaleEffect(isRecording ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isRecording)
                
                Text(isRecording ? "Enregistrement en cours" : "Prêt à enregistrer")
                    .font(.headline)
                    .fontWeight(.medium)
                
                Spacer()
                
                if isRecording {
                    Text(formatDuration(recordingDuration))
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                        .monospacedDigit()
                }
            }
            
            if isRecording {
                // Simple waveform visualization
                HStack(spacing: 2) {
                    ForEach(0..<20, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.blue)
                            .frame(width: 3, height: CGFloat.random(in: 4...20))
                            .animation(.easeInOut(duration: 0.3).repeatForever(autoreverses: true), value: isRecording)
                    }
                }
                .frame(height: 24)
            }
        }
        .padding(16)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var modeSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("🎯 Mode d'Enregistrement")
                .font(.headline)
                .fontWeight(.semibold)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 12) {
                ForEach(WetDryMode.allCases, id: \.self) { mode in
                    modeButton(mode)
                }
            }
        }
        .padding(16)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private func modeButton(_ mode: WetDryMode) -> some View {
        Button(action: {
            selectedMode = mode
            // Haptic feedback
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
        }) {
            VStack(spacing: 8) {
                Image(systemName: mode.icon)
                    .font(.title2)
                    .foregroundColor(selectedMode == mode ? .white : .blue)
                
                Text(mode.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                
                Text(mode.description)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .foregroundColor(selectedMode == mode ? .white : .primary)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 80)
            .background(selectedMode == mode ? Color.blue : Color(.systemBackground))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isRecording)
    }
    
    private var recordingControlsSection: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                // Record button
                Button(action: {
                    toggleRecording()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: isRecording ? "stop.circle.fill" : "record.circle.fill")
                            .font(.title2)
                        
                        Text(isRecording ? "Arrêter" : "Enregistrer")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    .background(isRecording ? Color.red : Color.blue)
                    .cornerRadius(10)
                }
                
                // Pause button (if recording)
                if isRecording {
                    Button(action: {
                        // Pause functionality
                    }) {
                        Image(systemName: "pause.circle.fill")
                            .font(.title)
                            .foregroundColor(.orange)
                            .padding(12)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(10)
                    }
                }
            }
            
            // Format and quality settings
            if !isRecording {
                VStack(spacing: 8) {
                    Text("Format: WAV 24-bit • Qualité: 48kHz")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Mode: \(selectedMode.title)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(16)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var recentRecordingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("📁 Enregistrements Récents")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Tout voir") {
                    // Show all recordings
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            
            // Placeholder for recent recordings
            VStack(spacing: 8) {
                recordingItem(name: "vocal_wet_dry_001.wav", duration: "2:34", date: "Il y a 5 min")
                recordingItem(name: "session_mix_002.wav", duration: "1:47", date: "Il y a 12 min")
                recordingItem(name: "test_all_003.wav", duration: "0:23", date: "Il y a 1h")
            }
        }
        .padding(16)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private func recordingItem(name: String, duration: String, date: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.circle.fill")
                .font(.title3)
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                HStack {
                    Text(duration)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                    
                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Button(action: {
                // Share or export
            }) {
                Image(systemName: "square.and.arrow.up")
                    .font(.subheadline)
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemBackground))
        .cornerRadius(6)
    }
    
    private func toggleRecording() {
        isRecording.toggle()
        
        if isRecording {
            startRecordingTimer()
        } else {
            stopRecordingTimer()
        }
        
        // Heavy haptic feedback for record start/stop
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.impactOccurred()
    }
    
    private func startRecordingTimer() {
        recordingDuration = 0
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            recordingDuration += 1
        }
    }
    
    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingDuration = 0
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - iOS Offline View
struct iOSOfflineView: View {
    @ObservedObject var audioManager: AudioManagerCPP
    @State private var selectedFile: URL?
    @State private var showingFilePicker = false
    @State private var processingProgress: Double = 0.0
    @State private var isProcessing = false
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                // File selection
                fileSelectionSection
                
                // Processing options
                if selectedFile != nil {
                    processingOptionsSection
                    
                    // Process button
                    processButtonSection
                }
                
                // Progress
                if isProcessing {
                    progressSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .background(Color(.systemBackground))
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            handleFileSelection(result)
        }
    }
    
    private var fileSelectionSection: some View {
        VStack(spacing: 12) {
            if let file = selectedFile {
                // Selected file display
                HStack(spacing: 12) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.lastPathComponent)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        
                        Text("Prêt pour traitement offline")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("Changer") {
                        showingFilePicker = true
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
                .padding(16)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            } else {
                // File picker button
                Button(action: {
                    showingFilePicker = true
                }) {
                    VStack(spacing: 12) {
                        Image(systemName: "plus.circle.dashed")
                            .font(.system(size: 40))
                            .foregroundColor(.blue.opacity(0.6))
                        
                        Text("Sélectionner un Fichier Audio")
                            .font(.headline)
                            .fontWeight(.medium)
                        
                        Text("WAV, AIFF, CAF, MP3, M4A")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.blue.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5]))
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
    
    private var processingOptionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("⚙️ Options de Traitement")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 8) {
                optionRow(title: "Mode", value: "Wet + Dry Séparés")
                optionRow(title: "Preset", value: "Studio")
                optionRow(title: "Format", value: "WAV 24-bit")
                optionRow(title: "Qualité", value: "48kHz Stéréo")
            }
        }
        .padding(16)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private func optionRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.blue)
        }
        .padding(.vertical, 4)
    }
    
    private var processButtonSection: some View {
        Button(action: {
            startProcessing()
        }) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.circle.fill")
                    .font(.title3)
                
                Text("Traiter Offline")
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(Color.blue)
            .cornerRadius(12)
        }
        .disabled(isProcessing)
    }
    
    private var progressSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("⚡ Traitement en cours...")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
                
                Spacer()
                
                Text("\(Int(processingProgress * 100))%")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
                    .monospacedDigit()
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: geometry.size.width * processingProgress, height: 8)
                        .animation(.easeInOut(duration: 0.3), value: processingProgress)
                }
            }
            .frame(height: 8)
        }
        .padding(16)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
    }
    
    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            selectedFile = urls.first
        case .failure:
            break
        }
    }
    
    private func startProcessing() {
        isProcessing = true
        processingProgress = 0.0
        
        // Simulate processing
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            processingProgress += 0.02
            
            if processingProgress >= 1.0 {
                timer.invalidate()
                isProcessing = false
                processingProgress = 0.0
            }
        }
    }
}

// MARK: - iOS Batch View
struct iOSBatchView: View {
    @ObservedObject var audioManager: AudioManagerCPP
    @State private var selectedFiles: [URL] = []
    @State private var showingFilePicker = false
    @State private var batchProgress: Double = 0.0
    @State private var isProcessing = false
    @State private var currentFileIndex = 0
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                // Batch status
                batchStatusSection
                
                // File queue
                fileQueueSection
                
                // Batch controls
                if !selectedFiles.isEmpty {
                    batchControlsSection
                }
                
                // Progress
                if isProcessing {
                    batchProgressSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .background(Color(.systemBackground))
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            handleFilesSelection(result)
        }
    }
    
    private var batchStatusSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("📊 Traitement par Lot")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("\(selectedFiles.count) fichier(s)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
            }
            
            if selectedFiles.isEmpty {
                Button(action: {
                    showingFilePicker = true
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                        Text("Ajouter des Fichiers")
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .cornerRadius(8)
                }
            }
        }
        .padding(16)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var fileQueueSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !selectedFiles.isEmpty {
                HStack {
                    Text("📋 File d'Attente")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Button("Ajouter") {
                        showingFilePicker = true
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
                
                ForEach(Array(selectedFiles.enumerated()), id: \.element) { index, file in
                    fileQueueItem(file: file, index: index)
                }
            }
        }
        .padding(16)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private func fileQueueItem(file: URL, index: Int) -> some View {
        HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Color.blue)
                .cornerRadius(10)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(file.lastPathComponent)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                Text("En attente")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: {
                selectedFiles.remove(at: index)
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.subheadline)
                    .foregroundColor(.red)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemBackground))  
        .cornerRadius(6)
    }
    
    private var batchControlsSection: some View {
        Button(action: {
            startBatchProcessing()
        }) {
            HStack(spacing: 8) {
                Image(systemName: "play.circle.fill")
                    .font(.title3)
                
                Text("Traiter le Lot")
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(Color.blue)
            .cornerRadius(12)
        }
        .disabled(isProcessing)
    }
    
    private var batchProgressSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("⚡ Traitement du lot...")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
                
                Spacer()
                
                Text("\(currentFileIndex)/\(selectedFiles.count)")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
                    .monospacedDigit()
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: geometry.size.width * batchProgress, height: 8)
                        .animation(.easeInOut(duration: 0.3), value: batchProgress)
                }
            }
            .frame(height: 8)
            
            if currentFileIndex > 0 && currentFileIndex <= selectedFiles.count {
                Text("Fichier: \(selectedFiles[currentFileIndex - 1].lastPathComponent)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(16)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
    }
    
    private func handleFilesSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            selectedFiles.append(contentsOf: urls)
        case .failure:
            break
        }
    }
    
    private func startBatchProcessing() {
        isProcessing = true
        batchProgress = 0.0
        currentFileIndex = 0
        
        // Simulate batch processing
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            currentFileIndex += 1
            batchProgress = Double(currentFileIndex) / Double(selectedFiles.count)
            
            if currentFileIndex >= selectedFiles.count {
                timer.invalidate()
                isProcessing = false
                batchProgress = 0.0
                currentFileIndex = 0
            }
        }
    }
}

#if DEBUG
#Preview("WetDry") {
    iOSWetDryView(audioManager: AudioManagerCPP.shared)
        .preferredColorScheme(.dark)
}

#Preview("Offline") {
    iOSOfflineView(audioManager: AudioManagerCPP.shared)
        .preferredColorScheme(.dark)
}

#Preview("Batch") {
    iOSBatchView(audioManager: AudioManagerCPP.shared)
        .preferredColorScheme(.dark)
}
#endif