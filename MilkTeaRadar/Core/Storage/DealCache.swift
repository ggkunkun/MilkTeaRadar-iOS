//
//  DealCache.swift
//  MilkTeaRadar
//
//  列表数据的本地缓存（JSON 文件），用于冷启动秒开与离线兜底。
//  使用 actor 保证并发读写安全。
//

import Foundation

struct CachedSnapshot: Codable {
    let document: DealsDocument
    let savedAt: Date

    /// 缓存是否已过期（超过 TTL 视为陈旧，需要刷新）
    var isStale: Bool {
        Date().timeIntervalSince(savedAt) > Config.cacheTTL
    }

    var ageText: String {
        let s = max(0, Date().timeIntervalSince(savedAt))
        if s < 60 { return "刚刚" }
        let m = Int(s / 60)
        if m < 60 { return "\(m) 分钟前" }
        let h = Int(m / 60)
        if h < 24 { return "\(h) 小时前" }
        return "\(Int(h / 24)) 天前"
    }
}

actor DealCache {

    static let shared = DealCache()

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                           in: .userDomainMask).first!
        let folder = dir.appendingPathComponent("MilkTeaRadar", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder,
                                                 withIntermediateDirectories: true)
        self.fileURL = folder.appendingPathComponent(Config.cacheFileName)
    }

    func save(_ document: DealsDocument) {
        let snap = CachedSnapshot(document: document, savedAt: Date())
        do {
            let data = try encoder.encode(snap)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[cache] 写入失败: \(error)")
        }
    }

    func load() -> CachedSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? decoder.decode(CachedSnapshot.self, from: data)
    }

    /// 冷启动或长时间后台后，缓存是否不足以直接展示
    func isCacheUsable() -> Bool {
        load() != nil
    }
}
