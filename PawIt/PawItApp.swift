import SwiftUI
import WidgetKit
import Core

@main
struct PawItApp: App {

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            NoteListView()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }
}
