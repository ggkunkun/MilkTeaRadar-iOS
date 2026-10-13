//
//  DataSourceChain.swift
//  MilkTeaRadar
//
//  多源数据链 —— 「云端服务器关闭也能更新」的核心保障。
//
//  【问题】
//  单数据源的应用，一旦服务端下线（宕机 / 限流 / 停止运营 / 域名过期），
//  就彻底失去更新能力，只能靠越来越旧的本地缓存。
//
//  【方案】四级降级链，逐级尝试，任何一级成功即返回：
//
//      L1 主源        自建 / 托管主域名
//      L2 镜像源      CDN（jsDelivr / GitHub Raw 等多域名）
//      L3 本地缓存    上次成功拉取后持久化的 JSON
//      L4 内置快照    随 App 打包，永久可用，零网络依赖
//
//  L1/L2 是不同域名、不同 CDN、不同运营方 —— 单点故障不会同时击穿。
//  L3/L4 完全不依赖网络。因此：
//    · 主源挂了 → L2 顶上
//    · 全部网络源都挂了 → L3 继续服务
//    · 首次安装且无网 → L4 立即有数据，App 不会白屏
//
//  每个源都会被记录「健康度」，连续失败的源会被临时降级，
//  避免每次刷新都去等一个已经死掉的域名（节省 8 秒超时 × N 次）。
//

import Foundation

// MARK: - 数据来源与结果

/// 一次取数的来源
enum DealSource: Equatable {
    case primary          // L1 主源
    case mirror(String)   // L2 镜像源
    case cache            // L3 本地缓存
    case bundled          // L4 内置快照
    case none

    var label: String {
        switch self {
        case .primary:          return "实时数据"
        case .mirror(let host): return "镜像源 · \(host)"
        case .cache:            return "本地缓存"
        case .bundled:          return "内置数据"
        case .none:             return "无数据"
        }
    }

    /// 是否为「网络实时」来源
    var isLive: Bool {
        switch self {
        case .primary, .mirror: return true
        default:                return false
        }
    }

    /// 数据是否可能滞后（用于 UI 提示）
    var mayBeStale: Bool {
        switch self {
        case .cache, .bundled: return true
        default:               return false
        }
    }
}

/// 取数结果
struct FetchOutcome {
    let document: DealsDocument
    let source: DealSource
    /// 该结果是否来自网络
    var isLive: Bool { source.isLive }
}

// MARK: - 源健康度

/// 记录每个源的成功/失败，用于动态排序
private struct SourceHealth {
    var consecutiveFailures = 0
    var lastSuccess: Date?
    var lastFailure: Date?

    /// 是否应被临时跳过
    func shouldSkip(now: Date) -> Bool {
        guard consecutiveFailures >= 2 else { return false }
        // 失败越多，冷却越久（最多 10 分钟）
        guard let lastFail = lastFailure else { return false }
        let cooldown = min(600, 30.0 * pow(2.0, Double(consecutiveFailures - 2)))
        return now.timeIntervalSince(lastFail) < cooldown
    }
}

// MARK: - 数据源链

/// 多源数据链：按优先级尝试，逐级降级
final class DataSourceChain {

    static let shared = DataSourceChain()

    /// 内置快照（懒加载，只读一次）
    private lazy var bundledDocument: DealsDocument? = {
        Bundle.main.url(forResource: "BundledDeals", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(DealsDocument.self, from: $0) }
    }()

    /// 源健康度表
    private var health: [String: SourceHealth] = [:]
    private let healthLock = NSLock()

    private init() {}

    // MARK: 内置快照

    /// 立即拿到内置数据（同步、零网络）—— 用于首屏，保证绝不空白
    var bundled: DealsDocument? { bundledDocument }

    // MARK: 主入口

    /// 依次尝试所有源，返回第一个成功的结果。
    ///
    /// - Parameters:
    ///   - allowNetwork: 是否允许走网络源（如系统报告无网络可传 false，直接落到本地）
    ///   - onAttempt: 每次尝试前回调，便于 UI 展示「正在尝试第 N 个源」
    /// - Returns: 取数结果；理论上总会返回（最低兜底为内置快照），
    ///            仅当连内置快照都缺失时才返回 nil
    func fetch(allowNetwork: Bool = true,
               onAttempt: ((Int, String) -> Void)? = nil) async -> FetchOutcome? {

        let now = Date()
        var attemptIndex = 0

        // ---------- L1 / L2：网络源 ----------
        if allowNetwork {
            for candidate in networkSources() {
                // 跳过近期连续失败的源
                if isSkipped(candidate.url.absoluteString, now: now) {
                    continue
                }
                attemptIndex += 1
                onAttempt?(attemptIndex, candidate.name)

                do {
                    let doc = try await APIClient.shared.fetchDeals(from: candidate.url)
                    markSuccess(candidate.url.absoluteString)
                    return FetchOutcome(document: doc, source: candidate.source)
                } catch {
                    markFailure(candidate.url.absoluteString)
                    continue   // 试下一个源
                }
            }
        }

        // ---------- L3：本地缓存 ----------
        if let snap = await DealCache.shared.load() {
            return FetchOutcome(document: snap.document, source: .cache)
        }

        // ---------- L4：内置快照 ----------
        if let doc = bundledDocument {
            return FetchOutcome(document: doc, source: .bundled)
        }

        return nil
    }

    // MARK: 源列表

    struct SourceCandidate {
        let name: String
        let url: URL
        let source: DealSource
    }

    /// 构建候选源列表：主源优先，其后是配置的镜像，最后是按内置规则推导的镜像
    private func networkSources() -> [SourceCandidate] {
        var out: [SourceCandidate] = []

        // L1 主源
        if let u = URL(string: Config.apiBaseURL + Config.dealsPath) {
            out.append(SourceCandidate(name: "主源", url: u, source: .primary))
        }

        // L2 显式配置的镜像
        for (idx, raw) in Config.mirrorURLs.enumerated() {
            guard let u = URL(string: raw) else { continue }
            out.append(SourceCandidate(
                name: "镜像\(idx + 1)",
                url: u,
                source: .mirror(u.host ?? "mirror")
            ))
        }

        // 去重（避免同一 URL 重复尝试）
        var seen = Set<String>()
        return out.filter { c in
            let k = c.url.absoluteString
            if seen.contains(k) { return false }
            seen.insert(k)
            return true
        }
    }

    // MARK: 健康度

    private func isSkipped(_ key: String, now: Date) -> Bool {
        healthLock.lock(); defer { healthLock.unlock() }
        return health[key]?.shouldSkip(now: now) ?? false
    }

    private func markSuccess(_ key: String) {
        healthLock.lock(); defer { healthLock.unlock() }
        var h = health[key] ?? SourceHealth()
        h.consecutiveFailures = 0
        h.lastSuccess = Date()
        health[key] = h
    }

    private func markFailure(_ key: String) {
        healthLock.lock(); defer { healthLock.unlock() }
        var h = health[key] ?? SourceHealth()
        h.consecutiveFailures += 1
        h.lastFailure = Date()
        health[key] = h
    }

    /// 供调试 / 设置页展示：各源当前状态
    func healthSnapshot() -> [(String, Int, Date?)] {
        healthLock.lock(); defer { healthLock.unlock() }
        return health.map { ($0.key, $0.value.consecutiveFailures, $0.value.lastSuccess) }
    }

    /// 手动重置健康度（用户点「重试」时调用，立即重新尝试所有源）
    func resetHealth() {
        healthLock.lock(); defer { healthLock.unlock() }
        health.removeAll()
    }
}
