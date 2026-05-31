/* (c) Copyright XiatStudio 2026~2026 */
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var vm: DashboardViewModel
    @Environment(\.colorScheme) private var colorScheme

    private var cardBackground: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color(.systemBackground)
    }

    var body: some View {
        if vm.isConfigured {
            configuredView
        } else {
            emptyState
        }
    }

    @ViewBuilder
    private var configuredView: some View {
        ScrollView {
            VStack(spacing: 24) {
                todayCard
                monthCard
                paydayCard
                Spacer(minLength: 32)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .onAppear { vm.refresh() }
    }

    // MARK: - Today Card

    private var todayCard: some View {
        VStack(spacing: 12) {
            statusBadge
            earningsCounter
            progressSection
        }
        .padding(24)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(.separator, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(vm.statusColor)
                .frame(width: 8, height: 8)
                .scaleEffect(statusDotPulse ? 1.5 : 1.0)
                .opacity(statusDotPulse ? 0.6 : 1.0)
            Text(vm.statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()

            // Voluntary overtime toggle — only on normal completed / voluntary OT
            if vm.todayStatus == .completed || vm.todayStatus == .voluntaryOvertime {
                Button {
                    vm.toggleVoluntaryOvertime()
                } label: {
                    Image(systemName: vm.todayStatus == .voluntaryOvertime
                          ? "clock.badge.exclamationmark.fill"
                          : "clock.badge.exclamationmark")
                        .font(.subheadline)
                        .foregroundStyle(vm.todayStatus == .voluntaryOvertime
                                         ? vm.statusColor : .secondary)
                }
            }

            Button {
                vm.togglePrivacy()
            } label: {
                Image(systemName: vm.isPrivacyMode ? "eye.slash.fill" : "eye.fill")
                    .font(.subheadline)
                    .foregroundStyle(vm.isPrivacyMode ? .orange : .secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(vm.statusColor.opacity(0.1))
        .clipShape(Capsule())
        .animation(.easeInOut(duration: 1).repeatForever(), value: statusDotPulse)
        .onAppear { statusDotPulse = vm.todayStatus == .working || vm.todayStatus == .overtime }
        .onChange(of: vm.todayStatus) { _, new in
            statusDotPulse = new == .working || new == .overtime
        }
    }

    @State private var statusDotPulse = false

    private var earningsCounter: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            if vm.todayStatus == .dayOff {
                Text("🏖️")
                    .font(.system(size: 48))
            } else if vm.isPrivacyMode {
                Text("***")
                    .font(.system(size: 48, weight: .bold, design: .monospaced))
            } else {
                Text(vm.currency)
                    .font(.system(size: 48, weight: .bold, design: .monospaced))
                Text(formatCurrency(vm.todayAmount))
                    .font(.system(size: 48, weight: .bold, design: .monospaced))
                    .contentTransition(.numericText(value: vm.todayAmount))
            }
        }
    }

    private var progressSection: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(vm.statusColor)
                        .frame(width: geo.size.width * vm.todayProgress, height: 8)
                        .animation(.easeInOut(duration: 0.5), value: vm.todayProgress)
                }
            }
            .frame(height: 8)

            HStack {
                Text("今日进度")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(vm.todayProgress.formatted(.percent.precision(.fractionLength(0))))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText(value: vm.todayProgress))
            }
        }
    }

    // MARK: - Month Card

    private var monthCard: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("本月")
                        .font(.headline)
                    Text("已工作 \(vm.monthSummary.workingDaysElapsed) / \(vm.monthSummary.workingDaysThisMonth) 天")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    if vm.isPrivacyMode {
                        Text("***")
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text("共 ***")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(vm.currency + formatCurrency(vm.monthSummary.monthEarnings))
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text("共 \(vm.currency + formatCurrency(vm.monthSummary.totalMonthEarnings))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.blue)
                        .frame(width: geo.size.width * vm.monthSummary.monthProgress, height: 6)
                        .animation(.easeInOut(duration: 0.5), value: vm.monthSummary.monthProgress)
                }
            }
            .frame(height: 6)
        }
        .padding(24)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(.separator, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }

    // MARK: - Payday Card

    private var paydayCard: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: vm.monthSummary.isPayday ? "party.popper" : "calendar")
                    .font(.title2)
                    .foregroundStyle(vm.monthSummary.isPayday ? .green : .orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(vm.paydayText)
                        .font(.headline)
                    Text(vm.monthSummary.isPayday ? "发工资了!" : "倒数 \(vm.monthSummary.paydayCycleElapsed) / \(vm.monthSummary.paydayCycleTotal) 天")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.orange)
                        .frame(width: geo.size.width * vm.monthSummary.paydayCycleProgress, height: 6)
                        .animation(.easeInOut(duration: 0.5), value: vm.monthSummary.paydayCycleProgress)
                }
            }
            .frame(height: 6)
        }
        .padding(24)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(.separator, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "dollarsign.circle")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("设置你的收入")
                .font(.title2)
                .fontWeight(.semibold)
            Text("在设置中输入月薪和工作时间，开始追踪每日收入。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    // MARK: - Helpers

    private func formatCurrency(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
