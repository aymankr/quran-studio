import Foundation
import AVFoundation
import OSLog

/// Batch processor for offline reverb processing - handles multiple files with queue management
/// Extends the AD 480 offline capabilities to professional batch processing workflows
class BatchOfflineProcessor: ObservableObject {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Reverb", category: "BatchProcessor")
    
    // MARK: - Batch Processing State
    @Published var isProcessing = false
    @Published var totalProgress: Double = 0.0
    @Published var currentFileIndex: Int = 0
    @Published var totalFiles: Int = 0
    @Published var currentFileName: String = ""
    @Published var processingQueue: [BatchItem] = []
    @Published var completedItems: [BatchResult] = []
    @Published var failedItems: [BatchError] = []
    
    // MARK: - Processing Statistics
    @Published var totalProcessingTime: TimeInterval = 0
    @Published var averageSpeedMultiplier: Double = 1.0
    @Published var estimatedTimeRemaining: TimeInterval = 0
    
    // MARK: - Core Processor
    private let offlineProcessor = OfflineReverbProcessor()
    private var processingTask: Task<Void, Error>?
    private var batchStartTime: Date?
    
    // MARK: - Batch Item Structure
    struct BatchItem: Identifiable {
        let id = UUID()
        let inputURL: URL
        let outputDirectory: URL
        let settings: OfflineReverbProcessor.ProcessingSettings
        var status: BatchStatus = .pending
        var progress: Double = 0.0
        var processingTime: TimeInterval = 0
        var speedMultiplier: Double = 1.0
        
        var displayName: String {
            inputURL.lastPathComponent
        }
    }
    
    struct BatchResult: Identifiable {
        let id = UUID()
        let item: BatchItem
        let outputFiles: [String: URL]
        let processingTime: TimeInterval
        let speedMultiplier: Double
        let timestamp: Date = Date()
    }
    
    struct BatchError: Identifiable {
        let id = UUID()
        let item: BatchItem
        let error: Error
        let timestamp: Date = Date()
        
        var localizedDescription: String {
            error.localizedDescription
        }
    }
    
    enum BatchStatus: String, CaseIterable {
        case pending = "pending"
        case processing = "processing"
        case completed = "completed"
        case failed = "failed"
        case cancelled = "cancelled"
        
        var displayName: String {
            switch self {
            case .pending: return "En attente"
            case .processing: return "En cours"
            case .completed: return "Terminé"
            case .failed: return "Échec"
            case .cancelled: return "Annulé"
            }
        }
        
        var color: String {
            switch self {
            case .pending: return "gray"
            case .processing: return "blue"
            case .completed: return "green"
            case .failed: return "red"
            case .cancelled: return "orange"
            }
        }
    }
    
    // MARK: - Queue Management
    func addToQueue(
        inputURLs: [URL],
        outputDirectory: URL,
        settings: OfflineReverbProcessor.ProcessingSettings
    ) {
        let newItems = inputURLs.map { url in
            BatchItem(
                inputURL: url,
                outputDirectory: outputDirectory,
                settings: settings
            )
        }
        
        processingQueue.append(contentsOf: newItems)
        totalFiles = processingQueue.count
        
        logger.info("📥 Added \(newItems.count) files to batch queue (total: \(self.totalFiles))")
    }
    
    func removeFromQueue(_ item: BatchItem) {
        processingQueue.removeAll { $0.id == item.id }
        totalFiles = processingQueue.count
        
        logger.info("🗑️ Removed file from batch queue: \(item.displayName)")
    }
    
    func clearQueue() {
        guard !isProcessing else { return }
        
        processingQueue.removeAll()
        completedItems.removeAll()
        failedItems.removeAll()
        totalFiles = 0
        currentFileIndex = 0
        
        logger.info("🧹 Batch queue cleared")
    }
    
    func reorderQueue(from source: IndexSet, to destination: Int) {
        guard !isProcessing else { return }
        
        processingQueue.move(fromOffsets: source, toOffset: destination)
        logger.info("🔄 Batch queue reordered")
    }
    
