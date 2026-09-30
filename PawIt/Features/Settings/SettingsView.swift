import SwiftUI
import Core

/// 设置页面（W7-5）——目前仅含「关闭养成」开关。
struct SettingsView: View {
    @State private var growthEnabled: Bool = GrowthSettings.isEnabled
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Growth System", isOn: $growthEnabled)
                        .onChange(of: growthEnabled) { _, newValue in
                            GrowthSettings.isEnabled = newValue
                        }
                } header: {
                    Text("Features")
                } footer: {
                    Text("When disabled, completing tasks won't feed your pet or track streaks. Your existing progress is preserved.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onDismiss() }
                }
            }
        }
    }
}
