import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

struct OfflineProcessingView: View {
    @StateObject private var processor = OfflineReverbProcessor()
    @ObservedObject var audioManager: AudioManagerCPP
    
    // UI State
    @State private var selectedInputFile: URL?
    @State private var processingSettings = OfflineReverbProcessor.ProcessingSettings()
    @State private var showingFilePicker = false
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    @State private var showingSuccessAlert = false
    @State private var processedFiles: [String: URL] = [:]
    @State private var estimatedTime: TimeInterval?
    
    // Colors
    private let cardColor = Color(red: 0.12, green: 0.12, blue: 0.18)
    private let accentColor = Color.blue
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            headerSection
            
            // File selection
            fileSelectionSection
            
            // Processing settings
            if selectedInputFile != nil {
                processingSettingsSection
                
                // Processing controls
                processingControlsSection
                
                // Progress section
                if processor.isProcessing {
                    progressSection
                }
            }
            
            // Results section
            if !processedFiles.isEmpty && !processor.isProcessing {
                resultsSection
            }
        }
        .padding(16)
        .background(cardColor.opacity(0.8))
        .cornerRadius(12)
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            handleFileSelection(result)
        }
        .alert("Erreur de traitement", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .alert("Traitement terminé", isPresented: $showingSuccessAlert) {
            Button("OK", role: .cancel) {}
            Button("Ouvrir dossier") {
                openOutputDirectory()
            }
        } message: {
            Text("Le traitement offline est terminé avec succès !")
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("⚡ Traitement Offline")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Spacer()
                
                // Speed indicator
                if processor.isProcessing {
                    HStack(spacing: 4) {
                        Image(systemName: "speedometer")
                            .font(.caption)
                        Text(String(format: "%.1fx", processor.processingSpeed))
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(6)
                }
            }
            
            Text("Traitement non temps réel inspiré du AD 480 - plus rapide que temps réel")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
        }
    }
    
    // MARK: - File Selection Section
    private var fileSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("📂 Fichier audio à traiter")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
            
            if let inputFile = selectedInputFile {
                selectedFileView(inputFile)
            } else {
                emptyFileSelectionView
            }
        }
    }
    
    @ViewBuilder
    private func selectedFileView(_ url: URL) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.title2)
                .foregroundColor(accentColor)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(url.lastPathComponent)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    if let info = getFileInfo(url) {
                        Text(formatDuration(info.duration))
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                        
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                        
                        Text("\(info.sampleRate, specifier: "%.0f") Hz")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                        
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                        
                        Text("\(info.channels) ch")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                
                if let estimatedTime = estimatedTime {
                    Text("Temps estimé: \(formatDuration(estimatedTime))")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }
            
            Spacer()
            
            Button("Changer") {
                showingFilePicker = true
            }
            .font(.caption)
            .foregroundColor(accentColor)
        }
        .padding(12)
        .background(cardColor.opacity(0.6))
        .cornerRadius(8)
    }
    
    private var emptyFileSelectionView: some View {
        Button(action: {
            showingFilePicker = true
        }) {
            VStack(spacing: 8) {
                Image(systemName: "plus.circle.dashed")
                    .font(.system(size: 40))
                    .foregroundColor(.white.opacity(0.4))
                
                Text("Sélectionner un fichier audio")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                
                Text("Formats supportés: WAV, AIFF, CAF, MP3, M4A, AAC")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
            .padding(24)
            .background(cardColor.opacity(0.4))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.white.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [5]))
            )
        }
    }
    
    // MARK: - Processing Settings Section
    private var processingSettingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("⚙️ Paramètres de traitement")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
            
            // Processing mode
            VStack(alignment: .leading, spacing: 8) {
                Text("Mode de traitement")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white.opacity(0.8))
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                    ForEach(OfflineReverbProcessor.ProcessingMode.allCases, id: \.self) { mode in
                        processingModeButton(mode)
                    }
                }
            }
            
            // Reverb preset
            VStack(alignment: .leading, spacing: 8) {
                Text("Preset de réverbération")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white.opacity(0.8))
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 6) {
                    ForEach(ReverbPreset.allCases, id: \.self) { preset in
                        reverbPresetButton(preset)
                    }
                }
            }
            
            // Wet/Dry mix (if applicable)
            if processingSettings.mode == .mixOnly {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Mix Wet/Dry")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.white.opacity(0.8))
                        
                        Spacer()
                        
                        Text("\(Int(processingSettings.wetDryMix * 100))%")
                            .font(.caption)
                            .foregroundColor(accentColor)
                            .monospacedDigit()
                    }
                    
                    Slider(value: $processingSettings.wetDryMix, in: 0...1)
                        .accentColor(accentColor)
                }
            }
            
            // Output format
            VStack(alignment: .leading, spacing: 8) {
                Text("Format de sortie")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white.opacity(0.8))
                
                HStack(spacing: 8) {
                    ForEach(OfflineReverbProcessor.OutputFormat.allCases, id: \.self) { format in
                        outputFormatButton(format)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func processingModeButton(_ mode: OfflineReverbProcessor.ProcessingMode) -> some View {
        Button(action: {
            processingSettings.mode = mode
        }) {
            VStack(spacing: 4) {
                Text(mode.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                
                Text(mode.description)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .foregroundColor(processingSettings.mode == mode ? .white : .white.opacity(0.7))
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(processingSettings.mode == mode ? accentColor : cardColor.opacity(0.6))
            .cornerRadius(6)
        }
        .disabled(processor.isProcessing)
    }
    
    @ViewBuilder
    private func reverbPresetButton(_ preset: ReverbPreset) -> some View {
        Button(action: {
            processingSettings.reverbPreset = preset
        }) {
            VStack(spacing: 2) {
                Text(getPresetEmoji(preset))
                    .font(.body)
                
                Text(getPresetName(preset))
                    .font(.caption2)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
            }
            .foregroundColor(processingSettings.reverbPreset == preset ? .white : .white.opacity(0.7))
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(processingSettings.reverbPreset == preset ? accentColor : cardColor.opacity(0.6))
            .cornerRadius(6)
        }
        .disabled(processor.isProcessing)
    }
    
    @ViewBuilder
    private func outputFormatButton(_ format: OfflineReverbProcessor.OutputFormat) -> some View {
        Button(action: {
            processingSettings.outputFormat = format
        }) {
            Text(format.displayName)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(processingSettings.outputFormat == format ? .white : .white.opacity(0.7))
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(processingSettings.outputFormat == format ? accentColor : cardColor.opacity(0.6))
                .cornerRadius(6)
        }
        .disabled(processor.isProcessing)
    }
    
    // MARK: - Processing Controls Section
    private var processingControlsSection: some View {
        HStack(spacing: 12) {
            Button(action: {
                startProcessing()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.circle.fill")
                        .font(.title3)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Traiter Offline")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        Text("Plus rapide que temps réel")
                            .font(.caption2)
                            .opacity(0.8)
                    }
                }
                .foregroundColor(.white)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .background(accentColor)
                .cornerRadius(10)
            }
            .disabled(processor.isProcessing || selectedInputFile == nil)
            
            if processor.isProcessing {
                Button(action: {
                    processor.cancelProcessing()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .padding(12)
                        .background(Color.red)
                        .cornerRadius(10)
                }
            }
        }
    }
    
    // MARK: - Progress Section
    private var progressSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("⚡ Traitement en cours...")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
                
                Spacer()
                
                Text(processor.progressDescription)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                    .monospacedDigit()
            }
            
            // Progress bar
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
                        .frame(width: geometry.size.width * processor.processingProgress, height: 8)
                        .animation(.easeInOut(duration: 0.3), value: processor.processingProgress)
                }
            }
            .frame(height: 8)
            
            if !processor.currentFile.isEmpty {
                Text("Fichier: \(processor.currentFile)")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(12)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
    }
    
    // MARK: - Results Section
    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("✅ Fichiers traités")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                
                Spacer()
                
                Button("Nouveau traitement") {
                    resetProcessing()
                }
                .font(.caption)
                .foregroundColor(accentColor)
            }
            
            VStack(spacing: 6) {
                ForEach(Array(processedFiles.keys), id: \.self) { key in
                    if let url = processedFiles[key] {
                        processedFileRow(key: key, url: url)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.green.opacity(0.1))
        .cornerRadius(8)
    }
    
    @ViewBuilder
    private func processedFileRow(key: String, url: URL) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(getChannelColor(key))
                .frame(width: 8, height: 8)
            
            Text(key.uppercased())
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 30, alignment: .leading)
            
            Text(url.lastPathComponent)
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(1)
                .truncationMode(.middle)
            
            Spacer()
            
            Button(action: {
                shareFile(url)
            }) {
                Image(systemName: "square.and.arrow.up")
                    .font(.caption)
                    .foregroundColor(accentColor)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(cardColor.opacity(0.4))
        .cornerRadius(4)
    }
    
    // MARK: - Helper Methods
    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                selectedInputFile = url
                estimatedTime = processor.estimateProcessingTime(for: url)
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
            showingErrorAlert = true
        }
    }
    
    private func startProcessing() {
        guard let inputFile = selectedInputFile else { return }
        
        let outputDirectory = getOutputDirectory()
        
        Task {
            do {
                let results = try await processor.processAudioFile(
                    inputURL: inputFile,
                    outputDirectory: outputDirectory,
                    settings: processingSettings
                )
                
                DispatchQueue.main.async {
                    self.processedFiles = results
                    self.showingSuccessAlert = true
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.showingErrorAlert = true
                }
            }
        }
    }
    
    private func resetProcessing() {
        selectedInputFile = nil
        processedFiles.removeAll()
        estimatedTime = nil
        processingSettings = OfflineReverbProcessor.ProcessingSettings()
    }
    
    private func getOutputDirectory() -> URL {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let outputDir = documentsDir.appendingPathComponent("OfflineProcessing", isDirectory: true)
        
        if !FileManager.default.fileExists(atPath: outputDir.path) {
            try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        }
        
        return outputDir
    }
    
    private func openOutputDirectory() {
        #if os(macOS)
        NSWorkspace.shared.open(getOutputDirectory())
        #endif
    }
    
    private func shareFile(_ url: URL) {
        #if os(macOS)
        let sharingService = NSSharingServicePicker(items: [url])
        if let window = NSApplication.shared.mainWindow,
           let contentView = window.contentView {
            let rect = NSRect(x: contentView.bounds.midX - 10, y: contentView.bounds.midY - 10, width: 20, height: 20)
            sharingService.show(relativeTo: rect, of: contentView, preferredEdge: .minY)
        }
        #endif
    }
    
    private func getFileInfo(_ url: URL) -> (duration: TimeInterval, sampleRate: Double, channels: Int)? {
        do {
            let file = try AVAudioFile(forReading: url)
            let duration = Double(file.length) / file.fileFormat.sampleRate
            return (
                duration: duration,
                sampleRate: file.fileFormat.sampleRate,
                channels: Int(file.fileFormat.channelCount)
            )
        } catch {
            return nil
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
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
    
    private func getChannelColor(_ channel: String) -> Color {
        switch channel.lowercased() {
        case "mix": return .purple
        case "wet": return .blue
        case "dry": return .green
        default: return .gray
        }
    }
}

#Preview {
    OfflineProcessingView(audioManager: AudioManagerCPP.shared)
        .preferredColorScheme(.dark)
}