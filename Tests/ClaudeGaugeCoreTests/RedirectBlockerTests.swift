import Foundation
import Testing
@testable import ClaudeGaugeCore

/// 302 を返し、リダイレクト先 (別ホスト) への要求が実際に飛ぶかを記録する URLProtocol。
final class RedirectingURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    // lock で保護している。
    nonisolated(unsafe) private static var requested: [URL] = []

    static var requestedURLs: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return requested
    }

    static func reset() {
        lock.lock()
        requested = []
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        Self.lock.lock()
        Self.requested.append(url)
        Self.lock.unlock()

        guard url.host == "api.anthropic.com" else {
            let ok = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: ok, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("redirect target reached".utf8))
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let target = URL(string: "https://example.invalid/steal")!
        let redirect = HTTPURLResponse(
            url: url, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": target.absoluteString]
        )!
        client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: redirect)
        // リダイレクトが拒否されたときに備え、302 自体を最終応答として返す。
        client?.urlProtocol(self, didReceive: redirect, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct RedirectBlockerTests {
    @Test("実際のセッション配線でもリダイレクト先へは要求を送らない")
    func doesNotFollowRedirectEndToEnd() async throws {
        RedirectingURLProtocol.reset()
        let configuration = URLSessionHTTPClient.makeConfiguration()
        configuration.protocolClasses = [RedirectingURLProtocol.self]
        let client = URLSessionHTTPClient(configuration: configuration)

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer DUMMY-TOKEN", forHTTPHeaderField: "Authorization")
        let (data, response) = try await client.send(request)

        let hosts = RedirectingURLProtocol.requestedURLs.compactMap(\.host)
        #expect(hosts == ["api.anthropic.com"])
        #expect(response.statusCode == 302)
        #expect(String(data: data, encoding: .utf8) != "redirect target reached")
    }

    @Test("delegate 単体でも nil を返してリダイレクトを止める")
    func blocksRedirect() {
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        let redirect = HTTPURLResponse(
            url: task.originalRequest!.url!, statusCode: 302, httpVersion: "HTTP/1.1",
            headerFields: ["Location": "https://example.invalid/steal"]
        )!
        let target = URLRequest(url: URL(string: "https://example.invalid/steal")!)

        var called = false
        var forwarded: URLRequest? = target
        RedirectBlocker().urlSession(session, task: task, willPerformHTTPRedirection: redirect, newRequest: target) {
            called = true
            forwarded = $0
        }

        #expect(called)
        #expect(forwarded == nil)
    }

    @Test("セッションはキャッシュと Cookie を使わず、全体のタイムアウトを 30 秒に抑える")
    func configuration() {
        let configuration = URLSessionHTTPClient.makeConfiguration()
        #expect(configuration.urlCache == nil)
        #expect(configuration.httpCookieStorage == nil)
        #expect(!configuration.httpShouldSetCookies)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
        #expect(configuration.timeoutIntervalForResource == 30)
    }
}