    // MARK: - Batch Processing
    func startBatchProcessing() async throws {
        guard !isProcessing && !processingQueue.isEmpty else {
            throw ProcessingError.invalidState
        }
        
        logger.info("🚀 Starting batch processing: \(self.processingQueue.count) files")
        
        // Initialize state
        DispatchQueue.main.async {
            self.isProcessing = true
            self.currentFileIndex = 0
            self.totalProgress = 0.0
            self.batchStartTime = Date()
            self.completedItems.removeAll()
            self.failedItems.removeAll()
        }
        
        // Process each item in the queue
        for (index, var item) in processingQueue.enumerated() {
            // Update current processing state
            DispatchQueue.main.async {
                self.currentFileIndex = index + 1
                self.currentFileName = item.displayName
                item.status = .processing
                self.processingQueue[index] = item
            }
            
            let itemStartTime = Date()
            
            do {
                // Process the file
                let results = try await offlineProcessor.processAudioFile(
                    inputURL: item.inputURL,
                    outputDirectory: item.outputDirectory,
                    settings: item.settings
                )
                
                let processingTime = Date().timeIntervalSince(itemStartTime)
                let fileInfo = getFileInfo(item.inputURL)
                let speedMultiplier = fileInfo.map { $0.duration / processingTime } ?? 1.0
                
                // Mark as completed
                item.status = .completed
                item.processingTime = processingTime
                item.speedMultiplier = speedMultiplier
                
                let result = BatchResult(
                    item: item,
                    outputFiles: results,
                    processingTime: processingTime,
                    speedMultiplier: speedMultiplier
                )
                
                DispatchQueue.main.async {
                    self.processingQueue[index] = item
                    self.completedItems.append(result)
                    self.updateBatchProgress()
                    self.updateStatistics()
                }
                
                logger.info("✅ Batch item completed: \(item.displayName) (\(String(format: "%.1fx", speedMultiplier)))")
                
            } catch {
                // Mark as failed
                item.status = .failed
                let batchError = BatchError(item: item, error: error)
                
                DispatchQueue.main.async {
                    self.processingQueue[index] = item
                    self.failedItems.append(batchError)
                    self.updateBatchProgress()
                }
                
                logger.error("❌ Batch item failed: \(item.displayName) - \(error.localizedDescription)")
            }
            
            // Check for cancellation
            try Task.checkCancellation()
        }
        
        // Batch processing completed
        DispatchQueue.main.async {
            self.isProcessing = false
            self.currentFileName = ""
            self.totalProcessingTime = Date().timeIntervalSince(self.batchStartTime ?? Date())
        }
        
        logger.info("🏁 Batch processing completed: \(self.completedItems.count) succeeded, \(self.failedItems.count) failed")
    }
    
    func cancelBatchProcessing() {
        processingTask?.cancel()
        offlineProcessor.cancelProcessing()
        
        // Mark remaining items as cancelled
        for (index, var item) in processingQueue.enumerated() {
            if item.status == .pending || item.status == .processing {
                item.status = .cancelled
                DispatchQueue.main.async {
                    self.processingQueue[index] = item
                }
            }
        }
        
        DispatchQueue.main.async {
            self.isProcessing = false
            self.currentFileName = ""
        }
        
        logger.info("❌ Batch processing cancelled")
    }
    
    // MARK: - Statistics and Progress
    private func updateBatchProgress() {
        let processedCount = completedItems.count + failedItems.count
        totalProgress = Double(processedCount) / Double(max(totalFiles, 1))
        
        // Update estimated time remaining
        if let startTime = batchStartTime, processedCount > 0 {
            let elapsedTime = Date().timeIntervalSince(startTime)
            let avgTimePerFile = elapsedTime / Double(processedCount)
            let remainingFiles = totalFiles - processedCount
            estimatedTimeRemaining = avgTimePerFile * Double(remainingFiles)
        }
    }
    
