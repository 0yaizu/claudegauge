import Foundation
import Testing
@testable import ClaudeGaugeCore

struct DisplayFormatterTests {
    private let utc = TimeZone(identifier: "UTC")!
    private let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    private let now = TestClock.base  // 2026-11-11 10:00 UTC

    @Test("使用率は四捨五入した整数 %", arguments: [
        (0.0, "0%"), (7.0, "7%"), (42.4, "42%"), (42.5, "43%"), (100.4, "100%"), (120.0, "120%"),
    ])
    func percent(value: Double, expected: String) {
        #expect(DisplayFormatter.percent(value) == expected)
    }

    @Test("NaN・無限大・巨大な値でも落ちず「—」を返す")
    func nonFiniteAndHugeValues() {
        for value in [Double.nan, .infinity, -.infinity, 1e300, -1e300, 1e30, 9.3e18] {
            #expect(DisplayFormatter.percent(value) == "—")
            #expect(DisplayFormatter.remaining(value) == "—")
        }
    }

    @Test("残り時間: 英語の短縮表記で 2 単位まで", arguments: [
        (0.0, "<1m"),
        (-30.0, "<1m"),
        (59.0, "<1m"),
        (60.0, "1m"),
        (2700.0, "45m"),
        (3599.0, "59m"),
        (3600.0, "1h"),
        (7980.0, "2h13m"),
        (12600.0, "3h30m"),
        (86399.0, "23h59m"),
        (86400.0, "1d"),
        (90000.0, "1d1h"),
        (529_200.0, "6d3h"),
    ])
    func remaining(seconds: Double, expected: String) {
        #expect(DisplayFormatter.remaining(seconds) == expected)
    }

    @Test("Forecast はどの % でも表示し、100% を超えてもそのまま出す")
    func forecastLabel() {
        func forecast(_ projected: Double?, _ timeToFull: WindowForecast.TimeToFull) -> WindowForecast {
            WindowForecast(elapsedRatio: 0.5, projectedFinalPercent: projected, timeToFull: timeToFull)
        }
        let reachesAt = now.addingTimeInterval(60)
        #expect(DisplayFormatter.forecastLabel(forecast(nil, .measuring)) == "Forecast: measuring")
        #expect(DisplayFormatter.forecastLabel(forecast(0, .notReached)) == "Forecast: 0%")
        #expect(DisplayFormatter.forecastLabel(forecast(60, .notReached)) == "Forecast: 60%")
        #expect(DisplayFormatter.forecastLabel(forecast(100, .notReached)) == "Forecast: 100%")
        #expect(DisplayFormatter.forecastLabel(forecast(119.6, .at(reachesAt))) == "Forecast: 120%")
        #expect(DisplayFormatter.forecastLabel(forecast(250, .at(reachesAt))) == "Forecast: 250%")
        #expect(DisplayFormatter.forecastLabel(forecast(130, .reached)) == "Forecast: 130%")
    }

    @Test("目安の予測 (経過率が低い) には ~ を付ける")
    func roughForecastLabel() {
        let rough = WindowForecast(elapsedRatio: 0.09, projectedFinalPercent: 141, timeToFull: .notReached)
        #expect(DisplayFormatter.forecastLabel(rough) == "Forecast: ~141%")
        let sure = WindowForecast(elapsedRatio: 0.10, projectedFinalPercent: 141, timeToFull: .notReached)
        #expect(DisplayFormatter.forecastLabel(sure) == "Forecast: 141%")
        let reached = WindowForecast(elapsedRatio: 0.01, projectedFinalPercent: 130, timeToFull: .reached)
        #expect(DisplayFormatter.forecastLabel(reached) == "Forecast: 130%")
    }

    @Test("予測できない枠 (リセット時刻なし) でも Forecast 行は出す")
    func forecastLabelWithoutForecast() {
        #expect(DisplayFormatter.forecastLabel(nil) == "Forecast: —")
    }

