import Foundation
import SwiftData

/// 图片附件。图片数据存在数据库里（externalStorage，随 iCloud 同步），
/// 本机另有一份文件（见 AttachmentStore）供显示用；在别的设备上同步过来的，第一次显示时写出文件。
@Model
final class Attachment {
    var id: UUID = UUID()
    var fileName: String = ""
    var order: Int = 0
    var createdAt: Date = Date()
    @Attribute(.externalStorage) var imageData: Data?
    var reminder: Reminder?

    /// 文件要先写好：图片数据从文件读进来
    init(fileName: String, order: Int) {
        self.fileName = fileName
        self.order = order
        self.imageData = AttachmentStore.data(fileName)
    }
}
