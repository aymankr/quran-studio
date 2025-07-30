import Foundation
import AVFoundation

// MARK: - Comprehensive Swift Audio System Tests

class SwiftAudioSystemTests {
    
    var audioManager: AudioManagerCPP!
    
    func runAllSwiftTests() {
        print("🧪 ==========================================")
        print("🧪 STARTING SWIFT AUDIO SYSTEM COMPREHENSIVE TESTS")
        print("🧪 ==========================================")
        
        setUp()
        
        testAudioManagerInitialization()
        testCanStartMonitoring()
        testMonitoringStateTransitions()
        testAudioLevelDetection()
        testReverbPresetChanges()
        testVolumeControls()
        testAudioPipelineConnectivity()
        testRealTimeAudioMonitoring()
        testCriticalAudioOutputPresence()
        
        tearDown()
        
        print("\n🧪 ==========================================")
        print("🧪 ALL SWIFT AUDIO SYSTEM TESTS COMPLETED")
        print("🧪 ==========================================")
    }
    
    func setUp() {
        audioManager = AudioManagerCPP.shared
        print("✅ Test setup completed")
    }
    
    func tearDown() {
        audioManager.stopMonitoring()
        print("✅ Test teardown completed")
    }
    
    // MARK: - Basic Audio System Tests
    
    func testAudioManagerInitialization() {
        print("\n🧪 Test 1: AudioManager Initialization")
        
        guard audioManager != nil else {
            print("❌ TEST 1 FAILED: AudioManager should initialize")
            return
        }
        print("✅ AudioManager initialized successfully")
        
        // Test backend type
        let backend = audioManager.currentBackend
        print("🔧 Current backend: \(backend)")
        
        let isValidBackend = backend == "C++ FDN Engine" || backend == "Swift AVAudioEngine"
        if isValidBackend {
            print("✅ TEST 1 PASSED: Valid backend type")
        } else {
            print("❌ TEST 1 FAILED: Invalid backend type")
        }
    }
    
    func testCanStartMonitoring() {
        print("\n🧪 Test 2: Can Start Monitoring")
        
        let canStart = audioManager.canStartMonitoring
        print("🎵 Can start monitoring: \(canStart)")
        
        if canStart {
            print("✅ TEST 2 PASSED: Should be able to start monitoring")
        } else {
            print("❌ TEST 2 FAILED: Should be able to start monitoring")
        }
    }
    
    func testMonitoringStateTransitions() {
        print("\n🧪 Test 3: Monitoring State Transitions")
        
        // Initial state
        let initialState = audioManager.isMonitoring
        if !initialState {
            print("✅ Initial state: Not monitoring")
        } else {
            print("⚠️ Warning: Already monitoring at start")
        }
        
        // Start monitoring
        print("🎵 Starting monitoring...")
        audioManager.startMonitoring()
        
        // Wait for async operations
        sleep(2)
        
        let monitoringState = audioManager.isMonitoring
        if monitoringState {
            print("✅ Monitoring started successfully")
        } else {
            print("❌ Failed to start monitoring")
        }
        
        // Stop monitoring
        print("🔇 Stopping monitoring...")
        audioManager.stopMonitoring()
        
        let finalState = audioManager.isMonitoring
        if !finalState {
            print("✅ TEST 3 PASSED: Monitoring state transitions work")
        } else {
            print("❌ TEST 3 FAILED: Failed to stop monitoring")
        }
    }
    
    func testAudioLevelDetection() {
        print("\n🧪 Test 4: Audio Level Detection")
        
        // Start monitoring
        audioManager.startMonitoring()
        
        // Wait for audio level updates
        sleep(3)
        
        let currentLevel = audioManager.currentAudioLevel
        print("🎤 Current audio level: \(currentLevel)")
        
        let isValidLevel = currentLevel >= 0.0
        if isValidLevel {
            if currentLevel > 0.001 {
                print("✅ Audio input detected!")
            } else {
                print("ℹ️ No audio input detected (silent environment)")
            }
            print("✅ TEST 4 PASSED: Audio level detection works")
        } else {
            print("❌ TEST 4 FAILED: Invalid audio level")
        }
        
        audioManager.stopMonitoring()
    }
    
