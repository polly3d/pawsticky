import Foundation

/// 小组件画廊 / 占位用的示例数据包（一张便签 + 它的清单 + 一只宠物）。
public struct WidgetSampleContent: Equatable, Sendable {
    public let note: Note
    public let items: [NoteItem]
    public let pet: PetProfile
}

/// 小组件画廊（添加小组件时的预览）与占位用的示例内容。
///
/// 新装用户的库是空的，而「添加小组件」画廊恰好是新用户决定要不要加的时刻——
/// 这时若读真实数据，预览就是一张空状态，看不出产品长什么样。
/// 所以画廊预览走这里的示例：有标题、有半完成的清单、有提醒、有宠物。
/// 示例**从不写库**，只在 provider 判定 `isPreview` 时用于渲染。
public enum WidgetSample {

    // 固定标识：SwiftUI 靠 id 做 diff / 动画，每次调用换新 id 会让预览闪烁。
    private static let noteID = UUID(uuidString: "5E1F0000-0000-4000-8000-000000000001")!
    private static let itemIDs = [
        UUID(uuidString: "5E1F0000-0000-4000-8000-000000000011")!,
        UUID(uuidString: "5E1F0000-0000-4000-8000-000000000012")!,
        UUID(uuidString: "5E1F0000-0000-4000-8000-000000000013")!,
    ]

    /// 生成示例内容。
    /// - Parameters:
    ///   - now: 当前时刻；示例提醒定在其 2 小时后——永远是「还没到」，不会渲染成逾期红字。
    ///   - selectedPet: 用户已选的宠物（选过宠物但还没写便签的人看到的是自己的宠物）；
    ///     nil 时退回猫（首发主打宠物）。
    public static func make(now: Date, selectedPet: PetProfile?) -> WidgetSampleContent {
        let note = Note(
            id: noteID,
            text: "Pick up groceries",
            createdAt: now,
            done: false,
            dueDate: now.addingTimeInterval(2 * 60 * 60),
            position: 0
        )

        // 第一项已勾选、其余未勾：同时展示划线样式与未完成样式，进度恰为 1/3。
        let items = [("Milk", true), ("Eggs", false), ("Bread", false)]
            .enumerated()
            .map { index, entry in
                NoteItem(
                    id: itemIDs[index], noteId: noteID,
                    text: entry.0, done: entry.1,
                    position: index, createdAt: now
                )
            }

        let pet = selectedPet ?? PetProfile(
            id: PetSpecies.cat.rawValue,
            species: .cat,
            displayName: PetAsset.displayName(species: .cat),
            isSelected: true,
            acquiredAt: now
        )

        return WidgetSampleContent(note: note, items: items, pet: pet)
    }
}
