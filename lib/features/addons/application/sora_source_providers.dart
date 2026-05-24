import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../features/settings/presentation/settings_state.dart';
import '../../../shared/models/media_item.dart';
import '../../catalog/application/catalog_mode.dart';
import '../../watch/domain/normalized_models.dart';
import '../data/anime_titles_service.dart';
import '../data/sora_js_runtime.dart';
import '../domain/sora_models.dart';
import '../domain/sora_parsers.dart';
import 'sora_addons_provider.dart';

/// Stable key for title-variant resolution: excludes addonId so variants are
/// computed once and shared across all addons searching the same media.
class _TitleVariantsKey {
  const _TitleVariantsKey({required this.media, required this.languageCodes});

  final MediaItem media;
  final List<String> languageCodes;

  @override
  bool operator ==(Object other) {
    if (other is! _TitleVariantsKey) return false;
    if (other.media.id != media.id) return false;
    if (other.media.title != media.title) return false;
    if (other.media.originalTitle != media.originalTitle) return false;
    if (other.media.originalLanguage != media.originalLanguage) return false;
    if (other.media.externalIds['tmdb'] != media.externalIds['tmdb']) {
      return false;
    }
    if (other.media.externalIds['anilist'] != media.externalIds['anilist']) {
      return false;
    }
    if (other.media.externalIds['mal'] != media.externalIds['mal']) {
      return false;
    }
    if (other.media.externalIds['sora_season_number'] !=
        media.externalIds['sora_season_number']) {
      return false;
    }
    if (other.media.externalIds['sora_season_name'] !=
        media.externalIds['sora_season_name']) {
      return false;
    }
    if (other.media.externalIds['sora_season_original_name'] !=
        media.externalIds['sora_season_original_name']) {
      return false;
    }
    if (other.media.externalIds['sora_season_aliases'] !=
        media.externalIds['sora_season_aliases']) {
      return false;
    }
    if (!_sameStringList(other.media.aliases, media.aliases)) return false;
    if (other.languageCodes.length != languageCodes.length) return false;
    for (int i = 0; i < languageCodes.length; i++) {
      if (other.languageCodes[i] != languageCodes[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    media.id,
    media.title,
    media.originalTitle,
    media.originalLanguage,
    media.externalIds['tmdb'],
    media.externalIds['anilist'],
    media.externalIds['mal'],
    media.externalIds['sora_season_number'],
    media.externalIds['sora_season_name'],
    media.externalIds['sora_season_original_name'],
    media.externalIds['sora_season_aliases'],
    Object.hashAll(media.aliases),
    Object.hashAll(languageCodes),
  );
}

final soraSourceLanguagesProvider =
    NotifierProvider<SoraSourceLanguageController, List<String>>(
      SoraSourceLanguageController.new,
    );

final soraTitleVariantsProvider =
    FutureProvider.family<List<SoraTitleVariant>, _TitleVariantsKey>((
      Ref ref,
      _TitleVariantsKey key,
    ) async {
      final List<SoraTitleVariant> variants = await _buildTitleVariants(
        media: key.media,
        languageCodes: key.languageCodes,
        settings: ref.watch(settingsProvider),
        catalogMode: ref.watch(catalogModeProvider),
      );
      _debugPrintTitleVariants(key.media.title, variants, key.languageCodes);
      return variants;
    });

@visibleForTesting
Future<List<SoraTitleVariant>> buildSoraTitleVariantsForTest({
  required MediaItem media,
  required List<String> languageCodes,
  required SettingsState settings,
  CatalogMode catalogMode = CatalogMode.tmdb,
}) {
  return _buildTitleVariants(
    media: media,
    languageCodes: languageCodes,
    settings: settings,
    catalogMode: catalogMode,
  );
}

// Monotonically increasing epoch. Incrementing it synchronously cancels every
// running search loop without touching Riverpod providers (which would restart
// them while their listeners are still alive).
int _soraSearchEpoch = 0;

/// Call this synchronously before switching away from the Find Sources tab.
/// Every in-flight search loop will see the stale epoch and break on its next
/// await, without restarting the providers.
void cancelAllSoraSearches() => _soraSearchEpoch++;

final soraSourceSearchProvider =
    FutureProvider.family<SoraSourceSearchBundle, SoraSourceSearchRequest>((
      Ref ref,
      SoraSourceSearchRequest request,
    ) async {
      // Capture epoch at provider start. Any later increment stops this run.
      final int myEpoch = _soraSearchEpoch;
      bool providerDisposed = false;
      ref.onDispose(() => providerDisposed = true);
      bool shouldStop() => providerDisposed || _soraSearchEpoch != myEpoch;

      final SoraAddonsState addonsState = ref.watch(soraAddonsProvider);
      final List<SoraInstalledAddon> addons = addonsState.enabled
          .where(
            (SoraInstalledAddon addon) =>
                request.addonId == null || addon.id == request.addonId,
          )
          .toList(growable: false);
      final List<SoraTitleVariant> variants = await ref.watch(
        soraTitleVariantsProvider(
          _TitleVariantsKey(
            media: request.media,
            languageCodes: request.languageCodes,
          ),
        ).future,
      );
      if (shouldStop()) {
        return SoraSourceSearchBundle(
          variants: variants,
          results: const <SoraSearchResult>[],
          errors: const <SoraSourceError>[],
        );
      }
      if (addons.isEmpty) {
        return SoraSourceSearchBundle(
          variants: variants,
          results: const <SoraSearchResult>[],
          errors: const <SoraSourceError>[],
        );
      }

      final Map<String, SoraSearchResult> deduped =
          <String, SoraSearchResult>{};
      final List<SoraSourceError> errors = <SoraSourceError>[];
      final Set<String> matchedAddonIds = <String>{};
      final List<String> languageCodes = request.languageCodes.isEmpty
          ? SoraSearchLanguage.defaultPriority
          : request.languageCodes;
      final runtime = ref.watch(soraJsRuntimeProvider);

      outer:
      for (
        int languageIndex = 0;
        languageIndex < languageCodes.length;
        languageIndex += 1
      ) {
        if (shouldStop()) break;
        final String languageCode = languageCodes[languageIndex];
        final List<String> queries = request.customQuery != null
            ? <String>[request.customQuery!]
            : _queriesForLanguage(
                variants: variants,
                languageCode: languageCode,
                fallbackTitle: request.media.title,
                fallbackOriginalTitle: request.media.originalTitle,
              );
        for (final SoraInstalledAddon addon in addons) {
          if (shouldStop()) break outer;
          if (matchedAddonIds.contains(addon.id)) {
            continue;
          }
          for (final String query in queries) {
            if (shouldStop()) break outer;
            try {
              debugPrint(
                '[Sora] Search addon="${addon.manifest.sourceName}" '
                'language=$languageCode query="$query"',
              );
              final List<SoraSearchResult> results = await runtime
                  .searchResults(
                    addon: addon,
                    keyword: query,
                    languageCode: languageCode,
                    titleVariants: variants,
                  );
              if (shouldStop()) break outer;
              debugPrint(
                '[Sora] Search result addon="${addon.manifest.sourceName}" '
                'language=$languageCode query="$query" count=${results.length}',
              );
              for (final SoraSearchResult result in results) {
                final String key = '${addon.id}:${result.href}';
                final SoraSearchResult? previous = deduped[key];
                if (previous == null || result.score > previous.score) {
                  deduped[key] = result;
                }
              }
              if (results.isNotEmpty) {
                matchedAddonIds.add(addon.id);
                break;
              }
            } on Object catch (error) {
              if (shouldStop()) break outer;
              errors.add(
                SoraSourceError(
                  addonId: addon.id,
                  addonName: addon.manifest.sourceName,
                  message: _friendlyError(error),
                ),
              );
              break;
            }
          }
        }
      }

      final List<SoraSearchResult> results = deduped.values.toList();
      results.sort((SoraSearchResult a, SoraSearchResult b) {
        final int score = b.score.compareTo(a.score);
        if (score != 0) {
          return score;
        }
        final int language = languageCodes
            .indexOf(a.languageCode)
            .compareTo(languageCodes.indexOf(b.languageCode));
        if (language != 0) {
          return language;
        }
        return a.title.compareTo(b.title);
      });
      return SoraSourceSearchBundle(
        variants: variants,
        results: results,
        errors: _uniqueErrors(errors),
      );
    });

final soraSourceContentProvider =
    FutureProvider.family<SoraSourceContent, SoraSourceRequest>((
      Ref ref,
      SoraSourceRequest request,
    ) async {
      final SoraInstalledAddon? addon = ref
          .watch(soraAddonsProvider)
          .byId(request.addonId);
      if (addon == null) {
        throw const SoraAddonException('Addon is no longer installed.');
      }
      final runtime = ref.watch(soraJsRuntimeProvider);
      final SoraSourceDetails details = await runtime.extractDetails(
        addon: addon,
        result: request.result,
      );
      final List<SoraEpisode> episodes = await runtime.extractEpisodes(
        addon: addon,
        result: request.result,
      );
      return SoraSourceContent(
        addon: addon,
        result: request.result,
        details: details,
        episodes: episodes,
      );
    });

final soraStreamResolveProvider =
    FutureProvider.family<SoraResolvedStreams, SoraStreamRequest>((
      Ref ref,
      SoraStreamRequest request,
    ) async {
      final SoraInstalledAddon? addon = ref
          .watch(soraAddonsProvider)
          .byId(request.addonId);
      if (addon == null) {
        throw const SoraAddonException('Addon is no longer installed.');
      }
      return ref
          .watch(soraJsRuntimeProvider)
          .extractStreams(
            addon: addon,
            episode: request.episode,
            voiceover: request.voiceover,
          );
    });

final soraStreamBundleProvider =
    FutureProvider.family<NormalizedStreamBundle, SoraStreamRequest>((
      Ref ref,
      SoraStreamRequest request,
    ) async {
      final SoraInstalledAddon? addon = ref
          .watch(soraAddonsProvider)
          .byId(request.addonId);
      if (addon == null) {
        throw const SoraAddonException('Addon is no longer installed.');
      }
      final SoraResolvedStreams streams = await ref.watch(
        soraStreamResolveProvider(request).future,
      );
      final SoraJsRuntime runtime = ref.watch(soraJsRuntimeProvider);
      final NormalizedStreamBundle bundle = parseSoraStreamBundle(
        streams,
        streamType: addon.manifest.streamType,
        refresh: () async {
          final SoraResolvedStreams refreshed = await runtime.refreshStream(
            addon: addon,
            episode: request.episode,
          );
          return parseSoraStreamBundle(
            refreshed,
            streamType: addon.manifest.streamType,
          );
        },
      );
      if (bundle.availableServers.isEmpty) {
        throw SoraAddonException(
          '${addon.manifest.sourceName} did not return any playable streams.',
        );
      }
      return bundle;
    });

final soraEpisodeProgressProvider =
    NotifierProvider<SoraEpisodeProgressController, Set<String>>(
      SoraEpisodeProgressController.new,
    );

class SoraSourceSearchBundle {
  const SoraSourceSearchBundle({
    required this.variants,
    required this.results,
    required this.errors,
  });

  final List<SoraTitleVariant> variants;
  final List<SoraSearchResult> results;
  final List<SoraSourceError> errors;
}

class SoraSourceError {
  const SoraSourceError({
    required this.addonId,
    required this.addonName,
    required this.message,
  });

  final String addonId;
  final String addonName;
  final String message;
}

class SoraSourceContent {
  const SoraSourceContent({
    required this.addon,
    required this.result,
    required this.details,
    required this.episodes,
  });

  final SoraInstalledAddon addon;
  final SoraSearchResult result;
  final SoraSourceDetails details;
  final List<SoraEpisode> episodes;
}

class SoraSourceLanguageController extends Notifier<List<String>> {
  static const String _key = 'sora.sourceLanguages';

  @override
  List<String> build() {
    unawaited(_load());
    return const <String>[];
  }

  Future<void> toggle(String code) async {
    final Set<String> supportedCodes = SoraSearchLanguage.supported
        .map((SoraSearchLanguage language) => language.code)
        .toSet();
    if (!supportedCodes.contains(code)) {
      return;
    }
    final List<String> next = <String>[...state];
    if (next.contains(code)) {
      next.remove(code);
    } else {
      next.add(code);
    }
    if (next.isEmpty) {
      next.add(SoraSearchLanguage.defaultPriority.first);
    }
    state = next;
    debugPrint('[Sora] Source language order: ${state.join(' -> ')}');
    await _save();
  }

  Future<void> move(String code, int direction) async {
    final List<String> next = <String>[...state];
    final int index = next.indexOf(code);
    final int target = index + direction;
    if (index == -1 || target < 0 || target >= next.length) {
      return;
    }
    next
      ..removeAt(index)
      ..insert(target, code);
    state = next;
    debugPrint('[Sora] Source language order: ${state.join(' -> ')}');
    await _save();
  }

  Future<void> reset() async {
    state = SoraSearchLanguage.defaultPriority;
    debugPrint('[Sora] Source language order: ${state.join(' -> ')}');
    await _save();
  }

  Future<void> _load() async {
    try {
      final SharedPreferences preferences =
          await SharedPreferences.getInstance();
      final List<String>? saved = preferences.getStringList(_key);
      final List<String> supportedCodes = SoraSearchLanguage.supported
          .map((SoraSearchLanguage language) => language.code)
          .toList(growable: false);
      final bool hadUnsupportedCodes =
          saved?.any((String code) => !supportedCodes.contains(code)) ?? false;
      final List<String> filtered =
          (saved ?? SoraSearchLanguage.defaultPriority)
              .where(supportedCodes.contains)
              .toList(growable: false);
      final List<String> next = filtered.isEmpty
          ? SoraSearchLanguage.defaultPriority
          : hadUnsupportedCodes
          ? _withMissingDefaultLanguages(filtered)
          : filtered;
      if (!_sameStringList(state, next)) {
        state = next;
      }
      if (saved != null && !_sameStringList(saved, next)) {
        await preferences.setStringList(_key, next);
      }
    } catch (_) {
      if (state.isEmpty) {
        state = SoraSearchLanguage.defaultPriority;
      }
    }
  }

  Future<void> _save() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(_key, state);
  }
}

List<String> _withMissingDefaultLanguages(List<String> languageCodes) {
  final List<String> next = <String>[...languageCodes];
  for (final String code in SoraSearchLanguage.defaultPriority) {
    if (!next.contains(code)) {
      next.add(code);
    }
  }
  return next;
}

bool _sameStringList(List<String> a, List<String> b) {
  if (a.length != b.length) {
    return false;
  }
  for (int index = 0; index < a.length; index += 1) {
    if (a[index] != b[index]) {
      return false;
    }
  }
  return true;
}

class SoraEpisodeProgressController extends Notifier<Set<String>> {
  static const String _key = 'sora.watchedEpisodes';

  @override
  Set<String> build() {
    unawaited(_load());
    return <String>{};
  }

  bool isWatched({
    required String mediaId,
    required SoraSearchResult result,
    required SoraEpisode episode,
  }) {
    return state.contains(
      keyFor(mediaId: mediaId, result: result, episode: episode),
    );
  }

  Future<void> mark({
    required String mediaId,
    required SoraSearchResult result,
    required SoraEpisode episode,
    required bool watched,
  }) async {
    final Set<String> next = <String>{...state};
    final String key = keyFor(
      mediaId: mediaId,
      result: result,
      episode: episode,
    );
    if (watched) {
      next.add(key);
    } else {
      next.remove(key);
    }
    state = next;
    await _save();
  }

  Future<void> markPrevious({
    required String mediaId,
    required SoraSearchResult result,
    required List<SoraEpisode> episodes,
    required SoraEpisode episode,
  }) async {
    final Set<String> next = <String>{...state};
    for (final SoraEpisode current in episodes) {
      if (current.number <= episode.number) {
        next.add(keyFor(mediaId: mediaId, result: result, episode: current));
      }
    }
    state = next;
    await _save();
  }

  String keyFor({
    required String mediaId,
    required SoraSearchResult result,
    required SoraEpisode episode,
  }) {
    return '$mediaId|${result.addonId}|${result.href}|${episode.href}';
  }

  Future<void> _load() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    state = (preferences.getStringList(_key) ?? const <String>[]).toSet();
  }

  Future<void> _save() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(_key, state.toList(growable: false));
  }
}

