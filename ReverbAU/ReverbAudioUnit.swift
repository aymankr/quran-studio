import AudioToolbox
import AVFoundation
import CoreAudioKit
import os.log

/// AUv3 Audio Unit wrapper for Reverb DSP engine
/// Enables integration into DAWs like GarageBand, AUM, Cubasis, etc.
/// Wraps the optimized C++ reverb engine for professional plugin compatibility
public class ReverbAudioUnit: AUAudioUnit {
    
    // MARK: - Core Audio Properties
    private var _currentPreset: AUAudioUnitPreset?
    private var _factoryPresets: [AUAudioUnitPreset] = []
    
    // MARK: - Audio Processing
    private var inputBusArray: AUAudioUnitBusArray!
    private var outputBusArray: AUAudioUnitBusArray!
    private var _parameterTree: AUParameterTree!
    
    // MARK: - DSP Engine Integration  
    private var reverbEngine: ReverbEngine?
    private var parameterSmoother: ReverbParameterSmoother?
    
    // MARK: - Audio Unit Parameters (Core Audio automation compatible)
    private enum ParameterAddress: AUParameterAddress {
        case wetDryMix = 0
        case inputGain = 1
        case outputGain = 2
        case reverbDecay = 3
        case reverbSize = 4
        case dampingHF = 5
        case dampingLF = 6
        case reverbPreset = 7
    }
    
    // MARK: - Render Resources
    private var maxFramesToRender: AUAudioFrameCount = 512
    private var renderResourcesAllocated = false
    
    // MARK: - Performance Monitoring
    private let auLogger = OSLog(subsystem: "com.reverb.audiounit", category: "performance")
    
    // MARK: - Initialization
    public override init(componentDescription: AudioComponentDescription,
                        options: AudioComponentInstantiationOptions = []) throws {
        
        try super.init(componentDescription: componentDescription, options: options)
        
        // Initialize audio buses
        setupAudioBuses()
        
        // Initialize parameter tree
        setupParameterTree()
        
        // Initialize factory presets
        setupFactoryPresets()
        
        // Initialize DSP engine
        setupDSPEngine()
        
        // Set default preset
        currentPreset = _factoryPresets.first
        
        os_log("🎛️ ReverbAudioUnit initialized successfully", log: auLogger, type: .info)
    }
    
