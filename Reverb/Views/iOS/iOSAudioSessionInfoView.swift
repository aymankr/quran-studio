import SwiftUI
import AVFoundation

/// Detailed audio session information view for iOS
@available(iOS 14.0, *)
struct iOSAudioSessionInfoView: View {
    @ObservedObject var audioSession: CrossPlatformAudioSession
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section("Current Configuration") {
                    InfoRow(title: "Sample Rate", value: "\(Int(audioSession.currentSampleRate)) Hz")
                    InfoRow(title: "Buffer Size", value: "\(audioSession.currentBufferSize) frames")
                    InfoRow(title: "Channels", value: "Stereo (2)")
                    InfoRow(title: "Bit Depth", value: "32-bit Float")
                    InfoRow(title: "Latency", value: String(format: "%.2f ms", audioSession.actualLatency))
                }
                
                Section("Audio Route") {
                    InfoRow(title: "Current Route", value: audioSession.audioRouteDescription)
                    InfoRow(title: "Bluetooth", value: audioSession.isBluetoothConnected ? "Connected" : "Not Connected")
                }
                
                Section("Capabilities") {
                    InfoRow(title: "Low Latency", value: audioSession.isLowLatencyCapable() ? "Supported" : "Not Supported")
                    InfoRow(title: "Platform", value: audioSession.getCurrentPlatform())
                    InfoRow(title: "Configured", value: audioSession.isConfigured ? "Yes" : "No")
                }
                
                Section("Performance") {
                    Button("Refresh Info") {
                        // Trigger a refresh of audio session info
                        audioSession.printDiagnostics()
                    }
                    .foregroundColor(.blue)
                }
            }
            .navigationTitle("Audio Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

/// Helper view for displaying information rows
private struct InfoRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

#Preview {
    iOSAudioSessionInfoView(audioSession: CrossPlatformAudioSession())
}