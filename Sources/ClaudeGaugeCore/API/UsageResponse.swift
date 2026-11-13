import Foundation

/// `GET /api/oauth/usage` のレスポンス。必要なキーだけを optional で持ち、未知のキーは無視する。
/// 非公開 API のため、形が変わっても全体のデコードを失敗させない (壊れた項目は nil にする)。
public struct UsageResponse: Decodable, Sendable {
    public struct Window: Decodable, Sendable {
        public let utilization: Double?
        public let resetsAt: String?

        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }
    }

    public struct Limit: Decodable, Sendable {
        public struct Scope: Decodable, Sendable {
            public struct Model: Decodable, Sendable {
                public let displayName: String?

                enum CodingKeys: String, CodingKey { case displayName = "display_name" }
            }

            public let model: Model?
        }

        public let kind: String?
        public let percent: Double?
        public let resetsAt: String?
        public let scope: Scope?

        enum CodingKeys: String, CodingKey {
            case kind, percent, scope
            case resetsAt = "resets_at"
        }
    }

    public struct Breakdown: Decodable, Sendable {
        public struct Row: Decodable, Sendable {
            public let key: String?
            public let displayName: String?
            public let percent: Double?

            enum CodingKeys: String, CodingKey {
                case key, percent
                case displayName = "display_name"
            }
        }

        public let rows: [Row]?
    }

    public let fiveHour: Window?
    public let sevenDay: Window?
    public let limits: [Limit]?
    public let sevenDayBreakdown: Breakdown?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case limits
        case sevenDayBreakdown = "seven_day_breakdown"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fiveHour = try? container.decodeIfPresent(Window.self, forKey: .fiveHour)
        sevenDay = try? container.decodeIfPresent(Window.self, forKey: .sevenDay)
        limits = try? container.decodeIfPresent([Limit].self, forKey: .limits)
        sevenDayBreakdown = try? container.decodeIfPresent(Breakdown.self, forKey: .sevenDayBreakdown)
    }
}
