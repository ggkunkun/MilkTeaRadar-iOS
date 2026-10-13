//
//  DealListViewModel.swift
//  MilkTeaRadar
//
//  MVVM 中的 ViewModel：持有视图状态，调用 Repository，不直接触碰网络。
//  @MainActor 保证所有 UI 状态更新都在主线程。
//

import Foundation
import SwiftUI

/// 顶部状态筛选（与 Android 端 StatusFilter 一致）
enum StatusFilter: String, CaseIterable, Identifiable {
    case all, today, soon, longTerm, reminded
    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:      return "全部"
        case .today:    return "今日截止"
        case .soon:     return "即将截止"
        case .longTerm: return "长期"
        case .reminded: return "我的提醒"
        }
    }
}

@MainActor
final class DealListViewModel: ObservableObject {

    // MARK: 输入

    @Published var status: StatusFilter = .all
    @Published var brand: String? = nil
    @Published var keyword: String = ""

    // MARK: 输出

    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var recoveryHint: String?
    @Published private(set) var source: DataSource = .offline
    @Published private(set) var lastSyncText: String = "尚未同步"
    @Published private(set) var reminderSet: Set<String> = []
    @Published var selectedDeal: Deal? = nil

    /// 本地 AI 洞察（离线可用）
    @Published private(set) var insights: [Insight] = []
    /// 多源链当前尝试的源（诊断用）
    @Published private(set) var attemptLog: String = ""

    private let repo: DealRepository

    init(repo: DealRepository) {
        self.repo = repo
    }

    // MARK: 生命周期

    func onAppear() async {
        isLoading = repo.deals.isEmpty
        defer { isLoading = false }
        await repo.bootstrap()
        syncFromRepo()
    }

    /// 手动刷新（下拉刷新 / 顶部刷新按钮）
    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        await repo.refresh(isManual: true)
        syncFromRepo()
    }

    // MARK: 生命周期补偿

    func handleForeground() {
        repo.handleWillEnterForeground()
        syncFromRepo()
    }

    func handleBackground() {
        repo.handleDidEnterBackground()
    }

    // MARK: 交互

    func toggleReminder(_ deal: Deal) async {
        _ = await repo.reminders.toggle(deal)
        syncFromRepo()
    }

    func isReminded(_ deal: Deal) -> Bool {
        reminderSet.contains(deal.id)
    }

    func resetFilters() {
        status = .all
        brand = nil
        keyword = ""
    }

    // MARK: 派生数据

    /// 今日必看：优先取 highlight，不足 3 条用剩余补齐
    var highlights: [Deal] {
        let picked = repo.deals.filter { $0.highlight }
        if picked.count >= 3 { return Array(picked.prefix(3)) }
        let rest = repo.deals.filter { !$0.highlight }
        return Array((picked + rest).prefix(3))
    }

    /// 当前筛选后的列表
    var visibleDeals: [Deal] {
        repo.deals.filter { deal in
            if let b = brand, deal.brand != b { return false }
            if !keyword.isEmpty {
                let hay = (deal.brand + deal.title + deal.discount + deal.channel).lowercased()
                if !hay.contains(keyword.lowercased()) { return false }
            }
            switch status {
            case .all:      return true
            case .today:    return deal.validity() == .today
            case .soon:     if case .soon = deal.validity() { return true }; return false
            case .longTerm: return deal.validity() == .longTerm
            case .reminded: return reminderSet.contains(deal.id)
            }
        }
    }

    /// 状态筛选角标数字
    func count(for filter: StatusFilter) -> Int {
        switch filter {
        case .all:      return repo.deals.count
        case .today:    return repo.deals.filter { $0.validity() == .today }.count
        case .soon:     return repo.deals.filter { if case .soon = $0.validity() { return true }; return false }.count
        case .longTerm: return repo.deals.filter { $0.validity() == .longTerm }.count
        case .reminded: return repo.deals.filter { reminderSet.contains($0.id) }.count
        }
    }

    var brands: [String] {
        Array(Set(repo.deals.map { $0.brand })).sorted()
    }

    var reminders: ReminderStore { repo.reminders }

    // MARK: 内部

    private func syncFromRepo() {
        source = repo.source
        reminderSet = repo.reminders.ids
        insights = repo.insights
        attemptLog = repo.attemptLog
        if let t = repo.lastSyncAt {
            lastSyncText = t.relativeText
        }
        if let e = repo.lastError, repo.deals.isEmpty {
            // 只有「一条数据都没有」才算错误；有数据(哪怕是内置快照)就不该报错
            errorMessage = e.localizedDescription
            recoveryHint = e.recoveryHint
        } else {
            errorMessage = nil
            recoveryHint = nil
        }
    }
}

// MARK: - 小工具

extension Date {
    var relativeText: String {
        let s = max(0, Date().timeIntervalSince(self))
        if s < 60 { return "刚刚" }
        let m = Int(s / 60)
        if m < 60 { return "\(m) 分钟前" }
        let h = Int(m / 60)
        if h < 24 { return "\(h) 小时前" }
        return "\(Int(h / 24)) 天前"
    }
}
