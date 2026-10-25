import SwiftUI

@main
struct BloodborneApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var games = GameStore()
    @StateObject private var launcher = RuntimeLauncher()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(games)
                .environmentObject(launcher)
                .preferredColorScheme(.dark)
                .statusBarHidden(true)
                .task { games.restore() }
        }
    }
}
