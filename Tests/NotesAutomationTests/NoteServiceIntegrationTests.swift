import Foundation
import Testing
@testable import NotesAutomation

/// End-to-end tests against the user's real Notes.app.
///
/// Requires Automation permission granted to the test binary (macOS will
/// prompt the first time). Each test creates a uniquely-named folder,
/// exercises it, then deletes it — so repeated runs don't leak state.
///
/// **Opt-in**: set `NOTES_AUTOMATION_INTEGRATION=1` in the environment
/// before running `swift test`. Unset, every test in this suite is
/// skipped — keeping CI deterministic and permission-prompt free.
///
/// ```bash
/// NOTES_AUTOMATION_INTEGRATION=1 swift test
/// ```
@Suite("NoteService integration")
struct NoteServiceIntegrationTests {
    /// Shared trait applied to every test in this suite. When the env var
    /// isn't `"1"`, Swift Testing skips the test with the given comment.
    static let enabledTrait: any TestTrait = .disabled(
        if: ProcessInfo.processInfo.environment["NOTES_AUTOMATION_INTEGRATION"] != "1",
        "set NOTES_AUTOMATION_INTEGRATION=1 to run against real Notes.app"
    )

    /// Folder-name prefix for test artifacts. Crash cleanup matches on this
    /// — a dangling folder with this prefix is always from a prior run.
    static let folderPrefix = "NotesAutomationTests"

    /// Best-effort cleanup: delete every folder whose name begins with the
    /// suite's prefix. Called at the start of each test so a previous
    /// crashed run can't pollute assertions.
    static func cleanUpPriorRuns() async {
        let runner = NSAppleScriptRunner()
        let source = """
        tell application "Notes"
            try
                delete (every folder whose name starts with "\(folderPrefix)")
            end try
        end tell
        """
        _ = try? await runner.run(source: source)
    }

    /// Delete a specific test folder by exact name.
    static func deleteFolder(named name: String) async {
        let esc = name.replacingOccurrences(of: "\"", with: "\\\"")
        let runner = NSAppleScriptRunner()
        let source = """
        tell application "Notes"
            try
                delete (every folder whose name is "\(esc)")
            end try
        end tell
        """
        _ = try? await runner.run(source: source)
    }

    /// Construct a fresh service + unique test-folder name per test.
    private func makeFixture() -> (NoteService, String) {
        let service = NoteService(runner: NSAppleScriptRunner())
        let folder = "\(Self.folderPrefix)-\(UUID().uuidString.prefix(8))"
        return (service, folder)
    }

    // MARK: - Tests

    @Test("list returns a well-shaped array from real Notes.app",
          .disabled(if: ProcessInfo.processInfo.environment["NOTES_AUTOMATION_INTEGRATION"] != "1",
                    "set NOTES_AUTOMATION_INTEGRATION=1"))
    func listSmokes() async throws {
        await Self.cleanUpPriorRuns()
        let (service, _) = makeFixture()

        let notes = try await service.list(limit: 5)

        // The user may have zero notes — we can only assert shape.
        #expect(notes.count >= 0)
        if let first = notes.first {
            #expect(!first.id.isEmpty)
            #expect(!first.title.isEmpty || !first.snippet.isEmpty)
        }
    }

    @Test("create → search → list → cleanup",
          .disabled(if: ProcessInfo.processInfo.environment["NOTES_AUTOMATION_INTEGRATION"] != "1",
                    "set NOTES_AUTOMATION_INTEGRATION=1"))
    func roundTrip() async throws {
        await Self.cleanUpPriorRuns()
        let (service, testFolder) = makeFixture()
        defer { Task { await Self.deleteFolder(named: testFolder) } }

        let uniqueTitle = "IntegrationTest-\(UUID().uuidString.prefix(8))"
        let body = "Body with unique token \(UUID().uuidString.prefix(8))"

        // Create
        let id = try await service.create(title: uniqueTitle, body: body, folder: testFolder)
        #expect(!id.isEmpty)

        // Give Notes a brief moment to index
        try await Task.sleep(nanoseconds: 500_000_000)

        // Find by title
        let byTitle = try await service.search(query: uniqueTitle, limit: 10)
        let titleHit = byTitle.first(where: { $0.title == uniqueTitle })
        #expect(titleHit != nil, "expected to find the note by its unique title")

        // It should be in the most-recent list and attributed to our folder
        let recent = try await service.list(limit: 20)
        let listedHit = recent.first(where: { $0.id == titleHit?.id })
        #expect(listedHit != nil, "expected the new note in the recent list")
        #expect(listedHit?.folder == testFolder)
    }

    @Test("search for random garbage returns []",
          .disabled(if: ProcessInfo.processInfo.environment["NOTES_AUTOMATION_INTEGRATION"] != "1",
                    "set NOTES_AUTOMATION_INTEGRATION=1"))
    func searchMiss() async throws {
        await Self.cleanUpPriorRuns()
        let (service, _) = makeFixture()
        let garbage = "no-such-note-\(UUID().uuidString)"
        let hits = try await service.search(query: garbage)
        #expect(hits.isEmpty)
    }
}
