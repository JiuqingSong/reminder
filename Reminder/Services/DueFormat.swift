import Foundation

enum DueFormat {
    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = format
        return f
    }

    private static let sameYear = formatter("M月d日 EEE")
    private static let otherYear = formatter("yyyy年M月d日 EEE")
    private static let time = formatter("HH:mm")
    private static let full = formatter("yyyy年M月d日 HH:mm")

    /// 例：10月14日 周二 14:30；跨年时带年份
    static func date(_ date: Date, hasTime: Bool, now: Date = Date()) -> String {
        let calendar = Calendar.current
        let base = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            ? sameYear.string(from: date)
            : otherYear.string(from: date)
        return hasTime ? base + " " + time.string(from: date) : base
    }

    static func timestamp(_ date: Date) -> String {
        full.string(from: date)
    }

    static func relative(days: Int) -> String {
        switch days {
        case 0: "今天"
        case 1: "明天"
        case 2: "后天"
        case let d where d > 2: "\(d)天后"
        default: "已过\(-days)天"
        }
    }
}
