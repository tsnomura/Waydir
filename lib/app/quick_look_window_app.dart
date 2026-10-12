import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:signals/signals_flutter.dart';

import '../core/models/file_entry.dart';
import '../core/settings/settings_store.dart';
import '../features/quick_look/quick_look_window.dart';
import '../i18n/strings.g.dart';
import '../ui/theme/app_theme.dart';
import '../ui/theme/app_theme_registry.dart';

class QuickLookWindowApp extends StatelessWidget {
  final String path;

  const QuickLookWindowApp({super.key, required this.path});

  @override
  Widget build(BuildContext context) {
    final entry = FileEntry.fromFileSystemEntity(File(path));

    return SignalBuilder(
      builder: (context) {
        final themeId = SettingsStore.instance.themeId.value;
        AppThemeRegistry.instance.loadSync();
        final theme = AppThemeRegistry.instance.resolve(themeId);
        AppColors.setTheme(theme);

        return MaterialApp(
          key: ValueKey(theme.id),
          title: entry.name,
          locale: TranslationProvider.of(context).flutterLocale,
          supportedLocales: AppLocaleUtils.supportedLocales,
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.build(theme),
          home: Material(
            color: AppColors.bg,
            child: QuickLookWindow(entry: entry),
          ),
        );
      },
    );
  }
}
