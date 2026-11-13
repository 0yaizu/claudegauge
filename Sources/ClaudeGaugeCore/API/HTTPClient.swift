import Foundation

/// HTTP 通信。テストでは偽物に差し替える。
public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// キャッシュと Cookie を使わず、リダイレクトを追わない (Authorization を別の宛先へ送らないため)。
public final class URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    /// 応答が少しずつ届き続けても、リクエスト全体はこの秒数で打ち切る (`timeoutInterval` は無通信時間の上限にすぎない)。
    static let resourceTimeout: TimeInterval = 30

    public convenience init() {
        self.init(configuration: Self.makeConfiguration())
    }

    init(configuration: URLSessionConfiguration) {
        session = URLSession(configuration: configuration, delegate: RedirectBlocker(), delegateQueue: nil)
    }

    static func makeConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForResource = resourceTimeout
        return configuration
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

final class RedirectBlocker: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
