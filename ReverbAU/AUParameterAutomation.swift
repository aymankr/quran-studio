import AudioToolbox
import AVFoundation
import CoreAudioKit

/// Advanced parameter automation support for AUv3 plugin
/// Provides seamless integration with DAW automation systems
public class AUParameterAutomation {
    
    // MARK: - Automation Configuration
    
    /// Parameter automation capabilities
    public struct AutomationCapabilities {
        let supportsRamping: Bool           // Smooth parameter changes over time
        let supportsEvents: Bool            // Discrete parameter events
        let supportsCurves: Bool            // Non-linear automation curves
        let maxRampDuration: TimeInterval   // Maximum ramp time in seconds
        let minUpdateInterval: TimeInterval // Minimum time between updates
    }
    
    /// Automation curve types for different parameter behaviors
    public enum AutomationCurve {
        case linear         // Linear interpolation
        case exponential    // Exponential curve (good for gains)
        case logarithmic    // Logarithmic curve (good for frequencies)
        case sCurve         // S-shaped curve (natural for user parameters)
        case custom(points: [CGPoint]) // Custom curve defined by control points
    }
    
    // MARK: - Parameter Event System
    
    /// Represents a single parameter automation event
    public struct ParameterEvent {
        let parameterAddress: AUParameterAddress
        let value: Float
        let timestamp: AUEventSampleTime
        let rampDuration: AUAudioFrameCount
        let curve: AutomationCurve
        
        /// Create immediate parameter change event
        static func immediate(address: AUParameterAddress, value: Float, at timestamp: AUEventSampleTime) -> ParameterEvent {
            return ParameterEvent(
                parameterAddress: address,
                value: value,
                timestamp: timestamp,
                rampDuration: 0,
                curve: .linear
            )
        }
        
        /// Create smooth parameter ramp event
        static func ramp(address: AUParameterAddress, 
                        to value: Float, 
                        at timestamp: AUEventSampleTime,
                        duration: AUAudioFrameCount,
                        curve: AutomationCurve = .linear) -> ParameterEvent {
            return ParameterEvent(
                parameterAddress: address,
                value: value,
                timestamp: timestamp,
                rampDuration: duration,
                curve: curve
            )
        }
    }
    
    // MARK: - Automation Engine
    
    private let audioUnit: ReverbAudioUnit
    private var automationQueue: [ParameterEvent] = []
    private var activeRamps: [AUParameterAddress: ActiveRamp] = [:]
    
    /// Active parameter ramp state
    private struct ActiveRamp {
        let startValue: Float
        let targetValue: Float
        let startSample: AUEventSampleTime
        let duration: AUAudioFrameCount
        let curve: AutomationCurve
        var currentSample: AUEventSampleTime = 0
        
        var isComplete: Bool {
            return currentSample >= startSample + AUEventSampleTime(duration)
        }
        
        func valueAt(sample: AUEventSampleTime) -> Float {
            guard sample >= startSample else { return startValue }
            guard !isComplete else { return targetValue }
            
            let progress = Float(sample - startSample) / Float(duration)
            return interpolateValue(from: startValue, to: targetValue, progress: progress, curve: curve)
        }
    }
    
    // MARK: - Initialization
    
    public init(audioUnit: ReverbAudioUnit) {
        self.audioUnit = audioUnit
        setupParameterAutomation()
    }
    
    private func setupParameterAutomation() {
        guard let parameterTree = audioUnit.parameterTree else { return }
        
        // Configure automation capabilities for each parameter
        configureParameterAutomation(parameterTree)
        
        // Set up parameter event handling
        setupParameterEventHandling(parameterTree)
    }
    
