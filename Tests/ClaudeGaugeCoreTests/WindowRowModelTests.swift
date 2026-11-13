import Foundation
import Testing
@testable import ClaudeGaugeCore

struct WindowRowModelTests {
    private let utc = TimeZone(identifier: "UTC")!
    private let now = TestClock.base  // 2026-11-11 10:00 UTC

    private func fiveHour(_ utilization: Double, elapsed: TimeInterval = 9000) -> WindowRowModel {
        let usage = WindowUsage(
            utilization: utilization,
            resetsAt: now.addingTimeInterval(WindowForecast.fiveHourLength - elapsed)
        )
        return WindowRowModel.make(
            title: "5h session", usage: usage, windowLength: WindowForecast.fiveHourLength, now: now, timeZone: utc
        )
    }

    @Test("リセット前に 100% へ届く場合は、Forecast と (100% at …) と Resets 行がそろう")
    func reachesLimit() {
        let row = fiveHour(60)  // 経過 50% で 60% → 予測 120%

        #expect(row.title == "5h session")
        #expect(row.percentText == "60%")
        #expect(row.forecastText == "Forecast: 120%")
        #expect(row.reachText == "(100% at 11:40)")
        #expect(row.resetsText == "Resets at 12:30 (2h30m remain)")
        #expect(row.fraction == 0.6)
        #expect(row.level == .normal)
    }

    @Test("届かない場合は (100% at …) を出さない")
    func doesNotReachLimit() {
        let row = fiveHour(30)

        #expect(row.forecastText == "Forecast: 60%")
        #expect(row.reachText == nil)
    }

    @Test("経過率が 3% 未満のうちは Forecast: measuring")
    func measuring() {
        let row = fiveHour(5, elapsed: 300)

        #expect(row.forecastText == "Forecast: measuring")
        #expect(row.reachText == nil)
    }

    @Test("経過率 3〜10% は目安 (~) で出し、100% 到達の時刻は出さない")
    func roughForecast() {
        let row = fiveHour(5, elapsed: 540)  // 予測 167%: 目安でなければ (100% at …) が付く

        #expect(row.forecastText == "Forecast: ~167%")
        #expect(row.reachText == nil)
    }

    @Test("週次は経過 5 時間 (約 3%) から目安が出る")
    func weeklyRoughAfterFiveHours() {
        let week = WindowForecast.weeklyLength
        let usage = WindowUsage(utilization: 9, resetsAt: now.addingTimeInterval(week - 5.1 * 3600))
        let row = WindowRowModel.make(title: "Weekly", usage: usage, windowLength: week, now: now, timeZone: utc)

        #expect(row.forecastText.hasPrefix("Forecast: ~"))
        #expect(row.reachText == nil)
    }

    @Test("週次は 7 日のウィンドウで予測する")
    func weekly() {
        let week = WindowForecast.weeklyLength
        let usage = WindowUsage(utilization: 40, resetsAt: now.addingTimeInterval(week / 2))
        let row = WindowRowModel.make(title: "Weekly", usage: usage, windowLength: week, now: now, timeZone: utc)

        #expect(row.title == "Weekly")
        #expect(row.forecastText == "Forecast: 80%")
        #expect(row.resetsText == "Resets at 11/14 22:00 (3d12h remain)")
    }

    @Test("枠が無い (Pro の 5h など) 場合はプレースホルダー")
    func missingWindow() {
        let row = WindowRowModel.make(
            title: "5h session", usage: nil, windowLength: WindowForecast.fiveHourLength, now: now, timeZone: utc
        )

        #expect(row.percentText == "—")
        #expect(row.forecastText == "Forecast: —")
        #expect(row.reachText == nil)
        #expect(row.resetsText == nil)
        #expect(row.fraction == 0)
        #expect(row.level == .normal)
    }

    @Test("リセット時刻が無ければ Resets 行と予測は出さない")
    func missingResetsAt() {
        let row = WindowRowModel.make(
            title: "5h session",
            usage: WindowUsage(utilization: 20, resetsAt: nil),
            windowLength: WindowForecast.fiveHourLength,
            now: now,
            timeZone: utc
        )

        #expect(row.percentText == "20%")
        #expect(row.forecastText == "Forecast: —")
        #expect(row.resetsText == nil)
    }

    @Test("棒グラフの割合は 0〜1 に収め、警告レベルは使用率で決まる", arguments: [
        (150.0, 1.0, UsageLevel.critical),
        (95.0, 0.95, .critical),
        (75.0, 0.75, .caution),
        (0.0, 0.0, .normal),
        (-5.0, 0.0, .normal),
    ])
    func fractionAndLevel(utilization: Double, fraction: Double, level: UsageLevel) {
        let row = fiveHour(utilization)

        #expect(row.fraction == fraction)
        #expect(row.level == level)
    }

    @Test("異常値 (NaN) でも棒は 0 で落ちない")
    func nanUtilization() {
        let row = fiveHour(.nan)

        #expect(row.fraction == 0)
        #expect(row.percentText == "—")
        #expect(row.level == .normal)
    }
}
