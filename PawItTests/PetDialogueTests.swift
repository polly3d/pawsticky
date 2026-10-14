import Testing
import Core
@testable import PawIt

/// 宠物对话文案的行为钉子：气泡里叫的名字必须就是卡片 / 数据库里的名字。
///
/// 背景：文案曾写死 Mochi / Luna / Coco / Hachi / Mimi / Peanut，而卡片、数据库、
/// 无障碍标签用的是 `PetAsset.displayName`（Tabby / Misty / Biscuit / Mochi / Bun / Nugget）——
/// 用户点了 Tabby，气泡却说 "Mochi is ready to help!"（而 Mochi 是另一只柴犬）。
struct PetDialogueTests {

    private func otherNames(than species: PetSpecies) -> [String] {
        PetSpecies.allCases
            .filter { $0 != species }
            .map { PetAsset.displayName(species: $0) }
    }

    @Test func selectionLineUsesTheCardName() {
        for species in PetSpecies.allCases {
            let name = PetAsset.displayName(species: species)
            let line = PetDialogue.selection(species)
            #expect(line.contains(name), "\(species) 的选宠对话 \"\(line)\" 应包含卡片上的名字 \(name)")
        }
    }

    @Test func switchLineUsesTheCardName() {
        for species in PetSpecies.allCases {
            let name = PetAsset.displayName(species: species)
            let line = PetDialogue.switched(species)
            #expect(line.contains(name), "\(species) 的换宠对话 \"\(line)\" 应包含卡片上的名字 \(name)")
        }
    }

    @Test func linesNeverNameADifferentPet() {
        for species in PetSpecies.allCases {
            for line in [PetDialogue.selection(species), PetDialogue.switched(species)] {
                for other in otherNames(than: species) {
                    #expect(!line.contains(other), "\(species) 的对话 \"\(line)\" 不应出现别的宠物的名字 \(other)")
                }
            }
        }
    }
}
