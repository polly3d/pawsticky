import Testing
@testable import Core

/// PetNoteRenderer 布局引擎测试（W6-1）。
struct PetNoteRendererTests {

    // MARK: - Layout 完整性

    @Test func allPoseAndSizeCombinationsProduceValidLayouts() {
        for pose in PetPose.allCases {
            for sizeClass: PetNoteRenderer.SizeClass in [.small, .medium, .large] {
                let layout = PetNoteRenderer.layout(pose: pose, sizeClass: sizeClass)

                #expect(layout.petWidthRatio > 0 && layout.petWidthRatio <= 1,
                    "petWidthRatio out of range for \(pose)/\(sizeClass)")
                #expect(layout.noteWidthRatio > 0 && layout.noteWidthRatio <= 1,
                    "noteWidthRatio out of range for \(pose)/\(sizeClass)")
                #expect(layout.noteHeightRatio > 0 && layout.noteHeightRatio <= 1,
                    "noteHeightRatio out of range for \(pose)/\(sizeClass)")
            }
        }
    }

    @Test func smallWidgetPetIsSmallerThanNote() {
        let layout = PetNoteRenderer.layout(pose: .holding, sizeClass: .small)
        #expect(layout.petWidthRatio < layout.noteWidthRatio)
    }

    @Test func mediumWidgetNoteHasHorizontalOffset() {
        let layout = PetNoteRenderer.layout(pose: .holding, sizeClass: .medium)
        #expect(layout.noteHorizontalOffset > 0, "Medium widget note should be offset to make room for pet")
    }

    // MARK: - Pose Inference

    @Test func inferPoseReturnsSleepingWhenNoNotes() {
        let pose = PetNoteRenderer.inferPose(isDone: false, isOverdue: false, hasNotes: false)
        #expect(pose == .sleeping)
    }

    @Test func inferPoseReturnsHappyWhenDone() {
        let pose = PetNoteRenderer.inferPose(isDone: true, isOverdue: false, hasNotes: true)
        #expect(pose == .happy)
    }

    @Test func inferPoseReturnsHoldingForNormalNote() {
        let pose = PetNoteRenderer.inferPose(isDone: false, isOverdue: false, hasNotes: true)
        #expect(pose == .holding)
    }

    @Test func inferPoseReturnsHoldingForOverdueNote() {
        let pose = PetNoteRenderer.inferPose(isDone: false, isOverdue: true, hasNotes: true)
        #expect(pose == .holding)
    }

    // MARK: - Mood Inference

    @Test func inferMoodReturnsHappyWhenDone() {
        let mood = PetNoteRenderer.inferMood(isDone: true, isOverdue: false)
        #expect(mood == .happy)
    }

    @Test func inferMoodReturnsWorriedWhenOverdue() {
        let mood = PetNoteRenderer.inferMood(isDone: false, isOverdue: true)
        #expect(mood == .worried)
    }

    @Test func inferMoodReturnsNeutralOtherwise() {
        let mood = PetNoteRenderer.inferMood(isDone: false, isOverdue: false)
        #expect(mood == .neutral)
    }

    // MARK: - PetAsset

    @Test func allSpeciesHaveUniqueImageNames() {
        var names = Set<String>()
        for species in PetSpecies.allCases {
            for pose in PetPose.allCases {
                let name = PetAsset.imageName(species: species, pose: pose)
                #expect(!names.contains(name), "Duplicate asset name: \(name)")
                names.insert(name)
            }
        }
        #expect(names.count == PetSpecies.allCases.count * PetPose.allCases.count)
    }

    @Test func allSpeciesHavePlaceholderSymbols() {
        for species in PetSpecies.allCases {
            let symbol = PetAsset.placeholderSymbol(species: species)
            #expect(!symbol.isEmpty)
        }
    }

    @Test func allSpeciesHaveDisplayNames() {
        for species in PetSpecies.allCases {
            let name = PetAsset.displayName(species: species)
            #expect(!name.isEmpty)
        }
    }

    @Test func accentHuesAreWithinValidRange() {
        for species in PetSpecies.allCases {
            let hue = PetAsset.accentHue(species: species)
            #expect(hue >= 0 && hue <= 360, "Hue out of range for \(species)")
        }
    }
}
