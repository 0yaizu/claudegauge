import Foundation
import Testing
@testable import ClaudeGaugeCore

struct UsageStoreTests {
    /// テストごとに独立した UserDefaults を使い、終わったら消す。
    private func withStore(_ body: (UserDefaultsUsageStore, UserDefaults) throws -> Void) rethrows {
        let name = "claudegauge.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(UserDefaultsUsageStore(defaults: defaults), defaults)
    }

    private let persisted = PersistedUsage(
        snapshot: UsageSnapshot(
            fiveHour: WindowUsage(utilization: 28, resetsAt: TestClock.base.addingTimeInterval(3600)),
            weekly: WindowUsage(utilization: 17, resetsAt: nil),
            scopedLimits: [ScopedLimit(name: "Fable", percent: 0, resetsAt: TestClock.base)],
            breakdown: [BreakdownRow(key: "chat", displayName: "Chats", percent: 100)],
            fetchedAt: TestClock.base
        ),
        lastAttemptAt: TestClock.base.addingTimeInterval(5),
        consecutiveRateLimits: 2
    )

    @Test("保存した内容 (使用率・試行時刻・429 の連続回数) をそのまま読み戻せる")
    func roundTrip() {
        withStore { store, _ in
            store.save(persisted)
            #expect(store.load() == persisted)
        }
    }

    @Test("何も保存されていなければ nil")
    func emptyStore() {
        withStore { store, _ in
            #expect(store.load() == nil)
        }
    }

    @Test("壊れたデータは nil として扱い、落ちない", arguments: ["not json", "{}", "[1,2,3]", ""])
    func corruptedData(text: String) {
        withStore { store, defaults in
            defaults.set(Data(text.utf8), forKey: UserDefaultsUsageStore.key)
            #expect(store.load() == nil)
        }
    }

    @Test("保存し直すと上書きされる")
    func overwrite() {
        withStore { store, _ in
            store.save(persisted)
            store.save(PersistedUsage(snapshot: nil, lastAttemptAt: nil, consecutiveRateLimits: 0))
            #expect(store.load() == PersistedUsage(snapshot: nil, lastAttemptAt: nil, consecutiveRateLimits: 0))
        }
    }

    @Test("保存するのは使用率と時刻だけで、トークンなどの認証情報は含まれない")
    func containsNoCredentials() throws {
        try withStore { store, defaults in
            store.save(persisted)
            let data = try #require(defaults.data(forKey: UserDefaultsUsageStore.key))
            let text = try #require(String(data: data, encoding: .utf8)).lowercased()
            for forbidden in ["token", "bearer", "secret", "password"] {
                #expect(!text.contains(forbidden))
            }
        }
    }

    @Test("UsageState との相互変換: 失敗の種類は保存しない")
    func stateConversion() {
        let state = UsageState(
            snapshot: persisted.snapshot,
            lastAttemptAt: persisted.lastAttemptAt,
            failure: .tokenExpired,
            consecutiveRateLimits: 2
        )

        #expect(state.persisted == persisted)

        let restored = UsageState(persisted: persisted)
        #expect(restored.snapshot == persisted.snapshot)
        #expect(restored.lastAttemptAt == persisted.lastAttemptAt)
        #expect(restored.consecutiveRateLimits == 2)
        #expect(restored.failure == nil)
    }

    @Test("保存データが無いときの UsageState は初期状態")
    func stateFromNothing() {
        #expect(UsageState(persisted: nil) == UsageState())
    }
}
