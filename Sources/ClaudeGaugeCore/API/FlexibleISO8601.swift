import Foundation

/// 小数秒が 0〜6 桁のどれでも読める ISO8601 パーサー。
/// API は `2026-11-11T10:59:59.901678+00:00` のように 6 桁を返すため、標準の小数秒オプションに頼らない。
public enum FlexibleISO8601 {
    public static func parse(_ text: String) -> Date? {
        let (base, fraction) = splitFraction(text)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: base) else { return nil }
        return date.addingTimeInterval(fraction)
    }

    /// "…:59.901678+00:00" → ("…:59+00:00", 0.901678)
    private static func splitFraction(_ text: String) -> (String, TimeInterval) {
        guard let dot = text.firstIndex(of: ".") else { return (text, 0) }
        let digitsStart = text.index(after: dot)
        let digits = text[digitsStart...].prefix(while: \.isNumber)
        guard !digits.isEmpty else { return (text, 0) }
        let rest = text[digits.endIndex...]
        let fraction = TimeInterval("0." + digits) ?? 0
        return (String(text[..<dot]) + rest, fraction)
    }
}