    private func updateStatistics() {
        guard !completedItems.isEmpty else { return }
        
        let totalSpeed = completedItems.reduce(0.0) { $0 + $1.speedMultiplier }
        averageSpeedMultiplier = totalSpeed / Double(completedItems.count)
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
    
    // MARK: - Batch Templates
    struct BatchTemplate {
        let name: String
        let description: String
        let settings: OfflineReverbProcessor.ProcessingSettings
        
        static let defaultTemplates: [BatchTemplate] = [
            BatchTemplate(
                name: "Vocal Processing",
                description: "Optimal pour voix parlée et chant",
                settings: OfflineReverbProcessor.ProcessingSettings(
                    reverbPreset: .vocalBooth,
                    wetDryMix: 0.3,
                    mode: .mixOnly,
                    outputFormat: .wav,
                    bitDepth: 24
                )
            ),
            BatchTemplate(
                name: "Music Production",
                description: "Traitement musical professionnel",
                settings: OfflineReverbProcessor.ProcessingSettings(
                    reverbPreset: .studio,
                    wetDryMix: 0.4,
                    mode: .wetDrySeparate,
                    outputFormat: .wav,
                    bitDepth: 24
                )
            ),
            BatchTemplate(
                name: "Cinematic Processing",
                description: "Ambiances cinématographiques",
                settings: OfflineReverbProcessor.ProcessingSettings(
                    reverbPreset: .cathedral,
                    wetDryMix: 0.6,
                    mode: .wetDrySeparate,
                    outputFormat: .wav,
                    bitDepth: 24
                )
            ),
            BatchTemplate(
                name: "Podcast Cleanup",
                description: "Nettoyage et enhancement podcast",
                settings: OfflineReverbProcessor.ProcessingSettings(
                    reverbPreset: .clean,
                    wetDryMix: 0.1,
                    mode: .mixOnly,
                    outputFormat: .wav,
                    bitDepth: 16
                )
            )
        ]
    }
    
    // MARK: - Export and Reporting
    func generateBatchReport() -> String {
        let totalProcessed = completedItems.count + failedItems.count
        let successRate = totalProcessed > 0 ? Double(completedItems.count) / Double(totalProcessed) * 100 : 0
        
        var report = """
        RAPPORT DE TRAITEMENT BATCH
        ===========================
        
        Fichiers traités: \(totalProcessed)/\(totalFiles)
        Succès: \(completedItems.count)
        Échecs: \(failedItems.count)
        Taux de réussite: \(String(format: "%.1f", successRate))%
        
        Temps total: \(formatDuration(totalProcessingTime))
        Vitesse moyenne: \(String(format: "%.1fx", averageSpeedMultiplier)) temps réel
        
        FICHIERS TRAITÉS AVEC SUCCÈS:
        """
        
        for result in completedItems {
            report += "\n- \(result.item.displayName) (\(String(format: "%.1fx", result.speedMultiplier)))"
        }
        
        if !failedItems.isEmpty {
            report += "\n\nÉCHECS:"
            for failure in failedItems {
                report += "\n- \(failure.item.displayName): \(failure.localizedDescription)"
            }
        }
        
        return report
    }
    
    func exportResults(to directory: URL) throws {
        let report = generateBatchReport()
        let reportURL = directory.appendingPathComponent("batch_report_\(Date().timeIntervalSince1970).txt")
        
        try report.write(to: reportURL, atomically: true, encoding: .utf8)
        logger.info("📄 Batch report exported: \(reportURL.lastPathComponent)")
    }
    
    // MARK: - Utility Methods
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
    
    // MARK: - Error Types
    enum ProcessingError: LocalizedError {
        case invalidState
        case emptyQueue
        case processingCancelled
        
        var errorDescription: String? {
            switch self {
            case .invalidState:
                return "État de traitement invalide"
            case .emptyQueue:
                return "File d'attente vide"
            case .processingCancelled:
                return "Traitement annulé"
            }
        }
    }
    
    deinit {
        cancelBatchProcessing()
        logger.info("🗑️ BatchOfflineProcessor deinitialized")
    }
}