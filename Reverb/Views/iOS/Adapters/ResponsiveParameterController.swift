import SwiftUI
import Combine
import UIKit

// Swift placeholder removed - using real C++ OptimizedAudioBridge from bridging header

/// Responsive parameter controller for iOS with debouncing and thread-safe audio parameter updates
/// Prevents audio thread overload while maintaining smooth UI responsiveness
@available(iOS 14.0, *)
class ResponsiveParameterController: ObservableObject {
    
    // MARK: - Parameter Types
    enum ParameterType {
        case wetDryMix      // Most critical - needs interpolation to prevent zipper
        case inputGain      // Moderate - needs debouncing
        case outputGain     // Moderate - needs debouncing
        case reverbDecay    // Low priority - can update directly
        case reverbSize     // Low priority - can update directly
        case dampingHF      // Low priority - can update directly
        case dampingLF      // Low priority - can update directly
    }
    
    // MARK: - Parameter Configuration
    struct ParameterConfig {
        let type: ParameterType
        let debounceInterval: TimeInterval  // How long to wait before sending to audio thread
        let interpolationTime: TimeInterval // How long to interpolate in DSP
        let updatePriority: UpdatePriority
        
        enum UpdatePriority {
            case immediate     // Update immediately (rare)
            case high         // Update within 16ms (UI frame)
            case normal       // Update within 50ms  
            case low          // Update within 200ms
        }
    }
    
    // MARK: - Published UI Properties
    @Published var wetDryMix: Float = 0.5 {
        didSet { scheduleParameterUpdate(.wetDryMix, value: wetDryMix) }
    }
    
    @Published var inputGain: Float = 1.0 {
        didSet { scheduleParameterUpdate(.inputGain, value: inputGain) }
    }
    
    @Published var outputGain: Float = 1.0 {
        didSet { scheduleParameterUpdate(.outputGain, value: outputGain) }
    }
    
    @Published var reverbDecay: Float = 0.7 {
        didSet { scheduleParameterUpdate(.reverbDecay, value: reverbDecay) }
    }
    
    @Published var reverbSize: Float = 0.5 {
        didSet { scheduleParameterUpdate(.reverbSize, value: reverbSize) }
    }
    
    @Published var dampingHF: Float = 0.3 {
        didSet { scheduleParameterUpdate(.dampingHF, value: dampingHF) }
    }
    
    @Published var dampingLF: Float = 0.1 {
        didSet { scheduleParameterUpdate(.dampingLF, value: dampingLF) }
    }
    
    // MARK: - Parameter Configurations
    private let parameterConfigs: [ParameterType: ParameterConfig] = [
        .wetDryMix: ParameterConfig(
            type: .wetDryMix,
            debounceInterval: 0.016,    // 16ms - one UI frame
            interpolationTime: 0.050,   // 50ms smooth interpolation
            updatePriority: .high
        ),
        .inputGain: ParameterConfig(
            type: .inputGain,
            debounceInterval: 0.033,    // 33ms - two UI frames
            interpolationTime: 0.030,   // 30ms interpolation
            updatePriority: .normal
        ),
        .outputGain: ParameterConfig(
            type: .outputGain,
            debounceInterval: 0.033,    // 33ms
            interpolationTime: 0.030,   // 30ms interpolation
            updatePriority: .normal
        ),
        .reverbDecay: ParameterConfig(
            type: .reverbDecay,
            debounceInterval: 0.100,    // 100ms - less critical
            interpolationTime: 0.200,   // 200ms smooth transition
            updatePriority: .low
        ),
        .reverbSize: ParameterConfig(
            type: .reverbSize,
            debounceInterval: 0.100,    // 100ms
            interpolationTime: 0.300,   // 300ms - size changes slowly
            updatePriority: .low
        ),
        .dampingHF: ParameterConfig(
            type: .dampingHF,
            debounceInterval: 0.050,    // 50ms
            interpolationTime: 0.100,   // 100ms
            updatePriority: .normal
        ),
        .dampingLF: ParameterConfig(
            type: .dampingLF,
            debounceInterval: 0.050,    // 50ms
            interpolationTime: 0.100,   // 100ms
            updatePriority: .normal
        )
    ]
    
    // MARK: - Internal State
    private var debounceCancellables: [ParameterType: AnyCancellable] = [:]
    private var updateQueue = DispatchQueue(label: "com.reverb.parameter-updates", qos: .userInteractive)
    private weak var audioBridge: OptimizedAudioBridge?
    
