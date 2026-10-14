import UIKit

/// 图片文件存放在 Application Support/Attachments，会随 iPhone 备份一起备份。
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
