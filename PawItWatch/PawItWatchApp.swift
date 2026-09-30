import SwiftUI
import Core

@main
struct PawItWatchApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 4) {
                Text("🐾")
                    .font(.system(size: 36))
                Text("PawIt")
                    .font(.headline)
                Text("由你的宠物帮你记住事情")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