    private func configureParameterAutomation(_ parameterTree: AUParameterTree) {
        // Configure each parameter with appropriate automation settings
        let parameterConfigs: [(AUParameterAddress, AutomationCapabilities)] = [
            // WetDryMix - Critical parameter requiring smooth automation
            (0, AutomationCapabilities(
                supportsRamping: true,
                supportsEvents: true,
                supportsCurves: true,
                maxRampDuration: 5.0,      // Up to 5 seconds for dramatic effects
                minUpdateInterval: 0.001   // 1ms minimum for smooth changes
            )),
            
            // InputGain - Gain parameter with logarithmic behavior
            (1, AutomationCapabilities(
                supportsRamping: true,
                supportsEvents: true,
                supportsCurves: true,
                maxRampDuration: 2.0,      // 2 seconds max for gain changes
                minUpdateInterval: 0.005   // 5ms minimum
            )),
            
            // OutputGain - Similar to input gain
            (2, AutomationCapabilities(
                supportsRamping: true,
                supportsEvents: true,
                supportsCurves: true,
                maxRampDuration: 2.0,
                minUpdateInterval: 0.005
            )),
            
            // ReverbDecay - Can change slowly
            (3, AutomationCapabilities(
                supportsRamping: true,
                supportsEvents: true,
                supportsCurves: false,      // Linear is fine for decay
                maxRampDuration: 10.0,     // Very slow changes acceptable
                minUpdateInterval: 0.050   // 50ms minimum
            )),
            
            // ReverbSize - Very slow parameter
            (4, AutomationCapabilities(
                supportsRamping: true,
                supportsEvents: true,
                supportsCurves: false,
                maxRampDuration: 15.0,     // Very slow room size changes
                minUpdateInterval: 0.100   // 100ms minimum
            )),
            
            // DampingHF - Moderate speed
            (5, AutomationCapabilities(
                supportsRamping: true,
                supportsEvents: true,
                supportsCurves: false,
                maxRampDuration: 5.0,
                minUpdateInterval: 0.020   // 20ms minimum
            )),
            
            // DampingLF - Moderate speed
            (6, AutomationCapabilities(
                supportsRamping: true,
                supportsEvents: true,
                supportsCurves: false,
                maxRampDuration: 5.0,
                minUpdateInterval: 0.020
            ))
        ]
        
        // Apply configurations to parameters
        for (address, capabilities) in parameterConfigs {
            if let parameter = parameterTree.parameter(withAddress: address) {
                configureParameter(parameter, with: capabilities)
            }
        }
    }
    
    private func configureParameter(_ parameter: AUParameter, with capabilities: AutomationCapabilities) {
        // Set parameter flags based on automation capabilities
        var flags = parameter.flags
        
        if capabilities.supportsRamping {
            flags.insert(.flag_CanRamp)
        }
        
        // Note: Parameter flags are read-only, so this is conceptual
        // The actual implementation would be in the parameter creation
    }
    
    private func setupParameterEventHandling(_ parameterTree: AUParameterTree) {
        // Set up parameter value observer for automation events
        parameterTree.implementorValueObserver = { [weak self] parameter, value in
            self?.handleParameterChange(parameter: parameter, value: value)
        }
        
        // Set up parameter string formatting for automation display
        parameterTree.implementorStringFromValueCallback = { parameter, valuePointer in
            return formatParameterValueForAutomation(parameter: parameter, valuePointer: valuePointer)
        }
    }
    
    // MARK: - Automation Event Processing
    
    /// Process automation events for the current audio buffer
    public func processAutomationEvents(frameCount: AUAudioFrameCount, 
                                      timestamp: AUEventSampleTime) {
        
        // Process queued automation events
        processQueuedEvents(frameCount: frameCount, currentTimestamp: timestamp)
        
        // Update active parameter ramps
        updateActiveRamps(frameCount: frameCount, currentTimestamp: timestamp)
        
        // Clean up completed ramps
        cleanupCompletedRamps(currentTimestamp: timestamp)
    }
    
    private func processQueuedEvents(frameCount: AUAudioFrameCount, currentTimestamp: AUEventSampleTime) {
        let endTimestamp = currentTimestamp + AUEventSampleTime(frameCount)
        
        // Process events that should occur during this buffer
        let eventsToProcess = automationQueue.filter { event in
            event.timestamp >= currentTimestamp && event.timestamp < endTimestamp
        }
        
        for event in eventsToProcess {
            processAutomationEvent(event, currentTimestamp: currentTimestamp)
        }
        
        // Remove processed events from queue
        automationQueue.removeAll { event in
            event.timestamp < endTimestamp
        }
    }
    
    private func processAutomationEvent(_ event: ParameterEvent, currentTimestamp: AUEventSampleTime) {
        guard let parameter = audioUnit.parameterTree?.parameter(withAddress: event.parameterAddress) else {
            return
        }
        
        if event.rampDuration > 0 {
            // Start parameter ramp
            startParameterRamp(
                parameter: parameter,
                event: event,
                currentTimestamp: currentTimestamp
            )
        } else {
            // Immediate parameter change
            parameter.setValue(event.value, originator: nil)
        }
    }
    
