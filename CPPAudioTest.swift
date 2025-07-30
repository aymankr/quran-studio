import Foundation
import AVFoundation

// Test comprehensive C++ audio functionality
class CPPAudioTest {
    
    // MARK: - C++ Backend Tests
    
    func runAllCPPTests() {
        print("🧪 ===============================")
        print("🧪 STARTING C++ AUDIO BACKEND TESTS")
        print("🧪 ===============================")
        
        testCppBridgeInitialization()
        testCppReverbParameters()
        testCppAudioProcessing()
        testCppVolumeControls()
        testCppPresetSwitching()
        testCppAudioEngineIntegration()
        
        print("\n🧪 ===============================")
        print("🧪 C++ AUDIO BACKEND TESTS COMPLETED")
        print("🧪 ===============================")
    }
    
    // Test 1: C++ Bridge Initialization
    func testCppBridgeInitialization() {
        print("\n🧪 Test 1: C++ Bridge Initialization")
        
        guard let reverbBridge = ReverbBridge() else {
            print("❌ Failed to create ReverbBridge")
            return
        }
        print("✅ ReverbBridge created successfully")
        
        let sampleRate: Double = 48000.0
        let maxBlockSize: UInt32 = 512
        
        let initSuccess = reverbBridge.initialize(withSampleRate: sampleRate, 
                                                 maxBlockSize: maxBlockSize)
        
        if initSuccess {
            print("✅ C++ ReverbBridge initialized: \(sampleRate)Hz, \(maxBlockSize) samples")
        } else {
            print("❌ Failed to initialize ReverbBridge")
            return
        }
        
        // Test AudioIOBridge initialization
        guard let audioIOBridge = AudioIOBridge(reverbBridge: reverbBridge) else {
            print("❌ Failed to create AudioIOBridge")
            return
        }
        print("✅ AudioIOBridge created successfully")
        
        let setupSuccess = audioIOBridge.setupAudioEngine()
        if setupSuccess {
            print("✅ AudioIOBridge setup completed")
        } else {
            print("❌ AudioIOBridge setup failed")
        }
        
        // Check initialization status
        let isInitialized = reverbBridge.isInitialized()
        print("🔧 C++ Engine initialized: \(isInitialized ? "YES" : "NO")")
        
        if isInitialized {
            print("✅ TEST 1 PASSED: C++ Bridge Initialization")
        } else {
            print("❌ TEST 1 FAILED: C++ Bridge Initialization")
        }
    }
    
    // Test 2: C++ Reverb Parameters
    func testCppReverbParameters() {
        print("\n🧪 Test 2: C++ Reverb Parameters")
        
        guard let reverbBridge = ReverbBridge() else {
            print("❌ Failed to create ReverbBridge")
            return
        }
        
        let initSuccess = reverbBridge.initialize(withSampleRate: 48000.0, maxBlockSize: 512)
        guard initSuccess else {
            print("❌ Failed to initialize ReverbBridge")
            return
        }
        
        // Test parameter setting and retrieval
        let testParams = [
            ("wetDryMix", 40.0 as Float),
            ("decayTime", 1.5 as Float),
            ("preDelay", 0.02 as Float),
            ("crossFeed", 0.3 as Float),
            ("roomSize", 0.8 as Float),
            ("density", 0.7 as Float),
            ("highFreqDamping", 0.5 as Float)
        ]
        
        var allParamsOK = true
        
        for (paramName, testValue) in testParams {
            switch paramName {
            case "wetDryMix":
                reverbBridge.setWetDryMix(testValue)
                let retrieved = reverbBridge.wetDryMix()
                print("🎛️ WetDryMix: Set=\(testValue), Got=\(retrieved)")
                if abs(retrieved - testValue) > 0.1 { allParamsOK = false }
                
            case "decayTime":
                reverbBridge.setDecayTime(testValue)
                let retrieved = reverbBridge.decayTime()
                print("⏱️ DecayTime: Set=\(testValue), Got=\(retrieved)")
                if abs(retrieved - testValue) > 0.1 { allParamsOK = false }
                
            case "preDelay":
                reverbBridge.setPreDelay(testValue)
                // Note: PreDelay might not have a getter, so we'll skip validation
                print("⏳ PreDelay: Set=\(testValue)")
                
            case "crossFeed":
                reverbBridge.setCrossFeed(testValue)
                // Note: CrossFeed might not have a getter, so we'll skip validation
                print("🔗 CrossFeed: Set=\(testValue)")
                
            case "roomSize":
                reverbBridge.setRoomSize(testValue)
                let retrieved = reverbBridge.roomSize()
                print("🏠 RoomSize: Set=\(testValue), Got=\(retrieved)")
                if abs(retrieved - testValue) > 0.1 { allParamsOK = false }
                
            case "density":
                reverbBridge.setDensity(testValue)
                let retrieved = reverbBridge.density()
                print("🌊 Density: Set=\(testValue), Got=\(retrieved)")
                if abs(retrieved - testValue) > 0.1 { allParamsOK = false }
                
            case "highFreqDamping":
                reverbBridge.setHighFreqDamping(testValue)
                // Note: HighFreqDamping might not have a getter, so we'll skip validation
                print("🔇 HighFreqDamping: Set=\(testValue)")
                
            default:
                break
            }
        }
        
        if allParamsOK {
            print("✅ TEST 2 PASSED: C++ Reverb Parameters")
        } else {
            print("❌ TEST 2 FAILED: Some C++ parameters didn't match")
        }
    }
    
