import 'dart:io';

import 'package:flutter/widgets.dart';

import '../../core/settings/settings_store.dart';

/// Whether the app is drawing to a remote display (xpra, forwarded X11), where
/// every frame is encoded and sent over the network.
bool detectRemoteDisplay(Map<String, String> environment) {
  if (environment.keys.any((key) => key.startsWith('XPRA_'))) return true;
  final display = environment['DISPLAY'] ?? '';
  final colon = display.lastIndexOf(':');
  if (colon <= 0) return false;
  final host = display.substring(0, colon);

  return host != 'unix' && !host.startsWith('/');
}

final bool isRemoteDisplay =
    Platform.isLinux && detectRemoteDisplay(Platform.environment);

/// Resolves the "reduce motion" setting: an explicit on/off wins, otherwise
/// the OS accessibility signal or a detected remote display turns it on.
bool resolveReduceMotion(String setting, {required bool platformDisabled}) {
  switch (setting) {
    case 'on':
      return true;
    case 'off':
      return false;
    default:
      return platformDisabled || isRemoteDisplay;
  }
}

/// Whether UI animations (fades, slide-ins, etc.) should be suppressed.
///
/// The in-app "reduce motion" override setting takes precedence when it has
/// been explicitly set to force animations on or off; otherwise this follows
/// the OS-level accessibility signal ([MediaQueryData.disableAnimations]),
/// which some remote-display setups (e.g. xpra) don't forward reliably, and
/// [isRemoteDisplay].
extension ReduceMotionGetter on BuildContext {
  bool get reduceMotion => resolveReduceMotion(
    SettingsStore.instance.reduceMotion.value,
    platformDisabled: MediaQuery.of(this).disableAnimations,
  );
}

/// Makes every framework animation honor the "reduce motion" setting:
/// [AnimationController]s with the default behavior run at 5% of their
/// duration while [disableAnimations] is true, so route transitions, implicit
/// animations, tooltips and fades finish within a frame or two.
class WaydirWidgetsBinding extends WidgetsFlutterBinding {
  static WidgetsBinding ensureInitialized() {
    if (_instance == null) WaydirWidgetsBinding();

    return WidgetsBinding.instance;
  }

  static WaydirWidgetsBinding? _instance;

  @override
  void initInstances() {
    super.initInstances();
    _instance = this;
  }

  @override
  bool get disableAnimations => resolveReduceMotion(
    SettingsStore.instance.reduceMotion.peek(),
    platformDisabled: super.disableAnimations,
  );
}
