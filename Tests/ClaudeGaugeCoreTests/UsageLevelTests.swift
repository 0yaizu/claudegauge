import Testing
@testable import ClaudeGaugeCore

struct UsageLevelTests {
    @Test("閾値の境界: 70 未満 緑 / 70 以上 90 未満 黄 / 90 以上 赤", arguments: [
        (0.0, UsageLevel.normal),
        (69.99, .normal),
        (70.0, .caution),
        (89.99, .caution),
        (90.0, .critical),
        (100.0, .critical),
        (130.0, .critical),
    ])
    func boundaries(percent: Double, expected: UsageLevel) {
        #expect(UsageLevel(percent: percent) == expected)
    }
}
