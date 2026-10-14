import Foundation
import UIKit

/// 识别文本中的链接、地址、电话，生成可点击的 AttributedString
enum ContentDetector {
    /// 地址用自定义 scheme 标记，点击时由 openURL 拦截后交给 MapOpener
    static let mapScheme = "x-reminder-map"

    private static let detector: NSDataDetector? = {
        let types: NSTextCheckingResult.CheckingType = [.link, .address, .phoneNumber]
        return try? NSDataDetector(types: types.rawValue)
    }()

    static func attributed(_ text: String) -> AttributedString {
        let result = NSMutableAttributedString(string: text)
        guard let detector else { return AttributedString(text) }

        for match in detector.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)) {
            var url: URL?
            switch match.resultType {
            case .link:
                url = match.url
            case .address:
                let address = (text as NSString).substring(with: match.range)
                var components = URLComponents()
                components.scheme = mapScheme
                components.host = "open"
                components.queryItems = [URLQueryItem(name: "q", value: address)]
                url = components.url
            case .phoneNumber:
                if let number = match.phoneNumber {
                    url = URL(string: "tel:" + number.filter { $0.isNumber || $0 == "+" })
                }
            default:
                break
            }
            if let url {
                result.addAttribute(.link, value: url, range: match.range)
            }
        }
        return AttributedString(result)
    }

    /// 从 mapScheme 链接中取回地址
    static func address(from url: URL) -> String? {
        guard url.scheme == mapScheme else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "q" }?.value
    }
}

/// 地址统一用 Google 地图打开：装了 App 用 App，没装用网页（网页链接在装了 App 时同样会跳转 App）
enum MapOpener {
    @MainActor
    static func open(address: String) {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#")
        let query = address.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""

        if let app = URL(string: "comgooglemaps://?q=\(query)"), UIApplication.shared.canOpenURL(app) {
            UIApplication.shared.open(app)
        } else if let web = URL(string: "https://www.google.com/maps/search/?api=1&query=\(query)") {
            UIApplication.shared.open(web)
        }
    }
}
