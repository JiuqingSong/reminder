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

    /// 从地图搜索结果新建地点；同名地点已存在时把位置加到它下面。
    /// alert 是添加时选的到店提醒设置，会覆盖地点原来的设置
    static func create(from mapItem: MKMapItem, alert: PlaceAlertChoice? = nil, in context: ModelContext) -> Place {
        let place = findOrCreate(name: mapItem.name ?? String(localized: "未命名地点"), in: context)
        if let alert {
            if alert.enabled { LocationAuthorization.shared.request() }
            place.alertEnabled = alert.enabled
            place.radius = alert.radius
        }
        addLocation(mapItem, to: place, in: context)
        return place
    }

    /// 开关到店提醒；开启时如果还没设置定位权限就申请
    static func setAlert(_ place: Place, on: Bool, in context: ModelContext) {
        if on { LocationAuthorization.shared.request() }
        place.alertEnabled = on
        ReminderActions.save(context)
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

/// 在地图上搜索添加地点时一起选的到店提醒设置，默认开启
struct PlaceAlertChoice {
    var enabled = true
    var radius: Double = 200
}

/// 定位权限。到店提醒只需要"使用 App 期间"权限，App 没在运行时也能弹出通知。
@MainActor
@Observable
final class LocationAuthorization: NSObject, CLLocationManagerDelegate {
    static let shared = LocationAuthorization()

    @ObservationIgnored private let manager = CLLocationManager()
    var status: CLAuthorizationStatus = .notDetermined
    /// 最近一次拿到的当前位置，给地图搜索定中心用
    var location: CLLocation?
    /// 还没有权限时要了位置，等授权后再取
    @ObservationIgnored private var wantsLocation = false

    private override init() {
        super.init()
        manager.delegate = self
        status = manager.authorizationStatus
        location = manager.location
    }

    var isAllowed: Bool { status == .authorizedWhenInUse || status == .authorizedAlways }

    func request() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    /// 取一次当前位置（先用系统缓存的），没有权限时先申请
    func requestLocation() {
        if let cached = manager.location { location = cached }
        if isAllowed {
            manager.requestLocation()
        } else {
            wantsLocation = true
            request()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.status = status
            if wantsLocation && isAllowed {
                wantsLocation = false
                self.manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        Task { @MainActor in self.location = last }
    }

    /// requestLocation 要求实现；取不到位置时地图保持原样
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
