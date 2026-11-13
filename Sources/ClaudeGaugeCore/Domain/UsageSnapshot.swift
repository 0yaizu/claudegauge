import Foundation

public struct WindowUsage: Codable, Equatable, Sendable {
    /// 0〜100 の使用率。
    public let utilization: Double
    public let resetsAt: Date?

    public init(utilization: Double, resetsAt: Date?) {
        self.utilization = utilization
        self.resetsAt = resetsAt
    }
}

/// モデル別の週次枠 (例: Fable)。
public struct ScopedLimit: Codable, Equatable, Sendable {
    public let name: String
    public let percent: Double
    public let resetsAt: Date?

    public init(name: String, percent: Double, resetsAt: Date?) {
        self.name = name
        self.percent = percent
        self.resetsAt = resetsAt
    }
}

/// 週次消費の内訳。`percent` は上限に対する使用率ではなく、消費全体に占める割合 (合計 100)。
public struct BreakdownRow: Codable, Equatable, Sendable {
    public let key: String
    public let displayName: String
    public let percent: Double

    public init(key: String, displayName: String, percent: Double) {
        self.key = key
        self.displayName = displayName
        self.percent = percent
    }
}

public struct UsageSnapshot: Codable, Equatable, Sendable {
    public let fiveHour: WindowUsage?
    public let weekly: WindowUsage?
    public let scopedLimits: [ScopedLimit]
    public let breakdown: [BreakdownRow]
    public let fetchedAt: Date

    public init(
        fiveHour: WindowUsage?,
        weekly: WindowUsage?,
        scopedLimits: [ScopedLimit],
        breakdown: [BreakdownRow],
        fetchedAt: Date
    ) {
        self.fiveHour = fiveHour
        self.weekly = weekly
        self.scopedLimits = scopedLimits
        self.breakdown = breakdown
        self.fetchedAt = fetchedAt
    }
}

extension UsageSnapshot {
    /// 取得済みの値のうち、まだリセット時刻を過ぎていない枠だけを残す。
    /// リセット済みの枠は、古い使用率が残っているだけなので外す (表示は「—」になる)。
    /// 5h と weekly は別々に判定する。取得時刻 (Last updated 用) はそのまま保つ。
    public func activeWindows(at now: Date) -> UsageSnapshot {
        let weeklyIsActive = weekly.map { !$0.hasReset(at: now) } ?? true
        return UsageSnapshot(
            fiveHour: fiveHour.flatMap { $0.hasReset(at: now) ? nil : $0 },
            weekly: weekly.flatMap { $0.hasReset(at: now) ? nil : $0 },
            scopedLimits: scopedLimits.filter { !($0.resetsAt.map { $0 <= now } ?? false) },
            // 内訳は週次の内訳なので、weekly がリセット済みなら一緒に外す。
            breakdown: weeklyIsActive ? breakdown : [],
            fetchedAt: fetchedAt
        )
    }

    /// これから来る最も早いリセット時刻 (5h と weekly)。表示を「—」に切り替える時刻の目安になる。
    public func nextResetAt(after now: Date) -> Date? {
        [fiveHour?.resetsAt, weekly?.resetsAt]
            .compactMap { $0 }
            .filter { $0 > now }
            .min()
    }
}

extension WindowUsage {
    /// リセット時刻ちょうどもリセット済みとみなす。リセット時刻が分からない枠 (5h がまだ始まっていない) は含めない。
    func hasReset(at now: Date) -> Bool {
        resetsAt.map { $0 <= now } ?? false
    }
}
