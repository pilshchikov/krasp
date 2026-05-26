import SwiftUI

@main
struct KraspApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            AppMenuView()
                .environmentObject(appState)
                .frame(width: 320)
        } label: {
            Image(systemName: appState.isEnabled ? "waveform.circle.fill" : "waveform.circle")
        }
        .menuBarExtraStyle(.window)
    }
}
