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
        var log = ["搜索：「\(text)」 \(Date().formatted(date: .omitted, time: .standard))"]
        let origin = center ?? visible?.center
        log.append("中心：\(describe(origin))\(center == nil ? "（没有当前位置，用地图中心）" : "（当前位置）")")
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
        for (index, region) in searchRegions.enumerated() {
            let (items, error) = await run(text, region: region)
            log.append("")
            log.append("搜索 \(index + 1)，范围 \(describe(region))：\(error.map { "失败 \($0)" } ?? "\(items.count) 个")")
            log += items.prefix(15).map { "  · \($0.name ?? "?")  \(distanceLabel(origin, $0))" }
            lists.append(items)
        }

        var seen = Set<String>()
        var merged = lists.joined().filter { seen.insert(key($0)).inserted }

        // MKLocalSearch 有时把搜索词当成别的品牌（搜 T&T 只给 AT&T）。
        // 自动补全按名字开头匹配，更准：名字以搜索词开头、结果里还没有的建议，查出位置后补进来
        let completions = await suggested
        log.append("")
        log.append("自动补全：\(completionStatus)，\(completions.count) 个")
        log += completions.prefix(15).map { "  · \($0.title) | \($0.subtitle)  [匹配 \(matchTier($0.title, query: text))]" }
        let names = Set(merged.map { normalize($0.name ?? "") })
        let missing = completions
            .filter { matchTier($0.title, query: text) >= 2 && !names.contains(normalize($0.title)) }
            .prefix(maxResolved)
        for completion in missing {
            let items: [MKMapItem]
            do {
                items = try await MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start().mapItems
            } catch {
                log.append("  查「\(completion.title)」失败 \(describe(error))")
                continue
            }
            log.append("  查「\(completion.title)」：" + items.map { "\($0.name ?? "?") \(distanceLabel(origin, $0))" }.joined(separator: "，"))
            merged += items.filter { seen.insert(key($0)).inserted }
        }
        let ranked = rank(merged, query: text, origin: origin)
        log.append("")
        log.append("最终 \(ranked.count) 个：")
        log += ranked.map { "  · \($0.name ?? "?")  [匹配 \(matchTier($0.name ?? "", query: text))]  \(distanceLabel(origin, $0))" }
        lastLog = log.joined(separator: "\n")
        return ranked
    }

    /// 最近一次搜索的过程，TestFlight 版里可以在搜索页查看，用来排查搜不到的问题
    @MainActor static var lastLog = ""
    @MainActor private static var completionStatus: String { completions.status }

    /// 每次搜索最多再查几个自动补全建议（MKLocalSearch 有频率限制）
    private static let maxResolved = 3
    @MainActor private static let completions = CompletionFetcher()

    @MainActor
    private static func run(_ text: String, region: MKCoordinateRegion?) async -> ([MKMapItem], String?) {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = [.pointOfInterest, .address]
        if let region { request.region = region }
        do {
            return (try await MKLocalSearch(request: request).start().mapItems, nil)
        } catch {
            return ([], describe(error))
        }
    }

    private static func describe(_ error: Error) -> String {
        let e = error as NSError
        return "\(e.domain) \(e.code)"
    }

    private static func describe(_ c: CLLocationCoordinate2D?) -> String {
        guard let c else { return "无" }
        return String(format: "%.3f, %.3f", c.latitude, c.longitude)
    }

    private static func describe(_ region: MKCoordinateRegion?) -> String {
        guard let region else { return "不限" }
        let km = region.span.latitudeDelta * 111
        return "\(describe(region.center)) 约 \(Int(km.rounded())) 公里"
    }

    private static func distanceLabel(_ origin: CLLocationCoordinate2D?, _ item: MKMapItem) -> String {
        guard let origin else { return "" }
        let meters = distanceMeters(from: CLLocation(latitude: origin.latitude, longitude: origin.longitude), to: item)
        return String(format: "%.1f km", meters / 1000)
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
    private static func contains(_ region: MKCoordinateRegion, _ c: CLLocationCoordinate2D) -> Bool {
        abs(c.latitude - region.center.latitude) <= region.span.latitudeDelta / 2
            && abs(c.longitude - region.center.longitude) <= region.span.longitudeDelta / 2
    }

    /// 这几个结果已经都在地图当前范围里时返回 nil，地图不动（用户自己缩小了地图时不要再放大回去）
    static func framing(_ items: [MKMapItem], visible: MKCoordinateRegion?) -> MapCameraPosition? {
        let top = items.prefix(5).map(\.placemark.coordinate)
        if let visible, !top.isEmpty, top.allSatisfy({ contains(visible, $0) }) { return nil }
        let points = top.map { MKMapPoint($0) }
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
    /// 最近一次请求是怎么结束的，写进诊断信息
    private(set) var status = ""

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.pointOfInterest, .address]
    }

    func fetch(_ text: String, region: MKCoordinateRegion?) async -> [MKLocalSearchCompletion] {
        if let region { completer.region = region }
        // 搜索词没变（例如按搜索键）时不会再回调，直接用上次的结果
        if text == completer.queryFragment && !completer.isSearching {
            status = "沿用上次"
            return completer.results
        }
        finish([], token: token, status: "被新的请求取代")
        token += 1
        let current = token
        return await withCheckedContinuation { c in
            continuation = c
            completer.queryFragment = text
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                self?.finish([], token: current, status: "2 秒超时")
            }
        }
    }

    private func finish(_ results: [MKLocalSearchCompletion], token: Int, status: String) {
        guard token == self.token, let continuation else { return }
        self.continuation = nil
        self.status = status
        continuation.resume(returning: results)
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        Task { @MainActor in finish(self.completer.results, token: token, status: "正常返回") }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        let e = error as NSError
        let text = "失败 \(e.domain) \(e.code)"
        Task { @MainActor in finish([], token: token, status: text) }
    }
}
