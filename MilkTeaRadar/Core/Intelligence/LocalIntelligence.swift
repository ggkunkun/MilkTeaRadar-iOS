//
//  LocalIntelligence.swift
//  MilkTeaRadar
//
//  内置 AI 引擎 —— 完全离线运行的本地智能层。
//
//  【为什么需要它】
//  云端服务器随时可能不可用（宕机、限流、网络中断、成本削减而关停）。
//  如果"智能"依赖云端推理，服务一关 App 就退化成静态列表。
//  这个引擎把智能放到设备本地，因此：
//    · 云端关闭 → 依然能做实时排序、推荐、洞察、倒计时提醒
//    · 完全断网 → 依然能工作
//    · 零推理成本、零延迟、零隐私外泄
//
//  【它做什么】
//    1. 优惠力度量化   —— 把「买一送一 / 8 折 / 满 40 减 20 / 免单」折算成统一价值分
//    2. 紧迫度计算     —— 结合当前时刻算剩余时间与紧急程度
//    3. 个性化偏好学习 —— 本地记录用户行为，学习品牌/渠道偏好（数据不出设备）
//    4. 综合智能排序   —— 力度 × 紧迫 × 偏好 × 新鲜度
//    5. 机会识别       —— 今天新上线、即将开始、周末生效等
//    6. 自然语言洞察   —— 本地生成「本周最划算」这类结论，不调用任何 API
//

import Foundation

// MARK: - 价值评估结果

/// 一条优惠的本地评估结果
struct DealScore {
    let deal: Deal
    /// 优惠力度分（0~100），越高越划算
    let valueScore: Double
    /// 紧迫度分（0~100），越高越紧急
    let urgencyScore: Double
    /// 个人偏好分（0~100）
    let preferenceScore: Double
    /// 综合分（0~100）
    let totalScore: Double
    /// 折扣率（0~1），如 0.5 表示约五折
    let discountRate: Double
    /// 本地生成的短评
    let verdict: String
}

/// 本地洞察条目
struct Insight {
    enum Kind {
        case topPick        // 本期最值得
        case endingSoon     // 即将结束
        case startingNow    // 刚刚开始
        case weekend        // 周末生效
        case streak         // 惯常优惠
    }
    let kind: Kind
    let title: String
    let detail: String
    let icon: String
    let relatedDealIds: [String]
}

// MARK: - 引擎

/// 本地智能引擎（单例）
///
/// 设计原则：**纯函数式 + 无网络依赖**。
/// 所有方法只依赖传入的数据与本地行为记录，因此在飞行模式下行为完全一致。
final class LocalIntelligence {

    static let shared = LocalIntelligence()

    /// 偏好存储必须是全局同一实例，否则 Repository 的上报与这里的读取会落到两份存储
    private var behavior: BehaviorStore { BehaviorStoreShared.shared }

    private init() {}

    // MARK: 对外主入口

    /// 对一批优惠做完整评估（力度 + 紧迫 + 偏好），并按综合分排序。
    /// - Parameter now: 注入当前时间，便于测试与「时间旅行」预览
    func evaluate(_ deals: [Deal], now: Date = Date()) -> [DealScore] {
        deals
            .map { score(for: $0, now: now) }
            .sorted { $0.totalScore > $1.totalScore }
    }

