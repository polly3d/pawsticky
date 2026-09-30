import SwiftUI
import Core

/// 旧占位视图，已被 NoteListView 替代（W3-2）。
/// 保留作为参考；App 入口已切换至 NoteListView。
struct ContentView: View {
    var body: some View {
        NoteListView()
    }
}

#Preview {
    ContentView()
}
