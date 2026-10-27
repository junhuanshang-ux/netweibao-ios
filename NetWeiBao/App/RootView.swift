import SwiftUI

struct RootView: View {
    @StateObject private var permissions = PermissionCoordinator()

    var body: some View {
        TabView {
            NavigationStack {
                NetworkHomeView()
            }
            .tabItem {
                Label("首页", systemImage: "house")
            }

            HomeView()
                .tabItem {
                    Label("工具", systemImage: "square.grid.2x2")
                }

            NavigationStack {
                ReportDashboardView()
            }
            .tabItem {
                Label("报告", systemImage: "doc.text.magnifyingglass")
            }

            AboutView()
                .tabItem {
                    Label("关于", systemImage: "info.circle")
                }
        }
        .environmentObject(permissions)
        .tint(AppTheme.accent)
        .toolbarBackground(AppTheme.background, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .task {
            permissions.requestAtLaunchIfNeeded()
        }
    }
}
