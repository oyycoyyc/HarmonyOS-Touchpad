import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { MappingMode, TouchpadSavedSettings } from '../model/TouchpadTypes';

const STORE_NAME: string = 'harmony_touchpad_prefs';
const KEY_MAPPING_MODE: string = 'mappingMode';
const KEY_NATURAL_SCROLL: string = 'naturalScroll';
const KEY_SENSITIVITY_INDEX: string = 'sensitivityIndex';
const KEY_INERTIA_ENABLED: string = 'inertiaEnabled';
const KEY_INERTIA_STRENGTH: string = 'inertiaStrength';
const KEY_EDGE_GUARD_ENABLED: string = 'edgeGuardEnabled';
const KEY_IS_LANDSCAPE_MODE: string = 'isLandscapeMode';
const KEY_SHOW_LOGS: string = 'showLogs';

/**
 * Isolates @kit.ArkData Preferences persistence so TouchpadController and pages stay cleanly decoupled.
 */
export class TouchpadSettingsStore {
  private pref: preferences.Preferences | null = null;

  public createDefaults(): TouchpadSavedSettings {
    return {
      mappingMode: MappingMode.MAC_THREE_FINGER_DRAG,
      naturalScroll: true,
      sensitivityIndex: 1,
      inertiaEnabled: false,
      inertiaStrength: 35,
      edgeGuardEnabled: true,
      isLandscapeMode: false,
      showLogs: true
    };
  }

  public load(context: common.UIAbilityContext): TouchpadSavedSettings {
    const defaults = this.createDefaults();
    const result: TouchpadSavedSettings = {
      mappingMode: defaults.mappingMode,
      naturalScroll: defaults.naturalScroll,
      sensitivityIndex: defaults.sensitivityIndex,
      inertiaEnabled: defaults.inertiaEnabled,
      inertiaStrength: defaults.inertiaStrength,
      edgeGuardEnabled: defaults.edgeGuardEnabled,
      isLandscapeMode: defaults.isLandscapeMode,
      showLogs: defaults.showLogs
    };

    try {
      const store = preferences.getPreferencesSync(context, { name: STORE_NAME });
      this.pref = store;

      const rawMapping = store.getSync(KEY_MAPPING_MODE, defaults.mappingMode);
      if (typeof rawMapping === 'string') {
        if (rawMapping === MappingMode.HARMONY_NATIVE) {
          result.mappingMode = MappingMode.HARMONY_NATIVE;
        } else if (rawMapping === MappingMode.MAC_THREE_FINGER_DRAG) {
          result.mappingMode = MappingMode.MAC_THREE_FINGER_DRAG;
        }
      }

      const rawNatural = store.getSync(KEY_NATURAL_SCROLL, defaults.naturalScroll);
      if (typeof rawNatural === 'boolean') {
        result.naturalScroll = rawNatural;
      }

      const rawSensIdx = store.getSync(KEY_SENSITIVITY_INDEX, defaults.sensitivityIndex);
      if (typeof rawSensIdx === 'number') {
        result.sensitivityIndex = this.clampInt(rawSensIdx, 0, 3);
      }

      const rawInertiaEnabled = store.getSync(KEY_INERTIA_ENABLED, defaults.inertiaEnabled);
      if (typeof rawInertiaEnabled === 'boolean') {
        result.inertiaEnabled = rawInertiaEnabled;
      }

      const rawInertiaStrength = store.getSync(KEY_INERTIA_STRENGTH, defaults.inertiaStrength);
      if (typeof rawInertiaStrength === 'number') {
        result.inertiaStrength = this.clampInt(rawInertiaStrength, 5, 100);
      }

      const rawEdgeGuard = store.getSync(KEY_EDGE_GUARD_ENABLED, defaults.edgeGuardEnabled);
      if (typeof rawEdgeGuard === 'boolean') {
        result.edgeGuardEnabled = rawEdgeGuard;
      }

      const rawLandscape = store.getSync(KEY_IS_LANDSCAPE_MODE, defaults.isLandscapeMode);
      if (typeof rawLandscape === 'boolean') {
        result.isLandscapeMode = rawLandscape;
      }

      const rawShowLogs = store.getSync(KEY_SHOW_LOGS, defaults.showLogs);
      if (typeof rawShowLogs === 'boolean') {
        result.showLogs = rawShowLogs;
      }
    } catch (_ignored) {
      return defaults;
    }

    return result;
  }

  public save(context: common.UIAbilityContext, settings: TouchpadSavedSettings): void {
    try {
      if (this.pref === null) {
        this.pref = preferences.getPreferencesSync(context, { name: STORE_NAME });
      }
      this.pref.putSync(KEY_MAPPING_MODE, settings.mappingMode);
      this.pref.putSync(KEY_NATURAL_SCROLL, settings.naturalScroll);
      this.pref.putSync(KEY_SENSITIVITY_INDEX, this.clampInt(settings.sensitivityIndex, 0, 3));
      this.pref.putSync(KEY_INERTIA_ENABLED, settings.inertiaEnabled);
      this.pref.putSync(KEY_INERTIA_STRENGTH, this.clampInt(settings.inertiaStrength, 5, 100));
      this.pref.putSync(KEY_EDGE_GUARD_ENABLED, settings.edgeGuardEnabled);
      this.pref.putSync(KEY_IS_LANDSCAPE_MODE, settings.isLandscapeMode);
      this.pref.putSync(KEY_SHOW_LOGS, settings.showLogs);
      this.pref.flush().catch(() => {});
    } catch (_ignored) {
      // Non-fatal persistence failure should never interrupt HID control
    }
  }

  private clampInt(value: number, min: number, max: number): number {
    const rounded = Math.round(value);
    if (rounded < min) {
      return min;
    }
    if (rounded > max) {
      return max;
    }
    return rounded;
  }
}