    // Parameter interpolation state for smooth transitions
    private var parameterInterpolators: [ParameterType: ParameterInterpolator] = [:]
    
    // MARK: - Initialization
    init(audioBridge: OptimizedAudioBridge) {
        self.audioBridge = audioBridge
        setupParameterInterpolators()
    }
    
    private func setupParameterInterpolators() {
        for (paramType, config) in parameterConfigs {
            parameterInterpolators[paramType] = ParameterInterpolator(
                interpolationTime: config.interpolationTime,
                sampleRate: 48000 // Will be updated with actual sample rate
            )
        }
    }
    
    // MARK: - Parameter Update Scheduling
    private func scheduleParameterUpdate(_ parameterType: ParameterType, value: Float) {
        guard let config = parameterConfigs[parameterType] else { return }
        
        // Cancel any existing debounce timer for this parameter
        debounceCancellables[parameterType]?.cancel()
        
        // Create new debounced update
        debounceCancellables[parameterType] = Timer.publish(
            every: config.debounceInterval,
            on: .main,
            in: .common
        )
        .autoconnect()
        .first() // Only fire once
        .sink { [weak self] _ in
            self?.executeParameterUpdate(parameterType, value: value, config: config)
        }
    }
    
    private func executeParameterUpdate(_ parameterType: ParameterType, 
                                      value: Float, 
                                      config: ParameterConfig) {
        
        updateQueue.async { [weak self] in
            guard let self = self else { return }
            guard let audioBridge = self.audioBridge else { return }
            
            // Get interpolator for smooth transitions
            let interpolator = self.parameterInterpolators[parameterType]
            
            switch parameterType {
            case .wetDryMix:
                // Start interpolation to new value
                interpolator?.startInterpolation(to: value)
                // The actual update will happen in audio thread via interpolator
                
            case .inputGain:
                interpolator?.startInterpolation(to: value)
                
            case .outputGain:
                interpolator?.startInterpolation(to: value)
                
            case .reverbDecay:
                // These parameters can update directly as they're less sensitive to zipper
                self.updateAudioParameter(parameterType, value: value)
                
            case .reverbSize:
                self.updateAudioParameter(parameterType, value: value)
                
            case .dampingHF:
                interpolator?.startInterpolation(to: value)
                
            case .dampingLF:
                interpolator?.startInterpolation(to: value)
            }
        }
    }
    
    private func updateAudioParameter(_ parameterType: ParameterType, value: Float) {
        guard let audioBridge = audioBridge else { return }
        
        // Update the C++ atomic parameters via the optimized bridge
        switch parameterType {
        case .wetDryMix:
            audioBridge.setWetDryMix(value)
        case .inputGain:
            audioBridge.setInputGain(value)
        case .outputGain:
            audioBridge.setOutputGain(value)
        case .reverbDecay:
            audioBridge.setReverbDecay(value)
        case .reverbSize:
            audioBridge.setReverbSize(value)
        case .dampingHF:
            audioBridge.setDampingHF(value)
        case .dampingLF:
            audioBridge.setDampingLF(value)
        }
    }
    
    // MARK: - Interpolation Process (Called from Audio Thread)
    func processParameterInterpolation(numSamples: Int) {
        // This method is called from the audio thread to update interpolated parameters
        for (paramType, interpolator) in parameterInterpolators {
            if interpolator.isInterpolating {
                let currentValue = interpolator.getCurrentValue(numSamples: numSamples)
                updateAudioParameter(paramType, value: currentValue)
            }
        }
    }
    
    // MARK: - UI Responsiveness Optimization
    func optimizeForDevice(_ deviceType: UIUserInterfaceIdiom) {
        switch deviceType {
        case .phone:
            // iPhone: More aggressive debouncing to save CPU
            adjustDebounceTimings(multiplier: 1.2)
        case .pad:
            // iPad: Can handle more frequent updates
            adjustDebounceTimings(multiplier: 0.8)
        default:
            // Default timings
            break
        }
    }
    
    private func adjustDebounceTimings(multiplier: Float) {
        // Dynamically adjust debounce timings based on device capabilities
        // This would require rebuilding the parameter configs, but demonstrates the concept
        print("📱 Adjusting parameter debounce timings by \(multiplier)x for device optimization")
    }
    
    // MARK: - Performance Monitoring
    @Published var parameterUpdateRate: Double = 0.0
    @Published var interpolationCPULoad: Double = 0.0
    
    private var updateRateTimer: Timer?
    private var updateCount: Int = 0
    