Future<List<SoraTitleVariant>> _buildTitleVariants({
  required MediaItem media,
  required List<String> languageCodes,
  required SettingsState settings,
  required CatalogMode catalogMode,
}) async {
  final Map<String, SoraTitleVariant> variants = <String, SoraTitleVariant>{};
  void add(String languageCode, String title, String source) {
    final String trimmed = title.trim();
    if (trimmed.isEmpty) {
      return;
    }
    variants.putIfAbsent(
      '${languageCode.toLowerCase()}|${trimmed.toLowerCase()}',
      () => SoraTitleVariant(
        languageCode: languageCode,
        title: trimmed,
        source: source,
      ),
    );
  }

  final List<String> codes = languageCodes.isEmpty
      ? SoraSearchLanguage.defaultPriority
      : languageCodes;
  final bool isAnime = media.type == MediaType.anime;
  final int seasonNumber =
      int.tryParse(media.externalIds['sora_season_number'] ?? '') ?? 0;
  final String seasonName = media.externalIds['sora_season_name'] ?? '';
  final String seasonFullTitle =
      media.externalIds['sora_season_full_title'] ?? '';
  final String originalSeasonName =
      media.externalIds['sora_season_original_name'] ?? '';
  final List<String> seasonAliases =
      (media.externalIds['sora_season_aliases'] ?? '')
          .split('\n')
          .map((String value) => value.trim())
          .where((String value) => value.isNotEmpty)
          .toList(growable: false);

  final bool canReadTmdbTranslations =
      catalogMode == CatalogMode.tmdb &&
      settings.tmdbEnabled &&
      settings.tmdbReadAccessToken.trim().isNotEmpty &&
      media.externalIds['tmdb'] != null;
  Map<String, String> translated = const <String, String>{};
  Map<String, String> seasonTranslated = const <String, String>{};
  if (canReadTmdbTranslations) {
    try {
      translated = await _fetchTmdbTranslations(
        media: media,
        languageCodes: codes,
        settings: settings,
      );
    } on Object {
      // Translation lookup is a best-effort search enhancement.
    }
    if (codes.contains('en') && (translated['en'] ?? '').trim().isEmpty) {
      try {
        final String englishTitle = await _fetchTmdbTitleForLanguage(
          media: media,
          language: 'en-US',
          settings: settings,
        );
        if (englishTitle.trim().isNotEmpty) {
          translated = <String, String>{...translated, 'en': englishTitle};
        }
      } on Object {
        // English title fallback is also best-effort.
      }
    }
    if (seasonNumber > 0) {
      try {
        seasonTranslated = await _fetchTmdbSeasonTranslations(
          media: media,
          seasonNumber: seasonNumber,
          languageCodes: codes,
          settings: settings,
        );
      } on Object {
        // Season translation lookup is a best-effort search enhancement.
      }
    }
  }

  // Resolve anime-specific titles from AniList / Jikan / Shikimori.
  if (catalogMode == CatalogMode.anilist && isAnime) {
    final String? anilistId = media.externalIds['anilist'];
    final String? malId = media.externalIds['mal'];
    final List<String> animeTitleCandidates = <String>[
      media.title,
      media.originalTitle,
      ...media.aliases,
      seasonName,
      originalSeasonName,
      ...seasonAliases,
    ];

    // When a specific season with a distinctive name is selected, run a
    // second season-specific Shikimori search (no MAL ID → falls through to
    // title search) so we get the correct season title in all languages.
    // Many multi-season anime have separate MAL entries per season/movie.
    final bool hasDistinctSeasonName =
        seasonName.isNotEmpty &&
        !RegExp(r'^Season\s+\d+$').hasMatch(seasonName) &&
        seasonName.toLowerCase() != media.title.toLowerCase() &&
        seasonName.toLowerCase() != media.originalTitle.toLowerCase();

    if (anilistId != null ||
        malId != null ||
        animeTitleCandidates.any((String title) => title.trim().isNotEmpty)) {
      try {
        // Series resolve (uses MAL/AniList IDs) and optional season resolve
        // (title-search only, season name first) run in parallel.
        final List<AnimeTitles> resolved = await Future.wait(
          <Future<AnimeTitles>>[
            AnimeTitlesService.resolve(
              anilistId: anilistId,
              malId: malId,
              titleCandidates: animeTitleCandidates,
            ).catchError((_) async => const AnimeTitles()),
            if (hasDistinctSeasonName)
              AnimeTitlesService.resolve(
                titleCandidates: <String>[
                  seasonName,
                  originalSeasonName,
                  ...seasonAliases,
                  ...animeTitleCandidates,
                ],
              ).catchError((_) async => const AnimeTitles()),
          ],
        );

        final AnimeTitles seriesAt = resolved[0];
        final AnimeTitles seasonAt = resolved.length > 1
            ? resolved[1]
            : const AnimeTitles();

        // Prefer season-specific titles; fall back to series-level titles.
        final String en = seasonAt.english.isNotEmpty
            ? seasonAt.english
            : seriesAt.english;
        final String romaji = seasonAt.romaji.isNotEmpty
            ? seasonAt.romaji
            : seriesAt.romaji;
        final String japanese = seasonAt.japanese.isNotEmpty
            ? seasonAt.japanese
            : seriesAt.japanese;
        final String ru = seasonAt.russian.isNotEmpty
            ? seasonAt.russian
            : seriesAt.russian;

        if (en.isNotEmpty) add('en', en, 'anime-api');
        if (romaji.isNotEmpty) add('ja', romaji, 'anime-api-romaji');
        if (japanese.isNotEmpty) add('ja', japanese, 'anime-api');
        if (ru.isNotEmpty) add('ru', ru, 'anime-api');
      } on Object {
        // Best-effort anime title enrichment.
      }
    }
  }

  final String metadataLanguageCode = settings.effectiveTmdbLanguage
      .split('-')
      .first
      .toLowerCase();
  for (final String code in codes) {
    final String? localizedTitle = translated[code];
    final String? title = localizedTitle;
    if (title != null && title.trim().isNotEmpty) {
      add(code, title, 'tmdb-$code');
    }

    if (code == metadataLanguageCode &&
        _textLooksLikeLanguage(media.title, code)) {
      add(code, media.title, 'metadata');
    }

    final String? localizedSeasonTitle = seasonTranslated[code];
    final String? metadataSeasonTitle = code == metadataLanguageCode
        ? seasonName
        : null;
    final String? seasonTitle = _realSeasonTitle(
      localizedSeasonTitle ?? metadataSeasonTitle,
      seasonNumber,
    );
    if (seasonTitle != null &&
        (localizedSeasonTitle != null ||
            _textLooksLikeLanguage(seasonTitle, code))) {
      final String seasonSource = localizedSeasonTitle != null
          ? 'tmdb-season-$code'
          : 'metadata-season';
      add(code, seasonTitle, seasonSource);
      if (title != null && title.trim().isNotEmpty) {
        final String? combined = _combinedTitleAndSeason(title, seasonTitle);
        if (combined != null) {
          add(code, combined, '$seasonSource-combined');
        }
      }
    }
  }

  // Full season title (e.g. "Jujutsu Kaisen: Shibuya Incident" or the raw
  // Japanese "青春ブタ野郎はサンタクロースの夢を見ない"). Language is detected
  // from the text itself so a Japanese TVDB season name goes into [ja], an
  // English one into [en], etc. Kept outside the language loop to avoid
  // duplicate adds and to bypass the _textLooksLikeLanguage guard.
  if (seasonFullTitle.isNotEmpty) {
    final String lang = _detectLanguageCode(
      seasonFullTitle,
      metadataLanguageCode,
    );
    add(lang, seasonFullTitle, 'season-full-title');
  }

  for (final String seasonAlias in <String>[
    originalSeasonName,
    ...seasonAliases,
  ]) {
    final String trimmed = seasonAlias.trim();
    if (trimmed.isEmpty || trimmed.toLowerCase() == seasonName.toLowerCase()) {
      continue;
    }
    final String lang = _detectLanguageCode(trimmed, metadataLanguageCode);
    add(lang, trimmed, 'season-alias');
    final String? fullAlias = _combinedTitleAndSeason(media.title, trimmed);
    if (fullAlias != null) {
      add(lang, fullAlias, 'season-alias-combined');
    }
  }

  // Keep script detection in charge: romaji/Latin anime aliases should remain
  // usable in English searches, while Japanese-script aliases stay Japanese.
  final String titleLangCode = _detectLanguageCode(
    media.title,
    metadataLanguageCode,
  );
  add(titleLangCode, media.title, 'metadata');

  final String originalLangCode = _detectLanguageCode(
    media.originalTitle,
    metadataLanguageCode,
  );
  if (media.originalTitle.trim().isNotEmpty &&
      media.originalTitle.trim().toLowerCase() !=
          media.title.trim().toLowerCase()) {
    add(originalLangCode, media.originalTitle, 'original-title');
  }
  for (final String alias in media.aliases) {
    if (alias.trim().isNotEmpty) {
      add(_detectLanguageCode(alias, metadataLanguageCode), alias, 'alias');
    }
  }

  final List<SoraTitleVariant> list = variants.values.toList();
  list.sort((SoraTitleVariant a, SoraTitleVariant b) {
    final int language = _languageIndex(
      codes,
      a.languageCode,
    ).compareTo(_languageIndex(codes, b.languageCode));
    if (language != 0) {
      return language;
    }
    return b.title.length.compareTo(a.title.length);
  });
  return list;
}

