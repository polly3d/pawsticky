import SwiftUI
import Core

/// 分享卡片预览+导出（W7-4）——预览 + 经系统分享面板导出（"Save Image" / IG Story 等）。
///
/// 不直接调用 `UIImageWriteToSavedPhotosAlbum`：Info.plist 没有相册用途描述时,
/// iOS 会在受保护资源访问时直接终止进程。保存到相册走分享面板自带的 "Save Image"，
/// 由系统界面完成，无需相册权限。
struct ShareCardSheet: View {

    let note: Note
    @State private var pet: PetProfile?
    @State private var growthState: GrowthState?
    @State private var showShareSheet = false
    @State private var renderedImage: UIImage?

    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // 预览
                ShareCardView(note: note, pet: pet, growthState: growthState)
                    .scaleEffect(
                        ShareCardView.previewSize.width / ShareCardView.cardSize.width
                    )
                    .frame(
                        width: ShareCardView.previewSize.width,
                        height: ShareCardView.previewSize.height
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)

                // 按钮
                Button {
                    exportAndShare()
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .padding(.horizontal, 40)
            }
            .padding()
            .navigationTitle("Share Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onDismiss() }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let image = renderedImage {
                    ActivityView(items: [image])
                }
            }
        }
        .task { loadData() }
    }

    private func loadData() {
        guard let store = SharedStore.cachedAppGroup() else { return }
        pet = try? store.selectedPet()
        if let petId = pet?.id {
            growthState = try? store.growthState(petId: petId)
        }
    }

    private func exportAndShare() {
        renderedImage = ShareCardView.renderImage(
            note: note, pet: pet, growthState: growthState
        )
        showShareSheet = true
    }
}

/// UIActivityViewController wrapper for SwiftUI。
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
