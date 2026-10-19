import Foundation
import SwiftData
import MapKit
import CoreLocation

/// 地点的增删。所有修改都经过 ReminderActions.save，保存后重建到店提醒。
@MainActor
enum PlaceActions {
    /// 已有同名地点（不区分大小写）时直接返回它
    static func findOrCreate(name: String, in context: ModelContext) -> Place {
        let key = Reminder.shopKey(name)
        if let existing = ((try? context.fetch(FetchDescriptor<Place>())) ?? []).first(where: { Reminder.shopKey($0.name) == key }) {
            return existing
        }
        let place = Place(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        context.insert(place)
        ReminderActions.save(context)
        return place
    }

    /// 从地图搜索结果新建地点；同名地点已存在时把位置加到它下面
    static func create(from mapItem: MKMapItem, in context: ModelContext) -> Place {
        let place = findOrCreate(name: mapItem.name ?? String(localized: "未命名地点"), in: context)
        addLocation(mapItem, to: place, in: context)
        return place
    }

    static func addLocation(_ mapItem: MKMapItem, to place: Place, in context: ModelContext) {
        let location = PlaceLocation(title: mapItem.name ?? "",
                                     address: mapItem.placemark.title ?? "",
                                     coordinate: mapItem.placemark.coordinate)
        context.insert(location)
        location.place = place
        ReminderActions.save(context)
    }

    static func delete(_ location: PlaceLocation, in context: ModelContext) {
        context.delete(location)
        ReminderActions.save(context)
    }

    /// 删除地点。用到它的物品只是去掉这个地点，物品本身保留
    static func delete(_ place: Place, in context: ModelContext) {
        context.delete(place)
        ReminderActions.save(context)
    }
}

/// 定位权限。到店提醒只需要"使用 App 期间"权限，App 没在运行时也能弹出通知。
@MainActor
@Observable
final class LocationAuthorization: NSObject, CLLocationManagerDelegate {
    static let shared = LocationAuthorization()

    @ObservationIgnored private let manager = CLLocationManager()
    var status: CLAuthorizationStatus = .notDetermined

    private override init() {
        super.init()
        manager.delegate = self
        status = manager.authorizationStatus
    }

    var isAllowed: Bool { status == .authorizedWhenInUse || status == .authorizedAlways }

    func request() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.status = status }
    }
}
