//
//  MilkTeaRadarApp.swift
//  MilkTeaRadar
//
//  应用入口。负责：
//   - 装配根视图；
//   - 注册通知代理（保证 App 在前台时也能收到提醒）；
//   - 监听前后台切换，交由 Repository 做补偿刷新。
//

import SwiftUI
import UserNotifications

@main
struct MilkTeaRadarApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var repository = DealRepository()

    var body: some Scene {
        WindowGroup {
            DealListView(repository: repository)
        }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .active:
                // 回到前台：可能离开很久，或数据已陈旧，触发补偿刷新
                repository.handleWillEnterForeground()
            case .background:
                // 进后台：断开长连接，省电并避免无效重连
                repository.handleDidEnterBackground()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// 让通知在 App 前台时也能展示
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
            @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}