Future<Map<String, String>> _fetchTmdbTranslations({
  required MediaItem media,
  required List<String> languageCodes,
  required SettingsState settings,
}) async {
  final String tmdbId = media.externalIds['tmdb'] ?? '';
  if (tmdbId.isEmpty) {
    return const <String, String>{};
  }
  final String path = media.type == MediaType.movie
      ? '/movie/$tmdbId/translations'
      : '/tv/$tmdbId/translations';
  final Response<dynamic> response =
      await Dio(
        BaseOptions(
          baseUrl: 'https://api.themoviedb.org/3',
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 14),
        ),
      ).get<dynamic>(
        path,
        options: Options(
          headers: <String, String>{
            'Authorization': 'Bearer ${settings.tmdbReadAccessToken}',
            'accept': 'application/json',
          },
        ),
      );
  final Object? data = response.data;
  if (data is! Map<String, dynamic> || data['translations'] is! List<dynamic>) {
    return const <String, String>{};
  }
  final Map<String, String> titles = <String, String>{};
  for (final Object? item in data['translations'] as List<dynamic>) {
    if (item is! Map<String, dynamic>) {
      continue;
    }
    final String languageCode = item['iso_639_1']?.toString() ?? '';
    if (!languageCodes.contains(languageCode)) {
      continue;
    }
    final Object? translationData = item['data'];
    if (translationData is! Map<String, dynamic>) {
      continue;
    }
    final String title =
        (translationData['title'] ?? translationData['name'] ?? '').toString();
    if (title.trim().isNotEmpty) {
      titles[languageCode] = title.trim();
    }
  }
  return titles;
}

