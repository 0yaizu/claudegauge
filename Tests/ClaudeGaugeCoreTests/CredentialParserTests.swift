import Foundation
import Testing
@testable import ClaudeGaugeCore

struct CredentialParserTests {
    /// ダミー値のみ。実トークンは決して入れない。
    private static let json = """
    {
      "mcpOAuth": {
        "plugin:sales:notion|abc": { "accessToken": "DUMMY-MCP-TOKEN", "refreshToken": "DUMMY-MCP-REFRESH" }
      },
      "claudeAiOauth": {
        "accessToken": "DUMMY-ACCESS-TOKEN",
        "refreshToken": "DUMMY-REFRESH-TOKEN",
        "expiresAt": 1794394959767,
        "subscriptionType": "max"
      }
    }
    """

    @Test("claudeAiOauth の accessToken と expiresAt だけを取る")
    func parsesClaudeAiOauth() throws {
        let credential = try CredentialParser.parse(Data(Self.json.utf8))
        #expect(credential.accessToken == "DUMMY-ACCESS-TOKEN")
        #expect(credential.expiresAt == Date(timeIntervalSince1970: 1_794_394_959.767))
    }

    @Test("前後の空白や改行があっても読める")
    func trimsWhitespace() throws {
        let credential = try CredentialParser.parse(Data(("\n  " + Self.json + "\n").utf8))
        #expect(credential.accessToken == "DUMMY-ACCESS-TOKEN")
    }

    @Test("security -w が 16 進で返した場合も復号する")
    func parsesHexOutput() throws {
        let hex = Data(Self.json.utf8).map { String(format: "%02x", $0) }.joined() + "\n"
        let credential = try CredentialParser.parse(Data(hex.utf8))
        #expect(credential.accessToken == "DUMMY-ACCESS-TOKEN")
    }

    @Test("expiresAt が秒単位でも日付に直せる")
    func acceptsEpochSeconds() throws {
        let text = #"{"claudeAiOauth": {"accessToken": "t", "expiresAt": 1794394959}}"#
        let credential = try CredentialParser.parse(Data(text.utf8))
        #expect(credential.expiresAt == Date(timeIntervalSince1970: 1_794_394_959))
    }

    @Test("claudeAiOauth が無ければ missingClaudeAiOauth")
    func missingClaudeAiOauth() {
        let text = #"{"mcpOAuth": {"x": {"accessToken": "DUMMY-MCP-TOKEN"}}}"#
        #expect(throws: CredentialError.missingClaudeAiOauth) {
            try CredentialParser.parse(Data(text.utf8))
        }
    }

    @Test("壊れた入力は malformed", arguments: ["", "not json", "{", "zz"])
    func malformed(text: String) {
        #expect(throws: CredentialError.malformed) {
            try CredentialParser.parse(Data(text.utf8))
        }
    }

    @Test("トークンは文字列化しても伏せられる")
    func redactsDescription() throws {
        let credential = try CredentialParser.parse(Data(Self.json.utf8))
        let text = "\(credential) \(String(reflecting: credential))"
        #expect(!text.contains("DUMMY-ACCESS-TOKEN"))
    }

    @Test("dump / Mirror でもトークンは出ない")
    func redactsReflection() throws {
        let credential = try CredentialParser.parse(Data(Self.json.utf8))
        var output = ""
        dump(credential, to: &output)
        #expect(!output.contains("DUMMY-ACCESS-TOKEN"))
        #expect(Mirror(reflecting: credential).children.isEmpty)
    }

    @Test("エラー文に入力の中身が含まれない")
    func errorDoesNotLeakInput() {
        let text = #"{"claudeAiOauth": {"accessToken": "DUMMY-SECRET"}"#  // 閉じ括弧欠落
        do {
            _ = try CredentialParser.parse(Data(text.utf8))
            Issue.record("エラーになるはず")
        } catch {
            #expect(!"\(error)".contains("DUMMY-SECRET"))
            #expect(!String(reflecting: error).contains("DUMMY-SECRET"))
        }
    }
}
