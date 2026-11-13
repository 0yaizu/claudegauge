import Foundation
import Testing
@testable import ClaudeGaugeCore

struct TokenExpiryTests {
    private let now = TestClock.base

    @Test("残り 5 分ちょうどはまだ有効")
    func exactlyFiveMinutesIsValid() {
        #expect(!TokenExpiry.isExpired(expiresAt: now.addingTimeInterval(300), now: now))
    }

    @Test("残り 5 分未満は期限切れ扱い")
    func underFiveMinutesIsExpired() {
        #expect(TokenExpiry.isExpired(expiresAt: now.addingTimeInterval(299.999), now: now))
    }

    @Test("すでに過ぎていれば期限切れ")
    func pastIsExpired() {
        #expect(TokenExpiry.isExpired(expiresAt: now.addingTimeInterval(-1), now: now))
    }

    @Test("十分先なら有効")
    func farFutureIsValid() {
        #expect(!TokenExpiry.isExpired(expiresAt: now.addingTimeInterval(3600), now: now))
    }
}
