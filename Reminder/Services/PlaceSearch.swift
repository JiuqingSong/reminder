import Foundation
import MapKit
import SwiftUI

/// 地图搜索地点。
///
/// MKLocalSearch 基本只返回给定范围内的结果，地图显示得小时，稍远一点的店就搜不到；
/// 它还会把搜索词理解成别的品牌（搜 T&T 只给 AT&T）。
/// 所以地图当前范围和周围 60 公里各搜一次，再用自动补全（按名字开头匹配）补上漏掉的，
/// 合并去重，再按"名字匹配程度 + 距离"排序：
/// 名字以搜索词开头的（T&T Supermarket）排在只是包含搜索词的（AT&T）前面，即使后者更近；
/// 同一档里近的在前。超过 50 公里的不因名字匹配往前排。
enum PlaceSearch {
    /// 稍远范围的边长（米）。地图当前显示得比这还大时就只搜地图范围
    static let wideSpan: CLLocationDistance = 60_000
    /// 超过这个距离，名字再匹配也只按距离排
    static let preferredDistance: CLLocationDistance = 50_000

    /// visible：地图当前范围；center：算距离和稍远范围用的中心，一般是当前位置
    @MainActor
    static func search(_ text: String,
                       visible: MKCoordinateRegion?,
                       center: CLLocationCoordinate2D?) async -> [MKMapItem] {
        let origin = center ?? visible?.center
        var regions: [MKCoordinateRegion] = []
        if let visible { regions.append(visible) }
        if let origin {
            let wide = MKCoordinateRegion(center: origin, latitudinalMeters: wideSpan, longitudinalMeters: wideSpan)
            if (visible?.span.latitudeDelta ?? 0) < wide.span.latitudeDelta { regions.append(wide) }
        }

        // 自动补全和搜索是两个服务，可以同时进行；
        // MKLocalSearch 同时发多个请求会被限流而失败，所以一个接一个地搜
        async let suggested = completions.fetch(text, region: regions.last)
        let searchRegions: [MKCoordinateRegion?] = regions.isEmpty ? [nil] : regions
        var lists: [[MKMapItem]] = []
        for region in searchRegions {
            lists.append(await run(text, region: region))
        }

        var seen = Set<String>()
        var merged = lists.joined().filter { seen.insert(key($0)).inserted }

        // MKLocalSearch 有时把搜索词当成别的品牌（搜 T&T 只给 AT&T）。
        // 自动补全按名字开头匹配，更准：名字以搜索词开头、结果里还没有的建议，查出位置后补进来
        let names = Set(merged.map { normalize($0.name ?? "") })
        let missing = await suggested
            .filter { matchTier($0.title, query: text) >= 2 && !names.contains(normalize($0.title)) }
            .prefix(maxResolved)
        for completion in missing {
            let items = (try? await MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start().mapItems) ?? []
            merged += items.filter { seen.insert(key($0)).inserted }
        }
        return rank(merged, query: text, origin: origin)
    }

    /// 每次搜索最多再查几个自动补全建议（MKLocalSearch 有频率限制）
    private static let maxResolved = 3
    @MainActor private static let completions = CompletionFetcher()

    @MainActor
    private static func run(_ text: String, region: MKCoordinateRegion?) async -> [MKMapItem] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = [.pointOfInterest, .address]
        if let region { request.region = region }
        return (try? await MKLocalSearch(request: request).start().mapItems) ?? []
    }

    /// 同名且几乎同一位置的算同一个
    private static func key(_ item: MKMapItem) -> String {
        let c = item.placemark.coordinate
        return "\(normalize(item.name ?? ""))|\((c.latitude * 2000).rounded())|\((c.longitude * 2000).rounded())"
    }

    static func rank(_ items: [MKMapItem], query: String, origin: CLLocationCoordinate2D?) -> [MKMapItem] {
        let from = origin.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        let scored = items.enumerated().map { index, item -> (item: MKMapItem, tier: Int, distance: Double, index: Int) in
            let distance = from.map { distanceMeters(from: $0, to: item) } ?? 0
            var tier = matchTier(item.name ?? "", query: query)
            if distance > preferredDistance { tier = 0 }
            return (item, tier, distance, index)
        }
        // 先比匹配程度，再比距离；都一样时保持 Apple 原来的顺序
        return scored.sorted {
            if $0.tier != $1.tier { return $0.tier > $1.tier }
            if from != nil, $0.distance != $1.distance { return $0.distance < $1.distance }
            return $0.index < $1.index
        }.map { $0.item }
    }

    /// 3 名字和搜索词相同；2 名字或其中某个词以搜索词开头；1 名字包含搜索词；0 其他（比如只有地址匹配）
    static func matchTier(_ name: String, query: String) -> Int {
        let n = normalize(name)
        let q = normalize(query)
        guard !q.isEmpty, !n.isEmpty else { return 0 }
        if n == q { return 3 }
        if n.hasPrefix(q) { return 2 }
        let words = name.split { $0.isWhitespace || "-–·•,()/".contains($0) }
        if words.contains(where: { normalize(String($0)).hasPrefix(q) }) { return 2 }
        if n.contains(q) { return 1 }
        return 0
    }

    static func distanceMeters(from origin: CLLocation, to item: MKMapItem) -> CLLocationDistance {
        let c = item.placemark.coordinate
        return origin.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
    }

    /// 忽略大小写、重音、全半角和空格
    private static func normalize(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .filter { !$0.isWhitespace }
    }

    /// 按 Search 键后地图显示的范围：排在前面的几个结果
    static func framing(_ items: [MKMapItem]) -> MapCameraPosition? {
        let points = items.prefix(5).map { MKMapPoint($0.placemark.coordinate) }
        guard let first = points.first else { return nil }
        var rect = MKMapRect(origin: first, size: MKMapSize(width: 0, height: 0))
        for p in points.dropFirst() {
            rect = rect.union(MKMapRect(origin: p, size: MKMapSize(width: 0, height: 0)))
        }
        // 留点边，只有一个结果时也不要放得太大（至少周围约 1.5 公里）
        let pointsPerMeter = MKMapPointsPerMeterAtLatitude(items[items.startIndex].placemark.coordinate.latitude)
        let pad = max(rect.width, rect.height) * 0.25 + 1500 * pointsPerMeter
        return .rect(rect.insetBy(dx: -pad, dy: -pad))
    }
}

/// 把 MKLocalSearchCompleter（委托回调）包成一次 async 调用。
/// 新的请求会让还没返回的旧请求直接得到空结果；2 秒没回应也返回空
@MainActor
final class CompletionFetcher: NSObject, MKLocalSearchCompleterDelegate {
    private let completer = MKLocalSearchCompleter()
    private var continuation: CheckedContinuation<[MKLocalSearchCompletion], Never>?
    private var token = 0

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.pointOfInterest, .address]
    }

    func fetch(_ text: String, region: MKCoordinateRegion?) async -> [MKLocalSearchCompletion] {
        if let region { completer.region = region }
        // 搜索词没变（例如按搜索键）时不会再回调，直接用上次的结果
        if text == completer.queryFragment && !completer.isSearching {
            return completer.results
        }
        finish([], token: token)
        token += 1
        let current = token
        return await withCheckedContinuation { c in
            continuation = c
            completer.queryFragment = text
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                self?.finish([], token: current)
            }
        }
    }

    private func finish(_ results: [MKLocalSearchCompletion], token: Int) {
        guard token == self.token, let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: results)
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        Task { @MainActor in finish(self.completer.results, token: token) }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in finish([], token: token) }
    }
}
