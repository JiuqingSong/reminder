import Foundation
import SwiftData

/// 图片附件。图片本体存为文件（见 AttachmentStore），数据库只记文件名。
@Model
final class Attachment {
    var id: UUID = UUID()
    var fileName: String = ""
    var order: Int = 0
    var createdAt: Date = Date()
    var reminder: Reminder?

    init(fileName: String, order: Int) {
        self.fileName = fileName
        self.order = order
    }
}
