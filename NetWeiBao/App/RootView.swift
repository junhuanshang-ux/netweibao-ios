import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("工作台", systemImage: "square.grid.2x2")
                }

            NavigationStack {
                PingDashboardView()
            }
            .tabItem {
                Label("Ping", systemImage: "dot.radiowaves.left.and.right")
            }

            AboutView()
                .tabItem {
                    Label("关于", systemImage: "info.circle")
                }
        }
        .tint(AppTheme.accent)
        .toolbarBackground(AppTheme.background, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}
