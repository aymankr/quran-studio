import SwiftUI

/// iOS-specific custom reverb parameter controls with touch-optimized sliders
@available(iOS 14.0, *)
struct iOSCustomReverbView: View {
    @ObservedObject var audioManager: AudioManagerCPP
    
    // Local state for custom parameters
    @State private var wetDryMix: Float = 35
    @State private var decayTime: Float = 1.2
    @State private var roomSize: Float = 0.7
    @State private var damping: Float = 0.3
    @State private var preDelay: Float = 25
    @State private var density: Float = 0.8
    
    @State private var showingAdvanced = false
    
    var body: some View {
        VStack(spacing: 20) {
            headerSection
            
            essentialParametersSection
            
            advancedParametersToggle
            
            if showingAdvanced {
                advancedParametersSection
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            resetSection
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.3))
        .cornerRadius(12)
        .onAppear {
            loadCurrentParameters()
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        HStack {
            Text("Custom Reverb")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            Spacer()
            
            // Preset indicator
            if audioManager.currentPreset == .custom {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
    }
    
    // MARK: - Essential Parameters
    private var essentialParametersSection: some View {
        VStack(spacing: 16) {
            iOSParameterSlider(
                title: "Wet/Dry Mix",
                value: $wetDryMix,
                range: 0...100,
                unit: "%"
            ) { value in
                audioManager.setWetDryMix(value / 100.0)
            }
            
            iOSParameterSlider(
                title: "Decay Time",
                value: $decayTime,
                range: 0.1...8.0,
                unit: "s"
            ) { value in
                audioManager.setDecayTime(value)
            }
            
            iOSParameterSlider(
                title: "Room Size",
                value: $roomSize,
                range: 0.0...1.0,
                unit: ""
            ) { value in
                audioManager.setRoomSize(value)
            }
        }
    }
    
    // MARK: - Advanced Parameters Toggle
    private var advancedParametersToggle: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.3)) {
                showingAdvanced.toggle()
            }
            
            // Haptic feedback
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
        }) {
            HStack {
                Text(showingAdvanced ? "Hide Advanced" : "Show Advanced")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Image(systemName: showingAdvanced ? "chevron.up" : "chevron.down")
                    .font(.caption)
            }
            .foregroundColor(.blue)
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Advanced Parameters
    private var advancedParametersSection: some View {
        VStack(spacing: 16) {
            Divider()
            
            iOSParameterSlider(
                title: "Damping",
                value: $damping,
                range: 0.0...1.0,
                unit: ""
            ) { value in
                audioManager.setDamping(value)
            }
            
            iOSParameterSlider(
                title: "Pre Delay",
                value: $preDelay,
                range: 0...200,
                unit: "ms"
            ) { value in
                audioManager.setPreDelay(value)
            }
            
            iOSParameterSlider(
                title: "Density",
                value: $density,
                range: 0.0...1.0,
                unit: ""
            ) { value in
                audioManager.setDensity(value)
            }
        }
    }
    
    // MARK: - Reset Section
    private var resetSection: some View {
        HStack {
            Button("Reset to Default") {
                resetToDefaults()
                
                // Haptic feedback
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
            }
            .font(.subheadline)
            .foregroundColor(.orange)
            
            Spacer()
            
            Button("Save as Preset") {
                saveAsCustomPreset()
                
                // Haptic feedback  
                let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
                impactFeedback.impactOccurred()
            }
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundColor(.green)
        }
        .padding(.top, 8)
    }
    
    // MARK: - Helper Methods
    private func loadCurrentParameters() {
        // Load current parameters from audio manager
        wetDryMix = audioManager.wetDryMix * 100
        decayTime = audioManager.decayTime
        roomSize = audioManager.roomSize
        damping = audioManager.damping
        preDelay = audioManager.preDelay
        density = audioManager.density
    }
    
    private func resetToDefaults() {
        wetDryMix = 35
        decayTime = 1.2
        roomSize = 0.7
        damping = 0.3
        preDelay = 25
        density = 0.8
        
        // Apply to audio manager
        audioManager.setWetDryMix(wetDryMix / 100.0)
        audioManager.setDecayTime(decayTime)
        audioManager.setRoomSize(roomSize)
        audioManager.setDamping(damping)
        audioManager.setPreDelay(preDelay)
        audioManager.setDensity(density)
    }
    
    private func saveAsCustomPreset() {
        audioManager.setPreset(.custom)
        print("Custom preset saved with current parameters")
    }
}

