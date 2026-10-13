//
//  DealRepository.swift
//  MilkTeaRadar
//
//  数据仓库：唯一的数据出口。
//
//  【核心可用性约束】
//  云端服务器随时可能不可用。因此数据获取走「四级降级链」，
//  智能处理走「纯本地引擎」，两者都不以云端在线为前提：
//
//    数据：主源 → 镜像 → 本地缓存 → 内置快照（永远有数据）
//    智能：LocalIntelligence 本地评估（永远可用）
//
//  由此保证：云端关闭时 App 依然能展示内容、依然能做实时排序与洞察。
//

import Foundation
import Combine

/// 数据来源（含多源链的各层级），用于 UI 顶部状态标识
enum DataSource: Equatable {
    case live                    // 主源，实时
    case mirror(host: String)    // 镜像源
    case cache(age: String)      // 本地缓存
    case bundled                 // 内置快照
    case offline                 // 完全无数据

    var label: String {
        switch self {
        case .live:                 return "实时数据"
        case .mirror(let h):        return "镜像 · \(h)"
        case .cache:                return "本地缓存"
        case .bundled:              return "内置数据"
        case .offline:              return "离线"
        }
    }

    /// 是否为网络实时来源
    var isLive: Bool {
        if case .live = self { return true }
        if case .mirror = self { return true }
        return false
    }

    /// 数据可能滞后（UI 应提示用户）
    var mayBeStale: Bool {
        switch self {
        case .cache, .bundled: return true
        default:               return false
        }
    }
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

    /// 本地 AI 生成的洞察（离线可用，随 deals 一起更新）
    @Published private(set) var insights: [Insight] = []
    /// 本地 AI 的评分结果（按综合分降序）
    @Published private(set) var scored: [DealScore] = []

    /// 当前正在尝试的数据源名称（多源链诊断用）
    @Published private(set) var attemptLog: String = ""

    let reminders = ReminderStore()
    let realtime = RealtimeClient()

    private let chain = DataSourceChain.shared
    private let brain = LocalIntelligence.shared

    private var backgroundedAt: Date?

    // MARK: 冷启动

    /// 应用启动入口。
    /// 顺序刻意设计为「零网络优先」：
    ///   ① 内置快照立即渲染（同步、零延迟、绝不白屏）
    ///   ② 本地缓存覆盖（比内置更新）
    ///   ③ 联网走多源链刷新
    func bootstrap() async {
        // ① 内置快照 —— 保证首帧必有内容，即使从未联网
        if let doc = chain.bundled {
            applyDocument(doc, source: .bundled)
        }

        // ② 本地缓存
        if let snap = await DealCache.shared.load() {
            if snap.document.version >= version {
                applyDocument(snap.document, source: .cache(age: snap.ageText))
            }
        }

        // ③ 多源联网刷新
        await refresh(isManual: false)

        // ④ 实时通道（配置了 SSE 才走长连接，否则内部自动轮询）
        realtime.onDeals = { [weak self] deals, version in
            Task { @MainActor in
                self?.applyDocument(
                    DealsDocument(app: nil,
                                  generatedAt: ISO8601DateFormatter().string(from: Date()),
                                  digestFile: nil,
                                  source: nil,
                                  version: version,
                                  deals: deals),
                    source: .live)
            }
        }
        realtime.start()
    }

    // MARK: 刷新（走多源链）

    func refresh(isManual: Bool) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        // 手动刷新时重置源健康度，立即重新尝试全部源
        if isManual {
            chain.resetHealth()
            attemptLog = ""
        }

        let outcome = await chain.fetch(allowNetwork: true) { [weak self] idx, name in
            Task { @MainActor in self?.attemptLog = "尝试第 \(idx) 个源：\(name)" }
        }

        guard let outcome else {
            lastError = .offline
            if deals.isEmpty { source = .offline }
            return
        }

        // 版本守卫：网络来源要求版本不低于本地；本地来源无条件接受（它就是兜底）
        if outcome.isLive && outcome.document.version < version {
            return
        }

        applyDocument(outcome.document, source: mappedSource(outcome.source))

        // 只有网络来源才回写缓存，避免把更旧的数据盖掉更新的缓存
        if outcome.isLive {
            await DealCache.shared.save(outcome.document)
            lastError = nil
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

    // MARK: 行为上报（喂给本地 AI 学习偏好）

    /// 用户查看详情 / 点提醒时调用，用于本地偏好学习（不联网）
    func noteInteraction(_ deal: Deal) {
        BehaviorStoreShared.shared.record(brand: deal.brand, channel: deal.channel)
        // 偏好变化后立即重算（本地计算，无需网络）
        rescore()
    }
}

// MARK: - 内部

private extension DealRepository {

    func mappedSource(_ s: DealSource) -> DataSource {
        switch s {
        case .primary:          return .live
        case .mirror(let host): return .mirror(host: host)
        case .cache:
            let age = lastSyncAt.map { $0.relativeText } ?? "未知"
            return .cache(age: age)
        case .bundled:          return .bundled
        case .none:             return .offline
        }
    }

    /// 应用数据文档：过滤 → 本地 AI 评分 → 排序 → 生成洞察
    func applyDocument(_ doc: DealsDocument, source newSource: DataSource) {
        version = max(version, doc.version)

        // 过期自动下架
        let active = doc.deals.filter { $0.validity().isActive }

        // 用本地 AI 引擎评分并排序（离线可用）
        let evaluated = brain.evaluate(active)
        scored = evaluated
        deals = evaluated.map { $0.deal }
        insights = brain.insights(for: active)

        // 记录来源与同步时间
        source = newSource
        if newSource.isLive {
            lastSyncAt = Date()
        }

        // 重建提醒排程（活动可能已下线或改期）
        Task { await reminders.resyncNotifications(with: deals) }
    }

    /// 仅重算评分（偏好变化时用，不改变数据本身）
    func rescore() {
        let evaluated = brain.evaluate(deals)
        scored = evaluated
        deals = evaluated.map { $0.deal }
    }
}

// MARK: - 供非 MainActor 上下文访问的共享行为存储

/// BehaviorStore 需要被 LocalIntelligence 与 Repository 共同访问。
/// LocalIntelligence 内部已持有实例，这里再暴露一个共享入口供上报使用。
final class BehaviorStoreShared {
    static let shared = BehaviorStore()
    private init() {}
}
