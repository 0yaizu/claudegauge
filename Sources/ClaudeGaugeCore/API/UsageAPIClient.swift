import Foundation

/// 本文やトークンを含めないよう、ケース名とステータスコードだけのエラーにする。
public enum UsageAPIError: Error, Equatable, Sendable {
    case unauthorized
    case rateLimited
    case server(Int)
    case unexpectedStatus(Int)
    case invalidResponse
    case network
}

public protocol UsageFetching: Sendable {
    func fetch(accessToken: String, now: Date) async throws -> UsageSnapshot
}

public struct UsageAPIClient: UsageFetching {
    static let url = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let betaHeader = "oauth-2025-04-20"
    static let timeout: TimeInterval = 10

    private let http: any HTTPClient

    public init(http: any HTTPClient = URLSessionHTTPClient()) {
        self.http = http
    }

    public func fetch(accessToken: String, now: Date) async throws -> UsageSnapshot {
        var request = URLRequest(url: Self.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: Self.timeout)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.betaHeader, forHTTPHeaderField: "anthropic-beta")

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await http.send(request)
        } catch {
            throw UsageAPIError.network
        }

        switch response.statusCode {
        case 200:
            guard let decoded = try? JSONDecoder().decode(UsageResponse.self, from: data) else {
                throw UsageAPIError.invalidResponse
            }
            let snapshot = UsageMapper.snapshot(from: decoded, fetchedAt: now)
            // 形が崩れた 200 (`{}` やエラー本文) を成功扱いにすると、直前の正常値を空で上書きしてしまう。
            guard snapshot.fiveHour != nil || snapshot.weekly != nil else { throw UsageAPIError.invalidResponse }
            return snapshot
        case 401, 403: throw UsageAPIError.unauthorized
        case 429: throw UsageAPIError.rateLimited
        case 500...599: throw UsageAPIError.server(response.statusCode)
        default: throw UsageAPIError.unexpectedStatus(response.statusCode)
        }
    }
}
