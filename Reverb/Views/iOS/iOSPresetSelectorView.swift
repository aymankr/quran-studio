import SwiftUI

/// iOS-specific preset selector view with touch-optimized interface
@available(iOS 14.0, *)
struct iOSPresetSelectorView: View {
    @ObservedObject var audioManager: AudioManagerCPP
    @Binding var selectedPreset: ReverbPreset
    
    let onPresetSelected: (ReverbPreset) -> Void
    
    private let presets: [ReverbPreset] = [.clean, .vocalBooth, .studio, .cathedral]
    private let gridColumns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Reverb Presets")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(presets, id: \.self) { preset in
                    presetButton(for: preset)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.3))
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private func presetButton(for preset: ReverbPreset) -> some View {
        Button(action: {
            selectedPreset = preset
            onPresetSelected(preset)
            
            // Provide haptic feedback
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
        }) {
            VStack(spacing: 8) {
                // Preset icon
                Image(systemName: iconFor(preset))
                    .font(.title2)
                    .foregroundColor(selectedPreset == preset ? .white : .blue)
                
                // Preset name
                Text(preset.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                // Preset description
                Text(descriptionFor(preset))
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 100)
            .padding(12)
            .background(
                selectedPreset == preset ? 
                    Color.blue.opacity(0.8) : 
                    Color(.systemGray5).opacity(0.6)
            )
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        selectedPreset == preset ? Color.white.opacity(0.3) : Color.clear,
                        lineWidth: 2
                    )
            )
            .scaleEffect(selectedPreset == preset ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: selectedPreset)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func iconFor(_ preset: ReverbPreset) -> String {
        switch preset {
        case .clean:
            return "waveform.circle"
        case .vocalBooth:
            return "mic.circle"
        case .studio:
            return "music.note.house"
        case .cathedral:
            return "building.columns.circle"
        case .custom:
            return "slider.horizontal.3"
        }
    }
    
    private func descriptionFor(_ preset: ReverbPreset) -> String {
        switch preset {
        case .clean:
            return "Minimal reverb for clear vocals"
        case .vocalBooth:
            return "Small room with controlled acoustics"
        case .studio:
            return "Professional studio environment"
        case .cathedral:
            return "Large space with long decay"
        case .custom:
            return "User-defined settings"
        }
    }
}

#Preview {
    iOSPresetSelectorView(
        audioManager: AudioManagerCPP.shared,
        selectedPreset: .constant(.studio)
    ) { preset in
        print("Selected preset: \(preset)")
    }
    .preferredColorScheme(.dark)
}