Future<Map<String, String>> _fetchTmdbSeasonTranslations({
  required MediaItem media,
  required int seasonNumber,
  required List<String> languageCodes,
  required SettingsState settings,
}) async {
  final String tmdbId = media.externalIds['tmdb'] ?? '';
  if (tmdbId.isEmpty || seasonNumber <= 0) {
    return const <String, String>{};
  }
  final Response<dynamic> response =
      await Dio(
        BaseOptions(
          baseUrl: 'https://api.themoviedb.org/3',
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 14),
        ),
      ).get<dynamic>(
        '/tv/$tmdbId/season/$seasonNumber/translations',
        options: Options(
          headers: <String, String>{
            'Authorization': 'Bearer ${settings.tmdbReadAccessToken}',
            'accept': 'application/json',
          },
        ),
      );
  final Object? data = response.data;
  if (data is! Map<String, dynamic> || data['translations'] is! List<dynamic>) {
    return const <String, String>{};
  }
  final Map<String, String> titles = <String, String>{};
  for (final Object? item in data['translations'] as List<dynamic>) {
    if (item is! Map<String, dynamic>) {
      continue;
    }
    final String languageCode = item['iso_639_1']?.toString() ?? '';
    if (!languageCodes.contains(languageCode)) {
      continue;
    }
    final Object? translationData = item['data'];
    if (translationData is! Map<String, dynamic>) {
      continue;
    }
    final String title =
        (translationData['name'] ?? translationData['title'] ?? '').toString();
    if (title.trim().isNotEmpty) {
      titles[languageCode] = title.trim();
    }
  }
  return titles;
}

