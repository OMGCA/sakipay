/* (c) Copyright XiatStudio 2026~2026 */
import { hilog } from '@kit.PerformanceAnalysisKit'

const DOMAIN: number = 0x0001
const TAG: string = 'sakipay'

/**
 * Project-level logging utility. Do not use console.xxx directly.
 */
export class Log {
  public static debug(message: string): void {
    hilog.debug(DOMAIN, TAG, message)
  }

  public static info(message: string): void {
    hilog.info(DOMAIN, TAG, message)
  }

  public static warn(message: string): void {
    hilog.warn(DOMAIN, TAG, message)
  }

  public static error(message: string): void {
    hilog.error(DOMAIN, TAG, message)
  }
}
