//
//  DealDetailView.swift
//  MilkTeaRadar
//
//  详情页：完整活动信息 + 规则说明 + 来源链接 + 提醒开关。
//  HIG：NavigationStack + 分组列表（InsetGrouped）+ 明确的行动按钮。
//

import SwiftUI

struct DealDetailView: View {

    let deal: Deal
    @ObservedObject var reminders: ReminderStore
    @Environment(\.dismiss) private var dismiss

    private var brandColor: Color { BrandPalette.color(for: deal.brand) }
    private var isOn: Bool { reminders.isOn(deal.id) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // 头部卡片：品牌 + 标题 + 力度
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 7) {
                            Circle().fill(brandColor).frame(width: 10, height: 10)
                            Text(deal.brand)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(brandColor)
                            Spacer()
                            ValidityPill(validity: deal.validity())
                        }
                        Text(deal.title)
                            .font(.title3.weight(.bold))
                        Text(deal.discount)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(15)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    // 信息分组
                    GroupBox("活动信息") {
                        InfoRow(label: "优惠渠道", value: deal.channel)
                        Divider()
                        InfoRow(label: "开始日期", value: deal.validFrom)
                        Divider()
                        InfoRow(label: "结束日期",
                                value: deal.validUntil == "long_term" ? "长期有效" : deal.validUntil)
                        if let u = deal.updatedAt, !u.isEmpty {
                            Divider()
                            InfoRow(label: "数据更新时间", value: String(u.prefix(16)))
                        }
                    }

                    if !deal.note.isEmpty {
                        GroupBox("规则与限制") {
                            Text(deal.note)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    // 提醒开关
                    Toggle(isOn: Binding(
                        get: { isOn },
                        set: { _ in Task { await reminders.toggle(deal) } }
                    )) {
                        HStack(spacing: 9) {
                            Image(systemName: isOn ? "bell.fill" : "bell")
                                .foregroundStyle(isOn ? .orange : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("到期提醒").font(.subheadline.weight(.medium))
                                Text(isOn ? "截止当天 09:00 通知你" : "开启后在活动截止当天提醒")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 15)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    // 来源
                    if let url = URL(string: deal.source), !deal.source.isEmpty {
                        Link(destination: url) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("查看来源")
                                        .font(.subheadline.weight(.semibold))
                                    Text(deal.sourceName.isEmpty ? deal.source : deal.sourceName)
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                            }
                            .padding(15)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }

                    Text("优惠活动时效性强，请以各品牌官方小程序 / APP 实时页面为准")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 4)
                }
                .padding(16)
            }
            .navigationTitle(deal.brand)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 子组件

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.trailing)
        }
    }
}
