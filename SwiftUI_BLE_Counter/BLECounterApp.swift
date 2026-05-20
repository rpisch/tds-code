import SwiftUI

@main
struct BLECounterApp: App {
    @StateObject private var bleManager = BLECounterManager()

    var body: some Scene {
        WindowGroup {
            ContentView(bleManager: bleManager)
        }
    }
}
