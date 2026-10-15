import Foundation
import SwiftData

/// 待买物品的操作。待买物品不发通知，但仍经过 ReminderActions.save 保存，保持一致。
@MainActor
enum ShoppingActions {
    /// 左划：普通物品标记已买；循环物品在"需要买"和"以后检查"之间切换
    static func swipe(_ item: Reminder, in context: ModelContext) {
        if item.shopRecurring {
            setNeeded(item, !item.shopNeeded, in: context)
        } else {
            markBought(item, in: context)
        }
    }

    static func markBought(_ item: Reminder, in context: ModelContext) {
        item.isDone = true
        item.completedAt = Date()
        item.updatedAt = Date()
        ReminderActions.save(context)
    }

    static func setNeeded(_ item: Reminder, _ needed: Bool, in context: ModelContext) {
        item.shopNeeded = needed
        item.updatedAt = Date()
        ReminderActions.save(context)
    }

    /// 改为循环时默认"需要买"；已买的普通物品改为循环后回到待买列表
    static func setRecurring(_ item: Reminder, _ recurring: Bool, in context: ModelContext) {
        item.shopRecurring = recurring
        if recurring {
            item.shopNeeded = true
            item.isDone = false
            item.completedAt = nil
        }
        item.updatedAt = Date()
        ReminderActions.save(context)
    }

    /// 永久删除所有已买物品
    static func clearBought(in context: ModelContext) {
        let descriptor = FetchDescriptor<Reminder>(predicate: #Predicate { $0.isShopping == true && $0.isDone == true })
        for item in (try? context.fetch(descriptor)) ?? [] {
            for attachment in item.attachments ?? [] {
                AttachmentStore.delete(attachment.fileName)
            }
            context.delete(item)
        }
        ReminderActions.save(context)
    }

    /// 待买列表里（含"以后检查"，不含已买）与这些名字同名的物品，按 shopKey 索引
    static func existing(matching names: [String], in context: ModelContext) -> [String: Reminder] {
        let keys = Set(names.map(Reminder.shopKey))
        let descriptor = FetchDescriptor<Reminder>(predicate: #Predicate { $0.isShopping == true && $0.isDone == false })
        var result: [String: Reminder] = [:]
        for item in (try? context.fetch(descriptor)) ?? [] {
            let key = Reminder.shopKey(item.title)
            if keys.contains(key), result[key] == nil { result[key] = item }
        }
        return result
    }

    /// 新建普通待买物品，排在列表最后，按给定顺序
    @discardableResult
    static func add(_ names: [String], in context: ModelContext) -> [Reminder] {
        let base = Date().timeIntervalSince1970
        let items = names.enumerated().map { index, name in
            let item = makeItem(text: name)
            item.sortOrder = base + Double(index) / 1000
            context.insert(item)
            return item
        }
        ReminderActions.save(context)
        return items
    }

    static func makeItem(text: String) -> Reminder {
        let item = Reminder(text: text)
        item.isShopping = true
        item.sortOrder = Date().timeIntervalSince1970
        return item
    }
}
