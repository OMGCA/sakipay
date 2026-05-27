# 窝囊计费 / Sakipay

<p align="center">
  <img src="app-icon.png" alt="Sakipay icon" width="128" height="128" />
</p>

<p align="center">
  <strong>每一秒，看见你赚的钱在跳动。<br/>Watch your earnings grow — second by second, in real time.</strong>
</p>

---

Sakipay is a real-time salary tracker. Configure your monthly pay, work hours, breaks, and tax rate — the app shows exactly how much you've earned today, updated every second. Think of it as a live payslip that ticks up while you work.

窝囊计费是一个实时工资追踪器。设定月薪、工作时间、休息时段和税率，应用会每秒更新你今天已赚到的钱。就像一张在你工作时不停跳动的活工资单。

---

## 功能 / Features

- **实时收入计数器 / Real-time earnings counter** — 查看你的时薪、分钟薪乃至秒薪，总收入在工作时间内实时跳动 / see your hourly, minute, and even second rate, with the total ticking up live during work hours
- **休息时段感知 / Break-aware** — 自定义休息时段，计时器在休息时暂停，就和真正的工资计算一样 / define custom break periods; the counter pauses when you're off the clock
- **税率可配 / Tax configurable** — 设置税率（0–45%），查看税后实得收入 / set your tax rate to see post-tax take-home earnings
- **发薪周期追踪 / Payday cycle tracking** — 从上个发薪日向前计数，随时了解你处于发薪周期的哪个阶段 / counts forward from the previous payday so you always know where you are in the pay cycle
- **月度总览 / Month summary** — 预估月度税前/税后收入、有效时薪和日均收入 / projected monthly pre-tax/post-tax income, effective hourly rate, and average daily earnings
- **桌面小组件 / Home screen widget** — 无需打开应用，一眼看到今天的收入 / glance at today's earnings without opening the app
- **浅色 & 深色模式 / Light & dark mode** — 双平台支持 / supported on both platforms

---

## 平台 / Platforms

| 平台 / Platform | 语言 / Language | UI 框架 | 系统要求 / Requirements |
|---|---|---|---|
| iOS | Swift | SwiftUI | iOS 18+ |
| HarmonyOS | ArkTS | ArkUI V2 (API 12+) | SDK 6.1.0(23), 兼容 6.0.0(20) |

---

## 工作原理 / How it works

应用通过你的月薪逐秒计算收入 / The app calculates a per-second earnings rate from your monthly salary:

```
每秒收入 = 月薪 × (1 − 税率) ÷ 月工作天数 ÷ 日工作小时数 ÷ 3600
secondRate = monthlyPay × (1 − taxRate) ÷ workingDaysPerMonth ÷ workHoursPerDay ÷ 3600
```

休息时段会从工作日中扣除，计时器只在真正的工作分钟内跳动。周末（周六和周日）显示为"休息日"。

Break periods are subtracted from the work day so the counter only ticks during actual working minutes. On weekends (Saturday & Sunday) the counter shows "day off".

---

## 架构 / Architecture

双平台共享相同的 MVVM 架构和领域模型 / Both platforms share the same MVVM architecture and domain model:

- **`EarningsCalculator`** — 纯计算引擎，月薪、作息、税率 → 收入 / pure calculation engine: salary, schedule, tax → earnings
- **`DashboardViewModel`** — 实时状态，每 5 秒通过计时器刷新 / live state, refreshes every 5 seconds via timer
- **`SettingsViewModel`** — 表单状态、持久化与校验 / form state, persistence, and validation
- **持久化 / Persistence**: SwiftData + App Group UserDefaults (iOS), `@ohos.data.preferences` (HarmonyOS)

---

## 构建 & 运行 / Build & Run

### iOS

- 在 Xcode 中打开 `sakipay/sakipay.xcodeproj` / Open `sakipay/sakipay.xcodeproj` in Xcode
- Widget 目标: `sakipayWidgetExtension`（`systemSmall` 尺寸）
- App 目标和 Widget 目标均需在 Signing & Capabilities 中添加 App Group `group.com.xiatstudio.sakipay`
- 共享源文件（`AppGroupStore.swift`、`EarningsCalculator.swift`）需在 Target Membership 中勾选两个目标

### HarmonyOS

- 在 DevEco Studio 中打开 `sakipay_hmos/`，或运行 / Open `sakipay_hmos/` in DevEco Studio, or:
- `cd sakipay_hmos && hvigorw assembleHap`

---

## 免责声明 / Disclaimer

本应用仅供娱乐及参考，不构成薪资凭证、劳动合同或专业的财务建议。实际收入可能与本应用显示金额存在差异。

This app is for entertainment and informational purposes only. It is not a substitute for your actual payslip, employment contract, or professional financial advice. Actual earnings may differ.
