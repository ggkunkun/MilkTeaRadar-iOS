//
//  ReminderStore.swift
//  MilkTeaRadar
//
//  提醒开关的持久化（UserDefaults）+ 本地通知调度。
//  本地提醒是纯客户端状态，服务端无需感知，因此不走冲突合并，
//  只做「开关状态持久化 + 重建通知」。
//

import Foundation
import UserNotifications

@MainActor
final class ReminderStore: ObservableObject {

    @Published private(set) var ids: Set<String> = []

    private let key = "mtr.reminders"

    init() {
        load()
    }

    // MARK: 持久化

    private func load() {
        let arr = UserDefaults.standard.array(forKey: key) as? [String] ?? []
        ids = Set(arr)
    }

    private func persist() {
        UserDefaults.standard.set(Array(ids), forKey: key)
    }

    func isOn(_ id: String) -> Bool { ids.contains(id) }

    // MARK: 切换

    /// 切换某条优惠的提醒。
    /// - Returns: 切换后是否开启
    func toggle(_ deal: Deal) async -> Bool {
        let nowOn = !ids.contains(deal.id)

        if nowOn {
            let granted = await requestAuthorization()
            guard granted else { return false }
            ids.insert(deal.id)
            await scheduleNotification(for: deal)
        } else {
            ids.remove(deal.id)
            cancelNotification(for: deal)
        }
        persist()
        return nowOn
    }

    /// 应用启动 / 数据刷新后重建通知（活动可能已下线或改期）
    func resyncNotifications(with deals: [Deal]) async {
        let center = UNUserNotificationCenter.current()
        let active = Set(deals.filter { $0.validity().isActive }.map { $0.id })

        // 清理已下线活动的提醒
        for id in ids where !active.contains(id) {
            ids.remove(id)
            center.removePendingNotificationRequests(withIdentifiers: ["mtr:" + id])
        }

        // 为仍在期内的提醒重建通知
        for deal in deals where ids.contains(deal.id) {
            await scheduleNotification(for: deal)
        }
        persist()
    }

    // MARK: 通知

    private func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .authorized { return true }

        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            print("[notify] 授权失败: \(error)")
            return false
        }
    }

    private func scheduleNotification(for deal: Deal) async {
        let center = UNUserNotificationCenter.current()
        let identifier = "mtr:" + deal.id
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        // 有明确截止日的活动：截止当天 09:00 提醒；长期活动不排程
        guard let end = Deal.dayFormatter.date(from: deal.validUntil) else { return }

        var comps = Calendar.current.dateComponents([.year, .month, .day], from: end)
        comps.hour = 9
        comps.minute = 0

        // 若截止日已过，不再排程
        guard let fire = Calendar.current.date(from: comps), fire > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(deal.brand) 优惠今天截止"
        content.body = "\(deal.title) · \(deal.discount)"
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let req = UNNotificationRequest(identifier: identifier, content: content,
                                        trigger: trigger)
        do { try await center.add(req) }
        catch { print("[notify] 排程失败: \(error)") }
    }

    private func cancelNotification(for deal: Deal) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["mtr:" + deal.id])
    }
}
