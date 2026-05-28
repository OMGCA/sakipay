/* (c) Copyright XiatStudio 2026~2026 */
import SwiftUI
import SwiftData

// MARK: - Time Wheel

struct TimeWheel: View {
    @Binding var hour: Int
    @Binding var minute: Int
    let minuteStep: Int

    init(hour: Binding<Int>, minute: Binding<Int>, minuteStep: Int = 5) {
        self._hour = hour
        self._minute = minute
        self.minuteStep = max(1, minuteStep)
    }

    var body: some View {
        HStack(spacing: 2) {
            Picker("时", selection: $hour) {
                ForEach(0..<24, id: \.self) { h in
                    Text(String(format: "%02d", h)).tag(h)
                }
            }
            .pickerStyle(.wheel)
            .frame(width: 56, height: 100)
            .clipped()

            Text(":")
                .font(.title3)
                .fontWeight(.medium)
                .padding(.horizontal, 2)

            Picker("分", selection: $minute) {
                ForEach(0..<60, id: \.self) { m in
                    if m % minuteStep == 0 {
                        Text(String(format: "%02d", m)).tag(m)
                    }
                }
            }
            .pickerStyle(.wheel)
            .frame(width: 56, height: 100)
            .clipped()
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var configs: [EarningsConfig]
    @EnvironmentObject var vm: DashboardViewModel

    @State private var monthlyPayText = ""
    @State private var currency = "¥"
    @State private var payDay = 15
    @State private var taxRate = 0.0
    @State private var workingDays = 21.75

    @State private var workStartH = 9
    @State private var workStartM = 0
    @State private var workEndH = 18
    @State private var workEndM = 0

    @State private var breakSegments: [BreakSegment] = [
        BreakSegment(startHour: 12, startMinute: 0, endHour: 13, endMinute: 30)
    ]

    @State private var isLoading = true
    @State private var showSavedToast = false
    @State private var showPrunedToast = false
    @State private var prunedCount = 0

    @FocusState private var payFieldFocused: Bool
    @FocusState private var daysFieldFocused: Bool

    private let currencies = ["¥", "$", "€", "£", "₩", "₹"]

    var config: EarningsConfig? { configs.first }

    var body: some View {
        NavigationStack {
            Form {
                salarySection
                workHoursSection
                breaksSection
                taxSection
                paydaySection
                aboutSection
            }
            .navigationTitle("设置")
            .toolbar { toolbarContent }
            .onAppear(perform: loadConfig)
            .scrollDismissesKeyboard(.immediately)
            .overlay(alignment: .bottom) {
                if showSavedToast {
                    toastView("已保存")
                }
                if showPrunedToast {
                    toastView("已自动清除 \(prunedCount) 个无效休息时段")
                        .onAppear {
                            Task {
                                try? await Task.sleep(for: .seconds(3))
                                showPrunedToast = false
                            }
                        }
                }
            }
        }
    }

    private func toastView(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(.black.opacity(0.7), in: Capsule())
            .padding(.bottom, 32)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("完成") {
                payFieldFocused = false
                daysFieldFocused = false
            }
        }

        ToolbarItem(placement: .confirmationAction) {
            Button("保存") { saveConfig() }
                .fontWeight(.semibold)
        }
    }

    // MARK: - Salary Section

    private var salarySection: some View {
        Section("月薪") {
            HStack(spacing: 8) {
                Picker("币种", selection: $currency) {
                    ForEach(currencies, id: \.self) { c in Text(c).tag(c) }
                }
                .pickerStyle(.menu)
                .labelsHidden()

                TextField("0.00", text: $monthlyPayText)
                    .keyboardType(.decimalPad)
                    .focused($payFieldFocused)
                    .font(.title3)
                    .fontWeight(.semibold)
            }

            HStack {
                Text("每月工作天数")
                Spacer()
                TextField("21.75", value: $workingDays, format: .number)
                    .keyboardType(.decimalPad)
                    .focused($daysFieldFocused)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
            }
        }
    }

    // MARK: - Work Hours

    private var workHoursSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("上班")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TimeWheel(hour: $workStartH, minute: $workStartM)
                    .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 4)
            .onChange(of: workStartH) { _, _ in pruneBreaksOnWorkChange() }
            .onChange(of: workStartM) { _, _ in pruneBreaksOnWorkChange() }

            VStack(alignment: .leading, spacing: 4) {
                Text("下班")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TimeWheel(hour: $workEndH, minute: $workEndM)
                    .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 4)
            .onChange(of: workEndH) { _, _ in pruneBreaksOnWorkChange() }
            .onChange(of: workEndM) { _, _ in pruneBreaksOnWorkChange() }

