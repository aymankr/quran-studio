import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

struct BatchProcessingView: View {
    @StateObject private var batchProcessor = BatchOfflineProcessor()
    @ObservedObject var audioManager: AudioManagerCPP
    
    // UI State
    @State private var selectedTemplate: BatchOfflineProcessor.BatchTemplate?
    @State private var showingFilePicker = false
    @State private var showingTemplateEditor = false
    @State private var showingReport = false
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    @State private var customSettings = OfflineReverbProcessor.ProcessingSettings()
    
    // Colors
    private let cardColor = Color(red: 0.12, green: 0.12, blue: 0.18)
    private let accentColor = Color.blue
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            headerSection
            
            // Template selection
            templateSelectionSection
            
            // Queue management
            queueManagementSection
            
            // Processing queue
            if !batchProcessor.processingQueue.isEmpty {
                processingQueueSection
            }
            
            // Batch controls
            batchControlsSection
            
            // Progress section
            if batchProcessor.isProcessing {
                progressSection
            }
            
            // Statistics
            if !batchProcessor.completedItems.isEmpty || !batchProcessor.failedItems.isEmpty {
                statisticsSection
            }
        }
        .padding(16)
        .background(cardColor.opacity(0.8))
        .cornerRadius(12)
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            handleFilesSelection(result)
        }
        .alert("Erreur de traitement", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showingReport) {
            BatchReportView(batchProcessor: batchProcessor)
        }
        .sheet(isPresented: $showingTemplateEditor) {
            BatchTemplateEditorView(settings: $customSettings) { settings in
                customSettings = settings
                addFilesToQueue(with: settings)
            }
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("⚡ Traitement par Lot")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Spacer()
                
                // Queue count indicator
                HStack(spacing: 4) {
                    Image(systemName: "list.number")
                        .font(.caption)
                    Text("\(batchProcessor.processingQueue.count)")
                        .fontWeight(.medium)
                }
                .font(.caption)
                .foregroundColor(batchProcessor.processingQueue.isEmpty ? .gray : accentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(accentColor.opacity(0.1))
                .cornerRadius(6)
            }
            
            Text("Traitement offline en série - optimisé pour production professionnelle")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
        }
    }
    
    // MARK: - Template Selection Section
    private var templateSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("🎯 Templates de traitement")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                ForEach(BatchOfflineProcessor.BatchTemplate.defaultTemplates, id: \.name) { template in
                    templateButton(template)
                }
                
                // Custom template button
                Button(action: {
                    showingTemplateEditor = true
                }) {
                    VStack(spacing: 6) {
                        Image(systemName: "gear.circle")
                            .font(.title2)
                            .foregroundColor(.orange)
                        
                        Text("Personnalisé")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                        
                        Text("Réglages sur mesure")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .padding(8)
                    .background(cardColor.opacity(0.6))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.orange.opacity(0.3), lineWidth: 1)
                    )
                }
                .disabled(batchProcessor.isProcessing)
            }
        }
    }
    
    @ViewBuilder
    private func templateButton(_ template: BatchOfflineProcessor.BatchTemplate) -> some View {
        Button(action: {
            selectedTemplate = template
            customSettings = template.settings
        }) {
            VStack(spacing: 6) {
                Image(systemName: getTemplateIcon(template.name))
                    .font(.title2)
                    .foregroundColor(selectedTemplate?.name == template.name ? .white : accentColor)
                
                Text(template.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                Text(template.description)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 80)
            .padding(8)
            .background(selectedTemplate?.name == template.name ? accentColor : cardColor.opacity(0.6))
            .cornerRadius(8)
        }
        .disabled(batchProcessor.isProcessing)
    }
    
    // MARK: - Queue Management Section
    private var queueManagementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("📁 Gestion de la file")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                
                Spacer()
                
                if !batchProcessor.processingQueue.isEmpty && !batchProcessor.isProcessing {
                    Button("Tout supprimer") {
                        batchProcessor.clearQueue()
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                }
            }
            
            HStack(spacing: 12) {
                Button(action: {
                    if selectedTemplate != nil || !customSettings.reverbPreset.rawValue.isEmpty {
                        showingFilePicker = true
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                        Text("Ajouter fichiers")
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                    .background(selectedTemplate != nil ? accentColor : Color.gray)
                    .cornerRadius(8)
                }
                .disabled(selectedTemplate == nil && customSettings.reverbPreset.rawValue.isEmpty)
                
                if !batchProcessor.completedItems.isEmpty || !batchProcessor.failedItems.isEmpty {
                    Button(action: {
                        showingReport = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text")
                            Text("Rapport")
                        }
                        .font(.caption)
                        .foregroundColor(accentColor)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(accentColor.opacity(0.1))
                        .cornerRadius(6)
                    }
                }
            }
        }
    }
    
    // MARK: - Processing Queue Section
    private var processingQueueSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("📋 File de traitement (\(batchProcessor.processingQueue.count))")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
            
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(Array(batchProcessor.processingQueue.enumerated()), id: \.element.id) { index, item in
                        queueItemRow(item: item, index: index)
                    }
                }
            }
            .frame(maxHeight: 200)
        }
        .padding(12)
        .background(cardColor.opacity(0.4))
        .cornerRadius(8)
    }
    
    @ViewBuilder
    private func queueItemRow(item: BatchOfflineProcessor.BatchItem, index: Int) -> some View {
        HStack(spacing: 8) {
            // Status indicator
            Circle()
                .fill(getStatusColor(item.status))
                .frame(width: 8, height: 8)
            
            // Index
            Text("\(index + 1)")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 20, alignment: .trailing)
            
            // File info
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    Text(item.status.displayName)
                        .font(.caption2)
                        .foregroundColor(getStatusColor(item.status))
                    
                    if item.status == .processing && item.progress > 0 {
                        Text("•")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.5))
                        
                        Text("\(Int(item.progress * 100))%")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.7))
                            .monospacedDigit()
                    }
                    
                    if item.speedMultiplier > 1 {
                        Text("•")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.5))
                        
                        Text("\(String(format: "%.1fx", item.speedMultiplier))")
                            .font(.caption2)
                            .foregroundColor(.green)
                            .monospacedDigit()
                    }
                }
            }
            
            Spacer()
            
            // Remove button
            if !batchProcessor.isProcessing && item.status == .pending {
                Button(action: {
                    batchProcessor.removeFromQueue(item)
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.red.opacity(0.7))
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(item.status == .processing ? accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(4)
    }
    
    // MARK: - Batch Controls Section
    private var batchControlsSection: some View {
        HStack(spacing: 12) {
            Button(action: {
                startBatchProcessing()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: batchProcessor.isProcessing ? "stop.circle.fill" : "play.circle.fill")
                        .font(.title3)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(batchProcessor.isProcessing ? "Arrêter le lot" : "Traiter le lot")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        if !batchProcessor.isProcessing {
                            Text("\(batchProcessor.processingQueue.count) fichier(s)")
                                .font(.caption2)
                                .opacity(0.8)
                        }
                    }
                }
                .foregroundColor(.white)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .background(batchProcessor.isProcessing ? Color.red : accentColor)
                .cornerRadius(10)
            }
            .disabled(batchProcessor.processingQueue.isEmpty)
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
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(batchProcessor.currentFileIndex)/\(batchProcessor.totalFiles)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .monospacedDigit()
                    
                    if batchProcessor.estimatedTimeRemaining > 0 {
                        Text("~\(formatDuration(batchProcessor.estimatedTimeRemaining))")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.7))
                            .monospacedDigit()
                    }
                }
            }
            
            // Overall progress bar
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
                        .frame(width: geometry.size.width * batchProcessor.totalProgress, height: 8)
                        .animation(.easeInOut(duration: 0.3), value: batchProcessor.totalProgress)
                }
            }
            .frame(height: 8)
            
            HStack {
                Text("Fichier actuel:")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
                
                Text(batchProcessor.currentFileName)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Spacer()
                
                if batchProcessor.averageSpeedMultiplier > 1 {
                    Text("\(String(format: "%.1fx", batchProcessor.averageSpeedMultiplier)) moy.")
                        .font(.caption2)
                        .foregroundColor(.green)
                        .monospacedDigit()
                }
            }
        }
        .padding(12)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
    }
    
    // MARK: - Statistics Section
    private var statisticsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("📊 Statistiques")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
            
            HStack(spacing: 16) {
                statisticItem(
                    title: "Réussis",
                    value: "\(batchProcessor.completedItems.count)",
                    color: .green
                )
                
                statisticItem(
                    title: "Échecs",
                    value: "\(batchProcessor.failedItems.count)",
                    color: .red
                )
                
                statisticItem(
                    title: "Vitesse moy.",
                    value: String(format: "%.1fx", batchProcessor.averageSpeedMultiplier),
                    color: .blue
                )
                
                statisticItem(
                    title: "Temps total",
                    value: formatDuration(batchProcessor.totalProcessingTime),
                    color: .orange
                )
            }
        }
        .padding(12)
        .background(cardColor.opacity(0.4))
        .cornerRadius(8)
    }
    
    @ViewBuilder
    private func statisticItem(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(color)
                .monospacedDigit()
            
            Text(title)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Helper Methods
    private func handleFilesSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            let audioFiles = urls.filter { url in
                let ext = url.pathExtension.lowercased()
                return ["wav", "aiff", "caf", "mp3", "m4a", "aac"].contains(ext)
            }
            
            if !audioFiles.isEmpty {
                addFilesToQueue(files: audioFiles)
            }
            
        case .failure(let error):
            errorMessage = error.localizedDescription
            showingErrorAlert = true
        }
    }
    
    private func addFilesToQueue(files: [URL]? = nil) {
        let settings = selectedTemplate?.settings ?? customSettings
        let outputDirectory = getOutputDirectory()
        
        if let files = files {
            batchProcessor.addToQueue(
                inputURLs: files,
                outputDirectory: outputDirectory,
                settings: settings
            )
        }
    }
    
    private func addFilesToQueue(with settings: OfflineReverbProcessor.ProcessingSettings) {
        customSettings = settings
        showingFilePicker = true
    }
    
    private func startBatchProcessing() {
        if batchProcessor.isProcessing {
            batchProcessor.cancelBatchProcessing()
        } else {
            Task {
                do {
                    try await batchProcessor.startBatchProcessing()
                } catch {
                    DispatchQueue.main.async {
                        self.errorMessage = error.localizedDescription
                        self.showingErrorAlert = true
                    }
                }
            }
        }
    }
    
    private func getOutputDirectory() -> URL {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let outputDir = documentsDir.appendingPathComponent("BatchProcessing", isDirectory: true)
        
        if !FileManager.default.fileExists(atPath: outputDir.path) {
            try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        }
        
        return outputDir
    }
    
    private func getTemplateIcon(_ name: String) -> String {
        switch name {
        case "Vocal Processing": return "mic.circle"
        case "Music Production": return "music.note"
        case "Cinematic Processing": return "tv.circle"
        case "Podcast Cleanup": return "podcast.circle"
        default: return "waveform.circle"
        }
    }
    
    private func getStatusColor(_ status: BatchOfflineProcessor.BatchStatus) -> Color {
        switch status {
        case .pending: return .gray
        case .processing: return .blue
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .orange
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

// MARK: - Batch Report View
struct BatchReportView: View {
    @ObservedObject var batchProcessor: BatchOfflineProcessor
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(batchProcessor.generateBatchReport())
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.8))
                        .cornerRadius(8)
                }
                .padding()
            }
            .navigationTitle("Rapport de traitement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Fermer") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Exporter") {
                        exportReport()
                    }
                }
            }
        }
    }
    
    private func exportReport() {
        let outputDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BatchProcessing", isDirectory: true)
        
        do {
            try batchProcessor.exportResults(to: outputDirectory)
        } catch {
            print("❌ Failed to export report: \(error)")
        }
    }
}

// MARK: - Template Editor View
struct BatchTemplateEditorView: View {
    @Binding var settings: OfflineReverbProcessor.ProcessingSettings
    let onSave: (OfflineReverbProcessor.ProcessingSettings) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                // Implementation of custom settings editor
                // This would include all the settings from OfflineReverbProcessor.ProcessingSettings
                Text("Template Editor - Implementation needed")
            }
            .navigationTitle("Template personnalisé")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Utiliser") {
                        onSave(settings)
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    BatchProcessingView(audioManager: AudioManagerCPP.shared)
        .preferredColorScheme(.dark)
}