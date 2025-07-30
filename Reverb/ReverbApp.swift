import SwiftUI

@main
struct ReverbApp: App {
    var body: some Scene {
        WindowGroup {
            ContentViewCPP()
        }
        #if os(macOS)
        .windowStyle(HiddenTitleBarWindowStyle())
        .windowResizability(.contentSize)
        #endif
    }
} 

