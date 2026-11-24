import SwiftUI

@main
struct TruckPadApp: App {
    @StateObject private var link = Link()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(link)
                .preferredColorScheme(.dark)
                .statusBarHidden(true)
        }
    }
}
