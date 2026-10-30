import Foundation
import NotesAutomation
import Synchronization

/// In-memory AppleScriptRunner for tests. Records every script it was asked
/// to run, and replies with a queued result or a constant.
///
/// Genuinely `Sendable`: all mutable state lives behind a `Mutex`, so a
/// shared instance is safe under Swift Testing's parallel execution.
final class FakeAppleScriptRunner: AppleScriptRunner, Sendable {
    private struct State {
        /// Responses to hand out in FIFO order. When empty, `run` returns
        /// `defaultResponse`.
        var responses: [Result<String, AppleScriptError>] = []
        var defaultResponse: Result<String, AppleScriptError> = .success("")
        var calls: [String] = []
    }

    private let state = Mutex(State())

    /// Every script source passed to ``run(source:)``, in call order.
    var calls: [String] { state.withLock { $0.calls } }

    func run(source: String) async throws(AppleScriptError) -> String {
        let result = state.withLock { state in
            state.calls.append(source)
            return state.responses.isEmpty ? state.defaultResponse : state.responses.removeFirst()
        }
        return try result.get()
    }

    func queue(_ result: String) {
        state.withLock { $0.responses.append(.success(result)) }
    }

    func queueError(_ msg: String) {
        state.withLock { $0.responses.append(.failure(.runtime(msg))) }
    }
}