    func startPerformanceMonitoring() {
        updateRateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            self.parameterUpdateRate = Double(self.updateCount)
            self.updateCount = 0
            
            // Calculate interpolation CPU load
            let activeInterpolators = self.parameterInterpolators.values.filter { $0.isInterpolating }.count
            self.interpolationCPULoad = Double(activeInterpolators) * 0.1 // Rough estimate
        }
    }
    
    func stopPerformanceMonitoring() {
        updateRateTimer?.invalidate()
        updateRateTimer = nil
    }
    
    // MARK: - Preset Management
    func loadPreset(_ preset: ReverbPreset) {
        // Load preset values without triggering individual updates
        deferUpdates {
            switch preset {
            case .clean:
                wetDryMix = 0.2
                reverbDecay = 0.3
                reverbSize = 0.2
                dampingHF = 0.7
                dampingLF = 0.1
                
            case .vocalBooth:
                wetDryMix = 0.3
                reverbDecay = 0.4
                reverbSize = 0.3
                dampingHF = 0.6
                dampingLF = 0.2
                
            case .studio:
                wetDryMix = 0.4
                reverbDecay = 0.6
                reverbSize = 0.5
                dampingHF = 0.4
                dampingLF = 0.1
                
            case .cathedral:
                wetDryMix = 0.6
                reverbDecay = 0.9
                reverbSize = 0.8
                dampingHF = 0.2
                dampingLF = 0.0
                
            case .custom:
                // Keep current values
                break
            }
        }
    }
    
    private func deferUpdates(_ updates: () -> Void) {
        // Temporarily disable parameter updates to avoid spamming audio thread
        let originalCancellables = debounceCancellables
        debounceCancellables.removeAll()
        
        updates()
        
        // Re-enable updates and send final state
        debounceCancellables = originalCancellables
        
        // Send all parameters at once after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.sendAllParametersToAudio()
        }
    }
    
    private func sendAllParametersToAudio() {
        guard let audioBridge = audioBridge else { return }
        
        audioBridge.setWetDryMix(wetDryMix)
        audioBridge.setInputGain(inputGain)
        audioBridge.setOutputGain(outputGain)
        audioBridge.setReverbDecay(reverbDecay)
        audioBridge.setReverbSize(reverbSize)
        audioBridge.setDampingHF(dampingHF)
        audioBridge.setDampingLF(dampingLF)
    }
}

// MARK: - Parameter Interpolator
class ParameterInterpolator {
    private var currentValue: Float = 0.0
    private var targetValue: Float = 0.0
    private var interpolationCoefficient: Float = 0.0
    private let sampleRate: Float
    
    var isInterpolating: Bool {
        return abs(currentValue - targetValue) > 0.001
    }
    
    init(interpolationTime: TimeInterval, sampleRate: Float) {
        self.sampleRate = sampleRate
        
        // Calculate exponential smoothing coefficient
        // coefficient = exp(-1.0 / (interpolationTime * sampleRate))
        self.interpolationCoefficient = expf(-1.0 / Float(interpolationTime * Double(sampleRate)))
    }
    
    func startInterpolation(to target: Float) {
        targetValue = target
    }
    
    func getCurrentValue(numSamples: Int) -> Float {
        if !isInterpolating {
            return currentValue
        }
        
        // Exponential smoothing for each sample
        for _ in 0..<numSamples {
            currentValue = currentValue * interpolationCoefficient + targetValue * (1.0 - interpolationCoefficient)
        }
        
        return currentValue
    }
    
    func setImmediate(value: Float) {
        currentValue = value
        targetValue = value
    }
}

// MARK: - iOS-Optimized Slider Components
@available(iOS 14.0, *)
struct ResponsiveSlider: View {
    let title: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let unit: String
    let parameterController: ResponsiveParameterController
    
    // Touch gesture state for enhanced responsiveness
    @State private var isDragging = false
    @State private var dragOffset: CGFloat = 0
    @State private var lastUpdateTime = Date()
    
    var body: some View {
        VStack(spacing: 8) {
            // Title and value display  
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                
                Spacer()
                
                Text("\(formatValue(value)) \(unit)")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
                    .monospacedDigit()
            }
            
            // Custom responsive slider
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
                        .shadow(radius: 2)
                        .frame(width: 28, height: 28)
                        .offset(x: (geometry.size.width - 28) * normalizedValue)
                        .scaleEffect(isDragging ? 1.2 : 1.0)
                        .animation(.spring(response: 0.3), value: isDragging)
                }
                .contentShape(Rectangle()) // Expand touch area
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gestureValue in
                            if !isDragging {
                                isDragging = true
                                // Provide haptic feedback on start
                                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                impactFeedback.impactOccurred()
                            }
                            