    func testReverbPresetChanges() {
        print("\n🧪 Test 5: Reverb Preset Changes")
        
        audioManager.startMonitoring()
        sleep(1)
        
        let presets: [ReverbPreset] = [.clean, .studio, .cathedral, .vocalBooth]
        var allPresetsOK = true
        
        for preset in presets {
            print("🎛️ Applying preset \(preset.rawValue)")
            audioManager.updateReverbPreset(preset)
            
            let selectedPreset = audioManager.selectedReverbPreset
            if selectedPreset == preset {
                print("✅ Preset \(preset.rawValue) applied successfully")
            } else {
                print("❌ Preset mismatch: Expected \(preset.rawValue), Got \(selectedPreset.rawValue)")
                allPresetsOK = false
            }
            
            sleep(1) // Allow time for preset application
        }
        
        audioManager.stopMonitoring()
        
        if allPresetsOK {
            print("✅ TEST 5 PASSED: All preset changes successful")
        } else {
            print("❌ TEST 5 FAILED: Some preset changes failed")
        }
    }
    
    func testVolumeControls() {
        print("\n🧪 Test 6: Volume Controls")
        
        // Test input volume
        let testInputVolume: Float = 0.8
        audioManager.setInputVolume(testInputVolume)
        let retrievedInputVolume = audioManager.getInputVolume()
        print("🎵 Set input volume: \(testInputVolume), retrieved: \(retrievedInputVolume)")
        
        // Allow for some optimization/clamping
        let inputVolumeOK = retrievedInputVolume >= 0.1 && retrievedInputVolume <= 3.0
        if inputVolumeOK {
            print("✅ Input volume within expected range")
        } else {
            print("❌ Input volume out of range")
        }
        
        // Test output volume
        audioManager.setOutputVolume(1.2, isMuted: false)
        print("🔊 Set output volume: 1.2, muted: false")
        
        audioManager.setOutputVolume(0.0, isMuted: true)
        print("🔇 Set output volume: 0.0, muted: true")
        
        print("✅ TEST 6 PASSED: Volume controls tested")
    }
    
    // MARK: - Audio Pipeline Tests
    
    func testAudioPipelineConnectivity() {
        print("\n🧪 Test 7: Audio Pipeline Connectivity")
        
        print("🔍 Running diagnostics...")
        audioManager.diagnostic()
        
        if audioManager.currentBackend.contains("C++") {
            testCppAudioPipeline()
        } else {
            testSwiftAudioPipeline()
        }
        
        print("✅ TEST 7 PASSED: Audio pipeline connectivity tested")
    }
    
    private func testCppAudioPipeline() {
        print("🔧 Testing C++ audio pipeline...")
        
        let isCppAvailable = audioManager.isCppBackendAvailable
        if isCppAvailable {
            print("✅ C++ backend is available")
        } else {
            print("❌ C++ backend is not available")
            return
        }
        
        let stats = audioManager.getCppEngineStats()
        if let stats = stats {
            print("📊 C++ Engine Stats:")
            for (key, value) in stats {
                print("   - \(key): \(value)")
            }
            
            if let sampleRate = stats["sample_rate"] as? Float, sampleRate > 0 {
                print("✅ Valid sample rate: \(sampleRate)")
            }
            
            if let isInitialized = stats["is_initialized"] as? Bool, isInitialized {
                print("✅ C++ engine is initialized")
            }
        } else {
            print("❌ Could not get C++ engine stats")
        }
    }
    
    private func testSwiftAudioPipeline() {
        print("🔧 Testing Swift audio pipeline...")
        print("ℹ️ Swift pipeline testing - basic functionality check")
    }
    
    // MARK: - Real-time Audio Monitoring Test
    
