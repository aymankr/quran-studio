import AudioToolbox
import CoreAudioKit
import SwiftUI

/// SwiftUI-based view controller for AUv3 plugin interface
/// Provides professional parameter control interface for DAW hosts
public class ReverbAudioUnitViewController: AUViewController, AUAudioUnitFactory {
    
    // MARK: - Properties
    private var audioUnit: ReverbAudioUnit?
    private var parameterObserverToken: AUParameterObserverToken?
    private var hostingController: UIHostingController<ReverbPluginView>?
    
    // MARK: - AUViewController Lifecycle
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set preferred content size for plugin window
        preferredContentSize = CGSize(width: 400, height: 600)
        
        setupAudioUnitInterface()
        setupSwiftUIView()
    }
    
    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        // Clean up parameter observations
        if let token = parameterObserverToken, let audioUnit = audioUnit {
            audioUnit.parameterTree?.removeParameterObserver(token)
            parameterObserverToken = nil
        }
    }
    
    // MARK: - Audio Unit Setup
    
    private func setupAudioUnitInterface() {
        guard let audioUnit = audioUnit else {
            print("❌ No audio unit available for interface setup")
            return
        }
        
        // Set up parameter observation for UI updates
        setupParameterObservation(audioUnit)
    }
    
    private func setupParameterObservation(_ audioUnit: ReverbAudioUnit) {
        guard let parameterTree = audioUnit.parameterTree else { return }
        
        // Observe parameter changes from host automation
        parameterObserverToken = parameterTree.token(byAddingParameterObserver: { [weak self] _, _ in
            // Update UI on main thread when parameters change from host
            DispatchQueue.main.async {
                self?.updateUIFromParameters()
            }
        })
    }
    
    private func updateUIFromParameters() {
        // The SwiftUI view will automatically update via @ObservedObject
        // This method is kept for any additional UI sync needs
    }
    
    // MARK: - SwiftUI Integration
    
    private func setupSwiftUIView() {
        guard let audioUnit = audioUnit else { return }
        
        // Create SwiftUI view with audio unit reference
        let pluginView = ReverbPluginView(audioUnit: audioUnit)
        
        // Wrap in UIHostingController
        let hostingController = UIHostingController(rootView: pluginView)
        self.hostingController = hostingController
        
        // Add as child view controller
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)
        
        // Setup constraints for full view coverage
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        // Apply dark theme for professional appearance
        hostingController.view.backgroundColor = UIColor.systemBackground
        hostingController.overrideUserInterfaceStyle = .dark
    }
    
    // MARK: - AUAudioUnitFactory Implementation
    
    public func createAudioUnit(with componentDescription: AudioComponentDescription) throws -> AUAudioUnit {
        let audioUnit = try ReverbAudioUnit(componentDescription: componentDescription, options: [])
        self.audioUnit = audioUnit
        return audioUnit
    }
}

// MARK: - SwiftUI Plugin Interface

/// Main SwiftUI view for the AUv3 plugin interface
/// Optimized for DAW integration with professional parameter control
struct ReverbPluginView: View {
    @ObservedObject private var parameterModel: AUParameterModel
    private let audioUnit: ReverbAudioUnit
    
    @State private var selectedPreset: Int = 2 // Studio by default
    @State private var showingAdvancedControls = false
    
