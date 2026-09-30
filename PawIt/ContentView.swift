import SwiftUI
import Core

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("🐾")
                .font(.system(size: 64))
            Text("PawIt")
                .font(.title.bold())
            Text("由你的宠物帮你记住事情")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
