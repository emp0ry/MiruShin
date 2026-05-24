import 'package:flutter/widgets.dart';

class SupportedLanguage {
  const SupportedLanguage({
    required this.locale,
    required this.labelKey,
    required this.nativeName,
  });

  final Locale locale;
  final String labelKey;
  final String nativeName;
}

abstract final class SupportedLanguages {
  static const List<SupportedLanguage> all = <SupportedLanguage>[
    SupportedLanguage(
      locale: Locale('en'),
      labelKey: 'English',
      nativeName: 'English',
    ),
    SupportedLanguage(
      locale: Locale('ru'),
      labelKey: 'Russian',
      nativeName: 'Русский',
    ),
    SupportedLanguage(
      locale: Locale('ja'),
      labelKey: 'Japanese',
      nativeName: '日本語',
    ),
  ];

  static SupportedLanguage fromLocale(Locale? locale) {
    return all.firstWhere(
      (SupportedLanguage language) =>
          language.locale.languageCode == locale?.languageCode,
      orElse: () => all.first,
    );
  }
}
