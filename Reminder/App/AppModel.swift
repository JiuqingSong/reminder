import SwiftData
#if DEBUG
import CoreData
#endif

/// App 界面和 Siri 共用同一个数据库容器，Siri 添加的提醒能立刻出现在列表里。
/// 有 iCloud 权限时（entitlements 里的 CloudKit 容器）自动同步到用户的私有 iCloud 数据库；
/// 没有权限（如侧载）或没登录 iCloud 时就是普通的本机数据库。
@MainActor
enum AppModel {
    static let cloudContainerID = "iCloud.com.songthin.willdo"
    static let models: [any PersistentModel.Type] = [Reminder.self, Attachment.self, Place.self, PlaceLocation.self]

    static let container: ModelContainer = {
        do {
            let configuration = ModelConfiguration()
            #if DEBUG
            initializeCloudKitSchema(storeURL: configuration.url)
            #endif
            return try ModelContainer(for: Schema(models), configurations: configuration)
        } catch {
            fatalError("无法打开数据库：\(error)")
        }
    }()

    #if DEBUG
    /// 在 CloudKit 开发环境里建好全部记录类型。只在 Xcode 调试运行时执行；
    /// 之后到 CloudKit Console 把开发环境的结构部署到生产环境，TestFlight / App Store 版才能同步。
    private static func initializeCloudKitSchema(storeURL: URL) {
        let description = NSPersistentStoreDescription(url: storeURL)
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: cloudContainerID)
        description.shouldAddStoreAsynchronously = false
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: models) else { return }
        let container = NSPersistentCloudKitContainer(name: "Reminder", managedObjectModel: model)
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError {
            print("CloudKit schema: load failed: \(loadError)")
            return
        }
        do {
            try container.initializeCloudKitSchema()
            print("CloudKit schema: initialized")
        } catch {
            print("CloudKit schema: \(error)")
        }
        for store in container.persistentStoreCoordinator.persistentStores {
            try? container.persistentStoreCoordinator.remove(store)
        }
    }
    #endif
}
