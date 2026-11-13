import Foundation
import Testing
@testable import ClaudeGaugeCore

struct FlexibleISO8601Tests {
    private let expectedSecond = TestClock.utc(2026, 11, 11, 10, 59, 59)

    @Test("小数秒の桁数と UTC 表記の違いを吸収する", arguments: [
        ("2026-11-11T10:59:59.901678+00:00", 0.901678),
        ("2026-11-11T10:59:59.901+00:00", 0.901),
        ("2026-11-11T10:59:59.9Z", 0.9),
        ("2026-11-11T10:59:59+00:00", 0.0),
        ("2026-11-11T10:59:59Z", 0.0),
    ])
    func parsesFractionalVariants(text: String, fraction: Double) throws {
        let date = try #require(FlexibleISO8601.parse(text))
        #expect(abs(date.timeIntervalSince(expectedSecond) - fraction) < 0.002)
    }

    @Test("オフセット付きの時刻を UTC に換算する")
    func appliesOffset() throws {
        let date = try #require(FlexibleISO8601.parse("2026-11-11T19:59:59+09:00"))
        #expect(date == expectedSecond)
    }

    @Test("不正な文字列は nil", arguments: ["", "yesterday", "2026-13-40T99:99:99Z", "2026-11-11"])
    func rejectsInvalid(text: String) {
        #expect(FlexibleISO8601.parse(text) == nil)
    }
}
