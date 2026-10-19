import Foundation
import SwiftData
import CoreLocation

/// 备份文件：单个 JSON，图片以 base64 内嵌。不依赖 zip，导入导出都只用系统 API。
struct BackupFile: Codable {
    var version: Int
    var exportedAt: Date
    var reminders: [BackupReminder]
    /// 购物地点（后来加的，旧备份里没有）
    var places: [BackupPlace]?
}

struct BackupPlace: Codable {
    var id: UUID
    var name: String
    var alertEnabled: Bool
    var radius: Double
    var createdAt: Date
    var locations: [BackupLocation]
}

struct BackupLocation: Codable {
    var id: UUID
    var title: String
    var address: String
    var latitude: Double
    var longitude: Double
    var createdAt: Date
}

struct BackupReminder: Codable {
    var id: UUID
    var text: String
    var dueDate: Date?
    var hasTime: Bool
    var leadDays: Int
    var recurrence: String
    var recurrenceInterval: Int
    var isDone: Bool
    var completedAt: Date?
    var sortOrder: Double
    var createdAt: Date
    var updatedAt: Date
    var images: [Data]
    // 待买物品（后来加的，旧备份里没有这些字段）
    var isShopping: Bool?
    var shopRecurring: Bool?
    var shopNeeded: Bool?
    var placeIDs: [UUID]?
}

@MainActor
enum BackupService {
    enum ImportMode {
        /// 保留现有数据，跳过备份中 id 已存在的事项
        case merge
        /// 清空现有数据后导入
        case replace
    }

    static func export(context: ModelContext) throws -> URL {
        let reminders = try context.fetch(FetchDescriptor<Reminder>())
        let backup = BackupFile(version: 1, exportedAt: Date(), reminders: reminders.map { r in
            BackupReminder(
                id: r.id,
                text: r.text,
                dueDate: r.dueDate,
                hasTime: r.hasTime,
                leadDays: r.leadDays,
                recurrence: r.recurrenceRaw,
                recurrenceInterval: r.recurrenceInterval,
                isDone: r.isDone,
                completedAt: r.completedAt,
                sortOrder: r.sortOrder,
                createdAt: r.createdAt,
                updatedAt: r.updatedAt,
                images: r.sortedAttachments.compactMap { try? Data(contentsOf: AttachmentStore.url(for: $0.fileName)) },
                isShopping: r.isShopping,
                shopRecurring: r.shopRecurring,
                shopNeeded: r.shopNeeded,
                placeIDs: r.sortedPlaces.map { $0.id }
            )
        }, places: try context.fetch(FetchDescriptor<Place>()).map { p in
            BackupPlace(
                id: p.id,
                name: p.name,
                alertEnabled: p.alertEnabled,
                radius: p.radius,
                createdAt: p.createdAt,
                locations: p.sortedLocations.map { l in
                    BackupLocation(id: l.id, title: l.title, address: l.address,
                                   latitude: l.latitude, longitude: l.longitude, createdAt: l.createdAt)
                }
            )
        })

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(backup)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(String(localized: "提醒备份-\(formatter.string(from: Date()))") + ".json")
        try data.write(to: url, options: .atomic)
        return url
    }

    static func read(_ url: URL) throws -> BackupFile {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BackupFile.self, from: Data(contentsOf: url))
    }

    /// 返回实际导入的条数
    static func restore(_ backup: BackupFile, mode: ImportMode, context: ModelContext) throws -> Int {
        let existing = try context.fetch(FetchDescriptor<Reminder>())
        var existingIDs = Set(existing.map(\.id))
        if mode == .replace {
            for reminder in existing {
                for attachment in reminder.attachments ?? [] {
                    AttachmentStore.delete(attachment.fileName)
                }
                context.delete(reminder)
            }
            existingIDs = []
        }
        let placesByID = restorePlaces(backup.places ?? [], mode: mode, context: context)

        var count = 0
        for item in backup.reminders where !existingIDs.contains(item.id) {
            let r = Reminder(text: item.text, dueDate: item.dueDate, hasTime: item.hasTime, leadDays: item.leadDays)
            r.id = item.id
            r.recurrenceRaw = item.recurrence
            r.recurrenceInterval = item.recurrenceInterval
            r.isDone = item.isDone
            r.completedAt = item.completedAt
            r.sortOrder = item.sortOrder
            r.createdAt = item.createdAt
            r.updatedAt = item.updatedAt
            r.isShopping = item.isShopping ?? false
            r.shopRecurring = item.shopRecurring ?? false
            r.shopNeeded = item.shopNeeded ?? true
            context.insert(r)
            r.places = (item.placeIDs ?? []).compactMap { placesByID[$0] }
            for (index, data) in item.images.enumerated() {
                guard let name = try? AttachmentStore.save(data: data) else { continue }
                let attachment = Attachment(fileName: name, order: index)
                context.insert(attachment)
                attachment.reminder = r
            }
            count += 1
        }
        ReminderActions.save(context)
        return count
    }

    /// 合并时保留 id 已存在的地点；返回 id → 地点，供物品关联
    private static func restorePlaces(_ places: [BackupPlace], mode: ImportMode, context: ModelContext) -> [UUID: Place] {
        let existing = (try? context.fetch(FetchDescriptor<Place>())) ?? []
        var byID: [UUID: Place] = [:]
        if mode == .replace {
            for place in existing { context.delete(place) }
        } else {
            for place in existing { byID[place.id] = place }
        }
        for item in places where byID[item.id] == nil {
            let place = Place(name: item.name)
            place.id = item.id
            place.alertEnabled = item.alertEnabled
            place.radius = item.radius
            place.createdAt = item.createdAt
            context.insert(place)
            for l in item.locations {
                let location = PlaceLocation(title: l.title, address: l.address,
                                             coordinate: CLLocationCoordinate2D(latitude: l.latitude, longitude: l.longitude))
                location.id = l.id
                location.createdAt = l.createdAt
                context.insert(location)
                location.place = place
            }
            byID[item.id] = place
        }
        return byID
    }
}
