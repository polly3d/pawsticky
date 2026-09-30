import Testing
import Core

struct PawItTests {
    @Test func smoke() {
        #expect(PawItInfo.appGroupID == "group.com.pawit.shared")
    }
}