    private func startParameterRamp(parameter: AUParameter, 
                                  event: ParameterEvent,
                                  currentTimestamp: AUEventSampleTime) {
        
        let startValue = parameter.value
        
        let ramp = ActiveRamp(
            startValue: startValue,
            targetValue: event.value,
            startSample: event.timestamp,
            duration: event.rampDuration,
            curve: event.curve,
            currentSample: currentTimestamp
        )
        
        activeRamps[event.parameterAddress] = ramp
    }
    
    private func updateActiveRamps(frameCount: AUAudioFrameCount, currentTimestamp: AUEventSampleTime) {
        for (address, ramp) in activeRamps {
            guard let parameter = audioUnit.parameterTree?.parameter(withAddress: address) else {
                continue
            }
            
            // Calculate current parameter value based on ramp progress
            let currentValue = ramp.valueAt(sample: currentTimestamp)
            parameter.setValue(currentValue, originator: nil)
            
            // Update ramp state
            activeRamps[address]?.currentSample = currentTimestamp
        }
    }
    
    private func cleanupCompletedRamps(currentTimestamp: AUEventSampleTime) {
        activeRamps = activeRamps.filter { _, ramp in
            !ramp.isComplete
        }
    }
    
    // MARK: - Public Automation Interface
    
    /// Schedule immediate parameter change
    public func scheduleParameterChange(address: AUParameterAddress, 
                                      value: Float, 
                                      at timestamp: AUEventSampleTime) {
        let event = ParameterEvent.immediate(address: address, value: value, at: timestamp)
        automationQueue.append(event)
        automationQueue.sort { $0.timestamp < $1.timestamp }
    }
    
    /// Schedule smooth parameter ramp
    public func scheduleParameterRamp(address: AUParameterAddress,
                                    to value: Float,
                                    at timestamp: AUEventSampleTime,
                                    duration: TimeInterval,
                                    curve: AutomationCurve = .linear) {
        
        // Convert duration to frame count (assuming 44.1kHz)
        let frameCount = AUAudioFrameCount(duration * 44100.0)
        
        let event = ParameterEvent.ramp(
            address: address,
            to: value,
            at: timestamp,
            duration: frameCount,
            curve: curve
        )
        
        automationQueue.append(event)
        automationQueue.sort { $0.timestamp < $1.timestamp }
    }
    
    /// Clear all pending automation events for a parameter
    public func clearAutomation(for address: AUParameterAddress) {
        automationQueue.removeAll { $0.parameterAddress == address }
        activeRamps.removeValue(forKey: address)
    }
    
    /// Clear all automation
    public func clearAllAutomation() {
        automationQueue.removeAll()
        activeRamps.removeAll()
    }
    
    // MARK: - Automation Playback Support
    
    /// Apply automation from host sequencer
    public func applyHostAutomation(events: [AUParameterEvent], bufferStartTime: AUEventSampleTime) {
        for event in events {
            let automationEvent = ParameterEvent(
                parameterAddress: event.parameterAddress,
                value: event.value,
                timestamp: bufferStartTime + AUEventSampleTime(event.eventSampleTime),
                rampDuration: event.rampDurationSampleFrames,
                curve: .linear // Host automation typically uses linear
            )
            
            automationQueue.append(automationEvent)
        }
        
        automationQueue.sort { $0.timestamp < $1.timestamp }
    }
    
    // MARK: - Parameter Event Handling
    
    private func handleParameterChange(parameter: AUParameter, value: AUValue) {
        // This is called when parameter values change from any source
        // (UI, automation, host, etc.)
        
        // Cancel any active ramp for this parameter to avoid conflicts
        activeRamps.removeValue(forKey: parameter.address)
        
        // The parameter value has already been set by the caller
        // Additional processing could be done here if needed
    }
    
    // MARK: - Preset Automation Support
    
