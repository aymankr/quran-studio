import Foundation

struct RecordingSession: Identifiable, Codable {
    var id = UUID()
    var date: Date
    var duration: TimeInterval
    var presetUsed: String
    
    static var mockSessions: [RecordingSession] {
        [
            RecordingSession(date: Date().addingTimeInterval(-3600), duration: 120, presetUsed: "Cathédrale"),
            RecordingSession(date: Date().addingTimeInterval(-7200), duration: 180, presetUsed: "Grande Salle")
        ]
    }
}

class RecordingHistory: ObservableObject {
    @Published var sessions: [RecordingSession] = []
    private let sessionsKey = "recordingSessions"
    
    init() {
        loadSessions()
    }
    
    func addSession(preset: String, duration: TimeInterval) {
        let newSession = RecordingSession(date: Date(), duration: duration, presetUsed: preset)
        sessions.append(newSession)
        saveSessions()
    }
    
    private func saveSessions() {
        if let encoded = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(encoded, forKey: sessionsKey)
        }
    }
    
    private func loadSessions() {
        if let data = UserDefaults.standard.data(forKey: sessionsKey),
           let decoded = try? JSONDecoder().decode([RecordingSession].self, from: data) {
            sessions = decoded
        }
    }
    
    func clearHistory() {
        sessions.removeAll()
        saveSessions()
    }
} 
