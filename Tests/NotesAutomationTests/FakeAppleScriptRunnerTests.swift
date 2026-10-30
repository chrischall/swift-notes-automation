import Testing
@testable import NotesAutomation

/// Guards the test fixture itself: its `Mutex`-backed state must record
/// every call and serve queued responses FIFO even under concurrent use.
@Suite("FakeAppleScriptRunner")
struct FakeAppleScriptRunnerTests {
    @Test("serves queued responses FIFO, then the default")
    func fifoThenDefault() async throws {
        let runner = FakeAppleScriptRunner()
        runner.queue("first")
        runner.queueError("boom")
        #expect(try await runner.run(source: "a") == "first")
        await #expect(throws: AppleScriptError.runtime("boom")) {
            try await runner.run(source: "b")
        }
        #expect(try await runner.run(source: "c") == "")
        #expect(runner.calls == ["a", "b", "c"])
    }

    @Test("records every call made concurrently")
    func concurrentCalls() async throws {
        let runner = FakeAppleScriptRunner()
        try await withThrowingTaskGroup { group in
            for i in 0 ..< 200 {
                group.addTask { _ = try await runner.run(source: "s\(i)") }
            }
            try await group.waitForAll()
        }
        #expect(Set(runner.calls) == Set((0 ..< 200).map { "s\($0)" }))
    }
}
