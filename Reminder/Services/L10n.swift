import Foundation

/// 多语言的小工具。界面文字的翻译在 Localizable.xcstrings，原文（key）就是简体中文。
enum L10n {
    /// 列表分隔符：中文用顿号，英文用逗号
    static var separator: String { String(localized: "、", comment: "列表分隔符") }

    static func join(_ items: [String]) -> String {
        items.joined(separator: separator)
    }
}
