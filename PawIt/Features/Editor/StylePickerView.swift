import SwiftUI
import Core

/// 便签颜色选择器（Soft Companion 风格）——6 款预设色圆形按钮 + 名称标签。
///
/// 升级：更大点击区域、选中态放大 + 弹跳、显示颜色名、暖色标题。
struct StylePickerView: View {
    @Binding var selectedStyle: String?

    private let presets = NoteStylePreset.allCases

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Color")
                .font(AppTheme.cardTitle)

            HStack(spacing: 10) {
                ForEach(presets, id: \.rawValue) { preset in
                    Button {
                        withAnimation(AppTheme.petHappyAnimation) {
                            selectedStyle = preset.rawValue
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Circle()
                                .fill(preset.backgroundColor)
                                .frame(
                                    width: isSelected(preset) ? 42 : 36,
                                    height: isSelected(preset) ? 42 : 36
                                )
                                .overlay(
                                    Circle()
                                        .strokeBorder(
                                            isSelected(preset) ? Color.primary : .clear,
                                            lineWidth: 2.5
                                        )
                                )
                                .overlay {
                                    if isSelected(preset) {
                                        Image(systemName: "checkmark")
                                            .font(.caption.bold())
                                            .foregroundStyle(preset.textColor)
                                    }
                                }
                                .shadow(
                                    color: AppTheme.lightShadow.color,
                                    radius: AppTheme.lightShadow.radius,
                                    y: AppTheme.lightShadow.y
                                )

                            if isSelected(preset) {
                                Text(preset.displayName)
                                    .font(.system(.caption2, design: .rounded, weight: .medium))
                                    .foregroundStyle(.primary)
                                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                            }
                        }
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
