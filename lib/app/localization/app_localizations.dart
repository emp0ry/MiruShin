import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppLocalizations {
  const AppLocalizations(this.locale, this._values, this._fallbackValues);

  final Locale locale;
  final Map<String, String> _values;
  final Map<String, String> _fallbackValues;

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ru'),
    Locale('ja'),
  ];

  static final Map<String, Map<String, String>> _cache =
      <String, Map<String, String>>{};

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static Future<AppLocalizations> load(Locale locale) async {
    final String code = _supportedCode(locale);
    final Map<String, String> fallbackValues = await _loadValues('en');
    final Map<String, String> values = code == 'en'
        ? fallbackValues
        : await _loadValues(code);
    return AppLocalizations(locale, values, fallbackValues);
  }

  String t(String key) {
    return _values[key] ?? _fallbackValues[key] ?? key;
  }

  String tf(String key, Map<String, Object?> values) {
    String result = t(key);
    for (final MapEntry<String, Object?> entry in values.entries) {
      result = result.replaceAll('{${entry.key}}', '${entry.value ?? ''}');
    }
    return result;
  }

  static String _supportedCode(Locale locale) {
    return supportedLocales.any(
          (Locale supportedLocale) =>
              supportedLocale.languageCode == locale.languageCode,
        )
        ? locale.languageCode
        : 'en';
  }

  static Future<Map<String, String>> _loadValues(String code) async {
    final Map<String, String>? cached = _cache[code];
    if (cached != null) return cached;

    final String raw = await rootBundle.loadString('lib/l10n/app_$code.arb');
    final Map<String, dynamic> decoded =
        jsonDecode(raw) as Map<String, dynamic>;
    final Map<String, String> values = <String, String>{};
    for (final MapEntry<String, dynamic> entry in decoded.entries) {
      if (entry.key.startsWith('@')) continue;
      final dynamic value = entry.value;
      if (value is String) values[entry.key] = value;
    }
    _cache[code] = values;
    return values;
  }
}

extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);

  String t(String key) => l10n.t(key);

  String tf(String key, Map<String, Object?> values) => l10n.tf(key, values);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return AppLocalizations.supportedLocales.any(
      (Locale supportedLocale) =>
          supportedLocale.languageCode == locale.languageCode,
    );
  }

  @override
  Future<AppLocalizations> load(Locale locale) {
    return AppLocalizations.load(locale);
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