    /// 生成本地洞察（不调用任何网络）
    func insights(for deals: [Deal], now: Date = Date()) -> [Insight] {
        var out: [Insight] = []
        let scores = evaluate(deals, now: now)

        // ① 本期最值得
        if let top = scores.first, top.totalScore >= 55 {
            let sameBrand = scores.filter { $0.deal.brand == top.deal.brand }.count
            out.append(Insight(
                kind: .topPick,
                title: "本期最值得：\(top.deal.brand)",
                detail: "\(top.deal.title) —— 约 \(pct(top.discountRate)) 折扣，\(top.verdict)" +
                        (sameBrand > 1 ? "；该品牌另有 \(sameBrand - 1) 项活动可叠加关注" : ""),
                icon: "crown.fill",
                relatedDealIds: [top.deal.id]
            ))
        }

        // ② 即将结束（今天 / 明天截止）
        let ending = deals.filter {
            guard let d = $0.daysLeft(now: now) else { return false }
            return d >= 0 && d <= 1
        }
        if !ending.isEmpty {
            out.append(Insight(
                kind: .endingSoon,
                title: "\(ending.count) 项活动即将结束",
                detail: ending.prefix(3).map { "\($0.brand)·\($0.title)" }.joined(separator: "；"),
                icon: "clock.badge.exclamationmark",
                relatedDealIds: ending.map { $0.id }
            ))
        }

        // ③ 刚刚开始（开始日期在最近 2 天内）
        let starting = deals.filter {
            guard let s = Deal.dayFormatter.date(from: $0.validFrom) else { return false }
            let delta = Calendar.current.dateComponents([.day],
                        from: Calendar.current.startOfDay(for: s),
                        to: Calendar.current.startOfDay(for: now)).day ?? 99
            return delta >= 0 && delta <= 2
        }
        if !starting.isEmpty {
            out.append(Insight(
                kind: .startingNow,
                title: "\(starting.count) 项活动新上线",
                detail: starting.prefix(3).map { "\($0.brand)·\($0.title)" }.joined(separator: "；"),
                icon: "sparkles",
                relatedDealIds: starting.map { $0.id }
            ))
        }

        // ④ 周末相关
        let weekendish = deals.filter {
            $0.note.contains("周末") || $0.note.contains("周六") ||
            $0.note.contains("周日") || $0.title.contains("周末")
        }
        if !weekendish.isEmpty {
            let isWeekendNow = isWeekend(now)
            out.append(Insight(
                kind: .weekend,
                title: isWeekendNow ? "周末优惠进行中" : "周末优惠可提前规划",
                detail: weekendish.prefix(3).map { "\($0.brand)·\($0.title)" }.joined(separator: "；"),
                icon: "calendar",
                relatedDealIds: weekendish.map { $0.id }
            ))
        }

        // ⑤ 长期稳定优惠（适合日常囤）
        let steady = deals.filter { $0.validUntil == "long_term" }
        if steady.count >= 3 {
            out.append(Insight(
                kind: .streak,
                title: "\(steady.count) 项长期有效，适合日常",
                detail: "这些不受截止时间限制，可作为常备选择",
                icon: "infinity",
                relatedDealIds: steady.map { $0.id }
            ))
        }

        return out
    }

    /// 单条优惠的完整评分
    func score(for deal: Deal, now: Date = Date()) -> DealScore {
        let value = valueScore(for: deal)
        let urgency = urgencyScore(for: deal, now: now)
        let pref = preferenceScore(for: deal)
        let freshness = freshnessBonus(for: deal, now: now)

        // 加权：力度是主因，紧迫与偏好次之，新鲜度做微调
        let total = min(100, value * 0.52 + urgency * 0.24 + pref * 0.18 + freshness * 0.06)

        return DealScore(
            deal: deal,
            valueScore: value,
            urgencyScore: urgency,
            preferenceScore: pref,
            totalScore: total,
            discountRate: estimateDiscountRate(deal),
            verdict: verdictText(value: value, urgency: urgency, deal: deal, now: now)
        )
    }

    // MARK: ① 力度量化

