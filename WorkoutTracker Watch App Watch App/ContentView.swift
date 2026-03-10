import SwiftUI

struct ContentView: View {
    @Environment(WatchStore.self) var store

    var body: some View {
        if store.isWorkoutActive {
            WatchWorkoutView()
        } else {
            WatchIdleView()
        }
    }
}
