import SwiftUI

@main
struct NetWeiBaoApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .tint(AppTheme.accent)
        }
    }
}
