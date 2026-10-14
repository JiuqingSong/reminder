import Foundation
import SwiftData

/// 备份文件：单个 JSON，图片以 base64 内嵌。不依赖 zip，导入导出都只用系统 API。
struct BackupFile: Codable {
    var version: Int
    var exportedAt: Date
    var reminders: [BackupReminder]
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
                images: r.sortedAttachments.compactMap { try? Data(contentsOf: AttachmentStore.url(for: $0.fileName)) }
            )
        })

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(backup)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("提醒备份-\(formatter.string(from: Date())).json")
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
            context.insert(r)
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
}
