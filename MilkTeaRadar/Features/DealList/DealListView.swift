//
//  DealListView.swift
//  MilkTeaRadar
//
//  列表页：顶部状态条 + 今日必看 + 筛选 + 卡片流。
//  HIG 要点：NavigationStack 大标题、列表行分隔、下拉刷新（Refreshable）、
//  空状态与错误状态均给出明确文案与行动按钮。
//

import SwiftUI

struct DealListView: View {

    @StateObject private var viewModel: DealListViewModel

    @MainActor init(repository: DealRepository = DealRepository()) {
        _viewModel = StateObject(wrappedValue: DealListViewModel(repo: repository))
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.visibleDeals.isEmpty {
                    SkeletonListView()
                } else {
                    mainContent
                }
            }
            .navigationTitle("奶茶优惠雷达")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await viewModel.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isRefreshing)
                }
            }
        }
        .task { await viewModel.onAppear() }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.willEnterForegroundNotification)) { _ in
            viewModel.handleForeground()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.didEnterBackgroundNotification)) { _ in
            viewModel.handleBackground()
        }
    }

    // MARK: 主体

    private var mainContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {

                StatusBanner(
                    source: viewModel.source,
                    lastSyncText: viewModel.lastSyncText,
                    errorMessage: viewModel.errorMessage,
                    recoveryHint: viewModel.recoveryHint
                ) {
                    Task { await viewModel.refresh() }
                }

                if viewModel.visibleDeals.isEmpty {
                    EmptyStateView {
                        viewModel.resetFilters()
                    }
                } else {
                    // 本地 AI 洞察（离线可用，不依赖云端推理）
                    if !viewModel.insights.isEmpty {
                        InsightSection(insights: viewModel.insights)
                    }
                    HeroSection(deals: viewModel.highlights) { deal in
                        viewModel.selectedDeal = deal
                    }
                    FilterChipsView(
                        status: $viewModel.status,
                        brand: $viewModel.brand,
                        keyword: $viewModel.keyword,
                        brands: viewModel.brands,
                        countFor: { viewModel.count(for: $0) }
                    )
                    DealGridView(deals: viewModel.visibleDeals,
                                 reminders: viewModel.reminderSet) { deal in
                        viewModel.selectedDeal = deal
                    } onToggle: { deal in
                        Task { await viewModel.toggleReminder(deal) }
                    }
                }

                FooterView()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .refreshable {                     // HIG 下拉刷新（同时保留自动刷新）
            await viewModel.refresh()
        }
        .sheet(item: $viewModel.selectedDeal) { deal in
            DealDetailView(deal: deal, reminders: viewModel.reminders)
        }
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - 状态条

struct StatusBanner: View {
    let source: DataSource
    let lastSyncText: String
    let errorMessage: String?
    let recoveryHint: String?
    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(tint)
                .font(.system(size: 15, weight: .semibold))

            VStack(alignment: .leading, spacing: 3) {
                Text(titleText).font(.footnote.weight(.semibold))
                Text(subText).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("重试", action: onRetry)
                .font(.footnote.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(tint.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var iconName: String {
        if errorMessage != nil { return "exclamationmark.triangle.fill" }
        switch source {
        case .live:              return "checkmark.circle.fill"
        case .mirror:            return "arrow.triangle.2.circlepath.circle.fill"
        case .cache:             return "clock.fill"
        case .bundled:           return "archivebox.fill"
        case .offline:           return "wifi.slash"
        }
    }

    private var tint: Color {
        if errorMessage != nil { return .orange }
        switch source {
        case .live:              return .green
        case .mirror:            return .teal
        case .cache:             return .blue
        case .bundled:           return .indigo
        case .offline:           return .secondary
        }
    }

    private var titleText: String {
        if let e = errorMessage { return e }
        switch source {
        case .live:              return "实时数据"
        case .mirror(let h):     return "镜像源 · \(h)"
        case .cache(let age):    return "本地缓存 · \(age)"
        case .bundled:           return "内置快照"
        case .offline:           return "离线模式"
        }
    }

    private var subText: String {
        if let h = recoveryHint { return h }
        return "数据更新至 \(lastSyncText)"
    }
}
