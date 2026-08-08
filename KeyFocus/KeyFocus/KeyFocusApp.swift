import SwiftUI

@main
struct KeyFocusApp: App {
    @State private var focus = FocusManager()
    @State private var cards = CardIdentityStore()
    @State private var nfc = NFCManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(focus)
                .environment(cards)
                .environment(nfc)
        }
    }
}