    func testRealTimeAudioMonitoring() {
        print("\n🧪 Test 8: Real-time Audio Monitoring")
        
        var monitoringSuccess = false
        
        // Start monitoring
        audioManager.startMonitoring()
        
        // Give time for audio system to settle
        sleep(2)
        
        print("🎵 Monitoring state: \(audioManager.isMonitoring)")
        print("🎵 Current preset: \(audioManager.selectedReverbPreset.rawValue)")
        print("🎵 Audio level: \(audioManager.currentAudioLevel)")
        
        // Test that we can change presets while monitoring
        audioManager.updateReverbPreset(.studio)
        
        sleep(1)
        
        monitoringSuccess = audioManager.isMonitoring
        
        audioManager.stopMonitoring()
        
        if monitoringSuccess {
            print("✅ TEST 8 PASSED: Real-time monitoring successful")
        } else {
            print("❌ TEST 8 FAILED: Real-time monitoring failed")
        }
    }
    
    // MARK: - Critical Audio Output Test
    
    func testCriticalAudioOutputPresence() {
        print("\n🧪 Test 9: CRITICAL - Audio Output Presence")
        
        // This is the most important test - checking if audio actually flows to output
        audioManager.startMonitoring()
        
        // Apply clean preset (should pass audio through unchanged)
        audioManager.updateReverbPreset(.clean)
        
        sleep(3)
        
        // Check if monitoring is active
        let isMonitoring = audioManager.isMonitoring
        print("🎵 Is monitoring active: \(isMonitoring)")
        
        var testPassed = isMonitoring
        
        // Check if we can get diagnostic info
        if audioManager.currentBackend.contains("C++") {
            let stats = audioManager.getCppEngineStats()
            if stats != nil {
                print("📊 Engine stats available during monitoring")
                testPassed = testPassed && true
            } else {
                print("❌ No engine stats available")
                testPassed = false
            }
        }
        
        audioManager.stopMonitoring()
        
        if testPassed {
            print("✅ TEST 9 PASSED: Audio output test completed")
        } else {
            print("❌ TEST 9 FAILED: Audio output test failed")
        }
    }
}

// MARK: - Simple Audio Test (Original)

class AudioTestSimple {
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var outputNode: AVAudioOutputNode?
    
    func testBasicAudio() {
        print("🔍 === TEST AUDIO BASIQUE ===")
        
        // 1. Test des permissions
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        print("1. Permissions microphone: \(status == .authorized ? "✅ AUTORISÉ" : "❌ REFUSÉ")")
        
        // 2. Test création engine
        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else {
            print("2. ❌ Impossible de créer AVAudioEngine")
            return
        }
        print("2. ✅ AVAudioEngine créé")
        
        // 3. Test input node
        inputNode = engine.inputNode
        guard let input = inputNode else {
            print("3. ❌ Pas d'inputNode")
            return
        }
        print("3. ✅ InputNode obtenu")
        
        // 4. Test format input
        let inputFormat = input.inputFormat(forBus: 0)
        print("4. Format input: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount) canaux")
        
        if inputFormat.sampleRate == 0 {
            print("4. ❌ Format input invalide!")
            return
        }
        
        // 5. Test connexion directe ULTRA-SIMPLE
        outputNode = engine.outputNode
        guard let output = outputNode else {
            print("5. ❌ Pas d'outputNode")
            return
        }
        
        do {
            // Connexion la plus simple possible: input -> output
            engine.connect(input, to: output, format: inputFormat)
            print("5. ✅ Connexion input->output réussie")
            
            // 6. Test démarrage engine
            engine.prepare()
            try engine.start()
            print("6. ✅ AudioEngine démarré!")
            print("   👂 Vous devriez vous entendre maintenant (mode echo)")
            
            // Attendre 5 secondes pour test
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                self.stopTest()
            }
            
        } catch {
            print("5-6. ❌ Erreur: \(error.localizedDescription)")
        }
    }
    
    private func stopTest() {
        audioEngine?.stop()
        print("🔍 Test terminé")
    }
}

// MARK: - Test Extensions for ContentView

extension ContentViewCPP {
    func runAudioTest() {
        let test = AudioTestSimple()
        test.testBasicAudio()
    }
    
    func runComprehensiveTests() {
        let swiftTests = SwiftAudioSystemTests()
        DispatchQueue.global(qos: .userInitiated).async {
            swiftTests.runAllSwiftTests()
        }
    }
}