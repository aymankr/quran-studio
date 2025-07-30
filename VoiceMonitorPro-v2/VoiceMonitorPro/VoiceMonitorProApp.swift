import SwiftUI

@main
struct VoiceMonitorProApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(SwiftAudioManager.shared)
        }
        #if os(macOS)
        .windowStyle(HiddenTitleBarWindowStyle())
        .windowResizability(.contentSize)
        #endif
    }
}