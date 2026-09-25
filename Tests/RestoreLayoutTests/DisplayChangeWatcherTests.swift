import Testing
@testable import RestoreLayout

@Suite("Display change watcher")
struct DisplayChangeWatcherTests {
    @Test func disabledNeverRestores() {
        #expect(!DisplayChangeWatcher.shouldRestore(enabled: false, previous: "A", current: "B"))
        #expect(!DisplayChangeWatcher.shouldRestore(enabled: false, previous: "A", current: "A"))
    }

    @Test func unchangedDisplaySetDoesNotRestore() {
        #expect(!DisplayChangeWatcher.shouldRestore(enabled: true, previous: "A+B", current: "A+B"))
    }

    @Test func changedDisplaySetRestoresWhenEnabled() {
        #expect(DisplayChangeWatcher.shouldRestore(enabled: true, previous: "A+B", current: "A"))
        #expect(DisplayChangeWatcher.shouldRestore(enabled: true, previous: "A", current: "A+B"))
    }
}
