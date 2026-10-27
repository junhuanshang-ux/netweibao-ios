import SwiftUI

struct ToolPlaceholderView: View {
    let tool: ToolItem

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    overview
                    capabilityCard
                    boundaryCard

                    InlineInfoNote(
                        text: "当前版本优先完成 Ping，其余模块会按顺序实现。受 iOS 系统权限限制，部分能力会以“可用近似指标”呈现，并在界面中明确标注。"
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 30)
            }
        }
        .navigationTitle(tool.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(tool.tint.opacity(0.13))
                Image(systemName: tool.icon)
                    .font(.system(size: 27, weight: .semibold))
                    .foregroundStyle(tool.tint)
            }
            .frame(width: 62, height: 62)

            VStack(alignment: .leading, spacing: 5) {
                Text(tool.title)
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)

                StatusBadge(text: "按顺序开发中", color: AppTheme.amber)
            }

            Spacer()
        }
        .padding(.top, 4)
    }

    private var overview: some View {
        Text(tool.details)
            .font(.system(size: 14, weight: .regular, design: .rounded))
            .foregroundStyle(AppTheme.textSecondary)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var capabilityCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(title: "计划能力")

                ForEach(tool.capabilities, id: \.self) { capability in
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(tool.tint)
                            .padding(.top, 1)

                        Text(capability)
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var boundaryCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.amber)
                    SectionLabel(title: "技术边界")
                }

                Text(tool.feasibility)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
