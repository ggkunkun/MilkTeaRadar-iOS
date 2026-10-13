//
//  DealsDocument.swift
//  MilkTeaRadar
//
//  服务端返回的完整数据文档 + 增量合并逻辑（并发冲突处理的核心）。
//

import Foundation

struct DealsDocument: Codable {
    let app: String?
    let generatedAt: String?
    let digestFile: String?
    let source: String?
    /// 服务端单调递增版本号。客户端据此丢弃乱序 / 重复的事件。
    let version: Int
    let deals: [Deal]

    enum CodingKeys: String, CodingKey {
        case app, version, deals, source
        case generatedAt = "generated_at"
        case digestFile = "digest_file"
    }

    init(app: String?, generatedAt: String?, digestFile: String?, source: String?, version: Int, deals: [Deal]) {
        self.app = app
        self.generatedAt = generatedAt
        self.digestFile = digestFile
        self.source = source
        self.version = version
        self.deals = deals
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        app         = try c.decodeIfPresent(String.self, forKey: .app)
        generatedAt = try c.decodeIfPresent(String.self, forKey: .generatedAt)
        digestFile  = try c.decodeIfPresent(String.self, forKey: .digestFile)
        source      = try c.decodeIfPresent(String.self, forKey: .source)
        version     = (try? c.decode(Int.self, forKey: .version)) ?? 0
        deals       = (try? c.decode([Deal].self, forKey: .deals)) ?? []
    }
}

// MARK: - 合并

/// 合并结果：最终列表 + 是否真的发生了变化
struct MergeResult {
    let deals: [Deal]
    let version: Int
    let changed: Bool
}

enum DealMerger {

    /// 把远端增量合并进本地基线。
    ///
    /// 冲突处理策略：
    ///  1. 版本号守卫：remote.version <= local.version 视为陈旧事件，直接丢弃；
    ///  2. 条目级：以 deal.id 为主键，逐条比较 updated_at，保留较新的一方
    ///     （last-write-wins，配合服务端单调时间戳，避免旧数据覆盖新数据）；
    ///  3. 删除优先：payload.removed 中的 id 一律移除，即使本地版本更新
    ///     （活动下线属于服务端权威状态，客户端不应继续保留）；
    ///  4. 幂等：同一 version 重复投递不会产生副作用。
    static func merge(local: [Deal],
                      localVersion: Int,
                      incoming: [Deal],
                      removed: [String],
                      remoteVersion: Int) -> MergeResult {

        // 1) 版本号守卫
        guard remoteVersion > localVersion else {
            return MergeResult(deals: local, version: localVersion, changed: false)
        }

        var index: [String: Deal] = [:]
        for d in local { index[d.id] = d }

        var didChange = false

        // 2) 条目级更新（按 updated_at 比较）
        for d in incoming {
            if let existing = index[d.id] {
                if isNewer(d, than: existing) {
                    index[d.id] = d
                    didChange = true
                }
            } else {
                index[d.id] = d
                didChange = true
            }
        }

        // 3) 删除优先
        for id in removed where index[id] != nil {
            index.removeValue(forKey: id)
            didChange = true
        }

        return MergeResult(deals: Array(index.values),
                           version: remoteVersion,
                           changed: didChange)
    }

    private static func isNewer(_ a: Deal, than b: Deal) -> Bool {
        switch (a.updatedAtDate, b.updatedAtDate) {
        case let (da?, db?): return da > db
        case (_?, nil):      return true
        default:              return false
        }
    }
}
