import Foundation
import Testing
@testable import ClaudeGaugeCore

struct UsageDecodingTests {
    private let fetchedAt = TestClock.base

    private func snapshot(from json: String) throws -> UsageSnapshot {
        let response = try JSONDecoder().decode(UsageResponse.self, from: Data(json.utf8))
        return UsageMapper.snapshot(from: response, fetchedAt: fetchedAt)
    }

    @Test("実レスポンスから 5h / weekly を取り出す")
    func mapsWindows() throws {
        let response = try JSONDecoder().decode(UsageResponse.self, from: Fixture.data("usage_full"))
        let snapshot = UsageMapper.snapshot(from: response, fetchedAt: fetchedAt)

        #expect(snapshot.fiveHour?.utilization == 7.0)
        #expect(snapshot.weekly?.utilization == 14.0)
        let resetsAt = try #require(snapshot.fiveHour?.resetsAt)
        #expect(abs(resetsAt.timeIntervalSince(TestClock.utc(2026, 11, 11, 10, 59, 59)) - 0.901678) < 0.002)
        #expect(snapshot.fetchedAt == fetchedAt)
    }

    @Test("モデル別の週次枠は weekly_scoped だけを拾う")
    func mapsScopedLimits() throws {
        let response = try JSONDecoder().decode(UsageResponse.self, from: Fixture.data("usage_full"))
        let snapshot = UsageMapper.snapshot(from: response, fetchedAt: fetchedAt)

        #expect(snapshot.scopedLimits.count == 1)
        #expect(snapshot.scopedLimits.first?.name == "Fable")
        #expect(snapshot.scopedLimits.first?.percent == 0)
    }

    @Test("週次の内訳を4行そのまま保持する")
    func mapsBreakdown() throws {
        let response = try JSONDecoder().decode(UsageResponse.self, from: Fixture.data("usage_full"))
        let snapshot = UsageMapper.snapshot(from: response, fetchedAt: fetchedAt)

        #expect(snapshot.breakdown.map(\.key) == ["claude_code", "chat", "cowork", "other"])
        #expect(snapshot.breakdown.map(\.percent) == [53, 12, 35, 0])
        #expect(snapshot.breakdown.first?.displayName == "Claude Code")
    }

    @Test("必要なキーが欠けていても落ちない")
    func toleratesMissingKeys() throws {
        let snapshot = try snapshot(from: "{}")
        #expect(snapshot.fiveHour == nil)
        #expect(snapshot.weekly == nil)
        #expect(snapshot.scopedLimits.isEmpty)
        #expect(snapshot.breakdown.isEmpty)
    }

    @Test("枠が null でも落ちない (Pro は 5h が返らない)")
    func toleratesNullWindows() throws {
        let snapshot = try snapshot(from: #"{"five_hour": null, "seven_day": {"utilization": 3.5, "resets_at": null}}"#)
        #expect(snapshot.fiveHour == nil)
        #expect(snapshot.weekly?.utilization == 3.5)
        #expect(snapshot.weekly?.resetsAt == nil)
    }

    @Test("utilization が無い枠は枠ごと無視する")
    func dropsWindowWithoutUtilization() throws {
        let snapshot = try snapshot(from: #"{"five_hour": {"resets_at": "2026-11-11T10:59:59Z"}}"#)
        #expect(snapshot.fiveHour == nil)
    }

    @Test("未知のキーと想定外の型の limits を無視する")
    func ignoresUnknownKeys() throws {
        let snapshot = try snapshot(from: #"{"mystery": {"a": 1}, "limits": [{"kind": null, "percent": null}]}"#)
        #expect(snapshot.scopedLimits.isEmpty)
    }
}
