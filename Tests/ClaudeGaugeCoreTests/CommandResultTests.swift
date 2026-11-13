import Foundation
import Testing
@testable import ClaudeGaugeCore

/// `security -w` の出力は、他のツールのトークンを含む Keychain 項目全体。誤って表示しても中身が出ない。
struct CommandResultTests {
    private let secret = "DUMMY-SECRET-mcpOAuth-token"
    private var result: CommandResult { CommandResult(status: 0, stdout: Data(secret.utf8)) }

    @Test("文字列化しても stdout の中身は出ない")
    func descriptionRedacts() {
        for text in [String(describing: result), String(reflecting: result), "\(result)"] {
            #expect(!text.contains(secret))
            #expect(text.contains("redacted"))
        }
    }

    @Test("dump / Mirror でも stdout の中身は出ない")
    func dumpRedacts() {
        var output = ""
        dump(result, to: &output)
        #expect(!output.contains(secret))
        #expect(Mirror(reflecting: result).children.isEmpty)
    }

    @Test("比較や参照は今までどおり使える")
    func stillUsable() {
        #expect(result == CommandResult(status: 0, stdout: Data(secret.utf8)))
        #expect(result.stdout == Data(secret.utf8))
        #expect(result.status == 0)
    }
}