                            // Calculate new value from gesture
                            let newValue = calculateValueFromGesture(gestureValue, in: geometry)
                            
                            // Throttle updates to avoid overwhelming the parameter controller
                            let now = Date()
                            if now.timeIntervalSince(lastUpdateTime) > 0.008 { // ~120 Hz max update rate
                                value = newValue
                                lastUpdateTime = now
                            }
                        }
                        .onEnded { _ in
                            isDragging = false
                            
                            // Final haptic feedback
                            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                            impactFeedback.impactOccurred()
                        }
                )
            }
            .frame(height: 28)
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
        if unit == "%" {
            return String(format: "%.0f", value * 100)
        } else if unit == "dB" {
            return String(format: "%.1f", value)
        } else {
            return String(format: "%.2f", value)
        }
    }
}

// MARK: - iOS Parameter Panel
@available(iOS 14.0, *)
struct iOSParameterPanel: View {
    @ObservedObject var parameterController: ResponsiveParameterController
    @State private var showingAdvancedParameters = false
    
    var body: some View {
        VStack(spacing: 16) {
            // Essential parameters - always visible
            VStack(spacing: 12) {
                ResponsiveSlider(
                    title: "Mix Wet/Dry",
                    value: $parameterController.wetDryMix,
                    range: 0.0...1.0,
                    unit: "%",
                    parameterController: parameterController
                )
                
                ResponsiveSlider(
                    title: "Gain d'entrée",
                    value: $parameterController.inputGain,
                    range: 0.0...2.0,
                    unit: "dB",
                    parameterController: parameterController
                )
                
                ResponsiveSlider(
                    title: "Gain de sortie",
                    value: $parameterController.outputGain,
                    range: 0.0...2.0,
                    unit: "dB",
                    parameterController: parameterController
                )
            }
            
            // Advanced parameters toggle
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showingAdvancedParameters.toggle()
                }
            }) {
                HStack {
                    Text(showingAdvancedParameters ? "Masquer avancés" : "Paramètres avancés")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Image(systemName: showingAdvancedParameters ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
                .foregroundColor(.blue)
                .padding(.vertical, 8)
            }
            
            // Advanced parameters - collapsible
            if showingAdvancedParameters {
                VStack(spacing: 12) {
                    ResponsiveSlider(
                        title: "Decay",
                        value: $parameterController.reverbDecay,
                        range: 0.0...1.0,
                        unit: "%",
                        parameterController: parameterController
                    )
                    
                    ResponsiveSlider(
                        title: "Taille",
                        value: $parameterController.reverbSize,
                        range: 0.0...1.0,
                        unit: "%",
                        parameterController: parameterController
                    )
                    
                    ResponsiveSlider(
                        title: "Damping HF",
                        value: $parameterController.dampingHF,
                        range: 0.0...1.0,
                        unit: "%",
                        parameterController: parameterController
                    )
                    
                    ResponsiveSlider(
                        title: "Damping LF",
                        value: $parameterController.dampingLF,
                        range: 0.0...1.0,
                        unit: "%",
                        parameterController: parameterController
                    )
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            // Performance monitoring (debug only)
            #if DEBUG
            if parameterController.parameterUpdateRate > 0 {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Debug Info:")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    
                    Text("Updates/sec: \(Int(parameterController.parameterUpdateRate))")
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .monospacedDigit()
                    
                    Text("Interpolation load: \(String(format: "%.1f", parameterController.interpolationCPULoad))%")
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
            }
            #endif
        }
        .padding(16)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .onAppear {
            parameterController.optimizeForDevice(UIDevice.current.userInterfaceIdiom)
            #if DEBUG
            parameterController.startPerformanceMonitoring()
            #endif
        }
        .onDisappear {
            #if DEBUG
            parameterController.stopPerformanceMonitoring()
            #endif
        }
    }
}

#if DEBUG
struct ResponsiveParameterControllerPreview: View {
    var body: some View {
        // Create a sample OptimizedAudioBridge for preview
        let sampleBridge = OptimizedAudioBridge(sampleRate: 48000, bufferSize: 256, channels: 2)
        return iOSParameterPanel(parameterController: ResponsiveParameterController(audioBridge: sampleBridge))
            .preferredColorScheme(.dark)
    }
}

#Preview {
    ResponsiveParameterControllerPreview()
}
#endif