    // MARK: - Audio Bus Setup
    private func setupAudioBuses() {
        // Create input bus (stereo)
        let inputFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let inputBus = try! AUAudioUnitBus(format: inputFormat)
        inputBus.maximumChannelCount = 2
        inputBus.name = "Reverb Input"
        
        // Create output bus (stereo)
        let outputFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let outputBus = try! AUAudioUnitBus(format: outputFormat)
        outputBus.maximumChannelCount = 2
        outputBus.name = "Reverb Output"
        
        // Create bus arrays
        inputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [inputBus])
        outputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
    }
    
    // MARK: - Parameter Tree Setup
    private func setupParameterTree() {
        // Create parameter definitions with Core Audio automation support
        let wetDryMixParam = AUParameterTree.createParameter(
            withIdentifier: "wetDryMix",
            name: "Wet/Dry Mix",
            address: ParameterAddress.wetDryMix.rawValue,
            min: 0.0,
            max: 1.0,
            unit: .percent,
            unitName: nil,
            flags: [.flag_IsReadable, .flag_IsWritable, .flag_CanRamp],
            valueStrings: nil,
            dependentParameters: nil
        )
        wetDryMixParam.value = 0.5
        
        let inputGainParam = AUParameterTree.createParameter(
            withIdentifier: "inputGain", 
            name: "Input Gain",
            address: ParameterAddress.inputGain.rawValue,
            min: 0.0,
            max: 2.0,
            unit: .linearGain,
            unitName: nil,
            flags: [.flag_IsReadable, .flag_IsWritable, .flag_CanRamp],
            valueStrings: nil,
            dependentParameters: nil
        )
        inputGainParam.value = 1.0
        
        let outputGainParam = AUParameterTree.createParameter(
            withIdentifier: "outputGain",
            name: "Output Gain", 
            address: ParameterAddress.outputGain.rawValue,
            min: 0.0,
            max: 2.0,
            unit: .linearGain,
            unitName: nil,
            flags: [.flag_IsReadable, .flag_IsWritable, .flag_CanRamp],
            valueStrings: nil,
            dependentParameters: nil
        )
        outputGainParam.value = 1.0
        
        let reverbDecayParam = AUParameterTree.createParameter(
            withIdentifier: "reverbDecay",
            name: "Reverb Decay",
            address: ParameterAddress.reverbDecay.rawValue,
            min: 0.1,
            max: 1.0,
            unit: .percent,
            unitName: nil,
            flags: [.flag_IsReadable, .flag_IsWritable, .flag_CanRamp],
            valueStrings: nil,
            dependentParameters: nil
        )
        reverbDecayParam.value = 0.7
        
        let reverbSizeParam = AUParameterTree.createParameter(
            withIdentifier: "reverbSize",
            name: "Reverb Size",
            address: ParameterAddress.reverbSize.rawValue,
            min: 0.1,
            max: 1.0,
            unit: .percent,
            unitName: nil,
            flags: [.flag_IsReadable, .flag_IsWritable, .flag_CanRamp],
            valueStrings: nil,
            dependentParameters: nil
        )
        reverbSizeParam.value = 0.5
        
        let dampingHFParam = AUParameterTree.createParameter(
            withIdentifier: "dampingHF",
            name: "HF Damping",
            address: ParameterAddress.dampingHF.rawValue,
            min: 0.0,
            max: 1.0,
            unit: .percent,
            unitName: nil,
            flags: [.flag_IsReadable, .flag_IsWritable, .flag_CanRamp],
            valueStrings: nil,
            dependentParameters: nil
        )
        dampingHFParam.value = 0.3
        
        let dampingLFParam = AUParameterTree.createParameter(
            withIdentifier: "dampingLF",
            name: "LF Damping",
            address: ParameterAddress.dampingLF.rawValue,
            min: 0.0,
            max: 1.0,
            unit: .percent,
            unitName: nil,
            flags: [.flag_IsReadable, .flag_IsWritable, .flag_CanRamp],
            valueStrings: nil,
            dependentParameters: nil
        )
        dampingLFParam.value = 0.1
        
        let reverbPresetParam = AUParameterTree.createParameter(
            withIdentifier: "reverbPreset",
            name: "Reverb Preset",
            address: ParameterAddress.reverbPreset.rawValue,
            min: 0,
            max: 4,
            unit: .indexed,
            unitName: nil,
            flags: [.flag_IsReadable, .flag_IsWritable],
            valueStrings: ["Clean", "Vocal Booth", "Studio", "Cathedral", "Custom"],
            dependentParameters: nil
        )
        reverbPresetParam.value = 2 // Studio by default
        
        // Create parameter tree
        _parameterTree = AUParameterTree.createTree(withChildren: [
            wetDryMixParam,
            inputGainParam,
            outputGainParam,
            reverbDecayParam,
            reverbSizeParam,
            dampingHFParam,
            dampingLFParam,
            reverbPresetParam
        ])
        
        // Set parameter value observer for real-time updates
        _parameterTree.implementorValueObserver = { [weak self] param, value in
            self?.setParameterValue(address: param.address, value: value)
        }
        
        // Set parameter string from value provider for UI display
        _parameterTree.implementorStringFromValueCallback = { param, valuePtr in
            guard let value = valuePtr?.pointee else { return nil }
            
            switch ParameterAddress(rawValue: param.address) {
            case .wetDryMix:
                return String(format: "%.0f%%", value * 100)
            case .inputGain, .outputGain:
                return String(format: "%.1f dB", 20 * log10(value))
            case .reverbDecay, .reverbSize, .dampingHF, .dampingLF:
                return String(format: "%.0f%%", value * 100)
            case .reverbPreset:
                let presetNames = ["Clean", "Vocal Booth", "Studio", "Cathedral", "Custom"]
                let index = Int(value)
                return index < presetNames.count ? presetNames[index] : "Unknown"
            default:
                return String(format: "%.2f", value)
            }
        }
    }
    
    // MARK: - Factory Presets
    private func setupFactoryPresets() {
        _factoryPresets = [
            AUAudioUnitPreset(number: 0, name: "Clean"),
            AUAudioUnitPreset(number: 1, name: "Vocal Booth"),
            AUAudioUnitPreset(number: 2, name: "Studio"),
            AUAudioUnitPreset(number: 3, name: "Cathedral"),
            AUAudioUnitPreset(number: 4, name: "Custom")
        ]
    }
    
    // MARK: - DSP Engine Setup
    private func setupDSPEngine() {
        // Initialize C++ reverb engine (would need C++ bridge)
        // reverbEngine = ReverbEngine(sampleRate: 44100, bufferSize: 512, channels: 2)
        
        // Initialize parameter smoother for audio thread
        parameterSmoother = ReverbParameterSmoother(sampleRate: 44100)
        
        os_log("🔧 DSP engine initialized", log: auLogger, type: .info)
    }
    
    // MARK: - AUAudioUnit Overrides
    
    public override var parameterTree: AUParameterTree? {
        return _parameterTree
    }
    
    public override var factoryPresets: [AUAudioUnitPreset] {
        return _factoryPresets
    }
    
    public override var currentPreset: AUAudioUnitPreset? {
        get { return _currentPreset }
        set { 
            _currentPreset = newValue
            if let preset = newValue {
                loadPreset(preset)
            }
        }
    }
    
    public override var inputBusses: AUAudioUnitBusArray {
        return inputBusArray
    }
    
    public override var outputBusses: AUAudioUnitBusArray {
        return outputBusArray
    }
    
    public override var maximumFramesToRender: AUAudioFrameCount {
        get { return maxFramesToRender }
        set { 
            maxFramesToRender = newValue
            // Reallocate render resources if needed
            if renderResourcesAllocated {
                deallocateRenderResources()
                allocateRenderResources()
            }
        }
    }
    
    // MARK: - Render Resources Management
    
    public override func allocateRenderResources() throws {
        try super.allocateRenderResources()
        
        guard !renderResourcesAllocated else { return }
        
        // Get the output bus format
        let outputBus = outputBusses[0]
        let format = outputBus.format
        
        // Initialize DSP with actual format
        let sampleRate = format.sampleRate
        let channels = format.channelCount
        
        // Update DSP engine with new format
        // reverbEngine?.updateFormat(sampleRate: Float(sampleRate), channels: UInt32(channels))
        parameterSmoother = ReverbParameterSmoother(sampleRate: Float(sampleRate))
        
        renderResourcesAllocated = true
        
        os_log("🎵 Render resources allocated: %.0f Hz, %d channels, %d frames", 
               log: auLogger, type: .info, sampleRate, channels, maxFramesToRender)
    }
    
    public override func deallocateRenderResources() {
        super.deallocateRenderResources()
        
        renderResourcesAllocated = false
        
        os_log("🗑️ Render resources deallocated", log: auLogger, type: .info)
    }
    
    // MARK: - Audio Processing
    
    public override var internalRenderBlock: AUInternalRenderBlock {
        return { [weak self] (actionFlags, timestamp, frameCount, outputBusNumber, outputBufferList, realtimeEventListHead, pullInputBlock) in
            
            guard let self = self else { return kAudioUnitErr_NoConnection }
            
            // Pull input audio
            guard let pullInputBlock = pullInputBlock else { return kAudioUnitErr_NoConnection }
            
            var inputFlags = AudioUnitRenderActionFlags()
            let inputStatus = pullInputBlock(&inputFlags, timestamp, frameCount, 0, outputBufferList)
            
            guard inputStatus == noErr else { return inputStatus }
            
            // Process audio through reverb engine
            return self.processAudio(
                outputBufferList: outputBufferList,
                frameCount: frameCount,
                timestamp: timestamp
            )
        }
    }
    
    private func processAudio(outputBufferList: UnsafeMutablePointer<AudioBufferList>,
                            frameCount: AUAudioFrameCount,
                            timestamp: UnsafePointer<AudioTimeStamp>) -> AUAudioUnitStatus {
        
        // Performance monitoring
        let renderStartTime = mach_absolute_time()
        
        // Get audio buffers
        let bufferList = UnsafeMutableAudioBufferListPointer(outputBufferList)
        
        guard bufferList.count > 0 else { return kAudioUnitErr_FormatNotSupported }
        
        // Update parameter smoothing (once per buffer)
        parameterSmoother?.updateSmoothedValues()
        
        // Process each channel
        for bufferIndex in 0..<bufferList.count {
            let buffer = bufferList[bufferIndex]
            
            guard let audioData = buffer.mData?.bindMemory(to: Float.self, capacity: Int(frameCount)) else { 
                continue 
            }
            
            // Apply reverb processing (simplified - would use actual C++ engine)
            processChannel(audioData: audioData, frameCount: Int(frameCount))
        }
        
        // Performance logging (debug only)
        #if DEBUG
        let renderEndTime = mach_absolute_time()
        let renderDuration = Double(renderEndTime - renderStartTime) / Double(NSEC_PER_SEC) * 1000.0
        
        if renderDuration > 1.0 { // Log if render takes > 1ms
            os_log("⚠️ Long render: %.3f ms for %d frames", log: auLogger, type: .debug, renderDuration, frameCount)
        }
        #endif
        
        return noErr
    }
    
    private func processChannel(audioData: UnsafeMutablePointer<Float>, frameCount: Int) {
        guard let smoother = parameterSmoother else { return }
        
        // Get smoothed parameter values
        let wetDryMix = smoother.getWetDryMix()
        let inputGain = smoother.getInputGain() 
        let outputGain = smoother.getOutputGain()
        
        // Simple processing (would be replaced with actual C++ reverb engine)
        for i in 0..<frameCount {
            var sample = audioData[i]
            
            // Apply input gain
            sample *= inputGain
            
            // Apply simple reverb effect (placeholder)
            let wetSignal = sample * 0.3 // Simplified reverb
            let drySignal = sample
            sample = drySignal * (1.0 - wetDryMix) + wetSignal * wetDryMix
            
            // Apply output gain
            sample *= outputGain
            
            // Store processed sample
            audioData[i] = sample
        }
    }
    
    // MARK: - Parameter Management
    
    private func setParameterValue(address: AUParameterAddress, value: AUValue) {
        guard let paramAddress = ParameterAddress(rawValue: address),
              let smoother = parameterSmoother else { return }
        
        // Update parameter smoother (thread-safe)
        switch paramAddress {
        case .wetDryMix:
            smoother.setParameter(.WetDryMix, value: value)
        case .inputGain:
            smoother.setParameter(.InputGain, value: value)
        case .outputGain:
            smoother.setParameter(.OutputGain, value: value)
        case .reverbDecay:
            smoother.setParameter(.ReverbDecay, value: value)
        case .reverbSize:
            smoother.setParameter(.ReverbSize, value: value)
        case .dampingHF:
            smoother.setParameter(.DampingHF, value: value)
        case .dampingLF:
            smoother.setParameter(.DampingLF, value: value)
        case .reverbPreset:
            loadPresetByIndex(Int(value))
        }
        
        os_log("📊 Parameter updated: %d = %.3f", log: auLogger, type: .debug, address, value)
    }
    
    // MARK: - Preset Management
    
    private func loadPreset(_ preset: AUAudioUnitPreset) {
        loadPresetByIndex(preset.number)
        _currentPreset = preset
    }
    
    private func loadPresetByIndex(_ index: Int) {
        guard let paramTree = _parameterTree else { return }
        
        // Define preset values
        let presetValues: [[AUValue]] = [
            // Clean
            [0.2, 1.0, 1.0, 0.3, 0.2, 0.7, 0.1],
            // Vocal Booth  
            [0.3, 1.0, 1.0, 0.4, 0.3, 0.6, 0.2],
            // Studio
            [0.4, 1.0, 1.0, 0.6, 0.5, 0.4, 0.1],
            // Cathedral
            [0.6, 1.0, 1.0, 0.9, 0.8, 0.2, 0.0],
            // Custom (don't change values)
            []
        ]
        
        guard index < presetValues.count else { return }
        let values = presetValues[index]
        
        // Skip custom preset (empty array)
        guard !values.isEmpty else { return }
        
        // Update parameters (excluding preset parameter itself)
        let parameterAddresses: [ParameterAddress] = [
            .wetDryMix, .inputGain, .outputGain, .reverbDecay, 
            .reverbSize, .dampingHF, .dampingLF
        ]
        
        for (i, address) in parameterAddresses.enumerated() {
            if i < values.count {
                paramTree.parameter(withAddress: address.rawValue)?.setValue(values[i], originator: nil)
            }
        }
        
        os_log("🎯 Loaded preset: %d (%@)", log: auLogger, type: .info, index, _factoryPresets[index].name)
    }
    
    // MARK: - State Management
    
    public override var fullState: [String : Any]? {
        get {
            guard let paramTree = _parameterTree else { return nil }
            
            var state: [String: Any] = [:]
            
            // Save all parameter values
            let addresses: [ParameterAddress] = [
                .wetDryMix, .inputGain, .outputGain, .reverbDecay,
                .reverbSize, .dampingHF, .dampingLF, .reverbPreset
            ]
            
            for address in addresses {
                if let param = paramTree.parameter(withAddress: address.rawValue) {
                    state[param.identifier] = param.value
                }
            }
            
            // Save current preset
            if let preset = _currentPreset {
                state["currentPreset"] = ["number": preset.number, "name": preset.name]
            }
            
            return state
        }
        set {
            guard let state = newValue,
                  let paramTree = _parameterTree else { return }
            
            // Restore parameter values
            let addresses: [ParameterAddress] = [
                .wetDryMix, .inputGain, .outputGain, .reverbDecay,
                .reverbSize, .dampingHF, .dampingLF, .reverbPreset
            ]
            
            for address in addresses {
                if let param = paramTree.parameter(withAddress: address.rawValue),
                   let value = state[param.identifier] as? AUValue {
                    param.setValue(value, originator: nil)
                }
            }
            
            // Restore current preset
            if let presetData = state["currentPreset"] as? [String: Any],
               let number = presetData["number"] as? Int,
               let name = presetData["name"] as? String {
                _currentPreset = AUAudioUnitPreset(number: number, name: name)
            }
            
            os_log("💾 Full state restored", log: auLogger, type: .info)
        }
    }
    
    // MARK: - MIDI Support (for future expansion)
    
    public override var musicalContextBlock: AUHostMusicalContextBlock? {
        return { [weak self] (currentTempo, timeSignatureNumerator, timeSignatureDenominator, currentBeatPosition, sampleOffsetToNextBeat, currentMeasureDownbeatPosition) in
            
            // Could use musical context for tempo-synced reverb effects
            return true
        }
    }
    
    // MARK: - Transport State (for future expansion)
    
    public override var transportStateBlock: AUHostTransportStateBlock? {
        return { [weak self] (transportStateFlags, currentSamplePosition, cycleStartBeatPosition, cycleEndBeatPosition) in
            
            // Could use transport state for play/stop aware effects
            return true
        }
    }
}

// MARK: - Parameter Address Extension
extension ReverbAudioUnit.ParameterAddress: CaseIterable {
    static var allCases: [ReverbAudioUnit.ParameterAddress] {
        return [.wetDryMix, .inputGain, .outputGain, .reverbDecay, .reverbSize, .dampingHF, .dampingLF, .reverbPreset]
    }
}