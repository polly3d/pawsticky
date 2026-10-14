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

                aboutSection
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

    // MARK: - About

    /// 审核指南 5.1.1(i)：隐私政策必须在 App 内“易于找到”——放在设置页第一屏即可见。
    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: AppInfo.versionDescription())

            externalLink("Privacy Policy", url: PawItInfo.privacyPolicyURL)
            externalLink("Support", url: PawItInfo.supportURL)

            NavigationLink("Acknowledgements") {
                AcknowledgementsView()
            }
        } header: {
            Text("About")
        } footer: {
            Text("Your notes stay on your device. PawSticky doesn't collect any personal data.")
        }
    }

    /// 外链行：整行可点，右侧小箭头提示“会跳出 App”。
    private func externalLink(_ title: LocalizedStringKey, url: URL) -> some View {
        Link(destination: url) {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .accessibilityHint("Opens in your browser")
    }
}
