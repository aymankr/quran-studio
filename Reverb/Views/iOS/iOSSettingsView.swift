import SwiftUI
import UIKit

/// iOS Settings view for audio configuration and app preferences
@available(iOS 14.0, *)
struct iOSSettingsView: View {
    @ObservedObject var audioManager: AudioManagerCPP
    @ObservedObject var audioSession: CrossPlatformAudioSession
    @Environment(\.presentationMode) var presentationMode
    
    @State private var selectedSampleRate: Double = 48000
    @State private var selectedBufferSize: Int = 256
    @State private var enableLowLatencyMode = true
    @State private var enableBluetoothAudio = true
    
    let sampleRates: [Double] = [44100, 48000, 96000]
    let bufferSizes: [Int] = [64, 128, 256, 512, 1024]
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Audio Configuration")) {
                    Picker("Sample Rate", selection: $selectedSampleRate) {
                        ForEach(sampleRates, id: \.self) { rate in
                            Text("\(Int(rate)) Hz").tag(rate)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    
                    Picker("Buffer Size", selection: $selectedBufferSize) {
                        ForEach(bufferSizes, id: \.self) { size in
                            Text("\(size) samples").tag(size)
                        }
                    }
                    .pickerStyle(WheelPickerStyle())
                }
                
                Section(header: Text("Performance")) {
                    Toggle("Low Latency Mode", isOn: $enableLowLatencyMode)
                    Toggle("Bluetooth Audio", isOn: $enableBluetoothAudio)
                }
                
                Section(header: Text("Audio Session")) {
                    HStack {
                        Text("Current Latency")
                        Spacer()
                        Text("\(String(format: "%.1f", audioSession.actualLatency))ms")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Buffer Size")
                        Spacer()
                        Text("\(audioSession.currentBufferSize) samples")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
        .onAppear {
            loadCurrentSettings()
        }
        .onChange(of: selectedSampleRate) { _ in
            applySettings()
        }
        .onChange(of: selectedBufferSize) { _ in
            applySettings()
        }
    }
    
    private func loadCurrentSettings() {
        selectedSampleRate = audioSession.currentSampleRate
        selectedBufferSize = Int(audioSession.currentBufferSize)
    }
    
    private func applySettings() {
        Task {
            await audioSession.configureAudioSession(
                sampleRate: selectedSampleRate,
                bufferSize: AVAudioFrameCount(selectedBufferSize),
                enableLowLatency: enableLowLatencyMode
            )
        }
    }
}

#if DEBUG
#Preview {
    iOSSettingsView(
        audioManager: AudioManagerCPP.shared,
        audioSession: CrossPlatformAudioSession()
    )
}
#endif