import 'package:flutter/widgets.dart';

import '../../core/settings/settings_store.dart';

/// Whether UI animations (fades, slide-ins, etc.) should be suppressed.
///
/// The in-app "reduce motion" override setting takes precedence when it has
/// been explicitly set to force animations on or off; otherwise this follows
/// the OS-level accessibility signal ([MediaQueryData.disableAnimations]),
/// which some remote-display setups (e.g. xpra) don't forward reliably.
extension ReduceMotionGetter on BuildContext {
  bool get reduceMotion {
    switch (SettingsStore.instance.reduceMotion.value) {
      case 'on':
        return true;
      case 'off':
        return false;
      default:
        return MediaQuery.of(this).disableAnimations;
    }
  }
}
