import SwiftData

/// App 界面和 Siri 共用同一个数据库容器，Siri 添加的提醒能立刻出现在列表里
@MainActor
enum AppModel {
    static let container: ModelContainer = {
        do {
            return try ModelContainer(for: Reminder.self, Attachment.self, Place.self, PlaceLocation.self)
        } catch {
            fatalError("无法打开数据库：\(error)")
        }
    }()
}
