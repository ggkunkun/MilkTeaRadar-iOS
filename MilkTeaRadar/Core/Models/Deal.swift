//
//  Deal.swift
//  MilkTeaRadar
//
//  领域模型 + 有效期计算。字段与 Android 端 Deal.kt 一一对应。
//

import Foundation

struct Deal: Identifiable, Codable, Hashable {
    let id: String
    let brand: String
    let title: String
    let discount: String
    let validFrom: String
    /// "YYYY-MM-DD" 或 "long_term"
    let validUntil: String
    let channel: String
    let source: String
    let sourceName: String
    let note: String
    let highlight: Bool
    /// 服务端最后更新时间（ISO8601），用于并发冲突判定
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, brand, title, discount, channel, source, note, highlight
        case validFrom = "valid_from"
        case validUntil = "valid_until"
        case sourceName = "source_name"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = try c.decode(String.self, forKey: .id)
        brand       = try c.decode(String.self, forKey: .brand)
        title       = try c.decode(String.self, forKey: .title)
        discount    = try c.decode(String.self, forKey: .discount)
        validFrom   = try c.decode(String.self, forKey: .validFrom)
        validUntil  = try c.decode(String.self, forKey: .validUntil)
        channel     = try c.decode(String.self, forKey: .channel)
        source      = try c.decode(String.self, forKey: .source)
        sourceName  = try c.decodeIfPresent(String.self, forKey: .sourceName) ?? ""
        note        = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        highlight   = try c.decodeIfPresent(Bool.self, forKey: .highlight) ?? false
        updatedAt   = try c.decodeIfPresent(String.self, forKey: .updatedAt)
    }
}

// MARK: - 有效期

enum DealValidity {
    case expired
    case today
    case soon(days: Int)
    case later(end: Date)
    case longTerm

    var label: String {
        switch self {
        case .expired:       return "已过期"
        case .today:         return "今天截止"
        case .soon(let d):   return "剩 \(d) 天"
        case .later(let e):  return "有效期至 \(e.monthDayText)"
        case .longTerm:      return "长期有效"
        }
    }

    var isActive: Bool {
        if case .expired = self { return false }
        return true
    }

    /// 紧急程度排序权重：越紧急越小
    var sortWeight: Int {
        switch self {
        case .today:         return 0
        case .soon(let d):   return 1 + (3 - d)
        case .later:         return 10
        case .longTerm:      return 20
        case .expired:       return 100
        }
    }
}

extension Deal {
    /// 距离截止还剩几天；long_term 返回 nil
    func daysLeft(now: Date = Date()) -> Int? {
        guard validUntil != "long_term" else { return nil }
        guard let end = Deal.dayFormatter.date(from: validUntil) else { return nil }
        let a = Calendar.current.startOfDay(for: now)
        let b = Calendar.current.startOfDay(for: end)
        return Calendar.current.dateComponents([.day], from: a, to: b).day
    }

    func validity(now: Date = Date()) -> DealValidity {
        guard let n = daysLeft(now: now) else { return .longTerm }
        if n < 0  { return .expired }
        if n == 0 { return .today }
        if n <= 3 { return .soon(days: n) }
        guard let end = Deal.dayFormatter.date(from: validUntil) else { return .longTerm }
        return .later(end: end)
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        return f
    }()

    static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    var updatedAtDate: Date? {
        guard let s = updatedAt else { return nil }
        return Deal.isoFormatter.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}

extension Date {
    var monthDayText: String {
        let c = Calendar.current
        return "\(c.component(.month, from: self))月\(c.component(.day, from: self))日"
    }
}