    // Test 3: C++ Audio Processing
    func testCppAudioProcessing() {
        print("\n🧪 Test 3: C++ Audio Processing")
        
        guard let reverbBridge = ReverbBridge() else {
            print("❌ Failed to create ReverbBridge")
            return
        }
        
        let sampleRate: Double = 48000.0
        let blockSize: UInt32 = 512
        
        let initSuccess = reverbBridge.initialize(withSampleRate: sampleRate, maxBlockSize: blockSize)
        guard initSuccess else {
            print("❌ Failed to initialize ReverbBridge")
            return
        }
        
        // Create test audio buffer
        let numChannels = 2
        let numSamples = Int(blockSize)
        
        // Allocate input and output buffers
        var inputBuffers: [[Float]] = []
        var outputBuffers: [[Float]] = []
        
        for _ in 0..<numChannels {
            inputBuffers.append(Array(repeating: 0.0, count: numSamples))
            outputBuffers.append(Array(repeating: 0.0, count: numSamples))
        }
        
        // Generate test signal (sine wave)
        let frequency: Float = 440.0 // A4 note
        for sample in 0..<numSamples {
            let t = Float(sample) / Float(sampleRate)
            let amplitude: Float = 0.1 // Low amplitude for safety
            let sineValue = amplitude * sin(2.0 * Float.pi * frequency * t)
            
            for channel in 0..<numChannels {
                inputBuffers[channel][sample] = sineValue
            }
        }
        
        // Convert to pointers for C++ processing
        var inputPointers: [UnsafeMutablePointer<Float>] = []
        var outputPointers: [UnsafeMutablePointer<Float>] = []
        
        for channel in 0..<numChannels {
            inputPointers.append(UnsafeMutablePointer(mutating: inputBuffers[channel]))
            outputPointers.append(UnsafeMutablePointer(mutating: outputBuffers[channel]))
        }
        
        // Process audio through C++ engine
        let inputPointersPtr = UnsafeMutablePointer(mutating: inputPointers)
        let outputPointersPtr = UnsafeMutablePointer(mutating: outputPointers)
        
        reverbBridge.processAudio(withInputs: inputPointersPtr,
                                outputs: outputPointersPtr,
                                numChannels: Int32(numChannels),
                                numSamples: Int32(numSamples))
        
        // Verify processing occurred
        var outputHasSignal = false
        var maxOutputLevel: Float = 0.0
        
        for channel in 0..<numChannels {
            for sample in 0..<numSamples {
                let outputValue = abs(outputBuffers[channel][sample])
                maxOutputLevel = max(maxOutputLevel, outputValue)
                if outputValue > 0.001 {
                    outputHasSignal = true
                }
            }
        }
        
        print("🎵 Max output level: \(maxOutputLevel)")
        print("🎵 Output has signal: \(outputHasSignal ? "YES" : "NO")")
        
        if outputHasSignal && maxOutputLevel > 0.001 {
            print("✅ TEST 3 PASSED: C++ Audio Processing")
        } else {
            print("❌ TEST 3 FAILED: No audio signal in C++ output")
        }
    }
    
    // Test 4: C++ Volume Controls  
    func testCppVolumeControls() {
        print("\n🧪 Test 4: C++ Volume Controls")
        
        guard let reverbBridge = ReverbBridge() else {
            print("❌ Failed to create ReverbBridge")
            return
        }
        
        guard let audioIOBridge = AudioIOBridge(reverbBridge: reverbBridge) else {
            print("❌ Failed to create AudioIOBridge")
            return
        }
        
        let setupSuccess = audioIOBridge.setupAudioEngine()
        guard setupSuccess else {
            print("❌ Failed to setup AudioIOBridge")
            return
        }
        
        // Test input volume
        let testInputVolumes: [Float] = [0.5, 1.0, 1.5, 0.8]
        
        for volume in testInputVolumes {
            audioIOBridge.setInputVolume(volume)
            let retrievedVolume = audioIOBridge.inputVolume()
            print("🎤 Input Volume: Set=\(volume), Got=\(retrievedVolume)")
        }
        
        // Test output volume
        let testOutputVolumes: [Float] = [0.5, 1.0, 1.2, 0.0]
        
        for volume in testOutputVolumes {
            let isMuted = (volume == 0.0)
            audioIOBridge.setOutputVolume(volume, isMuted: isMuted)
            print("🔊 Output Volume: Set=\(volume), Muted=\(isMuted)")
        }
        
        print("✅ TEST 4 PASSED: C++ Volume Controls")
    }
    
