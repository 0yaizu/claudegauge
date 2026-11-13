import Foundation
import Testing
@testable import ClaudeGaugeCore

struct GaugeValueTests {
    @Test("割合は 0〜1 に収め、警告レベルは使用率で決まる", arguments: [
        (0.0, 0.0, UsageLevel.normal),
        (28.0, 0.28, .normal),
        (70.0, 0.7, .caution),
        (95.0, 0.95, .critical),
        (150.0, 1.0, .critical),
        (-5.0, 0.0, .normal),
    ])
    func fractionAndLevel(utilization: Double, fraction: Double, level: UsageLevel) {
        let gauge = GaugeValue(utilization: utilization)

        #expect(gauge.fraction == fraction)
        #expect(gauge.level == level)
    }

    @Test("NaN や無限大は 0 / 通常として扱う", arguments: [Double.nan, .infinity, -.infinity])
    func nonFinite(utilization: Double) {
        let gauge = GaugeValue(utilization: utilization)

        #expect(gauge.fraction == 0)
        #expect(gauge.level == .normal)
    }
}

struct MenuBarModelTests {
    private func snapshot(fiveHour: Double?, weekly: Double?) -> UsageSnapshot {
        UsageSnapshot(
            fiveHour: fiveHour.map { WindowUsage(utilization: $0, resetsAt: nil) },
            weekly: weekly.map { WindowUsage(utilization: $0, resetsAt: nil) },
            scopedLimits: [],
            breakdown: [],
            fetchedAt: TestClock.base
        )
    }

    @Test("外側が 5h、内側が weekly。% は 5h が上、weekly が下")
    func ringsAndTexts() {
        let model = MenuBarModel.make(snapshot: snapshot(fiveHour: 28, weekly: 17))

        #expect(model.fiveHour.text == "28%")
        #expect(model.fiveHour.fraction == 0.28)
        #expect(model.weekly.text == "17%")
        #expect(model.weekly.fraction == 0.17)
    }

    @Test("枠ごとに警告レベルが決まる")
    func levelsPerRing() {
        let model = MenuBarModel.make(snapshot: snapshot(fiveHour: 95, weekly: 75))

        #expect(model.fiveHour.level == .critical)
        #expect(model.weekly.level == .caution)
    }

    @Test("まだ取得できていない間は「—」と空の輪")
    func noSnapshot() {
        let model = MenuBarModel.make(snapshot: nil)

        #expect(model.fiveHour.text == "—")
        #expect(model.weekly.text == "—")
        #expect(model.fiveHour.fraction == 0)
        #expect(model.weekly.fraction == 0)
        #expect(model.fiveHour.level == .normal)
    }

    @Test("片方の枠だけ無い場合 (Pro の 5h など)")
    func missingOneWindow() {
        let model = MenuBarModel.make(snapshot: snapshot(fiveHour: nil, weekly: 17))

        #expect(model.fiveHour.text == "—")
        #expect(model.fiveHour.fraction == 0)
        #expect(model.weekly.text == "17%")
    }

    @Test("100% を超えても輪は満杯で止め、% はそのまま出す")
    func overLimit() {
        let model = MenuBarModel.make(snapshot: snapshot(fiveHour: 130, weekly: 17))

        #expect(model.fiveHour.text == "130%")
        #expect(model.fiveHour.fraction == 1)
        #expect(model.fiveHour.level == .critical)
    }
}
