import SwiftUI

@main
struct VXApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .ignoresSafeArea(.container, edges: .bottom)
                .preferredColorScheme(.dark)
        }
    }
}
