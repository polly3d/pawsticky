import SwiftUI
import Core

/// 分享卡片预览+导出（W7-4）——预览 + 导出到相册/IG Story。
struct ShareCardSheet: View {

    let note: Note
    @State private var pet: PetProfile?
    @State private var growthState: GrowthState?
    @State private var showShareSheet = false
    @State private var renderedImage: UIImage?
    @State private var showSavedAlert = false

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
                VStack(spacing: 12) {
                    Button {
                        exportAndShare()
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)

                    Button {
                        saveToPhotos()
                    } label: {
                        Label("Save to Photos", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
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
            .alert("Saved to Photos", isPresented: $showSavedAlert) {
                Button("OK") { }
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

    private func saveToPhotos() {
        guard let image = ShareCardView.renderImage(
            note: note, pet: pet, growthState: growthState
        ) else { return }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        showSavedAlert = true
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
