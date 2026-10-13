//
//  Components.swift
//  MilkTeaRadar
//
//  列表页用到的子组件：骨架屏、今日必看、筛选条、卡片网格、空状态、页脚。
//

import SwiftUI

// MARK: - 骨架屏（首屏 / 刷新时占位，避免白屏）

struct SkeletonListView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ForEach(0..<6, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.systemGray5))
                        .frame(height: 118)
                        .shimmer()
                }
            }
            .padding(16)
        }
    }
}

/// 简易微光动画（无第三方依赖）
struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    gradient: Gradient(colors: [.clear, .white.opacity(0.55), .clear]),
                    startPoint: .init(x: phase - 0.3, y: 0.5),
                    endPoint: .init(x: phase + 0.3, y: 0.5)
                )
                .onAppear {
                    withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                        phase = 1.3
                    }
                }
            )
    }
}

extension View {
    func shimmer() -> some View { modifier(Shimmer()) }
}

// MARK: - 本地 AI 洞察区
//
// 这些结论全部由 LocalIntelligence 在设备本地生成，
// 不调用任何云端接口 —— 因此服务器关闭、断网时依然可用。

struct InsightSection: View {
    let insights: [Insight]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("🧠 本地智能")
                    .font(.title3.weight(.bold))
                Spacer()
                Text("设备端实时分析 · 无需联网")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(insights.enumerated()), id: \.offset) { _, ins in
                        InsightCard(insight: ins)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

struct InsightCard: View {
    let insight: Insight

    private var tint: Color {
        switch insight.kind {
        case .topPick:     return .orange
        case .endingSoon:  return .red
        case .startingNow: return .green
        case .weekend:     return .blue
        case .streak:      return .purple
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: insight.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                Spacer()
            }
            Text(insight.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Text(insight.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Spacer(minLength: 0)
        }
        .padding(13)
        .frame(width: 236, height: 132, alignment: .leading)
        .background(tint.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        )
    }
}

// MARK: - 今日必看

struct HeroSection: View {
    let deals: [Deal]
    let onTap: (Deal) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("🔥 今日必看").font(.title3.weight(.bold))
                Spacer()
                Text("按力度与普适性精选")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(deals) { deal in
                        HeroCard(deal: deal) { onTap(deal) }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

struct HeroCard: View {
    let deal: Deal
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("今日必看")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(BrandPalette.color(for: deal.brand))
                    .clipShape(Capsule())
                Spacer()
            }
            Text(deal.brand)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(BrandPalette.color(for: deal.brand))
            Text(deal.title).font(.subheadline.weight(.semibold)).lineLimit(2)
            Text(deal.discount).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            Spacer(minLength: 0)
            ValidityPill(validity: deal.validity())
        }
        .padding(13)
        .frame(width: 232, height: 168, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.07), radius: 8, x: 0, y: 3)
        .onTapGesture(perform: onTap)
    }
}

// MARK: - 筛选条

struct FilterChipsView: View {
    @Binding var status: StatusFilter
    @Binding var brand: String?
    @Binding var keyword: String
    let brands: [String]
    let countFor: (StatusFilter) -> Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(StatusFilter.allCases) { f in
                        Chip(
                            title: "\(f.title) \(countFor(f))",
                            isActive: status == f,
                            color: .brown
                        ) { status = f }
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Chip(title: "全部品牌",
                         isActive: brand == nil,
                         color: .brown) { brand = nil }
                    ForEach(brands, id: \.self) { b in
                        Chip(title: b,
                             isActive: brand == b,
                             color: BrandPalette.color(for: b)) { brand = b }
                    }
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索品牌 / 活动 / 渠道", text: $keyword)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

struct Chip: View {
    let title: String
    let isActive: Bool
    let color: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(title)
                .font(.footnote.weight(.medium))
                .foregroundStyle(isActive ? .white : .primary)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(isActive ? color : Color(.systemGray6))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 卡片网格

struct DealGridView: View {
    let deals: [Deal]
    let reminders: Set<String>
    let onSelect: (Deal) -> Void
    let onToggle: (Deal) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(deals) { deal in
                DealCard(
                    deal: deal,
                    reminded: reminders.contains(deal.id),
                    onToggleReminder: { onToggle(deal) },
                    onOpenDetail: { onSelect(deal) }
                )
            }
        }
    }
}

// MARK: - 空状态 / 错误态 / 页脚

struct EmptyStateView: View {
    let onReset: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("🧋").font(.system(size: 46))
            Text("当前筛选下没有进行中的优惠")
                .font(.subheadline).foregroundStyle(.secondary)
            Button("查看全部", action: onReset)
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }
}

struct ErrorStateView: View {
    let message: String
    let hint: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40)).foregroundStyle(.orange)
            Text(message).font(.headline)
            Text(hint).font(.footnote).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("重试", action: onRetry)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .padding(.horizontal, 24)
    }
}

struct FooterView: View {
    var body: some View {
        VStack(spacing: 4) {
            Text("数据来源见各优惠「来源」链接 · 每日 09:00 自动更新")
                .font(.caption2).foregroundStyle(.secondary)
            Text("优惠活动时效性强，请以各品牌官方小程序 / APP 实时页面为准")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 8)
    }
}
