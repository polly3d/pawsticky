import Testing
import Foundation
import Core
@testable import PawIt

/// C9（B3 真机发现）：Live Activities 被系统关闭后，pin 不能再静默失败——
/// 必须把失败暴露给 UI（typed error + 归因），弹窗指路"去 iPhone 设置打开"，
/// 设置页提供可发现的状态行。这里钉住"失败可见 + 文案指路"两件事。
struct LiveActivityPinTests {

    @Test func pinThrowsTypedErrorWhenActivitiesAreDisabled() {
        #expect(throws: LiveActivityUnavailableError.activitiesDisabled) {
            try LiveActivityManager.pin(
                note: Note(text: "milk"),
                items: [],
                pet: nil,
                activitiesEnabled: { false }
            )
        }
    }

    @Test func pinFailureAttributionSeparatesGuidedFromGeneric() {
        #expect(
            PinIssue.issue(for: LiveActivityUnavailableError.activitiesDisabled)
                == .liveActivitiesDisabled
        )
        #expect(PinIssue.issue(for: URLError(.badURL)) == .pinFailed)
    }

    @Test func disabledIssueGuidesUserToSystemSettings() {
        let issue = PinIssue.liveActivitiesDisabled
        #expect(issue.alertTitle.contains("Live Activities"))
        #expect(issue.alertMessage.contains("Settings"))
        #expect(issue.showsSettingsShortcut)
        #expect(!PinIssue.pinFailed.showsSettingsShortcut)
    }

    @Test func liveActivitiesStatusTextPinsOnOffVocabulary() {
        #expect(LiveActivityStatusText.text(activitiesEnabled: true) == "On")
        #expect(LiveActivityStatusText.text(activitiesEnabled: false) == "Off")
    }
}
