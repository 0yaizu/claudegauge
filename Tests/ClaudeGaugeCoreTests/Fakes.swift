import Foundation
@testable import ClaudeGaugeCore

/// テスト専用の偽物。本物の Keychain・ネットワークには一切触れない。
final class FakeCommandRunner: CommandRunning, @unchecked Sendable {
    struct Call: Equatable {
        let executable: String
        let arguments: [String]
        let timeout: TimeInterval
    }

    var result: Result<CommandResult, CommandError>
    private(set) var calls: [Call] = []

    init(_ result: Result<CommandResult, CommandError>) {
        self.result = result
    }

    func run(_ executable: String, arguments: [String], timeout: TimeInterval) async throws -> CommandResult {
        calls.append(Call(executable: executable, arguments: arguments, timeout: timeout))
        return try result.get()
    }
}

final class FakeHTTPClient: HTTPClient, @unchecked Sendable {
    var result: Result<(Data, HTTPURLResponse), Error>
    private(set) var requests: [URLRequest] = []

    init(_ result: Result<(Data, HTTPURLResponse), Error>) {
        self.result = result
    }

    static func response(status: Int, body: Data = Data()) -> FakeHTTPClient {
        let url = URL(string: "https://api.anthropic.com/api/oauth/usage")!
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        return FakeHTTPClient(.success((body, response)))
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        return try result.get()
    }
}

final class FakeCredentialSource: CredentialSource, @unchecked Sendable {
    var result: Result<OAuthCredential, CredentialError>
    private(set) var loadCount = 0

    init(_ result: Result<OAuthCredential, CredentialError>) {
        self.result = result
    }

    func load() async throws -> OAuthCredential {
        loadCount += 1
        return try result.get()
    }
}

final class FakeUsageFetcher: UsageFetching, @unchecked Sendable {
    private var queue: [Result<UsageSnapshot, UsageAPIError>]
    private(set) var tokens: [String] = []

    init(_ queue: [Result<UsageSnapshot, UsageAPIError>]) {
        self.queue = queue
    }

    var callCount: Int { tokens.count }

    func fetch(accessToken: String, now: Date) async throws -> UsageSnapshot {
        tokens.append(accessToken)
        precondition(!queue.isEmpty, "FakeUsageFetcher: 想定外の呼び出し")
        return try queue.removeFirst().get()
    }
}

/// `fetch` の途中で止まり、`release()` で再開する。取得中の再入をテストするため。
final class GatedUsageFetcher: UsageFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var calls = 0
    private let snapshot: UsageSnapshot

    init(snapshot: UsageSnapshot) {
        self.snapshot = snapshot
    }

    var callCount: Int { locked { calls } }
    var isSuspended: Bool { locked { continuation != nil } }

    func fetch(accessToken: String, now: Date) async throws -> UsageSnapshot {
        locked { calls += 1 }
        await withCheckedContinuation { (next: CheckedContinuation<Void, Never>) in
            locked { continuation = next }
        }
        return snapshot
    }

    func release() {
        let next = locked { () -> CheckedContinuation<Void, Never>? in
            defer { continuation = nil }
            return continuation
        }
        next?.resume()
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

final class FakeUsageStore: UsageStore, @unchecked Sendable {
    var stored: PersistedUsage?
    private(set) var saveCount = 0

    init(_ stored: PersistedUsage? = nil) {
        self.stored = stored
    }

    func load() -> PersistedUsage? { stored }

    func save(_ usage: PersistedUsage) {
        saveCount += 1
        stored = usage
    }
}

final class MutableClock: @unchecked Sendable {
    var now: Date

    init(_ now: Date) {
        self.now = now
    }
}

enum TestSnapshot {
    static func make(fiveHour: Double = 7, weekly: Double = 14, at date: Date = TestClock.base) -> UsageSnapshot {
        UsageSnapshot(
            fiveHour: WindowUsage(utilization: fiveHour, resetsAt: date.addingTimeInterval(3600)),
            weekly: WindowUsage(utilization: weekly, resetsAt: date.addingTimeInterval(86400)),
            scopedLimits: [],
            breakdown: [],
            fetchedAt: date
        )
    }
}
