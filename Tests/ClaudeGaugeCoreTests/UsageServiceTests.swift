import Foundation
import Testing
@testable import ClaudeGaugeCore

struct UsageServiceTests {
    private let clock = MutableClock(TestClock.base)

    private func credential(expiresIn seconds: TimeInterval) -> OAuthCredential {
        OAuthCredential(accessToken: "DUMMY-TOKEN", expiresAt: clock.now.addingTimeInterval(seconds))
    }

    private func makeService(
        credential: Result<OAuthCredential, CredentialError>? = nil,
        fetches: [Result<UsageSnapshot, UsageAPIError>]
    ) -> (UsageService, FakeCredentialSource, FakeUsageFetcher) {
        let source = FakeCredentialSource(credential ?? .success(self.credential(expiresIn: 3600)))
        let fetcher = FakeUsageFetcher(fetches)
        let clock = clock
        let service = UsageService(credentials: source, api: fetcher, now: { clock.now })
        return (service, source, fetcher)
    }

    @Test("成功すると snapshot を更新する")
    func success() async {
        let snapshot = TestSnapshot.make(fiveHour: 42)
        let (service, _, fetcher) = makeService(fetches: [.success(snapshot)])

        let state = await service.refresh()

        #expect(state.snapshot == snapshot)
        #expect(state.failure == nil)
        #expect(state.lastAttemptAt == clock.now)
        #expect(fetcher.tokens == ["DUMMY-TOKEN"])
    }

    @Test("失敗のあとに成功すると、失敗状態を消す")
    func successClearsFailure() async {
        let recovered = TestSnapshot.make(fiveHour: 20)
        let (service, _, _) = makeService(fetches: [.failure(.network), .success(recovered)])

        let failed = await service.refresh()
        #expect(failed.failure == .other)

        clock.now = clock.now.addingTimeInterval(180)
        let state = await service.refresh()

        #expect(state.failure == nil)
        #expect(state.snapshot == recovered)
    }

    @Test("トークン期限切れ (残り 5 分未満) なら API を呼ばず、直前の値を保持する")
    func tokenExpiredKeepsPrevious() async {
        let previous = TestSnapshot.make(fiveHour: 10)
        let (service, source, fetcher) = makeService(fetches: [.success(previous)])
        _ = await service.refresh()

        clock.now = clock.now.addingTimeInterval(180)
        source.result = .success(credential(expiresIn: 299))  // 判定時点で残り 299 秒
        let state = await service.refresh()

        #expect(fetcher.callCount == 1)
        #expect(state.failure == .tokenExpired)
        #expect(state.snapshot == previous)
    }

    @Test("残り 5 分ちょうどなら API を呼ぶ")
    func tokenExactlyFiveMinutesIsValid() async {
        let (service, source, fetcher) = makeService(fetches: [.success(TestSnapshot.make())])
        source.result = .success(credential(expiresIn: 300))

        let state = await service.refresh()

        #expect(fetcher.callCount == 1)
        #expect(state.failure == nil)
    }

    @Test("認証情報を読めなければ API を呼ばない")
    func credentialsUnavailable() async {
        let (service, _, fetcher) = makeService(credential: .failure(.keychainUnavailable), fetches: [])

        let state = await service.refresh()

        #expect(fetcher.callCount == 0)
        #expect(state.failure == .credentialsUnavailable)
        #expect(state.snapshot == nil)
    }

    @Test("認証情報を読めない失敗が続くと自動更新の間隔を倍にし (Keychain の許可ダイアログを出し続けない)、読めたら戻す")
    func credentialFailureBackoff() async {
        let (service, source, _) = makeService(
            credential: .failure(.keychainUnavailable),
            fetches: [.success(TestSnapshot.make())]
        )

        _ = await service.refresh()
        #expect(await service.nextInterval(base: 180) == 360)
        _ = await service.refresh()
        #expect(await service.nextInterval(base: 180) == 720)

        source.result = .success(credential(expiresIn: 3600))
        let state = await service.refresh()
        #expect(state.failure == nil)
        #expect(await service.nextInterval(base: 180) == 180)
    }

