import SwiftUI
import Core

/// 设置页面（Soft Companion 风格）——暖色背景一致。
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
            .scrollContentBackground(.hidden)
            .warmBackground()
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
