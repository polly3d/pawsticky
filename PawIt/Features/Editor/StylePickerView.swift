import SwiftUI
import Core

/// 便签颜色选择器（W3-6）——6 款预设色圆形按钮，选中态带边框。
struct StylePickerView: View {
    @Binding var selectedStyle: String?

    private let presets = NoteStylePreset.allCases

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Color")
                .font(.headline)

            HStack(spacing: 12) {
                ForEach(presets, id: \.rawValue) { preset in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedStyle = preset.rawValue
                        }
                    } label: {
                        Circle()
                            .fill(preset.backgroundColor)
                            .frame(width: 36, height: 36)
                            .overlay(
                                Circle()
                                    .strokeBorder(isSelected(preset) ? Color.primary : .clear, lineWidth: 2.5)
                            )
                            .overlay {
                                if isSelected(preset) {
                                    Image(systemName: "checkmark")
                                        .font(.caption.bold())
                                        .foregroundStyle(preset.textColor)
                                }
                            }
                            .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(preset.displayName)
                    .accessibilityAddTraits(isSelected(preset) ? .isSelected : [])
                }
            }
        }
    }

    private func isSelected(_ preset: NoteStylePreset) -> Bool {
        let current = selectedStyle ?? NoteStylePreset.classicYellow.rawValue
        return current == preset.rawValue
    }
}
