//
//  Config.swift
//  MilkTeaRadar
//
//  集中管理所有环境相关配置。
//  真实值来自 Info.plist 的自定义键（可用 .xcconfig 按 Debug/Release 区分），
//  代码里只保留兜底默认值，避免把地址硬编码进业务逻辑。
//

import Foundation

enum Config {

    /// 从 Info.plist 读取字符串，空值回退到 fallback
    private static func value(_ key: String, fallback: String) -> String {
        if let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String,
           !raw.trimmingCharacters(in: .whitespaces).isEmpty {
            return raw
        }
        return fallback
    }

    // MARK: - 服务端
    //
    // 关键：必须是「公网可访问」的地址，否则离开局域网（用移动数据）就拉不到数据。
    // 这里默认指向已部署的 PWA 托管地址，它同时对外提供 data/deals.json。
    // 换成你自己的服务端时，改 Info.plist 的 API_BASE_URL 即可，无需动代码。

    /// 服务端基地址（不要以 / 结尾）
    static let apiBaseURL = value("API_BASE_URL",
                                  fallback: "https://milk-tea-radar.app.workbuddy.host")

    /// 数据文件路径（静态托管场景下直接取 JSON；有自建服务端时改为 /deals）
    static let dealsPath = value("DEALS_PATH", fallback: "/data/deals.json")

    /// SSE 长连接地址。留空则自动降级为轮询（静态托管无 SSE 端点）。
    static let realtimeURL = value("REALTIME_URL", fallback: "")

    // MARK: - 镜像源（云端主源不可用时的替补）
    //
    // 这些是「不同域名、不同 CDN、不同运营方」的副本，
    // 因此单点故障不会同时击穿。DataSourceChain 会依次尝试：
    //   主源 → 镜像 1 → 镜像 2 → ... → 本地缓存 → 内置快照
    //
    // 配置方式：在 Info.plist 里加 MIRROR_URLS（数组），或用逗号分隔的字符串。
    // 留空则只使用主源（仍会自动降级到本地缓存与内置快照）。
    static let mirrorURLs: [String] = {
        if let arr = Bundle.main.object(forInfoDictionaryKey: "MIRROR_URLS") as? [String],
           !arr.isEmpty {
            return arr
        }
        if let s = Bundle.main.object(forInfoDictionaryKey: "MIRROR_URLS") as? String {
            return s.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        return []
    }()

    // MARK: - 网络策略

    /// 单次请求超时（秒）——题目要求默认 8 秒
    static let requestTimeout: TimeInterval = 8

    /// 最多重试次数（总尝试次数 = 1 + maxRetries）
    static let maxRetries = 3

    /// 指数退避基数（秒）
    static let backoffBase: TimeInterval = 0.4

    /// 单次退避上限（秒）
    static let backoffMax: TimeInterval = 6

    // MARK: - 补偿刷新

    /// SSE 不可用时的轮询间隔（秒）
    static let pollInterval: TimeInterval = 30

    /// 心跳超时：多久没收到任何字节就判定连接已死（秒）
    static let heartbeatTimeout: TimeInterval = 60

    /// 后台停留超过该阈值，回前台时强制全量刷新（秒）
    static let staleOnForeground: TimeInterval = 60

    // MARK: - 本地缓存

    /// 缓存文件名（存于 Application Support）
    static let cacheFileName = "deals_cache.json"

    /// 缓存被视为「过期」的时长（秒），超时后回前台/重连时刷新
    static let cacheTTL: TimeInterval = 30 * 60
}
