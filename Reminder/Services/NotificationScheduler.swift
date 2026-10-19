import Foundation
import SwiftData
import UserNotifications
import CoreLocation

/// 通知策略：每次数据变化都清空所有待发通知，按天重新生成"每日汇总"。
/// - 每天在设定时刻发一条汇总：今天到期 / 即将到期（已进入提醒区间）/ 已过期
/// - 角标 = 已进入提醒区间且未过期的事项数（不含常年、不含已过期）
/// - 某天没有可提醒内容但角标需要变化时，发一条只改角标、不弹窗的通知
/// - 到店提醒：开启了提醒、且有需要买的物品的地点，每个地图位置一条，进入范围时弹出（每次进入都提醒）
/// iOS 最多保留 64 条待发本地通知，这里最多排 62 条，其中到店提醒最多 20 条，剩下的给每日汇总。
@MainActor
enum NotificationScheduler {
    struct Item: Sendable {
        let title: String
        let due: Date
        let leadDays: Int
    }

    struct LocationItem: Sendable {
        let id: String
        let title: String
        let latitude: Double
        let longitude: Double
        let radius: Double
        let items: [String]
    }

    /// 点击通知后打开待买页的标记
    nonisolated static let openShoppingKey = "openShopping"

    nonisolated private static let horizonDays = 45
    nonisolated private static let maxRequests = 62
    static let maxLocations = 20
    private static var pending: Task<Void, Never>?

    static func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    @discardableResult
    static func reschedule(context: ModelContext) -> Task<Void, Never> {
        let descriptor = FetchDescriptor<Reminder>(predicate: #Predicate { $0.isDone == false })
        let items = ((try? context.fetch(descriptor)) ?? []).compactMap { r -> Item? in
            guard let due = r.dueDate else { return nil }
            return Item(title: r.title, due: due, leadDays: r.leadDays)
        }
        let locations = locationItems(context: context)
        let minutes = AppSettings.notifyMinutes
        // 串行执行，避免多次快速保存时清空/添加交错
        let previous = pending
        let task = Task {
            await previous?.value
            await schedule(items, locations: locations, notifyMinutes: minutes, now: Date())
        }
        pending = task
        return task
    }

    /// 生效的到店提醒位置，按地点创建顺序，最多 maxLocations 个
    private static func locationItems(context: ModelContext) -> [LocationItem] {
        let descriptor = FetchDescriptor<Place>(predicate: #Predicate { $0.alertEnabled == true },
                                                sortBy: [SortDescriptor(\.createdAt)])
        var result: [LocationItem] = []
        for place in (try? context.fetch(descriptor)) ?? [] {
            let names = place.neededItems.map(\.title)
            guard !names.isEmpty else { continue }
            for location in place.sortedLocations where result.count < maxLocations {
                let title = location.title.isEmpty || location.title == place.name
                    ? place.name
                    : "\(place.name) · \(location.title)"
                result.append(LocationItem(id: location.id.uuidString, title: title,
                                           latitude: location.latitude, longitude: location.longitude,
                                           radius: place.radius, items: names))
            }
        }
        return result
    }

    /// 已开启提醒的地图位置总数（不论有没有需要买的物品），用于提示是否超出上限
    static func alertLocationCount(context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<Place>(predicate: #Predicate { $0.alertEnabled == true })
        return ((try? context.fetch(descriptor)) ?? []).reduce(0) { $0 + ($1.locations?.count ?? 0) }
    }

    nonisolated private static func schedule(_ items: [Item], locations: [LocationItem], notifyMinutes: Int, now: Date) async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        for location in locations {
            await addLocation(center, location)
        }
        let budget = maxRequests - locations.count

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var currentBadge = Digest(items: items, day: today).badge
        try? await center.setBadgeCount(currentBadge)

        var count = 0
        for offset in 0..<horizonDays where count < budget {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let digest = Digest(items: items, day: day)

            // 午夜：角标变化时更新（不弹窗）
            if offset > 0, digest.badge != currentBadge {
                await add(center, id: "badge-\(dayKey(day))", content: badgeOnly(digest.badge), at: day)
                currentBadge = digest.badge
                count += 1
            }

            // 设定时刻：汇总提醒
            guard !digest.isEmpty,
                  let fire = calendar.date(byAdding: .minute, value: notifyMinutes, to: day),
                  fire > now,
                  count < budget else { continue }
            await add(center, id: "digest-\(dayKey(day))", content: digest.content(), at: fire)
            count += 1
        }
    }

    nonisolated private static func add(_ center: UNUserNotificationCenter, id: String, content: UNNotificationContent, at date: Date) async {
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    nonisolated private static func addLocation(_ center: UNUserNotificationCenter, _ location: LocationItem) async {
        let region = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
            radius: location.radius,
            identifier: "place-\(location.id)"
        )
        region.notifyOnEntry = true
        region.notifyOnExit = false
        let content = UNMutableNotificationContent()
        content.title = location.title
        content.body = String(localized: "以下物品可以在这里购买：\(L10n.join(location.items))")
        content.sound = .default
        content.userInfo = [openShoppingKey: true]
        let trigger = UNLocationNotificationTrigger(region: region, repeats: true)
        try? await center.add(UNNotificationRequest(identifier: "place-\(location.id)", content: content, trigger: trigger))
    }

    nonisolated private static func badgeOnly(_ badge: Int) -> UNNotificationContent {
        let content = UNMutableNotificationContent()
        content.badge = NSNumber(value: badge)
        return content
    }

    nonisolated private static func dayKey(_ day: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: day)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
}

/// 某一天的提醒汇总
private struct Digest {
    var dueToday: [String] = []
    var upcoming: [(title: String, days: Int)] = []
    var overdue: [(title: String, days: Int)] = []

    init(items: [NotificationScheduler.Item], day: Date) {
        let calendar = Calendar.current
        for item in items {
            let days = calendar.dayDistance(from: day, to: item.due)
            if days < 0 {
                overdue.append((item.title, -days))
            } else if days == 0 {
                dueToday.append(item.title)
            } else if days <= item.leadDays {
                upcoming.append((item.title, days))
            }
        }
        upcoming.sort { $0.days < $1.days }
        overdue.sort { $0.days < $1.days }
    }

    var isEmpty: Bool { dueToday.isEmpty && upcoming.isEmpty && overdue.isEmpty }
    var badge: Int { dueToday.count + upcoming.count }

    func content() -> UNNotificationContent {
        let content = UNMutableNotificationContent()
        if !dueToday.isEmpty {
            content.title = String(localized: "今天有 \(dueToday.count) 件事到期")
        } else if !upcoming.isEmpty {
            content.title = String(localized: "有 \(upcoming.count) 件事即将到期")
        } else {
            content.title = String(localized: "有 \(overdue.count) 件事已过期")
        }

        var lines: [String] = []
        if !dueToday.isEmpty {
            lines.append(String(localized: "今天：\(L10n.join(dueToday))"))
        }
        for group in Dictionary(grouping: upcoming, by: \.days).sorted(by: { $0.key < $1.key }) {
            let titles = L10n.join(group.value.map(\.title))
            lines.append(String(localized: "\(DueFormat.relative(days: group.key))：\(titles)"))
        }
        if !overdue.isEmpty {
            let titles = L10n.join(overdue.map { String(localized: "\($0.title)（\($0.days)天）") })
            lines.append(String(localized: "已过期：\(titles)"))
        }
        content.body = lines.joined(separator: "\n")
        content.sound = .default
        content.badge = NSNumber(value: badge)
        return content
    }
}
