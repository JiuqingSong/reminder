import Foundation
import MapKit

/// 地图搜索地点。
///
/// MKLocalSearch 基本只返回给定范围内的结果，地图显示得小时，稍远一点的店就搜不到。
/// 所以地图当前范围和周围 60 公里各搜一次，合并去重，再按"名字匹配程度 + 距离"排序：
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

        // 两次搜索同时进行；没有结果时 MKLocalSearch 会抛错，当作空列表
        var lists: [[MKMapItem]] = []
        if regions.isEmpty {
            lists = [await run(text, region: nil)]
        } else if regions.count == 1 {
            lists = [await run(text, region: regions[0])]
        } else {
            async let near = run(text, region: regions[0])
            async let wide = run(text, region: regions[1])
            lists = [await near, await wide]
        }

        var seen = Set<String>()
        let merged = lists.joined().filter { seen.insert(key($0)).inserted }
        return rank(merged, query: text, origin: origin)
    }

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
        }.map(\.item)
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
