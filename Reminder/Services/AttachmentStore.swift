import UIKit
import SwiftData

/// 图片文件存放在 Application Support/Attachments，会随 iPhone 备份一起备份。
/// 数据库里的 Attachment.imageData 是同步用的正本，这里的文件是本机的显示副本。
enum AttachmentStore {
    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static let thumbnailCache = NSCache<NSString, UIImage>()

    static func url(for fileName: String) -> URL {
        directory.appendingPathComponent(fileName)
    }

    /// 压缩到长边 2048 像素后存为 JPEG，返回文件名
    static func save(_ image: UIImage) throws -> String {
        guard let data = image.resized(maxDimension: 2048).jpegData(compressionQuality: 0.85) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let name = UUID().uuidString + ".jpg"
        try data.write(to: url(for: name), options: .atomic)
        return name
    }

    /// 直接写入已压缩好的图片数据（从备份恢复时用）
    static func save(data: Data) throws -> String {
        let name = UUID().uuidString + ".jpg"
        try data.write(to: url(for: name), options: .atomic)
        return name
    }

    static func duplicate(_ fileName: String) -> String? {
        let name = UUID().uuidString + ".jpg"
        do {
            try FileManager.default.copyItem(at: url(for: fileName), to: url(for: name))
            return name
        } catch {
            return nil
        }
    }

    static func delete(_ fileName: String) {
        try? FileManager.default.removeItem(at: url(for: fileName))
        thumbnailCache.removeObject(forKey: fileName as NSString)
    }

    static func image(_ fileName: String) -> UIImage? {
        UIImage(contentsOfFile: url(for: fileName).path)
    }

    static func thumbnail(_ fileName: String) -> UIImage? {
        if let cached = thumbnailCache.object(forKey: fileName as NSString) { return cached }
        guard let thumb = image(fileName)?.preparingThumbnail(of: CGSize(width: 300, height: 300)) else { return nil }
        thumbnailCache.setObject(thumb, forKey: fileName as NSString)
        return thumb
    }

    static func data(_ fileName: String) -> Data? {
        try? Data(contentsOf: url(for: fileName))
    }

    private static func fileExists(_ fileName: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: fileName).path)
    }

    // MARK: - 按附件取用：本机没有文件时（从别的设备同步来的）先用数据库里的数据写出文件

    /// 确保本机有文件，返回文件名
    @discardableResult
    static func ensureFile(_ attachment: Attachment) -> String {
        let name = attachment.fileName
        if !name.isEmpty, !fileExists(name), let data = attachment.imageData {
            try? data.write(to: url(for: name), options: .atomic)
        }
        return name
    }

    static func thumbnail(for attachment: Attachment) -> UIImage? {
        thumbnail(ensureFile(attachment))
    }

    static func data(for attachment: Attachment) -> Data? {
        data(ensureFile(attachment)) ?? attachment.imageData
    }

    private static let migratedKey = "attachmentsInDatabase"

    /// 启动和 iCloud 有变化时调用：
    /// - 只做一次：1.1 之前的图片只有文件，把数据存进数据库，才能同步到别的设备
    /// - 同步来的图片写出本机文件
    /// - 删掉已经没有附件引用的文件（在别的设备上删除的）
    @MainActor
    static func reconcile(context: ModelContext) {
        guard let all = try? context.fetch(FetchDescriptor<Attachment>()) else { return }
        let migrated = UserDefaults.standard.bool(forKey: migratedKey)
        var used = Set<String>()
        var changed = false
        for attachment in all where !attachment.fileName.isEmpty {
            used.insert(attachment.fileName)
            if fileExists(attachment.fileName) {
                if !migrated, attachment.imageData == nil {
                    attachment.imageData = data(attachment.fileName)
                    changed = true
                }
            } else {
                ensureFile(attachment)
            }
        }
        if changed { try? context.save() }
        if !migrated { UserDefaults.standard.set(true, forKey: migratedKey) }

        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for file in files where !used.contains(file) {
            delete(file)
        }
    }
}

extension UIImage {
    func resized(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return self }
        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