Future<String> _fetchTmdbTitleForLanguage({
  required MediaItem media,
  required String language,
  required SettingsState settings,
}) async {
  final String tmdbId = media.externalIds['tmdb'] ?? '';
  if (tmdbId.isEmpty) {
    return '';
  }
  final String path = media.type == MediaType.movie
      ? '/movie/$tmdbId'
      : '/tv/$tmdbId';
  final Response<dynamic> response =
      await Dio(
        BaseOptions(
          baseUrl: 'https://api.themoviedb.org/3',
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 14),
        ),
      ).get<dynamic>(
        path,
        queryParameters: <String, String>{
          'language': language,
          'region': settings.tmdbRegion,
        },
        options: Options(
          headers: <String, String>{
            'Authorization': 'Bearer ${settings.tmdbReadAccessToken}',
            'accept': 'application/json',
          },
        ),
      );
  final Object? data = response.data;
  if (data is! Map<String, dynamic>) {
    return '';
  }
  return (data['title'] ?? data['name'] ?? '').toString().trim();
}

List<String> _queriesForLanguage({
  required List<SoraTitleVariant> variants,
  required String languageCode,
  required String fallbackTitle,
  required String fallbackOriginalTitle,
}) {
  final List<String> queries = variants
      .where((SoraTitleVariant variant) => variant.languageCode == languageCode)
      .map((SoraTitleVariant variant) => variant.title)
      .toList(growable: true);
  if (queries.isEmpty) {
    if (_textLooksLikeLanguage(fallbackTitle, languageCode)) {
      queries.add(fallbackTitle);
    }
    if (fallbackOriginalTitle != fallbackTitle &&
        _textLooksLikeLanguage(fallbackOriginalTitle, languageCode)) {
      queries.add(fallbackOriginalTitle);
    }
  }
  final Set<String> seen = <String>{};
  return queries
      .where((String query) {
        final String key = query.trim().toLowerCase();
        if (key.isEmpty || seen.contains(key)) {
          return false;
        }
        seen.add(key);
        return true;
      })
      .take(3)
      .toList(growable: false);
}