    @Test("手動 Reload は、間隔が延びていても 60 秒たてば読みに行き、読めたら間隔を戻す")
    func manualReloadIgnoresBackoff() async {
        let (service, source, fetcher) = makeService(
            credential: .failure(.timedOut),
            fetches: [.success(TestSnapshot.make())]
        )
        _ = await service.refresh()
        _ = await service.refresh()
        #expect(await service.nextInterval(base: 180) == 720)

        clock.now = clock.now.addingTimeInterval(RefreshPolicy.reloadCooldown)
        source.result = .success(credential(expiresIn: 3600))
        let state = await service.reload()

        #expect(fetcher.callCount == 1)
        #expect(state.failure == nil)
        #expect(await service.nextInterval(base: 180) == 180)
    }

    @Test("認証情報は読めたが期限切れのときは、Keychain の失敗の連続を数え直す")
    func tokenExpiredResetsCredentialFailures() async {
        let (service, source, _) = makeService(credential: .failure(.keychainUnavailable), fetches: [])
        _ = await service.refresh()
        #expect(await service.nextInterval(base: 180) == 360)

        source.result = .success(credential(expiresIn: 10))
        let state = await service.refresh()

        #expect(state.failure == .tokenExpired)
        #expect(await service.nextInterval(base: 180) == 180)
    }

    @Test("Keychain の失敗の連続は、上限で止まる")
    func credentialFailuresStopAtCap() async {
        let (service, _, _) = makeService(credential: .failure(.keychainUnavailable), fetches: [])
        for _ in 0..<(RefreshPolicy.maximumBackoffSteps + 5) { _ = await service.refresh() }

        #expect(await service.state.consecutiveCredentialFailures == RefreshPolicy.maximumBackoffSteps)
        #expect(await service.nextInterval(base: 180) == RefreshPolicy.maximumBackoffInterval)
    }

    @Test("API の失敗は種類ごとに記録し、直前の値を保持する", arguments: [
        (UsageAPIError.unauthorized, UsageFailure.unauthorized),
        (.rateLimited, .rateLimited),
        (.server(500), .other),
        (.network, .other),
        (.invalidResponse, .other),
        (.unexpectedStatus(404), .other),
    ])
    func apiFailures(error: UsageAPIError, expected: UsageFailure) async {
        let previous = TestSnapshot.make()
        let (service, _, _) = makeService(fetches: [.success(previous), .failure(error)])
        _ = await service.refresh()

        clock.now = clock.now.addingTimeInterval(180)
        let state = await service.refresh()

        #expect(state.failure == expected)
        #expect(state.snapshot == previous)
        #expect(state.lastAttemptAt == clock.now)
    }

    @Test("取得時刻 (Last updated) は API を呼ぶ直前の時刻")
    func fetchedAtIsTakenRightBeforeFetch() async {
        let source = FakeCredentialSource(.success(credential(expiresIn: 3600)))
        let clock = clock
        // 認証情報の読み取りに 15 秒かかった状況を作る。
        let slowSource = SlowCredentialSource(wrapping: source) { clock.now = clock.now.addingTimeInterval(15) }
        let recorder = RecordingUsageFetcher()
        let service = UsageService(credentials: slowSource, api: recorder, now: { clock.now })

        let state = await service.refresh()

        #expect(state.lastAttemptAt == TestClock.base)
        #expect(recorder.fetchTimes == [TestClock.base.addingTimeInterval(15)])
    }

    @Test("429 が続くと間隔を倍にし、成功で元に戻す")
    func rateLimitBackoff() async {
        let (service, _, _) = makeService(fetches: [
            .failure(.rateLimited), .failure(.rateLimited), .success(TestSnapshot.make()),
        ])

        _ = await service.refresh()
        #expect(await service.nextInterval(base: 180) == 360)
        _ = await service.refresh()
        #expect(await service.nextInterval(base: 180) == 720)
        let state = await service.refresh()
        #expect(state.consecutiveRateLimits == 0)
        #expect(await service.nextInterval(base: 180) == 180)
    }

