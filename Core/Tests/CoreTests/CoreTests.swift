import Foundation
import Testing
@testable import Core

struct CoreTests {
    @Test func smoke() {
        #expect(PawItInfo.appGroupID == "group.com.fitpetgo.pawsticky.shared")
    }

    @Test func noteEquatable() {
        let id = UUID()
        let createdAt = Date(timeIntervalSinceReferenceDate: 0)
        #expect(
            Note(id: id, text: "喂食", createdAt: createdAt)
                == Note(id: id, text: "喂食", createdAt: createdAt)
        )
    }
}