    /// Animate preset changes smoothly
    public func animatePresetChange(to presetIndex: Int, 
                                  duration: TimeInterval,
                                  startTime: AUEventSampleTime) {
        
        guard presetIndex < audioUnit.factoryPresets.count else { return }
        
        let preset = audioUnit.factoryPresets[presetIndex]
        
        // Define preset parameter values
        let presetValues: [AUParameterAddress: Float] = getPresetValues(for: presetIndex)
        
        // Schedule ramps for all parameters
        for (address, targetValue) in presetValues {
            scheduleParameterRamp(
                address: address,
                to: targetValue,
                at: startTime,
                duration: duration,
                curve: .sCurve // Use S-curve for natural preset transitions
            )
        }
    }
    
    private func getPresetValues(for presetIndex: Int) -> [AUParameterAddress: Float] {
        // Return parameter values for each preset
        switch presetIndex {
        case 0: // Clean
            return [0: 0.2, 1: 1.0, 2: 1.0, 3: 0.3, 4: 0.2, 5: 0.7, 6: 0.1]
        case 1: // Vocal Booth
            return [0: 0.3, 1: 1.0, 2: 1.0, 3: 0.4, 4: 0.3, 5: 0.6, 6: 0.2]
        case 2: // Studio
            return [0: 0.4, 1: 1.0, 2: 1.0, 3: 0.6, 4: 0.5, 5: 0.4, 6: 0.1]
        case 3: // Cathedral
            return [0: 0.6, 1: 1.0, 2: 1.0, 3: 0.9, 4: 0.8, 5: 0.2, 6: 0.0]
        default:
            return [:]
        }
    }
}

// MARK: - Interpolation Functions

/// Interpolate between two values using specified curve
private func interpolateValue(from startValue: Float, 
                            to endValue: Float, 
                            progress: Float, 
                            curve: AUParameterAutomation.AutomationCurve) -> Float {
    
    let clampedProgress = max(0.0, min(1.0, progress))
    
    switch curve {
    case .linear:
        return startValue + (endValue - startValue) * clampedProgress
        
    case .exponential:
        let expProgress = (exp(clampedProgress) - 1.0) / (exp(1.0) - 1.0)
        return startValue + (endValue - startValue) * expProgress
        
    case .logarithmic:
        let logProgress = log(clampedProgress * (exp(1.0) - 1.0) + 1.0)
        return startValue + (endValue - startValue) * logProgress
        
    case .sCurve:
        // Smoothstep function: 3t² - 2t³
        let smoothProgress = clampedProgress * clampedProgress * (3.0 - 2.0 * clampedProgress)
        return startValue + (endValue - startValue) * smoothProgress
        
    case .custom(let points):
        // Interpolate using custom control points
        return interpolateCustomCurve(startValue: startValue, 
                                    endValue: endValue, 
                                    progress: clampedProgress, 
                                    controlPoints: points)
    }
}

private func interpolateCustomCurve(startValue: Float, 
                                  endValue: Float, 
                                  progress: Float, 
                                  controlPoints: [CGPoint]) -> Float {
    // Simple linear interpolation between control points
    // In a real implementation, this would use spline interpolation
    
    guard !controlPoints.isEmpty else {
        return startValue + (endValue - startValue) * progress
    }
    
    // Find the appropriate control point segment
    for i in 0..<(controlPoints.count - 1) {
        let p1 = controlPoints[i]
        let p2 = controlPoints[i + 1]
        
        if progress >= Float(p1.x) && progress <= Float(p2.x) {
            let segmentProgress = (progress - Float(p1.x)) / Float(p2.x - p1.x)
            let curveValue = Float(p1.y) + (Float(p2.y) - Float(p1.y)) * segmentProgress
            return startValue + (endValue - startValue) * curveValue
        }
    }
    
    // Default to linear if no segment found
    return startValue + (endValue - startValue) * progress
}

// MARK: - Parameter Formatting

private func formatParameterValueForAutomation(parameter: AUParameter, 
                                             valuePointer: UnsafePointer<AUValue>?) -> String? {
    guard let value = valuePointer?.pointee else { return nil }
    
    switch parameter.address {
    case 0: // WetDryMix
        return String(format: "%.1f%%", value * 100)
    case 1, 2: // Input/Output Gain
        return String(format: "%.2f dB", 20 * log10(max(0.001, value)))
    case 3, 4, 5, 6: // Reverb parameters
        return String(format: "%.1f%%", value * 100)
    default:
        return String(format: "%.3f", value)
    }
}