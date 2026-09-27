import Testing
@testable import Realign

@Suite("Display change watcher")
struct DisplayChangeWatcherTests {
    typealias Decision = DisplayChangeWatcher.Decision

    /// Truth table: (enabled, previous, current) -> decision.
    @Test(arguments: [
        // Empty current is transient: keep previous, whatever else holds.
        (true, "A", "", Decision.ignore),
        (false, "A", "", Decision.ignore),
        (true, "", "", Decision.ignore),
        // Unchanged set: record only.
        (true, "A+B", "A+B", Decision.record),
        (false, "A+B", "A+B", Decision.record),
        // Changed while disabled: record only, so enabling later does not replay it.
        (false, "A+B", "A", Decision.record),
        (false, "A", "A+B", Decision.record),
        // First real set after starting with none: baseline only.
        (true, "", "A", Decision.record),
        // Changed while enabled: restore.
        (true, "A+B", "A", Decision.restore),
        (true, "A", "A+B", Decision.restore),
    ])
    func decide(enabled: Bool, previous: String, current: String, expected: Decision) {
        #expect(
            DisplayChangeWatcher.decide(enabled: enabled, previous: previous, current: current)
                == expected
        )
    }
}
