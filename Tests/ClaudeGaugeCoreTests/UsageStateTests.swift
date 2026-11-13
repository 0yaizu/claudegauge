import Testing
@testable import ClaudeGaugeCore

struct UsageStateTests {
    @Test("トークンが切れている (期限切れ・認証エラー) ときだけ案内を出す", arguments: [
        (UsageFailure?.some(.tokenExpired), true),
        (.some(.unauthorized), true),
        (.some(.credentialsUnavailable), false),
        (.some(.rateLimited), false),
        (.some(.other), false),
        (nil, false),
    ])
    func showsRefreshNotice(failure: UsageFailure?, expected: Bool) {
        #expect(UsageState(failure: failure).showsRefreshNotice == expected)
    }

    @Test("429 の連続回数は 0〜上限に収める (書き換えられた保存データでも、加算で落ちない)", arguments: [
        (Int.max, RefreshPolicy.maximumBackoffSteps),
        (RefreshPolicy.maximumBackoffSteps + 1, RefreshPolicy.maximumBackoffSteps),
        (3, 3),
        (0, 0),
        (-5, 0),
        (Int.min, 0),
    ])
    func clampsRateLimitCount(count: Int, expected: Int) {
        #expect(UsageState(consecutiveRateLimits: count).consecutiveRateLimits == expected)

        let persisted = PersistedUsage(snapshot: nil, lastAttemptAt: nil, consecutiveRateLimits: count)
        #expect(UsageState(persisted: persisted).consecutiveRateLimits == expected)
    }
}
