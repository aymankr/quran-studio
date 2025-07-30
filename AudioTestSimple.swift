import AVFoundation
import Foundation

class SimpleAudioTest {
    private var audioEngine: AVAudioEngine?
    
    func testDirectConnection() {
        print("🧪 === SIMPLE AUDIO TEST ===")
        
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let outputNode = engine.outputNode
        
        let inputFormat = inputNode.inputFormat(forBus: 0)
        print("📊 Input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount) channels")
        
        do {
            // Direct connection: Input -> Output (no processing)
            engine.connect(inputNode, to: outputNode, format: inputFormat)
            
            inputNode.volume = 1.0
            engine.isAutoShutdownEnabled = false
            
            engine.prepare()
            try engine.start()
            
            print("✅ Direct connection established: Microphone -> Speakers")
            print("🎤 You should be able to hear yourself now!")
            print("💡 Engine running: \(engine.isRunning)")
            
            self.audioEngine = engine
            
            // Keep the test running
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                print("🛑 Stopping direct audio test...")
                engine.stop()
                self.audioEngine = nil
            }
            
        } catch {
            print("❌ Direct connection failed: \(error)")
        }
    }
}

// Run the test
print("🚀 Starting Simple Audio Test...")
let test = SimpleAudioTest()
test.testDirectConnection()

// Keep the program running for 5 seconds
Thread.sleep(forTimeInterval: 5.0)
print("🏁 Test completed")