    /// 把优惠文案折算成折扣率（0~1，越小越便宜）。
    ///
    /// 规则来自对优惠文案的结构化解析，纯本地字符串处理：
    ///   · 免单 / 0 元        → 1.00
    ///   · 买一送一 / 第二杯半价 → 0.50 / 0.75
    ///   · N 折               → (10-N)/10
    ///   · 满 X 减 Y          → Y/X（按凑满最优估算）
    ///   · 立减 / 直降 N 元    → 按客单价 18 元估算
    ///   · 1 分购 / 特价 N 元  → 按客单价估算
    func estimateDiscountRate(_ deal: Deal) -> Double {
        let text = deal.title + " " + deal.discount

        // 免单 / 0 元
        if text.contains("免单") || text.contains("0 元") || text.contains("0元") {
            return 1.0
        }
        // 1 分购
        if text.contains("1 分") || text.contains("一分") {
            return 0.95
        }
        // 买一送一
        if text.contains("买一送一") || text.contains("买 1 送 1") {
            return 0.50
        }
        // 第二杯半价
        if text.contains("第二杯半价") {
            return 0.75
        }
        // N 折（含小数，如 8.5 折）
        if let r = firstMatch(in: text, pattern: #"([0-9]+(?:\.[0-9]+)?)\s*折"#).flatMap(Double.init) {
            return max(0.05, min(0.95, (10 - r) / 10))
        }
        // 满 X 减 Y / 满 X 立减 Y
        if let m = firstMatch2(in: text, pattern: #"满\s*([0-9]+)\s*减\s*([0-9]+)"#),
           let x = Double(m.0), let y = Double(m.1), x > 0 {
            return max(0.05, min(0.95, y / x))
        }
        // 直降 / 立减 N 元（按客单价 18 元估）
        if let r = firstMatch(in: text, pattern: #"(?:直降|立减|减)\s*([0-9]+(?:\.[0-9]+)?)\s*元"#)
                    .flatMap(Double.init) {
            return max(0.05, min(0.95, r / 18.0))
        }
        // 特价 N 元
        if let r = firstMatch(in: text, pattern: #"特价\s*([0-9]+(?:\.[0-9]+)?)\s*元"#)
                    .flatMap(Double.init) {
            return max(0.05, min(0.95, 1 - r / 18.0))
        }
        // 低至 N 元
        if let r = firstMatch(in: text, pattern: #"低至\s*([0-9]+(?:\.[0-9]+)?)\s*元"#)
                    .flatMap(Double.init) {
            return max(0.05, min(0.95, 1 - r / 18.0))
        }
        // 半价
        if text.contains("半价") {
            return 0.50
        }
        // 兜底：重点活动给一个中性偏上的估值，普通给中性
        return deal.highlight ? 0.35 : 0.20
    }

    private func valueScore(for deal: Deal) -> Double {
        estimateDiscountRate(deal) * 100
    }

    // MARK: ② 紧迫度

    private func urgencyScore(for deal: Deal, now: Date) -> Double {
        guard let days = deal.daysLeft(now: now) else {
            return 25   // 长期活动：低紧迫但不为零
        }
        if days < 0 { return 0 }
        switch days {
        case 0: return 100      // 今天截止
        case 1: return 92
        case 2: return 80
        case 3: return 68
        case 4...7: return 52
        case 8...14: return 36
        default: return 22
        }
    }

    // MARK: ③ 偏好学习（本地）

    private func preferenceScore(for deal: Deal) -> Double {
        let b = behavior.brandWeight(deal.brand)      // 0~1
        let c = behavior.channelWeight(deal.channel)  // 0~1
        // 无历史时给中性 50，避免冷启动把所有条目压低
        let raw = (b * 0.7 + c * 0.3) * 100
        return behavior.hasHistory ? raw : 50
    }

    // MARK: 新鲜度

    private func freshnessBonus(for deal: Deal, now: Date) -> Double {
        guard let updated = deal.updatedAtDate else { return 50 }
        let hours = now.timeIntervalSince(updated) / 3600
        if hours < 24 { return 100 }
        if hours < 24 * 3 { return 80 }
        if hours < 24 * 7 { return 60 }
        return 40
    }

    // MARK: 短评生成（本地模板，非云端推理）

    private func verdictText(value: Double, urgency: Double, deal: Deal, now: Date) -> String {
        var parts: [String] = []

        if value >= 90 { parts.append("几乎免单级") }
        else if value >= 65 { parts.append("力度很猛") }
        else if value >= 45 { parts.append("力度不错") }
        else if value >= 28 { parts.append("常规优惠") }
        else { parts.append("力度一般") }

        if urgency >= 90 { parts.append("今天就是最后一天") }
        else if urgency >= 75 { parts.append("这两天要抓紧") }
        else if urgency <= 25 && deal.validUntil == "long_term" { parts.append("长期有效不急") }

        if deal.highlight { parts.append("已被标为重点") }

        return parts.joined(separator: "，")
    }

    // MARK: 工具

    private func isWeekend(_ date: Date) -> Bool {
        let wd = Calendar.current.component(.weekday, from: date)
        return wd == 1 || wd == 7   // 周日 / 周六
    }

    private func pct(_ rate: Double) -> String {
        let off = Int((rate * 100).rounded())
        return "\(off)% off"
    }

    private func firstMatch(in text: String, pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1 else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    private func firstMatch2(in text: String, pattern: String) -> (String, String)? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 2 else { return nil }
        return (ns.substring(with: m.range(at: 1)), ns.substring(with: m.range(at: 2)))
    }
}

// MARK: - 行为记录（本地学习，数据不出设备）

/// 记录用户交互，用于本地偏好学习。
/// 全部存在 UserDefaults，不上传、不联网 —— 这也是「云端关闭仍可用」的一部分。
final class BehaviorStore {

    private let key = "mtr.behavior.v1"

    struct Record: Codable {
        var brandCounts: [String: Int] = [:]
        var channelCounts: [String: Int] = [:]
        var totalEvents: Int = 0
    }

    private var rec: Record

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(Record.self, from: data) {
            rec = decoded
        } else {
            rec = Record()
        }
    }

    /// 是否已有足够历史（冷启动判定）
    var hasHistory: Bool { rec.totalEvents >= 5 }

    /// 记录一次交互，如 .tap / .remind / .detail
    func record(brand: String, channel: String) {
        rec.brandCounts[brand, default: 0] += 1
        rec.channelCounts[channel, default: 0] += 1
        rec.totalEvents += 1
        persist()
    }

    /// 品牌权重 0~1（归一化到出现最多的品牌）
    func brandWeight(_ brand: String) -> Double {
        guard let maxV = rec.brandCounts.values.max(), maxV > 0 else { return 0 }
        return Double(rec.brandCounts[brand] ?? 0) / Double(maxV)
    }

    func channelWeight(_ channel: String) -> Double {
        guard let maxV = rec.channelCounts.values.max(), maxV > 0 else { return 0 }
        return Double(rec.channelCounts[channel] ?? 0) / Double(maxV)
    }

    func reset() {
        rec = Record()
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(rec) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
