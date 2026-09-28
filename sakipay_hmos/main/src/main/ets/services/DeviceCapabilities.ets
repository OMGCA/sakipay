/* (c) Copyright XiatStudio 2026~2026 */
import { deviceInfo } from '@kit.BasicServicesKit'

/**
 * Runtime probes for version-gated UI.
 *
 * The UI Design Kit bottom tabs component (HdsTabs) ships with API 20 (6.0.0(20)),
 * and its floating tab-bar style (barFloatingStyle / immersive material) with
 * API 23 (6.1.0(23)). Everything below those thresholds has to fall back.
 *
 * Never reference HdsTabs outside components/HdsTabsHost.ets — the device tells us
 * here whether that module can be loaded at all.
 */
export class DeviceCapabilities {
  /** First API level that provides HdsTabs (UI Design Kit). */
  private static readonly HDS_TABS_API: number = 20
  /** First API level that provides HdsTabs.barFloatingStyle. */
  private static readonly HDS_FLOATING_API: number = 23
  /** First API level that provides formProvider.getPublishedRunningFormInfos. */
  private static readonly PUBLISHED_FORMS_API: number = 20
  /** SysCap backing the HDS component core (HdsTabs, HdsTabsController). */
  private static readonly HDS_TABS_SYSCAP: string = 'SystemCapability.UIDesign.HDSComponent.Core'

  /**
   * System API level of the running device, e.g. 12, 20, 23.
   */
  public static sdkApiVersion(): number {
    return deviceInfo.sdkApiVersion
  }

  /**
   * True when HdsTabs may be used: the API level is high enough and the device
   * actually exposes the HDS component capability.
   */
  public static supportsHdsTabs(): boolean {
    if (deviceInfo.sdkApiVersion < DeviceCapabilities.HDS_TABS_API) {
      return false
    }
    return canIUse(DeviceCapabilities.HDS_TABS_SYSCAP)
  }

  /**
   * True when the floating tab bar (barFloatingStyle) may be applied on top of HdsTabs.
   */
  public static supportsFloatingTabBar(): boolean {
    return deviceInfo.sdkApiVersion >= DeviceCapabilities.HDS_FLOATING_API
  }

  /**
   * True when formProvider.getPublishedRunningFormInfos is available.
   */
  public static supportsPublishedFormInfos(): boolean {
    return deviceInfo.sdkApiVersion >= DeviceCapabilities.PUBLISHED_FORMS_API
  }
}
