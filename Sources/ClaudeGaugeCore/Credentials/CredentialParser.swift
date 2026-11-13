import Foundation

/// `security find-generic-password -w` の出力から `claudeAiOauth` の 2 項目だけを取り出す。
/// 同じ項目には他の MCP サーバーの認証情報 (mcpOAuth) も入っているため、
/// デコード対象の型にそれらを定義せず、保持も出力もしない。
public enum CredentialParser {
    /// これ以上の値はミリ秒、未満は秒として扱う。
    private static let millisecondThreshold: Double = 1e11

    private struct Root: Decodable {
        struct Inner: Decodable {
            let accessToken: String
            let expiresAt: Double
        }

        let claudeAiOauth: Inner?
    }

    public static func parse(_ data: Data) throws -> OAuthCredential {
        guard let text = String(data: data, encoding: .utf8) else { throw CredentialError.malformed }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        let json: Data
        if trimmed.hasPrefix("{") {
            json = Data(trimmed.utf8)
        } else if let decoded = decodeHex(trimmed) {
            json = decoded
        } else {
            throw CredentialError.malformed
        }

        let root: Root
        do {
            root = try JSONDecoder().decode(Root.self, from: json)
        } catch {
            throw CredentialError.malformed
        }
        guard let inner = root.claudeAiOauth else { throw CredentialError.missingClaudeAiOauth }

        let seconds = inner.expiresAt >= millisecondThreshold ? inner.expiresAt / 1000 : inner.expiresAt
        return OAuthCredential(accessToken: inner.accessToken, expiresAt: Date(timeIntervalSince1970: seconds))
    }

    /// `security -w` は表示できないバイトを含むと 16 進文字列で返す。
    private static func decodeHex(_ text: String) -> Data? {
        guard !text.isEmpty, text.utf8.count.isMultiple(of: 2), text.allSatisfy(\.isHexDigit) else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(text.utf8.count / 2)
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2)
            guard let byte = UInt8(text[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return Data(bytes)
    }
}
