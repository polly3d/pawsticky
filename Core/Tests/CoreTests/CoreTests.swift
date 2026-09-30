import Foundation
import Testing
@testable import Core

struct CoreTests {
    @Test func smoke() {
        #expect(PawItInfo.appGroupID == "group.com.pawit.shared")
    }

    @Test func noteEquatable() {
        let id = UUID()
        #expect(Note(id: id, title: "喂食") == Note(id: id, title: "喂食"))
    }
}
