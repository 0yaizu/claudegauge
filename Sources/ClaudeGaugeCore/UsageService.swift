import Foundation

/// 直近の取得失敗の種類。UI に出す文言があるのは `tokenExpired` だけ (他は最終更新の時刻のみ)。
public enum UsageFailure: Equatable, Sendable {
    case tokenExpired
    case credentialsUnavailable
    case unauthorized
    case rateLimited
    case other
}

public struct UsageState: Equatable, Sendable {
    /// 最後に取得に成功した値。失敗しても保持する。
    public internal(set) var snapshot: UsageSnapshot?
    /// 直近の試行時刻 (成功・失敗を問わない)。Reload のクールダウンに使う。
    public internal(set) var lastAttemptAt: Date?
    public internal(set) var failure: UsageFailure?
    public internal(set) var consecutiveRateLimits: Int
    /// Keychain を読めなかった連続回数。保存しない (再起動後は、1 回試してから数え直す)。
    public internal(set) var consecutiveCredentialFailures = 0

    /// 再起動をまたいで引き継ぐ部分。
    public var persisted: PersistedUsage {
        PersistedUsage(snapshot: snapshot, lastAttemptAt: lastAttemptAt, consecutiveRateLimits: consecutiveRateLimits)
    }

    /// 保存されていた状態から作る。失敗の種類は引き継がない。
    public init(persisted: PersistedUsage?) {
        self.init(
            snapshot: persisted?.snapshot,
            lastAttemptAt: persisted?.lastAttemptAt,
            failure: nil,
            consecutiveRateLimits: persisted?.consecutiveRateLimits ?? 0
        )
    }

    /// トークンが切れている (期限切れ・認証エラー) ため、Claude Code を一度起動してもらう案内を出す。
    public var showsRefreshNotice: Bool {
        failure == .tokenExpired || failure == .unauthorized
    }

    public init(
        snapshot: UsageSnapshot? = nil,
        lastAttemptAt: Date? = nil,
        failure: UsageFailure? = nil,
        consecutiveRateLimits: Int = 0
    ) {
        self.snapshot = snapshot
        self.lastAttemptAt = lastAttemptAt
        self.failure = failure
        // 保存データが書き換えられていても、後の加算 (`+= 1`) でオーバーフローしないよう収める。
        self.consecutiveRateLimits = min(max(consecutiveRateLimits, 0), RefreshPolicy.maximumBackoffSteps)
    }
}

/// 認証情報の取得 → 期限判定 → API 取得 → 状態遷移。
/// トークンの更新 (refresh) は一切しない。期限が近ければ API を呼ばずに案内を出す。
public actor UsageService {
    private let credentials: any CredentialSource
    private let api: any UsageFetching
    private let store: (any UsageStore)?
    private let now: @Sendable () -> Date

    public private(set) var state: UsageState
    private var isRefreshing = false

    /// `initialState` は、前回の状態を引き継ぐときに渡す。`store` があれば、取得のたびに保存する。
    public init(
        credentials: any CredentialSource,
        api: any UsageFetching,
        initialState: UsageState = UsageState(),
        store: (any UsageStore)? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.credentials = credentials
        self.api = api
        self.store = store
        self.now = now
        state = initialState
    }

    /// 次の自動更新までの間隔。429 や Keychain の失敗が続いている間は延ばす。
    /// 手動の Reload は、この間隔に関係なく (60 秒のクールダウンだけで) 試せる。
    public func nextInterval(base: TimeInterval) -> TimeInterval {
        RefreshPolicy.backoffInterval(
            base: base,
            consecutiveFailures: state.consecutiveRateLimits + state.consecutiveCredentialFailures
        )
    }

    /// 手動の Reload。前回の試行から 60 秒未満なら何もしない。
    public func reload() async -> UsageState {
        guard RefreshPolicy.canReload(lastAttemptAt: state.lastAttemptAt, now: now()) else { return state }
        return await refresh()
    }

    /// 自動更新。取得中に重ねて呼ばれた場合は何もしない。
    public func refresh() async -> UsageState {
        guard !isRefreshing else { return state }
        isRefreshing = true
        defer { isRefreshing = false }

        // 試行時刻は取得の前に記録する。取得中に待ち時間を計算し直しても、0 (すぐ取得) にならない。
        state.lastAttemptAt = now()
        let outcome = await attempt()

        var next = state
        switch outcome {
        case let .success(snapshot):
            next.snapshot = snapshot
            next.failure = nil
            next.consecutiveRateLimits = 0
            next.consecutiveCredentialFailures = 0
        case let .failure(failure):
            next.failure = failure
            // Keychain を読めた (期限切れ・API の失敗) なら、Keychain の失敗の連続は途切れる。
            next.consecutiveCredentialFailures = failure == .credentialsUnavailable
                ? min(next.consecutiveCredentialFailures + 1, RefreshPolicy.maximumBackoffSteps)
                : 0
            if failure == .rateLimited {
                next.consecutiveRateLimits = min(next.consecutiveRateLimits + 1, RefreshPolicy.maximumBackoffSteps)
            }
        }
        state = next
        store?.save(next.persisted)
        return next
    }

    private enum Outcome {
        case success(UsageSnapshot)
        case failure(UsageFailure)
    }

    private func attempt() async -> Outcome {
        let credential: OAuthCredential
        do {
            credential = try await credentials.load()
        } catch {
            return .failure(.credentialsUnavailable)
        }
        // Keychain の読み取りに時間がかかった場合に備え、期限判定と取得時刻は読み取り後の時刻を使う。
        let fetchTime = now()
        if TokenExpiry.isExpired(expiresAt: credential.expiresAt, now: fetchTime) {
            return .failure(.tokenExpired)
        }
        do {
            return .success(try await api.fetch(accessToken: credential.accessToken, now: fetchTime))
        } catch UsageAPIError.unauthorized {
            return .failure(.unauthorized)
        } catch UsageAPIError.rateLimited {
            return .failure(.rateLimited)
        } catch {
            return .failure(.other)
        }
    }
}
