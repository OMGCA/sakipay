// ArkTS type declarations for the native module `libentry.so`.
//
// Every function forwards to the shared Kotlin logic (libsakipay.so). Structured
// results are JSON documents — parse them with JSON.parse().

export const defaultConfigJson: () => string;
export const defaultBreakJson: () => string;
export const normalizeConfig: (configJson: string) => string;
export const composeConfigJson: (
  monthlyPay: number,
  currency: string,
  payDay: number,
  taxRate: number,
  workingDaysPerMonth: number,
  workStartHour: number,
  workStartMinute: number,
  workEndHour: number,
  workEndMinute: number,
  breaksJson: string,
  dayOverridesJson: string,
  useCalibratedWorkDays: boolean
) => string;
export const configBreaksJson: (configJson: string) => string;
export const configDayOverridesJson: (configJson: string) => string;
export const todayEarningsJson: (
  configJson: string,
  nowMillis: number,
  tzOffsetMinutes: number,
  voluntaryOvertimeTotalSeconds: number,
  isPaused: boolean
) => string;
export const monthSummaryJson: (
  configJson: string,
  nowMillis: number,
  tzOffsetMinutes: number,
  isPaused: boolean
) => string;
export const calibratedWorkingDays: (configJson: string, year: number, month: number) => number;
export const calibratedWorkingDaysNow: (
  configJson: string,
  nowMillis: number,
  tzOffsetMinutes: number
) => number;
export const holidayDataJson: (year: number) => string;
export const resolveDayKind: (year: number, month: number, day: number, dayOverridesJson: string) => string;
export const workWindowMinutes: (workStartMinutes: number, workEndMinutes: number) => number;
export const workScheduleTotalHours: (workStartMinutes: number, workEndMinutes: number, breaksJson: string) => number;
export const secondRate: (configJson: string, nowMillis: number, tzOffsetMinutes: number) => number;
export const pruneBreaksJson: (configJson: string) => string;
export const addBreakJson: (configJson: string) => string;
export const addBreakToBreaks: (workStartMinutes: number, workEndMinutes: number, breaksJson: string) => string;
export const otTotalSecondsJson: (
  stateJson: string,
  nowMillis: number,
  tzOffsetMinutes: number,
  mutatesState: boolean
) => string;
export const otStartJson: (stateJson: string, nowMillis: number, tzOffsetMinutes: number) => string;
export const otEndJson: (
  stateJson: string,
  nowMillis: number,
  tzOffsetMinutes: number,
  secondRate: number
) => string;
export const otBankDailyJson: (
  stateJson: string,
  nowMillis: number,
  tzOffsetMinutes: number,
  secondRate: number
) => string;
export const statusText: (statusWire: string) => string;
export const paydayText: (daysUntilPayday: number, isPayday: boolean) => string;
