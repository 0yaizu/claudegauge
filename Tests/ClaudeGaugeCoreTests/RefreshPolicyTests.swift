import Foundation
import Testing
@testable import ClaudeGaugeCore

struct RefreshPolicyTests {
    private let now = TestClock.base

    @Test("更新間隔は 1〜10 分に丸める", arguments: [
        (0.0, 60.0),
        (30.0, 60.0),
        (60.0, 60.0),
        (180.0, 180.0),
        (600.0, 600.0),
        (601.0, 600.0),
        (3600.0, 600.0),
        (-5.0, 60.0),
    ])
    func clampsInterval(input: Double, expected: Double) {
        #expect(RefreshPolicy.clampedInterval(input) == expected)
    }

    @Test("デフォルト間隔は 3 分")
    func defaultInterval() {
        #expect(RefreshPolicy.defaultInterval == 180)
    }

    @Test("Reload は前回の試行が無ければ許可")
    func reloadAllowedWithoutHistory() {
        #expect(RefreshPolicy.canReload(lastAttemptAt: nil, now: now))
    }

    @Test("Reload は前回から 60 秒未満なら拒否", arguments: [0.0, 1.0, 30.0, 59.999])
    func reloadRejectedUnderOneMinute(elapsed: Double) {
        #expect(!RefreshPolicy.canReload(lastAttemptAt: now.addingTimeInterval(-elapsed), now: now))
    }

    @Test("Reload は前回から 60 秒以上で許可", arguments: [60.0, 61.0, 3600.0])
    func reloadAllowedAfterOneMinute(elapsed: Double) {
        #expect(RefreshPolicy.canReload(lastAttemptAt: now.addingTimeInterval(-elapsed), now: now))
    }

    @Test("時計が戻っても Reload を拒否し続けない (未来の試行時刻は無視)")
    func reloadAllowedWhenClockWentBack() {
        #expect(RefreshPolicy.canReload(lastAttemptAt: now.addingTimeInterval(120), now: now))
    }

    @Test("次の取得までの待ち時間は、前回の試行から間隔が経つまで", arguments: [
        (30.0, 150.0),
        (180.0, 0.0),
        (500.0, 0.0),
    ])
    func delayUntilNextRefresh(elapsed: Double, expected: Double) {
        let delay = RefreshPolicy.delayUntilNextRefresh(
            lastAttemptAt: now.addingTimeInterval(-elapsed), interval: 180, now: now
        )
        #expect(delay == expected)
    }

    @Test("まだ一度も取得していなければ待たない")
    func noDelayWithoutHistory() {
        #expect(RefreshPolicy.delayUntilNextRefresh(lastAttemptAt: nil, interval: 180, now: now) == 0)
    }

    @Test("時計が戻って前回の試行が未来になっても、待ち時間は間隔を超えない")
    func delayCappedByInterval() {
        let delay = RefreshPolicy.delayUntilNextRefresh(
            lastAttemptAt: now.addingTimeInterval(3600), interval: 180, now: now
        )
        #expect(delay == 180)
    }

    @Test("429 を受けるたびに間隔を倍にする", arguments: [
        (0, 180.0), (1, 360.0), (2, 720.0), (3, 1440.0), (4, 1800.0), (10, 1800.0),
    ])
    func backoff(consecutiveRateLimits: Int, expected: Double) {
        #expect(RefreshPolicy.backoffInterval(base: 180, consecutiveFailures: consecutiveRateLimits) == expected)
    }

    @Test("負の連続回数は 0 回として扱う")
    func backoffNegative() {
        #expect(RefreshPolicy.backoffInterval(base: 180, consecutiveFailures: -3) == 180)
    }
}
