//
//  DealRepository.swift
//  MilkTeaRadar
//
//  数据仓库：唯一的数据出口。
//  职责：
//   1) 冷启动：先读本地缓存秒开，再静默拉取远端；
//   2) 实时：订阅 SSE 增量事件，按版本号合并后推送给 UI；
//   3) 降级：网络失败保留缓存，对外抛出可操作错误；
//   4) 补偿：前后台切换 / 网络恢复时按「陈旧度」决定是否全量刷新。
//

import Foundation
import Combine

/// 数据来源，用于 UI 顶部状态标识
enum DataSource: Equatable {
    case live          // 本次来自网络
    case cache(age: String)   // 来自本地缓存
    case offline      // 断网中
}

@MainActor
final class DealRepository: ObservableObject {

    // MARK: 对外状态

    @Published private(set) var deals: [Deal] = []
    @Published private(set) var version: Int = 0
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var source: DataSource = .offline
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: NetworkError?

    let reminders = ReminderStore()
    let realtime = RealtimeClient()

    private var backgroundedAt: Date?

    // MARK: 冷启动

    /// 应用启动入口：先渲染缓存，再联网刷新
    func bootstrap() async {
        if let snap = await DealCache.shared.load() {
            applyDocument(snap.document, isLive: false)
            source = .cache(age: snap.ageText)
        }
        await refresh(isManual: false)
        realtime.onDeals = { [weak self] deals, version in
            Task { @MainActor in self?.applyDocument(
                DealsDocument(app: nil, generatedAt: ISO8601DateFormatter().string(from: Date()),
                              digestFile: nil, source: nil, version: version, deals: deals),
                isLive: true) }
        realtime.start()
    }

    // MARK: 刷新

    func refresh(isManual: Bool) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let doc = try await APIClient.shared.fetchDeals()
            // 版本守卫：只有更新的版本才应用
            guard doc.version >= version else { return }
            applyDocument(doc, isLive: true)
            await DealCache.shared.save(doc)
            lastError = nil
        } catch let e as NetworkError {
            lastError = e
            if deals.isEmpty {
                // 没有任何缓存可展示 -> 抛出让 UI 显示错误页（但绝不白屏）
                throw e
            }
        } catch {
            lastError = NetworkError.map(error)
        }
    }

    // MARK: 生命周期补偿

    func handleDidEnterBackground() {
        backgroundedAt = Date()
        realtime.stop()
    }

    /// 回到前台：若离开超过阈值或数据陈旧，立即补偿刷新并重连
    func handleWillEnterForeground() {
        let away = backgroundedAt.map { Date().timeIntervalSince($0) } ?? .greatestFiniteMagnitude
        let docStale = lastSyncAt.map { Date().timeIntervalSince($0) > Config.staleOnForeground }
                        ?? true
        backgroundedAt = nil

        if away > Config.staleOnForeground || docStale {
            Task { await refresh(isManual: false) }
        }
        realtime.start()
    }
}

// MARK: - 内部

private extension DealRepository {

    func applyDocument(_ doc: DealsDocument, isLive: Bool) {
        version = doc.version
        deals = doc.deals
            .filter { $0.validity().isActive }          // 过期自动下架
            .sorted { sortRule($0, $1) }
        if isLive {
            lastSyncAt = Date()
            source = .live
        }
        Task { await reminders.resyncNotifications(with: deals) }
    }

    /// 排序：先按紧急程度，再按是否重点，最后按品牌
    func sortRule(_ a: Deal, _ b: Deal) -> Bool {
        let va = a.validity().sortWeight, vb = b.validity().sortWeight
        if va != vb { return va < vb }
        if a.highlight != b.highlight { return a.highlight && !b.highlight }
        return a.brand < b.brand
    }
}
