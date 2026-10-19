import Foundation

/// 日期格式跟随 App 当前语言，例如 10月14日 周二 / Tue, Oct 14
enum DueFormat {
    private static func formatter(_ template: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }

    private static let sameYear = formatter("MMMdEEE")
    private static let otherYear = formatter("yMMMdEEE")
    private static let time = formatter("HHmm")
    private static let full = formatter("yMMMdHHmm")

    /// 例：10月14日 周二 14:30；跨年时带年份
    static func date(_ date: Date, hasTime: Bool, now: Date = Date()) -> String {
        let calendar = Calendar.current
        let base = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            ? sameYear.string(from: date)
            : otherYear.string(from: date)
        return hasTime ? base + " " + time.string(from: date) : base
    }

    /// 例：14:30
    static func clock(_ date: Date) -> String {
        time.string(from: date)
    }

    static func timestamp(_ date: Date) -> String {
        full.string(from: date)
    }

    static func relative(days: Int) -> String {
        switch days {
        case 0: String(localized: "今天")
        case 1: String(localized: "明天")
        case 2: String(localized: "后天")
        case let d where d > 2: String(localized: "\(d)天后")
        default: String(localized: "已过\(-days)天")
        }
    }
}
