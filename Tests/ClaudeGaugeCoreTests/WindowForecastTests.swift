import Foundation
import Testing
@testable import ClaudeGaugeCore

struct WindowForecastTests {
    private let now = TestClock.base
    private let fiveHours: TimeInterval = 5 * 3600

    /// `elapsed` 秒経過した時点の予測を作る。
    private func forecast(utilization: Double, elapsed: TimeInterval, length: TimeInterval? = nil) -> WindowForecast? {
        let length = length ?? fiveHours
        return WindowForecast.make(
            utilization: utilization,
            resetsAt: now.addingTimeInterval(length - elapsed),
            windowLength: length,
            now: now
        )
    }

    @Test("経過率は経過時間 ÷ ウィンドウ長")
    func elapsedRatio() throws {
        let result = try #require(forecast(utilization: 30, elapsed: 9000))
        #expect(result.elapsedRatio == 0.5)
    }

    @Test("使用率 30% / 経過 50% → 予測 60%、到達しない")
    func projectionBelowLimit() throws {
        let result = try #require(forecast(utilization: 30, elapsed: 9000))
        #expect(result.projectedFinalPercent == 60)
        #expect(result.timeToFull == .notReached)
        #expect(!result.isWarning)
    }

    @Test("使用率 60% / 経過 50% → 予測 120%、6000 秒後 (時点) に 100%")
    func projectionAboveLimit() throws {
        let result = try #require(forecast(utilization: 60, elapsed: 9000))
        #expect(result.projectedFinalPercent == 120)
        #expect(result.timeToFull == .at(now.addingTimeInterval(6000)))
        #expect(result.isWarning)
    }

    @Test("予測がちょうど 100% なら到達しない扱い")
    func projectionExactlyHundred() throws {
        let result = try #require(forecast(utilization: 50, elapsed: 9000))
        #expect(result.projectedFinalPercent == 100)
        #expect(result.timeToFull == .notReached)
    }

    // 5h = 18000 秒。3% = 540 秒、10% = 1800 秒。

    @Test("経過率 3% 未満は計測中")
    func measuringBelowThreePercent() throws {
        let result = try #require(forecast(utilization: 1, elapsed: 539))
        #expect(result.timeToFull == .measuring)
        #expect(result.projectedFinalPercent == nil)
        #expect(!result.isRough)
        #expect(!result.isWarning)
    }

    @Test("経過率ちょうど 3% から予測する。10% 未満は目安 (isRough)")
    func exactlyThreePercentIsRough() throws {
        let result = try #require(forecast(utilization: 1, elapsed: 540))
        let projected = try #require(result.projectedFinalPercent)
        #expect(abs(projected - 1 * 18000.0 / 540) < 1e-9)
        #expect(result.isRough)
    }

    @Test("経過率 10% 以上は目安ではない")
    func tenPercentIsNotRough() throws {
        let below = try #require(forecast(utilization: 2, elapsed: 1799))
        #expect(below.isRough)
        let exactly = try #require(forecast(utilization: 5, elapsed: 1800))
        #expect(!exactly.isRough)
        #expect(exactly.projectedFinalPercent == 50)
    }

    @Test("目安の間は、100% を超える予測でも警告にしない (外れやすい数字で警告を出さない)")
    func roughIsNotWarning() throws {
        let result = try #require(forecast(utilization: 5, elapsed: 540))  // 予測 166%
        guard case .at = result.timeToFull else {
            Issue.record("予測が 100% を超えるはず")
            return
        }
        #expect(result.isRough)
        #expect(!result.isWarning)
    }

    @Test("すでに 100% 以上なら、経過率が低くても目安ではなく警告")
    func reachedIsNeverRough() throws {
        let result = try #require(forecast(utilization: 100, elapsed: 600))
        #expect(!result.isRough)
        #expect(result.isWarning)
    }

    @Test("使用率 100% 以上は到達済み (計測中でも)")
    func reached() throws {
        let result = try #require(forecast(utilization: 100, elapsed: 600))
        #expect(result.timeToFull == .reached)
        #expect(result.isWarning)
    }

    @Test("使用率 0% は到達しない")
    func zeroUsage() throws {
        let result = try #require(forecast(utilization: 0, elapsed: 9000))
        #expect(result.projectedFinalPercent == 0)
        #expect(result.timeToFull == .notReached)
    }

    @Test("resets_at が過去 (古い値) なら経過率 1 に丸める")
    func staleResetsAt() throws {
        let result = try #require(WindowForecast.make(
            utilization: 50, resetsAt: now.addingTimeInterval(-100), windowLength: fiveHours, now: now
        ))
        #expect(result.elapsedRatio == 1)
        #expect(result.projectedFinalPercent == 50)
        #expect(result.timeToFull == .notReached)
    }

    @Test("resets_at が無ければ予測できない")
    func missingResetsAt() {
        #expect(WindowForecast.make(utilization: 10, resetsAt: nil, windowLength: fiveHours, now: now) == nil)
    }

    @Test("ウィンドウ長が 0 以下なら予測できない", arguments: [0.0, -1.0])
    func invalidWindowLength(length: Double) {
        #expect(WindowForecast.make(utilization: 10, resetsAt: now.addingTimeInterval(100), windowLength: length, now: now) == nil)
    }

    @Test("週次 (7 日) でも同じ式")
    func weekly() throws {
        let week: TimeInterval = 7 * 24 * 3600
        let result = try #require(forecast(utilization: 40, elapsed: week / 2, length: week))
        #expect(result.projectedFinalPercent == 80)
    }
}
