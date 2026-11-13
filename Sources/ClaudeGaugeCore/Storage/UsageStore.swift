import Foundation

/// 再起動をまたいで引き継ぐ状態。使用率と時刻だけで、トークンなどの認証情報は含めない。
/// 失敗の種類 (`UsageFailure`) は保存しない。再起動後は次の取得で改めて判定する。
public struct PersistedUsage: Codable, Equatable, Sendable {
    public let snapshot: UsageSnapshot?
    /// 直近の試行時刻。再起動直後に取得し直さず、Reload のクールダウンも保つために使う。
    public let lastAttemptAt: Date?
    /// 429 の連続回数。再起動で間隔が元に戻り、制限に当たり続けるのを防ぐ。
    public let consecutiveRateLimits: Int

    public init(snapshot: UsageSnapshot?, lastAttemptAt: Date?, consecutiveRateLimits: Int) {
        self.snapshot = snapshot
        self.lastAttemptAt = lastAttemptAt
        self.consecutiveRateLimits = consecutiveRateLimits
    }
}

public protocol UsageStore: Sendable {
    func load() -> PersistedUsage?
    func save(_ usage: PersistedUsage)
}

/// `UserDefaults` はスレッドセーフ (Apple のドキュメントに明記) だが、SDK 上は `Sendable` と宣言されていない。
public struct UserDefaultsUsageStore: UsageStore, @unchecked Sendable {
    static let key = "lastUsage"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 保存されていない・壊れている場合は nil (落とさない)。
    public func load() -> PersistedUsage? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(PersistedUsage.self, from: data)
    }

    public func save(_ usage: PersistedUsage) {
        guard let data = try? JSONEncoder().encode(usage) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
