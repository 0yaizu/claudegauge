import Foundation
import Testing
@testable import ClaudeGaugeCore

struct UsageSnapshotWindowsTests {
    private let now = TestClock.base  // 2026-11-11 10:00 UTC

    private func snapshot(
        fiveHourResetsIn: TimeInterval?,
        weeklyResetsIn: TimeInterval?,
        scopedResetsIn: TimeInterval? = nil,
        withBreakdown: Bool = false
    ) -> UsageSnapshot {
        func window(_ utilization: Double, _ resetsIn: TimeInterval?) -> WindowUsage {
            WindowUsage(utilization: utilization, resetsAt: resetsIn.map { now.addingTimeInterval($0) })
        }
        return UsageSnapshot(
            fiveHour: window(30, fiveHourResetsIn),
            weekly: window(10, weeklyResetsIn),
            scopedLimits: scopedResetsIn.map {
                [ScopedLimit(name: "Fable", percent: 5, resetsAt: now.addingTimeInterval($0))]
            } ?? [],
            breakdown: withBreakdown ? [BreakdownRow(key: "chat", displayName: "Chats", percent: 100)] : [],
            fetchedAt: now.addingTimeInterval(-600)
        )
    }

    @Test("リセット前の枠はそのまま残す")
    func keepsActiveWindows() {
        let original = snapshot(fiveHourResetsIn: 3600, weeklyResetsIn: 86400)
        #expect(original.activeWindows(at: now) == original)
    }

    @Test("リセット時刻を過ぎた枠だけを外す (5h と weekly は別々に判定する)")
    func dropsOnlyExpiredWindow() {
        let result = snapshot(fiveHourResetsIn: -1, weeklyResetsIn: 86400).activeWindows(at: now)

        #expect(result.fiveHour == nil)
        #expect(result.weekly?.utilization == 10)
    }

    @Test("weekly だけが過ぎていれば weekly だけを外す")
    func dropsOnlyExpiredWeekly() {
        let result = snapshot(fiveHourResetsIn: 3600, weeklyResetsIn: -1).activeWindows(at: now)

        #expect(result.fiveHour?.utilization == 30)
        #expect(result.weekly == nil)
    }

    @Test("リセット時刻ちょうどは、リセット済みとして外す")
    func resetInstantCountsAsReset() {
        let result = snapshot(fiveHourResetsIn: 0, weeklyResetsIn: 0).activeWindows(at: now)

        #expect(result.fiveHour == nil)
        #expect(result.weekly == nil)
    }

    @Test("リセット時刻が無い枠 (5h がまだ始まっていない) は外さない")
    func keepsWindowWithoutResetTime() {
        let result = snapshot(fiveHourResetsIn: nil, weeklyResetsIn: nil).activeWindows(at: now)

        #expect(result.fiveHour?.utilization == 30)
        #expect(result.weekly?.utilization == 10)
    }

    @Test("モデル別の枠も、リセット時刻を過ぎたら外す")
    func dropsExpiredScopedLimits() {
        let expired = snapshot(fiveHourResetsIn: 3600, weeklyResetsIn: 86400, scopedResetsIn: -5).activeWindows(at: now)
        let active = snapshot(fiveHourResetsIn: 3600, weeklyResetsIn: 86400, scopedResetsIn: 5).activeWindows(at: now)

        #expect(expired.scopedLimits.isEmpty)
        #expect(active.scopedLimits.count == 1)
    }

    @Test("週次の内訳は、weekly がリセット済みなら外す")
    func dropsBreakdownWithExpiredWeekly() {
        let expired = snapshot(fiveHourResetsIn: 3600, weeklyResetsIn: -1, withBreakdown: true).activeWindows(at: now)
        let active = snapshot(fiveHourResetsIn: 3600, weeklyResetsIn: 86400, withBreakdown: true).activeWindows(at: now)

        #expect(expired.breakdown.isEmpty)
        #expect(active.breakdown.count == 1)
    }

    @Test("取得時刻はそのまま保つ (Last updated 用)")
    func keepsFetchedAt() {
        let result = snapshot(fiveHourResetsIn: -1, weeklyResetsIn: -1).activeWindows(at: now)
        #expect(result.fetchedAt == now.addingTimeInterval(-600))
    }

    @Test("次のリセット時刻は、これから来るもののうち最も早いもの")
    func nextResetIsEarliestUpcoming() {
        let value = snapshot(fiveHourResetsIn: 7200, weeklyResetsIn: 3600)
        #expect(value.nextResetAt(after: now) == now.addingTimeInterval(3600))
    }

    @Test("過ぎたリセットと、リセット時刻が無い枠は数えない")
    func nextResetIgnoresPastAndMissing() {
        #expect(snapshot(fiveHourResetsIn: -10, weeklyResetsIn: 3600).nextResetAt(after: now) == now.addingTimeInterval(3600))
        #expect(snapshot(fiveHourResetsIn: nil, weeklyResetsIn: 3600).nextResetAt(after: now) == now.addingTimeInterval(3600))
    }

    @Test("これから来るリセットが無ければ nil")
    func nextResetNil() {
        #expect(snapshot(fiveHourResetsIn: -10, weeklyResetsIn: 0).nextResetAt(after: now) == nil)
        #expect(snapshot(fiveHourResetsIn: nil, weeklyResetsIn: nil).nextResetAt(after: now) == nil)
    }
}
