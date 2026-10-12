//
//  DealCard.swift
//  MilkTeaRadar
//
//  优惠卡片组件。遵循 HIG：圆角卡片、足够点击区（≥44pt）、
//  强调色用于行动点、辅助信息用次级字色。
//

import SwiftUI

struct DealCard: View {
    let deal: Deal
    let reminded: Bool
    let onToggleReminder: () -> Void
    let onOpenDetail: () -> Void

    private var brandColor: Color {
        BrandPalette.color(for: deal.brand)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 头部：品牌 + 有效期徽章
            HStack(alignment: .center, spacing: 8) {
                Circle()
                    .fill(brandColor)
                    .frame(width: 10, height: 10)
                Text(deal.brand)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(brandColor)
                Spacer(minLength: 4)
                ValidityPill(validity: deal.validity())
            }

            // 标题与力度
            Text(deal.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)
            Text(deal.discount)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            if !deal.note.isEmpty {
                Text(deal.note)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }

            Divider().padding(.vertical, 2)

            // 底部：渠道 + 来源 + 提醒
            HStack(spacing: 10) {
                ChannelTag(text: deal.channel)
                if !deal.source.isEmpty {
                    Link("来源 · \(deal.sourceName.isEmpty ? "查看" : deal.sourceName)",
                         destination: URL(string: deal.source)!)
                        .font(.footnote)
                }
                Spacer(minLength: 0)
                Button(action: onToggleReminder) {
                    Image(systemName: reminded ? "bell.fill" : "bell")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(reminded ? .orange : .secondary)
                        .frame(width: 44, height: 44)      // HIG 最小点击区
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(reminded ? "取消提醒" : "提醒我")
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpenDetail)
    }
}

// MARK: - 子组件

struct ValidityPill: View {
    let validity: DealValidity

    var body: some View {
        Text(validity.label)
            .font(.caption.weight(.medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(background)
            .clipShape(Capsule())
    }

    private var foreground: Color {
        switch validity {
        case .today, .soon:  return .red
        case .expired:       return .secondary
        case .later:         return .primary
        case .longTerm:      return .green
        }
    }

    private var background: Color {
        switch validity {
        case .today, .soon:  return .red.opacity(0.12)
        case .expired:       return .gray.opacity(0.12)
        case .later:         return .gray.opacity(0.10)
        case .longTerm:      return .green.opacity(0.12)
        }
    }
}

struct ChannelTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(.systemGray6))
            .clipShape(Capsule())
    }
}

// MARK: - 品牌色板

enum BrandPalette {
    static let map: [String: UInt32] = [
        "喜茶": 0x3d9a50, "奈雪的茶": 0xc2185b, "古茗": 0x4a90b8,
        "蜜雪冰城": 0xd32f2f, "茶百道": 0x1e88e5, "霸王茶姬": 0x6d4c41,
        "瑞幸咖啡": 0x0093ee, "CoCo都可": 0xf57c00, "一点点": 0x795548,
        "书亦烧仙草": 0x388e3c, "益禾堂": 0x7cb342, "甜啦啦": 0xfb8c00,
    ]

    static func color(for brand: String) -> Color {
        guard let hex = map[brand] else { return Color(red: 0.65, green: 0.40, blue: 0.25) }
        return Color(hex: hex)
    }
}

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