    init(audioUnit: ReverbAudioUnit) {
        self.audioUnit = audioUnit
        self._parameterModel = ObservedObject(wrappedValue: AUParameterModel(audioUnit: audioUnit))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with logo and preset selection
            headerSection
            
            Divider()
                .background(Color.gray.opacity(0.3))
            
            ScrollView {
                VStack(spacing: 20) {
                    // Essential parameters
                    essentialParametersSection
                    
                    // Advanced parameters (collapsible)
                    advancedParametersSection
                    
                    // Preset management
                    presetSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .background(Color.black)
        .foregroundColor(.white)
    }
    
    // MARK: - View Sections
    
    private var headerSection: some View {
        HStack {
            // Plugin branding
            VStack(alignment: .leading, spacing: 2) {
                Text("REVERB")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text("Professional Reverb Plugin")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            // Preset selector
            Menu {
                ForEach(0..<audioUnit.factoryPresets.count, id: \.self) { index in
                    Button(audioUnit.factoryPresets[index].name) {
                        selectedPreset = index
                        audioUnit.currentPreset = audioUnit.factoryPresets[index]
                    }
                }
            } label: {
                HStack {
                    Text(audioUnit.factoryPresets[selectedPreset].name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
                .foregroundColor(.blue)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(.systemGray6).opacity(0.3))
    }
    
    private var essentialParametersSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Essential Parameters")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Spacer()
            }
            
            VStack(spacing: 12) {
                // Wet/Dry Mix - Most important parameter
                AUParameterSlider(
                    title: "Wet/Dry Mix",
                    parameter: parameterModel.wetDryMixParameter,
                    range: 0...1,
                    format: .percentage
                )
                
                // Input/Output Gains
                HStack(spacing: 12) {
                    AUParameterSlider(
                        title: "Input Gain",
                        parameter: parameterModel.inputGainParameter,
                        range: 0...2,
                        format: .decibels
                    )
                    
                    AUParameterSlider(
                        title: "Output Gain", 
                        parameter: parameterModel.outputGainParameter,
                        range: 0...2,
                        format: .decibels
                    )
                }
            }
        }
        .padding(16)
        .background(Color(.systemGray6).opacity(0.1))
        .cornerRadius(12)
    }
    
    private var advancedParametersSection: some View {
        VStack(spacing: 16) {
            // Section header with expand/collapse
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showingAdvancedControls.toggle()
                }
            }) {
                HStack {
                    Text("Advanced Parameters")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Image(systemName: showingAdvancedControls ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            
            if showingAdvancedControls {
                VStack(spacing: 12) {
                    // Reverb characteristics
                    HStack(spacing: 12) {
                        AUParameterSlider(
                            title: "Reverb Decay",
                            parameter: parameterModel.reverbDecayParameter,
                            range: 0.1...1.0,
                            format: .percentage
                        )
                        
                        AUParameterSlider(
                            title: "Reverb Size",
                            parameter: parameterModel.reverbSizeParameter,
                            range: 0.1...1.0,
                            format: .percentage
                        )
                    }
                    
                    // Damping parameters
                    HStack(spacing: 12) {
                        AUParameterSlider(
                            title: "HF Damping",
                            parameter: parameterModel.dampingHFParameter,
                            range: 0...1,
                            format: .percentage
                        )
                        
                        AUParameterSlider(
                            title: "LF Damping",
                            parameter: parameterModel.dampingLFParameter,
                            range: 0...1,
                            format: .percentage
                        )
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(Color(.systemGray6).opacity(0.1))
        .cornerRadius(12)
    }
    
    private var presetSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Factory Presets")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Spacer()
            }
            
            // Preset buttons grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                ForEach(0..<audioUnit.factoryPresets.count, id: \.self) { index in
                    Button(action: {
                        selectedPreset = index
                        audioUnit.currentPreset = audioUnit.factoryPresets[index]
                    }) {
                        Text(audioUnit.factoryPresets[index].name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(selectedPreset == index ? .black : .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(selectedPreset == index ? Color.blue : Color.gray.opacity(0.2))
                            .cornerRadius(8)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.systemGray6).opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Parameter Model for SwiftUI Binding

/// Observable model that bridges AUParameter to SwiftUI
class AUParameterModel: ObservableObject {
    private let audioUnit: ReverbAudioUnit
    private var parameterObserverToken: AUParameterObserverToken?
    
    // Parameter references for direct access
    var wetDryMixParameter: AUParameter?
    var inputGainParameter: AUParameter?
    var outputGainParameter: AUParameter?
    var reverbDecayParameter: AUParameter?
    var reverbSizeParameter: AUParameter?
    var dampingHFParameter: AUParameter?
    var dampingLFParameter: AUParameter?
    
    // Published values for SwiftUI binding
    @Published var wetDryMix: Float = 0.5
    @Published var inputGain: Float = 1.0
    @Published var outputGain: Float = 1.0
    @Published var reverbDecay: Float = 0.7
    @Published var reverbSize: Float = 0.5
    @Published var dampingHF: Float = 0.3
    @Published var dampingLF: Float = 0.1
    
    init(audioUnit: ReverbAudioUnit) {
        self.audioUnit = audioUnit
        setupParameterReferences()
        setupParameterObservation()
        updateValuesFromParameters()
    }
    
    deinit {
        if let token = parameterObserverToken {
            audioUnit.parameterTree?.removeParameterObserver(token)
        }
    }
    
    private func setupParameterReferences() {
        guard let parameterTree = audioUnit.parameterTree else { return }
        
        wetDryMixParameter = parameterTree.parameter(withAddress: 0)
        inputGainParameter = parameterTree.parameter(withAddress: 1)
        outputGainParameter = parameterTree.parameter(withAddress: 2)
        reverbDecayParameter = parameterTree.parameter(withAddress: 3)
        reverbSizeParameter = parameterTree.parameter(withAddress: 4)
        dampingHFParameter = parameterTree.parameter(withAddress: 5)
        dampingLFParameter = parameterTree.parameter(withAddress: 6)
    }
    
    private func setupParameterObservation() {
        guard let parameterTree = audioUnit.parameterTree else { return }
        
        parameterObserverToken = parameterTree.token(byAddingParameterObserver: { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.updateValuesFromParameters()
            }
        })
    }
    
    private func updateValuesFromParameters() {
        wetDryMix = wetDryMixParameter?.value ?? 0.5
        inputGain = inputGainParameter?.value ?? 1.0
        outputGain = outputGainParameter?.value ?? 1.0
        reverbDecay = reverbDecayParameter?.value ?? 0.7
        reverbSize = reverbSizeParameter?.value ?? 0.5
        dampingHF = dampingHFParameter?.value ?? 0.3
        dampingLF = dampingLFParameter?.value ?? 0.1
    }
}

// MARK: - Custom Parameter Slider

/// Professional parameter slider component for AUv3 interface
struct AUParameterSlider: View {
    let title: String
    let parameter: AUParameter?
    let range: ClosedRange<Float>
    let format: ValueFormat
    
    enum ValueFormat {
        case percentage
        case decibels
        case generic
    }
    
    @State private var currentValue: Float = 0.0
    @State private var isDragging = false
    
    var body: some View {
        VStack(spacing: 8) {
            // Title and value
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                
                Spacer()
                
                Text(formattedValue)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
                    .monospacedDigit()
            }
            
            // Slider
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 8)
                    
                    // Fill
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(
                            colors: [.green, .blue],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: geometry.size.width * normalizedValue, height: 8)
                    
                    // Thumb
                    Circle()
                        .fill(Color.white)
                        .shadow(radius: 1)
                        .frame(width: 16, height: 16)
                        .offset(x: (geometry.size.width - 16) * normalizedValue)
                        .scaleEffect(isDragging ? 1.2 : 1.0)
                        .animation(.spring(response: 0.3), value: isDragging)
                }
            }
            .frame(height: 16)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                        }
                        
                        let newValue = calculateValue(from: value.location.x, in: geometry)
                        currentValue = newValue
                        parameter?.setValue(newValue, originator: nil)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
        }
        .onAppear {
            currentValue = parameter?.value ?? range.lowerBound
        }
    }
    
    private var normalizedValue: CGFloat {
        CGFloat((currentValue - range.lowerBound) / (range.upperBound - range.lowerBound))
    }
    
    private var formattedValue: String {
        switch format {
        case .percentage:
            return String(format: "%.0f%%", currentValue * 100)
        case .decibels:
            return String(format: "%.1f dB", 20 * log10(currentValue))
        case .generic:
            return String(format: "%.2f", currentValue)
        }
    }
    
    private func calculateValue(from locationX: CGFloat, in geometry: GeometryProxy) -> Float {
        let relativeX = locationX / geometry.size.width
        let clampedX = max(0, min(1, relativeX))
        return range.lowerBound + Float(clampedX) * (range.upperBound - range.lowerBound)
    }
}

// MARK: - Preview Support

#if DEBUG
struct ReverbPluginView_Previews: PreviewProvider {
    static var previews: some View {
        ReverbPluginView(audioUnit: try! ReverbAudioUnit(
            componentDescription: AudioComponentDescription(
                componentType: kAudioUnitType_Effect,
                componentSubType: FourCharCode("rvb1"),
                componentManufacturer: FourCharCode("Demo"),
                componentFlags: 0,
                componentFlagsMask: 0
            )
        ))
        .preferredColorScheme(.dark)
    }
}
#endif