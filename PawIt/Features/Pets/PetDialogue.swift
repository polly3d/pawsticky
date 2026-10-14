import Core

/// 宠物对话文案（欢迎流程选宠 / 日常换宠时气泡里的话）。
///
/// 从 `OnboardingView` 与 `PetSelectionView` 里各自私有的两份 switch 收敛到这里：
/// 名字一律取自 `PetAsset.displayName`，与卡片、数据库、无障碍标签是同一个来源——
/// 此前文案里写死的是 Mochi / Luna / Coco…，用户点了 Tabby，气泡却说 "Mochi is ready to help!"。
/// 单元测试（`PetDialogueTests`）钉住"文案里的名字 = 卡片上的名字"。
enum PetDialogue {

    /// 欢迎流程里选中宠物后的宣言。
    static func selection(_ species: PetSpecies) -> String {
        let name = PetAsset.displayName(species: species)
        switch species {
        case .cat:     return "\(name) is ready to help! Warm & playful, just for you."
        case .graycat: return "\(name) will keep things calm and organized for you."
        case .corgi:   return "\(name) can't wait to get started! So much energy!"
        case .shiba:   return "\(name) will remember everything. Count on it."
        case .rabbit:  return "\(name) is curious about what you'll write first!"
        case .hamster: return "Tiny but mighty! \(name)'s got your back."
        }
    }

    /// 日常"My Pet"里换宠后的反馈。
    static func switched(_ species: PetSpecies) -> String {
        let name = PetAsset.displayName(species: species)
        switch species {
        case .cat:     return "\(name) is happy to see you again!"
        case .graycat: return "\(name) purrs softly. Ready to help."
        case .corgi:   return "\(name)'s tail is wagging like crazy!"
        case .shiba:   return "\(name) gives you a cool nod."
        case .rabbit:  return "\(name) hops with excitement!"
        case .hamster: return "\(name) squeaks with joy!"
        }
    }
}