    @Test("連続回数が上限でも 429 を受けて落ちず、間隔は上限のまま")
    func rateLimitCountStopsAtCap() async {
        let cap = RefreshPolicy.maximumBackoffSteps
        let service = UsageService(
            credentials: FakeCredentialSource(.success(credential(expiresIn: 3600))),
            api: FakeUsageFetcher([.failure(.rateLimited)]),
            initialState: UsageState(consecutiveRateLimits: Int.max),
            now: { [clock] in clock.now }
        )

        let state = await service.refresh()

        #expect(state.consecutiveRateLimits == cap)
        #expect(await service.nextInterval(base: 180) == RefreshPolicy.maximumBackoffInterval)
    }

    @Test("429 以外の失敗では連続回数を増やさず、既存の回数も消さない")
    func otherFailuresKeepRateLimitCount() async {
        let (service, _, _) = makeService(fetches: [.failure(.network), .failure(.rateLimited), .failure(.network)])

        let first = await service.refresh()
        #expect(first.consecutiveRateLimits == 0)
        _ = await service.refresh()
        let third = await service.refresh()
        #expect(third.consecutiveRateLimits == 1)
    }

    @Test("手動 Reload は前回から 60 秒未満なら拒否し、API を呼ばない")
    func reloadCooldown() async {
        let (service, _, fetcher) = makeService(fetches: [.success(TestSnapshot.make()), .success(TestSnapshot.make())])
        _ = await service.refresh()

        clock.now = clock.now.addingTimeInterval(59)
        let rejected = await service.reload()
        #expect(fetcher.callCount == 1)
        #expect(rejected.lastAttemptAt == TestClock.base)

        clock.now = clock.now.addingTimeInterval(1)
        _ = await service.reload()
        #expect(fetcher.callCount == 2)
    }

    @Test("初回の Reload は許可される")
    func firstReloadAllowed() async {
        let (service, _, fetcher) = makeService(fetches: [.success(TestSnapshot.make())])
        _ = await service.reload()
        #expect(fetcher.callCount == 1)
    }

    @Test("失敗した試行も Reload のクールダウンに数える")
    func failedAttemptCountsForCooldown() async {
        let (service, _, fetcher) = makeService(fetches: [.failure(.network), .success(TestSnapshot.make())])
        _ = await service.refresh()

        clock.now = clock.now.addingTimeInterval(30)
        _ = await service.reload()
        #expect(fetcher.callCount == 1)
    }

    @Test("起動時に前回の状態を引き継ぐ (前回の値・試行時刻・429 の連続回数)")
    func restoresPreviousState() async {
        let previous = UsageState(
            snapshot: TestSnapshot.make(fiveHour: 42),
            lastAttemptAt: clock.now.addingTimeInterval(-30),
            consecutiveRateLimits: 2
        )
        let service = UsageService(
            credentials: FakeCredentialSource(.success(credential(expiresIn: 3600))),
            api: FakeUsageFetcher([]),
            initialState: previous,
            now: { [clock] in clock.now }
        )

        #expect(await service.state == previous)
        #expect(await service.nextInterval(base: 180) == 720)  // 429 のバックオフも引き継ぐ
    }

    @Test("再起動直後でも、前回の試行から 60 秒未満なら Reload を拒否する")
    func reloadCooldownSurvivesRestart() async {
        let fetcher = FakeUsageFetcher([])
        let service = UsageService(
            credentials: FakeCredentialSource(.success(credential(expiresIn: 3600))),
            api: fetcher,
            initialState: UsageState(lastAttemptAt: clock.now.addingTimeInterval(-30)),
            now: { [clock] in clock.now }
        )

        _ = await service.reload()

        #expect(fetcher.callCount == 0)
    }

