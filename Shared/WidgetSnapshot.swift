import Foundation

/// App 和小组件之间传递的数据。App 每次数据变化时写到 App Group 共享目录，小组件只读。
/// 只存原始的日期和提醒天数，"今天/明天/已过几天"由小组件按显示的那一天现算，跨过午夜不用 App 重写。
struct WidgetSnapshot: Codable, Equatable {
    struct Item: Codable, Equatable {
        var title: String
        /// nil 表示常年
        var due: Date?
        var hasTime: Bool
        var leadDays: Int
    }

    /// 未完成的提醒（不含待买），常年的按列表里的顺序排在前面，有日期的按到期时间
    var items: [Item] = []

    static let appGroup = "group.com.songthin.willdo"
    static let widgetKind = "ReminderWidget"

    private static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("widget.json")
    }

    static func load() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    /// 返回是否写入成功（侧载等没有 App Group 权限的安装方式会失败）
    @discardableResult
    func save() -> Bool {
        guard let url = Self.fileURL else { return false }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    // MARK: - 小组件显示

    enum Tone { case overdue, alerting, pinned }

    struct Row: Hashable {
        var title: String
        /// 右侧的"今天 14:30 / 明天 / 已过3天"，常年为 nil
        var label: String?
        var tone: Tone
    }

    /// 显示顺序：已过期、近期（已进入提醒区间），然后常年。"以后"的不显示。
    func rows(on day: Date, calendar: Calendar = .current) -> [Row] {
        var overdue: [Row] = []
        var alerting: [Row] = []
        var pinned: [Row] = []
        for item in items {
            guard let due = item.due else {
                pinned.append(Row(title: item.title, label: nil, tone: .pinned))
                continue
            }
            let days = calendar.dayDistance(from: day, to: due)
            if days < 0 {
                overdue.append(Row(title: item.title, label: DueFormat.relative(days: days), tone: .overdue))
            } else if days <= item.leadDays {
                var label = DueFormat.relative(days: days)
                if item.hasTime && days == 0 { label += " " + DueFormat.clock(due) }
                alerting.append(Row(title: item.title, label: label, tone: .alerting))
            }
        }
        return overdue + alerting + pinned
    }

    /// 和 App 角标同口径：已进入提醒区间且未过期的事项数
    func alertingCount(on day: Date, calendar: Calendar = .current) -> Int {
        items.filter { item in
            guard let due = item.due else { return false }
            let days = calendar.dayDistance(from: day, to: due)
            return days >= 0 && days <= item.leadDays
        }.count
    }

    func overdueCount(on day: Date, calendar: Calendar = .current) -> Int {
        items.filter { item in
            guard let due = item.due else { return false }
            return calendar.dayDistance(from: day, to: due) < 0
        }.count
    }
}

extension Calendar {
    /// 两个时刻之间相差的自然日数（忽略时分）
    func dayDistance(from a: Date, to b: Date) -> Int {
        dateComponents([.day], from: startOfDay(for: a), to: startOfDay(for: b)).day ?? 0
    }
}