String? _realSeasonTitle(String? value, int seasonNumber) {
  final String title = value?.trim() ?? '';
  if (title.isEmpty || _isGenericSeasonName(title, seasonNumber)) {
    return null;
  }
  return title;
}

String? _combinedTitleAndSeason(String title, String seasonTitle) {
  final String trimmedTitle = title.trim();
  final String trimmedSeason = seasonTitle.trim();
  if (trimmedTitle.isEmpty || trimmedSeason.isEmpty) {
    return null;
  }
  final String normalizedTitle = _normalizedSeasonText(trimmedTitle);
  final String normalizedSeason = _normalizedSeasonText(trimmedSeason);
  if (normalizedTitle.contains(normalizedSeason) ||
      normalizedSeason.contains(normalizedTitle)) {
    return null;
  }
  return '$trimmedTitle: $trimmedSeason';
}

bool _isGenericSeasonName(String value, int seasonNumber) {
  final String normalized = _normalizedSeasonText(value);
  if (normalized.isEmpty) {
    return value.trim().isEmpty;
  }
  return normalized == 'season $seasonNumber' ||
      normalized == '$seasonNumber' ||
      normalized == 'series $seasonNumber' ||
      normalized == 's $seasonNumber' ||
      normalized == 's$seasonNumber';
}

