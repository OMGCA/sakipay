/* (c) Copyright XiatStudio 2026~2026 */
import { formBindingData, formInfo, formProvider } from '@kit.FormKit'
import { PreferencesStore } from './PreferencesStore'
import { DeviceCapabilities } from './DeviceCapabilities'
import { Log } from './Log'

/**
 * Pushes fresh card data to every widget instance currently on the home screen.
 *
 * formProvider.getPublishedRunningFormInfos() is API 20+; below that the ids persisted
 * by SakipayFormAbility.onAddForm / onRemoveForm are used instead, so widget refreshes
 * still work on API 13-19 devices.
 */
export class FormRefresher {
  /**
   * Resolves the form ids to push to — live running forms where available, otherwise
   * the set remembered in preferences.
   */
  public static async runningFormIds(store: PreferencesStore): Promise<string[]> {
    if (DeviceCapabilities.supportsPublishedFormInfos()) {
      try {
        const forms: formInfo.RunningFormInfo[] = await formProvider.getPublishedRunningFormInfos()
        const ids: string[] = []
        for (const form of forms) {
          ids.push(form.formId)
        }
        return ids
      } catch (err) {
        Log.error(`runningFormIds: published lookup failed, using stored ids — ${err}`)
      }
    }
    return store.getFormIds()
  }

  /**
   * Pushes the given card data to every form instance. No-op when none are placed,
   * and individual failures are logged rather than thrown.
   */
  public static async refreshForms(store: PreferencesStore,
    data: Record<string, string | number>): Promise<void> {
    const ids: string[] = await FormRefresher.runningFormIds(store)
    if (ids.length === 0) {
      return
    }
    const fbData: formBindingData.FormBindingData = formBindingData.createFormBindingData(data)
    for (const id of ids) {
      try {
        await formProvider.updateForm(id, fbData)
      } catch (err) {
        Log.error(`refreshForms: update of ${id} failed — ${err}`)
      }
    }
  }
}