/// iOS-optimized parameter slider with haptic feedback
struct iOSParameterSlider: View {
    let title: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let unit: String
    let onChange: (Float) -> Void
    
    @State private var isDragging = false
    
    var body: some View {
        VStack(spacing: 8) {
            // Title and value display
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                
                Spacer()
                
                Text(formatValue(value) + unit)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
                    .monospacedDigit()
            }
            
            // Custom slider
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 16)
                    
                    // Fill
                    RoundedRectangle(cornerRadius: 8)
                        .fill(LinearGradient(
                            colors: [.green, .blue],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: geometry.size.width * normalizedValue, height: 16)
                        .animation(.easeOut(duration: 0.05), value: value)
                    
                    // Thumb
                    Circle()
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                        .frame(width: isDragging ? 32 : 28, height: isDragging ? 32 : 28)
                        .offset(x: (geometry.size.width - (isDragging ? 32 : 28)) * normalizedValue)
                        .animation(.spring(response: 0.3), value: isDragging)
                }
            }
            .frame(height: 32)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gestureValue in
                        if !isDragging {
                            isDragging = true
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                        }
                        
                        let newValue = calculateValueFromGesture(gestureValue, in: geometry)
                        value = newValue
                        onChange(newValue)
                    }
                    .onEnded { _ in
                        isDragging = false
                        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                        impactFeedback.impactOccurred()
                    }
            )
        }
    }
    
    private var normalizedValue: CGFloat {
        CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
    }
    
    private func calculateValueFromGesture(_ gesture: DragGesture.Value, in geometry: GeometryProxy) -> Float {
        let relativeX = gesture.location.x / geometry.size.width
        let clampedX = max(0, min(1, relativeX))
        return range.lowerBound + Float(clampedX) * (range.upperBound - range.lowerBound)
    }
    
    private func formatValue(_ value: Float) -> String {
        if unit == "%" || unit == "ms" {
            return String(format: "%.0f", value)
        } else if unit == "s" {
            return String(format: "%.2f", value)
        } else {
            return String(format: "%.2f", value)
        }
    }
}

// MARK: - AudioManagerCPP Extensions for Custom Parameters
extension AudioManagerCPP {
    var wetDryMix: Float { 0.35 } // Placeholder
    var decayTime: Float { 1.2 } // Placeholder
    var roomSize: Float { 0.7 } // Placeholder
    var damping: Float { 0.3 } // Placeholder
    var preDelay: Float { 25 } // Placeholder
    var density: Float { 0.8 } // Placeholder
    
    func setWetDryMix(_ value: Float) {
        // Placeholder implementation
        print("Setting wet/dry mix to \(value)")
    }
    
    func setDecayTime(_ value: Float) {
        // Placeholder implementation
        print("Setting decay time to \(value)")
    }
    
    func setRoomSize(_ value: Float) {
        // Placeholder implementation
        print("Setting room size to \(value)")
    }
    
    func setDamping(_ value: Float) {
        // Placeholder implementation
        print("Setting damping to \(value)")
    }
    
    func setPreDelay(_ value: Float) {
        // Placeholder implementation
        print("Setting pre-delay to \(value)")
    }
    
    func setDensity(_ value: Float) {
        // Placeholder implementation
        print("Setting density to \(value)")
    }
}

private func geometry(_ geometry: GeometryProxy) -> GeometryProxy {
    return geometry
}

#Preview {
    iOSCustomReverbView(audioManager: AudioManagerCPP.shared)
        .preferredColorScheme(.dark)
}