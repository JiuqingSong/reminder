import Foundation
import SwiftData
import CoreLocation

/// 购物地点。没有地图位置时是纯文字地点，不能开启到店提醒。
/// 一个地点可以有多个地图位置（分店），到达任何一个都会提醒。
@Model
final class Place {
    var id: UUID = UUID()
    var name: String = ""
    var alertEnabled: Bool = false
    /// 到店提醒的范围，单位米
    var radius: Double = 200
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \PlaceLocation.place)
    var locations: [PlaceLocation]? = []

    @Relationship(inverse: \Reminder.places)
    var items: [Reminder]? = []

    init(name: String) {
        self.name = name
    }
}

/// 地点在地图上的一个位置（一家分店）
@Model
final class PlaceLocation {
    var id: UUID = UUID()
    var title: String = ""
    var address: String = ""
    var latitude: Double = 0
    var longitude: Double = 0
    var createdAt: Date = Date()
    var place: Place?

    init(title: String, address: String, coordinate: CLLocationCoordinate2D) {
        self.title = title
        self.address = address
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }
}

enum PlaceRadius {
    static let options: [Double] = [100, 200, 300, 500, 1000]

    static func label(_ meters: Double) -> String {
        meters >= 1000 ? String(localized: "\(Int(meters / 1000)) 公里") : String(localized: "\(Int(meters)) 米")
    }
}

extension Place {
    var sortedLocations: [PlaceLocation] {
        (locations ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    var isTextOnly: Bool { locations?.isEmpty ?? true }

    /// 实际生效的到店提醒：开启了提醒且有地图位置
    var isAlerting: Bool { alertEnabled && !isTextOnly }

    var summary: String {
        let count = locations?.count ?? 0
        if count == 0 { return String(localized: "纯文字") }
        if count == 1 { return sortedLocations.first?.address ?? "" }
        return String(localized: "\(count) 个位置")
    }

    /// 在这里需要买的物品
    var neededItems: [Reminder] {
        (items ?? []).filter(\.isShopNeeded).sorted { ($0.sortOrder, $0.createdAt) < ($1.sortOrder, $1.createdAt) }
    }
}

extension PlaceLocation {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
