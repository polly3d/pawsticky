import SwiftUI

// MARK: - 内联状态行

/// 设置页里的一行内联结果：成功绿色对勾，失败橙色三角。
/// 不用弹窗的理由见 `BackupController`。
struct BackupStatusRow: View {
    let message: String
    let isSuccess: Bool

    var body: some View {
        Label {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isSuccess ? .green : .orange)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 保存备份页

/// 设置 → Back Up Notes：口令可选（留空 = 明文备份），然后交给系统“存储到文件”面板。
struct BackupExportView: View {
    let controller: BackupController

    @State private var passphrase = ""
    @State private var confirmation = ""

    private var check: BackupPassphraseCheck {
        BackupPassphrasePolicy.check(passphrase, confirmation: confirmation)
    }

    private var canSave: Bool {
        (check == .blank || check == .acceptable) && !controller.isWorking
    }

    /// 系统面板是否应当显示：由控制器里有没有待保存的文档决定。
    private var isExporting: Binding<Bool> {
        Binding(
            get: { controller.document != nil },
            set: { if !$0 { controller.document = nil } }
        )
    }

    var body: some View {
        Form {
            Section {
                SecureField("Passphrase", text: $passphrase)
                if !passphrase.isEmpty {
                    SecureField("Confirm passphrase", text: $confirmation)
                }
            } header: {
                Text("Passphrase (optional)")
            } footer: {
                passphraseFooter
            }

            Section {
                Button {
                    Task { await controller.startExport(passphrase: passphrase) }
                } label: {
                    HStack {
                        Text("Save Backup…")
                        Spacer()
                        if controller.isWorking { ProgressView() }
                    }
                }
                .disabled(!canSave)

                if let outcome = controller.exportOutcome {
                    BackupStatusRow(message: outcome.message, isSuccess: outcome.isSuccess)
                }
            } footer: {
                Text("You choose where the file is saved, for example in iCloud Drive. PawSticky never uploads your notes.")
            }
        }
        .scrollContentBackground(.hidden)
        .warmBackground()
        .navigationTitle("Back Up Notes")
        .navigationBarTitleDisplayMode(.inline)
        // 呈现类修饰符各挂在自己的空视图上：同一个视图叠多个 sheet / alert / 文件面板，
        // 在 SwiftUI 里互相抢呈现槽位是老问题。
        .background {
            Color.clear.fileExporter(
                isPresented: isExporting,
                document: controller.document,
                contentType: .json,
                defaultFilename: BackupFile.defaultName()
            ) { result in
                controller.exportFinished(result)
            }
        }
        .onChange(of: controller.exportOutcome) { _, outcome in
            guard let outcome else { return }
            if outcome.isSuccess {
                // 口令用完即清：不让它留在屏幕与内存里
                passphrase = ""
                confirmation = ""
            }
            AccessibilityNotification.Announcement(outcome.message).post()
        }
        .onDisappear { controller.exportOutcome = nil }
    }

    @ViewBuilder
    private var passphraseFooter: some View {
        switch check {
        case .blank:
            Text("Leave blank to save a plain backup. Add a passphrase to encrypt it — you'll need the same passphrase to restore, and it can't be recovered if you forget it.")
        case .tooShort(let minimum):
            Text("Use at least \(minimum) characters.")
        case .mismatch where confirmation.isEmpty:
            Text("Enter the passphrase again to confirm.")
        case .mismatch:
            Text("Passphrases don't match.")
                .foregroundStyle(.red)
        case .acceptable:
            Text("This backup will be encrypted. Keep the passphrase somewhere safe — it can't be recovered.")
        }
    }
}

// MARK: - 待确认的恢复

/// 选好备份文件后出现在设置页里的确认卡片：恢复会**整体替换**现有数据，
/// 所以必须由用户再点一次红色按钮才动手（加密备份在这里输入口令）。
struct BackupRestoreCard: View {
    let controller: BackupController

    @State private var passphrase = ""

    var body: some View {
        if let prompt = controller.prompt {
            Section {
                if let name = controller.stagedFileName {
                    LabeledContent("Backup") {
                        Text(name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                if prompt == .passphrase {
                    SecureField("Backup passphrase", text: $passphrase)
                }
                Button(role: .destructive) {
                    // 口令随点随清：输错时让用户重新输入，而不是在看不见的输入框里改某一位
                    let entered = passphrase
                    passphrase = ""
                    Task { await controller.confirmRestore(passphrase: entered) }
                } label: {
                    Text("Replace All Notes and Pets")
                }
                .disabled(controller.isWorking || (prompt == .passphrase && passphrase.isEmpty))

                Button("Cancel", role: .cancel) {
                    passphrase = ""
                    controller.cancelRestore()
                }
                .disabled(controller.isWorking)
            } header: {
                Text("Restore")
            } footer: {
                Text("This replaces every note and pet on this device with the contents of the backup. It can't be undone.")
            }
        }
    }
}
