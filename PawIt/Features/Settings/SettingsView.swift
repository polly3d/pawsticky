import SwiftUI
import Core

/// 设置页面（Soft Companion 风格）——暖色背景一致。
struct SettingsView: View {
    @State private var growthEnabled: Bool = GrowthSettings.isEnabled
    @State private var backup: BackupController
    @State private var showImporter = false
    let onDismiss: () -> Void

    init(
        repository: NoteRepository? = NoteRepository.cachedAppGroup(),
        onDismiss: @escaping () -> Void
    ) {
        _backup = State(initialValue: BackupController(service: repository.map(BackupService.init)))
        self.onDismiss = onDismiss
    }

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

                dataSection
                BackupRestoreCard(controller: backup)
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .warmBackground()
            // 文件选择器挂在独立的空视图上，避免与其它呈现修饰符抢槽位
            .background {
                Color.clear.fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                    Task { await backup.filePicked(result) }
                }
            }
            .onChange(of: backup.restoreOutcome) { _, outcome in
                guard let outcome else { return }
                AccessibilityNotification.Announcement(outcome.message).post()
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

    // MARK: - Data

    /// 备份 / 恢复：v1.0 没有账号与云端，换机 / 防丢靠用户自己保管的备份文件。
    private var dataSection: some View {
        Section {
            NavigationLink {
                BackupExportView(controller: backup)
            } label: {
                Label("Back Up Notes", systemImage: "square.and.arrow.up")
            }
            .disabled(backup.isWorking)

            Button {
                showImporter = true
            } label: {
                HStack {
                    Label("Restore from Backup", systemImage: "square.and.arrow.down")
                    Spacer()
                    if backup.isWorking { ProgressView() }
                }
            }
            // 确认卡片还开着时，先处理完（替换或取消）再选下一个文件
            .disabled(backup.isWorking || backup.prompt != nil)

            if let outcome = backup.restoreOutcome {
                BackupStatusRow(message: outcome.message, isSuccess: outcome.isSuccess)
            }
        } header: {
            Text("Data")
        } footer: {
            Text("Backups are files you save wherever you like, such as iCloud Drive. PawSticky never uploads your notes.")
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
