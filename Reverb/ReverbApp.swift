import SwiftUI

@main
struct ReverbApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .windowStyle(HiddenTitleBarWindowStyle())
        .windowResizability(.contentSize)
        #endif
    }
} 

