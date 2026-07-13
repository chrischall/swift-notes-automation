import Foundation
import Testing
@testable import NotesAutomation

/// Tests for folder enumeration — ``NoteService/folders()`` (AppleScript)
/// and ``NoteStoreReader/folders()`` (SQLite). Both let a caller browse
/// the set of folders rather than only using `folder` as a list/search
/// filter.
@Suite("Folder enumeration")
struct NoteFoldersTests {
    // MARK: - Service (AppleScript)

    @Test("foldersScript emits one folder name per line")
    func scriptShape() {
        let s = NoteService.foldersScript()
        #expect(s.contains("tell application \"Notes\""))
        #expect(s.contains("folder"))
        #expect(s.contains("linefeed") || s.contains("ASCII character 10"))
    }

    @Test("parseFolderLines splits lines and drops blanks")
    func parseLines() {
        let names = NoteService.parseFolderLines("Notes\nWork\n\nRecipes\n")
        #expect(names == ["Notes", "Work", "Recipes"])
    }

    @Test("folders returns parsed names from the runner output")
    func foldersDispatches() async throws {
        let runner = FakeAppleScriptRunner()
        runner.queue("Notes\nWork\nTravel\n")
        let svc = NoteService(runner: runner)

        let names = try await svc.folders()

        #expect(names == ["Notes", "Work", "Travel"])
        #expect(runner.calls.count == 1)
    }

    @Test("folders propagates runner errors")
    func foldersPropagates() async throws {
        let runner = FakeAppleScriptRunner()
        runner.queueError("Not authorized to send Apple events to Notes.")
        let svc = NoteService(runner: runner)
        await #expect(throws: AppleScriptError.self) {
            _ = try await svc.folders()
        }
    }

    // MARK: - Reader (SQLite)

    @Test("reader folders lists folder names, excluding the trash folder")
    func readerFolders() async throws {
        let path = try NoteStoreFixture.create()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let reader = try NoteStoreReader(path: path)

        let names = try await reader.folders()

        // Fixture seeds "Notes", "Work", and a trash folder "Recently
        // Deleted" (ZFOLDERTYPE=1). Trash is excluded.
        #expect(Set(names) == ["Notes", "Work"])
    }
}
