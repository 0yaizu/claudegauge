import Foundation
import Testing
@testable import ClaudeGaugeCore

struct UsageAPIClientTests {
    private let now = TestClock.base

    @Test("URL・メソッド・ヘッダ・タイムアウトが正しい")
    func buildsRequest() async throws {
        let http = FakeHTTPClient.response(status: 200, body: try Fixture.data("usage_full"))
        let client = UsageAPIClient(http: http)

        _ = try await client.fetch(accessToken: "DUMMY-TOKEN", now: now)

        let request = try #require(http.requests.first)
        #expect(http.requests.count == 1)
        #expect(request.url?.absoluteString == "https://api.anthropic.com/api/oauth/usage")
        #expect(request.httpMethod == "GET")
        #expect(request.httpBody == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer DUMMY-TOKEN")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
        #expect(request.timeoutInterval == 10)
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test("200 は UsageSnapshot に変換し、fetchedAt は now")
    func mapsSuccess() async throws {
        let http = FakeHTTPClient.response(status: 200, body: try Fixture.data("usage_full"))
        let snapshot = try await UsageAPIClient(http: http).fetch(accessToken: "t", now: now)

        #expect(snapshot.fiveHour?.utilization == 7)
        #expect(snapshot.weekly?.utilization == 14)
        #expect(snapshot.fetchedAt == now)
    }

    @Test("ステータスコードをエラーに振り分ける", arguments: [
        (401, UsageAPIError.unauthorized),
        (403, .unauthorized),
        (429, .rateLimited),
        (500, .server(500)),
        (503, .server(503)),
        (404, .unexpectedStatus(404)),
        (302, .unexpectedStatus(302)),
    ])
    func mapsStatus(status: Int, expected: UsageAPIError) async {
        let client = UsageAPIClient(http: FakeHTTPClient.response(status: status))
        await #expect(throws: expected) { try await client.fetch(accessToken: "t", now: now) }
    }

    @Test("200 でも JSON が壊れていれば invalidResponse")
    func invalidBody() async {
        let client = UsageAPIClient(http: FakeHTTPClient.response(status: 200, body: Data("<html>".utf8)))
        await #expect(throws: UsageAPIError.invalidResponse) { try await client.fetch(accessToken: "t", now: now) }
    }

    @Test("200 でも使用率の枠が 1 つも無ければ invalidResponse (直前の正常値を消さない)", arguments: [
        "{}",
        #"{"error": {"type": "overloaded"}}"#,
        #"{"five_hour": null, "seven_day": null}"#,
        #"{"five_hour": {"resets_at": "2026-11-11T10:59:59Z"}}"#,
    ])
    func emptyShapeIsInvalid(body: String) async {
        let client = UsageAPIClient(http: FakeHTTPClient.response(status: 200, body: Data(body.utf8)))
        await #expect(throws: UsageAPIError.invalidResponse) { try await client.fetch(accessToken: "t", now: now) }
    }

    @Test("Pro プランのように weekly だけ返る応答は成功")
    func weeklyOnlyIsValid() async throws {
        let body = #"{"five_hour": null, "seven_day": {"utilization": 3.5, "resets_at": "2026-11-18T10:00:00Z"}}"#
        let client = UsageAPIClient(http: FakeHTTPClient.response(status: 200, body: Data(body.utf8)))
        let snapshot = try await client.fetch(accessToken: "t", now: now)
        #expect(snapshot.fiveHour == nil)
        #expect(snapshot.weekly?.utilization == 3.5)
    }

    @Test("通信エラーは network")
    func transportError() async {
        let client = UsageAPIClient(http: FakeHTTPClient(.failure(URLError(.notConnectedToInternet))))
        await #expect(throws: UsageAPIError.network) { try await client.fetch(accessToken: "t", now: now) }
    }

    @Test("エラー文にトークンもレスポンス本文も含まれない")
    func errorsDoNotLeak() async {
        let body = Data("DUMMY-BODY-SECRET".utf8)
        let client = UsageAPIClient(http: FakeHTTPClient.response(status: 500, body: body))
        do {
            _ = try await client.fetch(accessToken: "DUMMY-TOKEN-SECRET", now: now)
            Issue.record("エラーになるはず")
        } catch {
            let text = "\(error) \(String(reflecting: error))"
            #expect(!text.contains("DUMMY-TOKEN-SECRET"))
            #expect(!text.contains("DUMMY-BODY-SECRET"))
        }
    }
}
