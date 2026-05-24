import '../../addons/domain/sora_models.dart';
import '../../../shared/models/media_item.dart';

List<SoraTitleVariant> buildTitleVariants(MediaItem media, int seasonNumber) {
  final Map<String, SoraTitleVariant> seen = <String, SoraTitleVariant>{};

  void add(String languageCode, String title, String source) {
    final String trimmed = title.trim();
    if (trimmed.isEmpty) {
      return;
    }
    seen.putIfAbsent(
      '${languageCode.toLowerCase()}|${trimmed.toLowerCase()}',
      () => SoraTitleVariant(
        languageCode: languageCode,
        title: trimmed,
        source: source,
      ),
    );
  }

  final String langCode = _detectLanguageCode(
    media.title,
    media.originalLanguage,
  );
  final String origLangCode = _detectLanguageCode(
    media.originalTitle,
    media.originalLanguage,
  );

  add(langCode, media.title, 'title');

  if (media.originalTitle.trim().isNotEmpty &&
      media.originalTitle.trim().toLowerCase() !=
          media.title.trim().toLowerCase()) {
    add(origLangCode, media.originalTitle, 'original-title');
  }

  for (final String alias in media.aliases) {
    if (alias.trim().isNotEmpty) {
      final String aliasLang = _detectLanguageCode(
        alias,
        media.originalLanguage,
      );
      add(aliasLang, alias, 'alias');
    }
  }

  final List<SoraTitleVariant> result = seen.values.toList();
  result.sort((SoraTitleVariant a, SoraTitleVariant b) {
    final int langOrder = _langPriority(
      a.languageCode,
    ).compareTo(_langPriority(b.languageCode));
    if (langOrder != 0) {
      return langOrder;
    }
    return b.title.length.compareTo(a.title.length);
  });
  return result;
}

String _detectLanguageCode(String text, String originalLanguage) {
  if (_containsJapanese(text)) {
    return 'ja';
  }
  if (_containsCyrillic(text)) {
    return 'ru';
  }
  final String lang = originalLanguage.toLowerCase();
  if (lang.startsWith('ja') || lang == 'jpn') {
    return 'ja';
  }
  if (lang.startsWith('ru') || lang == 'rus') {
    return 'ru';
  }
  return 'en';
}

bool _containsJapanese(String text) {
  return RegExp(r'[぀-ゟ゠-ヿ一-鿿]').hasMatch(text);
}

bool _containsCyrillic(String text) {
  return RegExp(r'[Ѐ-ӿ]').hasMatch(text);
}

int _langPriority(String code) {
  return switch (code) {
    'en' => 0,
    'ru' => 1,
    'ja' => 2,
    _ => 3,
  };
}