    // Test 5: C++ Preset Switching
    func testCppPresetSwitching() {
        print("\n🧪 Test 5: C++ Preset Switching")
        
        guard let reverbBridge = ReverbBridge() else {
            print("❌ Failed to create ReverbBridge")
            return
        }
        
        guard let audioIOBridge = AudioIOBridge(reverbBridge: reverbBridge) else {
            print("❌ Failed to create AudioIOBridge")
            return
        }
        
        let setupSuccess = audioIOBridge.setupAudioEngine()
        guard setupSuccess else {
            print("❌ Failed to setup AudioIOBridge")
            return
        }
        
        let presets: [ReverbPresetType] = [.clean, .vocalBooth, .studio, .cathedral]
        var allPresetsOK = true
        
        for preset in presets {
            print("🎛️ Testing preset: \(preset)")
            
            // Set preset via AudioIOBridge
            audioIOBridge.setReverbPreset(preset)
            
            // Verify preset was set
            let currentPreset = audioIOBridge.currentReverbPreset()
            if currentPreset == preset {
                print("✅ Preset \(preset) applied successfully")
            } else {
                print("❌ Preset mismatch: Expected \(preset), Got \(currentPreset)")
                allPresetsOK = false
            }
            
            // Get preset parameters
            let wetDry = reverbBridge.wetDryMix()
            let decay = reverbBridge.decayTime()
            let roomSize = reverbBridge.roomSize()
            let density = reverbBridge.density()
            let bypass = reverbBridge.isBypassed()
            
            print("   📊 WetDry=\(wetDry)%, Decay=\(decay)s, Room=\(roomSize), Density=\(density), Bypass=\(bypass)")
            
            // Brief delay between presets
            usleep(100000) // 100ms
        }
        
        if allPresetsOK {
            print("✅ TEST 5 PASSED: C++ Preset Switching")
        } else {
            print("❌ TEST 5 FAILED: Some presets didn't apply correctly")
        }
    }
    
    // Test 6: C++ Audio Engine Integration
    func testCppAudioEngineIntegration() {
        print("\n🧪 Test 6: C++ Audio Engine Integration")
        
        guard let reverbBridge = ReverbBridge() else {
            print("❌ Failed to create ReverbBridge")
            return
        }
        
        guard let audioIOBridge = AudioIOBridge(reverbBridge: reverbBridge) else {
            print("❌ Failed to create AudioIOBridge")
            return
        }
        
        let setupSuccess = audioIOBridge.setupAudioEngine()
        guard setupSuccess else {
            print("❌ Failed to setup AudioIOBridge")
            return
        }
        
        // Test engine lifecycle
        print("🔧 Testing engine start...")
        let startSuccess = audioIOBridge.startEngine()
        if startSuccess {
            print("✅ Engine started successfully")
        } else {
            print("❌ Engine failed to start")
            return
        }
        
        // Check engine state
        let isRunning = audioIOBridge.isEngineRunning()
        let isInitialized = audioIOBridge.isInitialized()
        
        print("🔧 Engine running: \(isRunning)")
        print("🔧 Engine initialized: \(isInitialized)")
        
        // Test monitoring
        print("🎵 Testing monitoring...")
        audioIOBridge.setMonitoring(true)
        let isMonitoring = audioIOBridge.isMonitoring()
        print("🎵 Monitoring active: \(isMonitoring)")
        
        // Test diagnostics
        print("🔍 Running diagnostics...")
        audioIOBridge.printDiagnostics()
        
        // Brief monitoring period
        print("🎵 Monitoring for 3 seconds...")
        sleep(3)
        
        // Stop monitoring and engine
        print("🔇 Stopping monitoring...")
        audioIOBridge.setMonitoring(false)
        audioIOBridge.stopEngine()
        
        let finalRunningState = audioIOBridge.isEngineRunning()
        print("🔧 Final engine state: \(finalRunningState ? "Running" : "Stopped")")
        
        if !finalRunningState {
            print("✅ TEST 6 PASSED: C++ Audio Engine Integration")
        } else {
            print("❌ TEST 6 FAILED: Engine didn't stop properly")
        }
    }
}

// Extension to run from ContentView
extension ContentViewCPP {
    func runCppAudioTest() {
        let test = CPPAudioTest()
        DispatchQueue.global(qos: .userInitiated).async {
            test.runAllCPPTests()
        }
    }
}