String _normalizedSeasonText(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

int _languageIndex(List<String> languageCodes, String languageCode) {
  final int index = languageCodes.indexOf(languageCode);
  return index == -1 ? languageCodes.length : index;
}

String _detectLanguageCode(String text, String fallback) {
  if (_containsJapaneseScript(text)) {
    return 'ja';
  }
  if (_containsCyrillicScript(text)) {
    return 'ru';
  }
  if (_textLooksLikeLanguage(text, 'en')) {
    return 'en';
  }
  final String normalizedFallback = fallback.trim().toLowerCase();
  if (normalizedFallback == 'eng') return 'en';
  if (normalizedFallback == 'rus' || normalizedFallback == 'ru') return 'ru';
  if (normalizedFallback == 'jpn' || normalizedFallback == 'ja') return 'ja';
  if (normalizedFallback.length >= 2) return normalizedFallback.substring(0, 2);
  return 'en';
}

bool _textLooksLikeLanguage(String text, String languageCode) {
  final String trimmed = text.trim();
  if (trimmed.isEmpty) {
    return false;
  }
  return switch (languageCode) {
    'ru' => _containsCyrillicScript(trimmed),
    'ja' => _containsJapaneseScript(trimmed),
    'en' =>
      !_containsCyrillicScript(trimmed) && !_containsJapaneseScript(trimmed),
    _ => false,
  };
}

bool _containsJapaneseScript(String text) {
  return text.runes.any(
    (int rune) =>
        (rune >= 0x3040 && rune <= 0x30FF) ||
        (rune >= 0x3400 && rune <= 0x9FFF),
  );
}

bool _containsCyrillicScript(String text) {
  return RegExp(r'[Ѐ-ӿ]').hasMatch(text);
}

List<SoraSourceError> _uniqueErrors(List<SoraSourceError> errors) {
  final Set<String> seen = <String>{};
  return errors
      .where((SoraSourceError error) {
        final String key = '${error.addonId}|${error.message}';
        if (seen.contains(key)) {
          return false;
        }
        seen.add(key);
        return true;
      })
      .toList(growable: false);
}

String _friendlyError(Object error) {
  if (error is SoraAddonException) {
    return error.message;
  }
  return error.toString();
}

void _debugPrintTitleVariants(
  String mediaTitle,
  List<SoraTitleVariant> variants,
  List<String> languageCodes,
) {
  final List<String> codes = languageCodes.isEmpty
      ? SoraSearchLanguage.defaultPriority
      : languageCodes;
  final Map<String, List<String>> variantsByLang = <String, List<String>>{};
  for (final SoraTitleVariant v in variants) {
    variantsByLang
        .putIfAbsent(v.languageCode, () => <String>[])
        .add('"${v.title}"');
  }
  final StringBuffer sb = StringBuffer('[Sora] Find Sources - "$mediaTitle"');
  for (final String code in codes) {
    final List<String> titles = variantsByLang[code] ?? const <String>[];
    sb.write('\n  [$code] ${titles.isEmpty ? "(none)" : titles.join(", ")}');
  }
  debugPrint(sb.toString());
}