    @Test("時刻は 19:35 形式。同じ日は時刻のみ、別の日は日付つき")
    func clock() {
        let sameDay = TestClock.utc(2026, 11, 11, 10, 59, 59)
        let laterUTC = TestClock.utc(2026, 11, 11, 21, 59, 59)

        #expect(DisplayFormatter.clock(sameDay, now: now, timeZone: utc) == "10:59")
        #expect(DisplayFormatter.clock(sameDay, now: now, timeZone: tokyo) == "19:59")
        #expect(DisplayFormatter.clock(laterUTC, now: now, timeZone: utc) == "21:59")
        #expect(DisplayFormatter.clock(laterUTC, now: now, timeZone: tokyo) == "11/12 06:59")
        #expect(DisplayFormatter.clock(TestClock.utc(2026, 11, 5, 9, 5, 0), now: now, timeZone: utc) == "11/5 09:05")
    }

    @Test("Resets 行は時刻と残り時間を並べる")
    func resetsLine() {
        let in3h30m = TestClock.utc(2026, 11, 11, 13, 30, 0)
        let nextWeek = TestClock.utc(2026, 11, 18, 10, 0, 0)
        let alreadyPast = now.addingTimeInterval(-100)

        #expect(DisplayFormatter.resetsLine(in3h30m, now: now, timeZone: utc) == "Resets at 13:30 (3h30m remain)")
        #expect(DisplayFormatter.resetsLine(in3h30m, now: now, timeZone: tokyo) == "Resets at 22:30 (3h30m remain)")
        #expect(DisplayFormatter.resetsLine(nextWeek, now: now, timeZone: utc) == "Resets at 11/18 10:00 (7d remain)")
        #expect(DisplayFormatter.resetsLine(alreadyPast, now: now, timeZone: utc) == "Resets at 09:58 (<1m remain)")
    }

    @Test("API が返す 59:59.9 の境界は最寄りの分に丸めて表示する")
    func resetsLineRoundsToNearestMinute() {
        let apiStyle = TestClock.utc(2026, 11, 11, 10, 59, 59).addingTimeInterval(0.901678)
        let beforeMidnight = TestClock.utc(2026, 11, 11, 23, 59, 59).addingTimeInterval(0.9)

        #expect(DisplayFormatter.resetsLine(apiStyle, now: now, timeZone: utc) == "Resets at 11:00 (1h remain)")
        #expect(DisplayFormatter.resetsLine(apiStyle, now: now, timeZone: tokyo) == "Resets at 20:00 (1h remain)")
        // 日付をまたぐ丸めでは日付も進む
        #expect(DisplayFormatter.resetsLine(beforeMidnight, now: now, timeZone: utc) == "Resets at 11/12 00:00 (14h remain)")
    }

    @Test("リセット前に 100% へ届く場合だけ Forecast の隣に (100% at 時刻) を出す")
    func reachLabel() {
        let sameDay = now.addingTimeInterval(6000)  // 11:40 UTC / 20:40 JST
        let nextDayInTokyo = TestClock.utc(2026, 11, 11, 21, 59, 59)

        #expect(DisplayFormatter.reachLabel(.at(sameDay), now: now, timeZone: utc) == "(100% at 11:40)")
        #expect(DisplayFormatter.reachLabel(.at(sameDay), now: now, timeZone: tokyo) == "(100% at 20:40)")
        #expect(DisplayFormatter.reachLabel(.at(nextDayInTokyo), now: now, timeZone: tokyo) == "(100% at 11/12 06:59)")
        #expect(DisplayFormatter.reachLabel(.measuring, now: now, timeZone: utc) == nil)
        #expect(DisplayFormatter.reachLabel(.reached, now: now, timeZone: utc) == nil)
        #expect(DisplayFormatter.reachLabel(.notReached, now: now, timeZone: utc) == nil)
    }

    @Test("最終更新は時刻で表示する")
    func lastUpdated() {
        let thisMorning = TestClock.utc(2026, 11, 11, 9, 35, 12)
        let yesterday = TestClock.utc(2026, 11, 10, 19, 35, 0)

        #expect(DisplayFormatter.lastUpdated(thisMorning, now: now, timeZone: utc) == "Last updated 09:35")
        #expect(DisplayFormatter.lastUpdated(thisMorning, now: now, timeZone: tokyo) == "Last updated 18:35")
        #expect(DisplayFormatter.lastUpdated(yesterday, now: now, timeZone: utc) == "Last updated 11/10 19:35")
    }

    @Test("期限切れの案内文")
    func tokenExpired() {
        #expect(DisplayFormatter.tokenExpiredNotice == "Open Claude Code once to refresh")
    }
}
