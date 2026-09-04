import SwiftUI

@main
struct ArenaStrikeApp: App {
    @StateObject private var settings = GameSettings()

    var body: some Scene {
        WindowGroup {
            MenuView()
                .environmentObject(settings)
                .preferredColorScheme(.dark)
        }
    }
}
