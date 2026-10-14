import Foundation

enum AppSettings {
    static let notifyMinutesKey = "notifyMinutes"
    static let defaultLeadDaysKey = "defaultLeadDays"

    /// 每天发送提醒的时刻，单位：从 0 点起的分钟数。默认 9:00
    static let defaultNotifyMinutes = 9 * 60

    static var notifyMinutes: Int {
        UserDefaults.standard.object(forKey: notifyMinutesKey) as? Int ?? defaultNotifyMinutes
    }
}
