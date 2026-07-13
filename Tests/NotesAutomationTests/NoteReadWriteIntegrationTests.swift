import Foundation
import Testing
@testable import NotesAutomation

/// End-to-end tests for the read/write surface added alongside the
/// original CRUD: ``NoteService/get(id:)``, ``NoteService/update(id:title:body:folder:)``,
/// and ``NoteService/folders()``. These exercise the *real* AppleScript —
/// the part unit tests (which only assert script shape) can't validate.
///
/// **Opt-in**: set `NOTES_AUTOMATION_INTEGRATION=1`. Each test creates a
/// uniquely-named folder, exercises it, then deletes it.
@Suite("NoteService read/write integration")
struct NoteReadWriteIntegrationTests {
    static let gate = ProcessInfo.processInfo.environment["NOTES_AUTOMATION_INTEGRATION"] != "1"
    static let folderPrefix = "NotesAutomationTests"

    private func makeFixture() -> (NoteService, String) {
        let service = NoteService(runner: NSAppleScriptRunner())
        let folder = "\(Self.folderPrefix)-\(UUID().uuidString.prefix(8))"
        return (service, folder)
    }

    private func deleteFolder(named name: String) async {
        let esc = name.replacingOccurrences(of: "\"", with: "\\\"")
        let runner = NSAppleScriptRunner()
        _ = try? await runner.run(source: """
        tell application "Notes"
            try
                delete (every folder whose name is "\(esc)")
            end try
        end tell
        """)
    }

    @Test("get returns the full untruncated body, HTML, and dates",
          .disabled(if: gate, "set NOTES_AUTOMATION_INTEGRATION=1"))
    func getFullBody() async throws {
        let (service, testFolder) = makeFixture()
        defer { Task { await deleteFolder(named: testFolder) } }

        // A body comfortably longer than the ~200-char snippet cap so we
        // can prove `get` is not returning the truncated preview.
        let token = String(UUID().uuidString.prefix(8))
        let longBody = (1...40).map { "Paragraph \($0) — token \(token)." }.joined(separator: "\n")
        let title = "GetTest-\(token)"

        let id = try await service.create(title: title, body: longBody, folder: testFolder)
        try await Task.sleep(nanoseconds: 500_000_000)

        let detail = try await service.get(id: id)
        #expect(detail.title == title)
        #expect(detail.folder == testFolder)
        #expect(detail.plainText.count > 200)          // NOT snippet-truncated
        #expect(detail.plainText.contains("Paragraph 40"))
        #expect(detail.html.localizedCaseInsensitiveContains("<"))  // real HTML
        #expect(detail.creationDate != nil)             // isoDate handler works
        #expect(detail.modificationDate != nil)
    }

    @Test("update edits an existing note's title and body in place",
          .disabled(if: gate, "set NOTES_AUTOMATION_INTEGRATION=1"))
    func updateInPlace() async throws {
        let (service, testFolder) = makeFixture()
        defer { Task { await deleteFolder(named: testFolder) } }

        let token = String(UUID().uuidString.prefix(8))
        let id = try await service.create(
            title: "Before-\(token)", body: "original body \(token)", folder: testFolder
        )
        try await Task.sleep(nanoseconds: 500_000_000)

        let newBodyToken = String(UUID().uuidString.prefix(8))
        try await service.update(
            id: id, title: "After-\(token)", body: "rewritten body \(newBodyToken)"
        )
        try await Task.sleep(nanoseconds: 500_000_000)

        let detail = try await service.get(id: id)
        #expect(detail.title == "After-\(token)")
        #expect(detail.plainText.contains(newBodyToken))
    }

    @Test("folders enumerates a freshly-created folder",
          .disabled(if: gate, "set NOTES_AUTOMATION_INTEGRATION=1"))
    func foldersEnumerate() async throws {
        let (service, testFolder) = makeFixture()
        defer { Task { await deleteFolder(named: testFolder) } }

        _ = try await service.create(title: "Folder probe", body: "x", folder: testFolder)
        try await Task.sleep(nanoseconds: 500_000_000)

        let names = try await service.folders()
        #expect(names.contains(testFolder))
    }
}