    @Test("取得するたびに、使用率・試行時刻・429 の連続回数を保存する")
    func savesAfterEveryAttempt() async {
        let store = FakeUsageStore()
        let snapshot = TestSnapshot.make(fiveHour: 42)
        let fetcher = FakeUsageFetcher([.failure(.rateLimited), .success(snapshot)])
        let service = UsageService(
            credentials: FakeCredentialSource(.success(credential(expiresIn: 3600))),
            api: fetcher,
            store: store,
            now: { [clock] in clock.now }
        )

        _ = await service.refresh()
        #expect(store.saveCount == 1)
        #expect(store.stored?.consecutiveRateLimits == 1)
        #expect(store.stored?.snapshot == nil)
        #expect(store.stored?.lastAttemptAt == clock.now)

        clock.now = clock.now.addingTimeInterval(360)
        _ = await service.refresh()
        #expect(store.saveCount == 2)
        #expect(store.stored?.consecutiveRateLimits == 0)
        #expect(store.stored?.snapshot == snapshot)
    }

    @Test("取得に失敗しても、直前の値は保存したまま残る")
    func failureKeepsStoredSnapshot() async {
        let previous = TestSnapshot.make(fiveHour: 10)
        let store = FakeUsageStore()
        let fetcher = FakeUsageFetcher([.success(previous), .failure(.network)])
        let service = UsageService(
            credentials: FakeCredentialSource(.success(credential(expiresIn: 3600))),
            api: fetcher,
            store: store,
            now: { [clock] in clock.now }
        )

        _ = await service.refresh()
        clock.now = clock.now.addingTimeInterval(180)
        _ = await service.refresh()

        #expect(store.stored?.snapshot == previous)
        #expect(store.stored?.lastAttemptAt == clock.now)
    }

    @Test("取得中に重ねて呼ばれたら何もせず、API は 1 回しか呼ばれない")
    func reentrantRefreshIsIgnored() async {
        let gated = GatedUsageFetcher(snapshot: TestSnapshot.make(fiveHour: 33))
        let clock = clock
        let service = UsageService(
            credentials: FakeCredentialSource(.success(credential(expiresIn: 3600))),
            api: gated,
            now: { clock.now }
        )

        let first = Task { await service.refresh() }
        while !gated.isSuspended { await Task.yield() }

        let second = await service.refresh()
        #expect(second.snapshot == nil)
        #expect(gated.callCount == 1)

        gated.release()
        let finished = await first.value
        #expect(finished.snapshot?.fiveHour?.utilization == 33)
        #expect(gated.callCount == 1)
    }

    @Test("取得中も試行時刻を記録済みにする (待ち時間が 0 になり、更新ループが空回りするのを防ぐ)")
    func attemptIsRecordedWhileInFlight() async {
        let gated = GatedUsageFetcher(snapshot: TestSnapshot.make())
        let clock = clock
        let service = UsageService(
            credentials: FakeCredentialSource(.success(credential(expiresIn: 3600))),
            api: gated,
            now: { clock.now }
        )

        let first = Task { await service.refresh() }
        while !gated.isSuspended { await Task.yield() }

        let lastAttemptAt = await service.state.lastAttemptAt
        #expect(lastAttemptAt == clock.now)
        // 取得中に更新ループが作り直されても、次の取得まで 1 間隔ぶん待つ。
        let delay = RefreshPolicy.delayUntilNextRefresh(lastAttemptAt: lastAttemptAt, interval: 180, now: clock.now)
        #expect(delay == 180)
        // 取得中の Reload も、クールダウンで止まる。
        _ = await service.reload()
        #expect(gated.callCount == 1)

        gated.release()
        _ = await first.value
    }
}

/// 認証情報の読み取り中に時計を進める。
private struct SlowCredentialSource: CredentialSource {
    let wrapping: FakeCredentialSource
    let onLoad: @Sendable () -> Void

    func load() async throws -> OAuthCredential {
        onLoad()
        return try await wrapping.load()
    }
}

private final class RecordingUsageFetcher: UsageFetching, @unchecked Sendable {
    private(set) var fetchTimes: [Date] = []

    func fetch(accessToken: String, now: Date) async throws -> UsageSnapshot {
        fetchTimes.append(now)
        return TestSnapshot.make(at: now)
    }
}