            HStack {
                Text("每日工时")
                Spacer()
                Text(formattedWorkHours)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("工作时间")
        }
    }

    // MARK: - Breaks Section

    private var breaksSection: some View {
        Section {
            ForEach($breakSegments) { $segment in
                breakSegmentRow($segment)
            }

            Button {
                let ws = workMinutes(workStartH, workStartM)
                let we = workMinutes(workEndH, workEndM)
                guard we > ws + 120 else { return }  // Need at least 2h gap
                let lastEnd = breakSegments.last?.endMinutes ?? ws
                let newStart = min(lastEnd + 60, we - 60)
                let newEnd = min(newStart + 60, we)
                breakSegments.append(BreakSegment(
                    startHour: newStart / 60, startMinute: (newStart % 60) / 5 * 5,
                    endHour: newEnd / 60, endMinute: (newEnd % 60) / 5 * 5
                ))
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("添加休息时段")
                }
            }
        } header: {
            Text("休息时段（不计薪）")
        } footer: {
            Text("调整工作时间时，超出范围的休息时段将被自动清除。")
        }
    }

    private func breakSegmentRow(_ segment: Binding<BreakSegment>) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text("时段")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    let targetID = segment.wrappedValue.id
                    DispatchQueue.main.async {
                        self.breakSegments.removeAll { $0.id == targetID }
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            HStack(spacing: 8) {
                VStack(spacing: 2) {
                    Text("开始").font(.caption2).foregroundStyle(.tertiary)
                    TimeWheel(hour: segment.startHour, minute: segment.startMinute)
                }

                Text("—")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)

                VStack(spacing: 2) {
                    Text("结束").font(.caption2).foregroundStyle(.tertiary)
                    TimeWheel(hour: segment.endHour, minute: segment.endMinute)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Tax Section

    private var taxSection: some View {
        Section {
            VStack(spacing: 12) {
                HStack {
                    Text("税率")
                    Spacer()
                    Text(taxRate.formatted(.percent.precision(.fractionLength(0))))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $taxRate, in: 0...0.45, step: 0.01)

                if taxRate > 0, let pay = Double(monthlyPayText), pay > 0 {
                    let postTax = pay * (1 - taxRate)
                    HStack {
                        Text("税后月薪")
                        Spacer()
                        Text("\(currency)\(String(format: "%.2f", postTax))")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("个税（可选）")
        } footer: {
            Text("设置后每日数据将显示税后金额。")
        }
    }

    // MARK: - Payday Section

    private var paydaySection: some View {
        Section("发薪日") {
            Picker("每月几号", selection: $payDay) {
                ForEach(1...31, id: \.self) { day in
                    Text("\(day)日").tag(day)
                }
            }
        }
    }

    private var aboutSection: some View {
        Section("关于") {
            Button {
                if let url = URL(string: "https://github.com/OMGCA/sakipay/blob/dev/0.0.3/privacy_policy/privacy_policy.md") {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack {
                    Text("隐私政策")
                        .foregroundStyle(.blue)
                    Spacer()
                    Image(systemName: "arrow.up.forward")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                if let url = URL(string: "https://xiatstudio.feishu.cn/share/base/form/shrcnwvu9S2vUZVIqOXvKRTQhie") {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack {
                    Text("反馈")
                        .foregroundStyle(.blue)
                    Spacer()
                    Image(systemName: "arrow.up.forward")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Text("版本")
                Spacer()
                Text("0.0.3")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Logic

    private func workMinutes(_ h: Int, _ m: Int) -> Int { h * 60 + m }

    private var formattedWorkHours: String {
        let ws = workMinutes(workStartH, workStartM)
        let we = workMinutes(workEndH, workEndM)
        guard we > ws else { return "0.0 小时" }
        let breakMin = breakSegments
            .filter(\.isValid)
            .reduce(0) { $0 + ($1.endMinutes - $1.startMinutes) }
        let workMin = max(0, (we - ws) - breakMin)
        let hours = Double(workMin) / 60.0
        return String(format: "%.1f 小时", hours)
    }

    private func pruneBreaksOnWorkChange() {
        let ws = workMinutes(workStartH, workStartM)
        let we = workMinutes(workEndH, workEndM)

        guard we > ws else { return }

        let before = breakSegments.count
        let filtered = breakSegments.filter { $0.fitsWithin(workStart: ws, workEnd: we) }
        let removed = before - filtered.count

        guard removed > 0 else { return }

        // Delay mutation to avoid modifying the array while SwiftUI is reading it
        DispatchQueue.main.async {
            self.breakSegments = filtered
            self.prunedCount = removed
            self.showPrunedToast = true
        }
    }

    private func loadConfig() {
        isLoading = true
        defer { isLoading = false }

        guard let c = config else { return }
        monthlyPayText = c.monthlyPay > 0 ? String(format: "%.2f", c.monthlyPay) : ""
        currency = c.currency
        payDay = c.payDay
        taxRate = c.taxRate
        workingDays = c.workingDaysPerMonth
        workStartH = c.workStartHour; workStartM = c.workStartMinute
        workEndH = c.workEndHour; workEndM = c.workEndMinute
        breakSegments = c.breaks
    }

    private func saveConfig() {
        let pay = Double(monthlyPayText) ?? 0
        guard pay > 0 else { return }

        // Snapshot breakSegments to avoid mutation conflicts
        let validBreaks = breakSegments.filter(\.isValid)

        if let existing = config {
            existing.monthlyPay = pay
            existing.currency = currency
            existing.payDay = payDay
            existing.taxRate = taxRate
            existing.workingDaysPerMonth = workingDays
            existing.workStartHour = workStartH
            existing.workStartMinute = workStartM
            existing.workEndHour = workEndH
            existing.workEndMinute = workEndM
            // Encode breaks to JSON safely — crash here means encoding failed
            existing.breaks = validBreaks
            existing.updatedAt = Date()
        } else {
            let new = EarningsConfig()
            new.monthlyPay = pay
            new.currency = currency
            new.payDay = payDay
            new.taxRate = taxRate
            new.workingDaysPerMonth = workingDays
            new.workStartHour = workStartH
            new.workStartMinute = workStartM
            new.workEndHour = workEndH
            new.workEndMinute = workEndM
            new.breaks = validBreaks
            modelContext.insert(new)
        }

        do {
            if modelContext.hasChanges {
                try modelContext.save()
            }
        } catch {
            print("[sakipay] saveConfig failed: \(error.localizedDescription)")
            return
        }

        if let c = config {
            vm.configure(with: c)
        }

        showSavedToast = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            showSavedToast = false
        }
    }
}
