enum CanonicalScoreFormat {
  point100('POINT_100'),
  point10Decimal('POINT_10_DECIMAL'),
  point10('POINT_10'),
  point5('POINT_5'),
  point3('POINT_3');

  const CanonicalScoreFormat(this.anilistValue);

  final String anilistValue;

  static CanonicalScoreFormat fromAniList(String? value) {
    final String normalized = (value ?? '').trim().toUpperCase();
    if (normalized == 'SMILEY') return CanonicalScoreFormat.point3;
    return CanonicalScoreFormat.values.firstWhere(
      (CanonicalScoreFormat format) => format.anilistValue == normalized,
      orElse: () => CanonicalScoreFormat.point10Decimal,
    );
  }

  int rawFromInput(num value) => switch (this) {
    CanonicalScoreFormat.point100 => value.round().clamp(0, 100),
    CanonicalScoreFormat.point10Decimal =>
      (value.toDouble() * 10).round().clamp(0, 100),
    CanonicalScoreFormat.point10 => value.round().clamp(0, 10) * 10,
    CanonicalScoreFormat.point5 => value.round().clamp(0, 5) * 20,
    CanonicalScoreFormat.point3 => switch (value.round().clamp(0, 3)) {
      1 => 35,
      2 => 60,
      3 => 85,
      _ => 0,
    },
  };

  num displayFromRaw(int rawScore) {
    final int raw = rawScore.clamp(0, 100);
    return switch (this) {
      CanonicalScoreFormat.point100 => raw,
      CanonicalScoreFormat.point10Decimal => raw / 10,
      CanonicalScoreFormat.point10 => (raw / 10).round(),
      CanonicalScoreFormat.point5 => (raw / 20).round(),
      CanonicalScoreFormat.point3 =>
        raw <= 0
            ? 0
            : raw < 48
            ? 1
            : raw < 73
            ? 2
            : 3,
    };
  }

  String displayLabel(int rawScore) {
    final num display = displayFromRaw(rawScore);
    if (this == CanonicalScoreFormat.point3) {
      return switch (display.toInt()) {
        1 => ':(',
        2 => ':|',
        3 => ':)',
        _ => '—',
      };
    }
    if (this == CanonicalScoreFormat.point5) {
      return display.toInt() <= 0 ? '—' : '${display.toInt()} ★';
    }
    if (this == CanonicalScoreFormat.point10Decimal) {
      return display.toStringAsFixed(1);
    }
    return '${display.toInt()}';
  }
}

enum LibraryOriginKind {
  user,
  player,
  provider,
  drive,
  migration,
  undo,
  system,
}

enum LibraryMutationIntent {
  add,
  edit,
  remove,
  progress,
  episodeCompleted,
  streamPreference,
  remoteImport,
  undo,
}

class LibraryOperationDraft {
  const LibraryOperationDraft({
    required this.localId,
    required this.originKind,
    required this.intent,
    required this.fields,
    required this.before,
    required this.after,
    required this.targets,
    required this.occurredAt,
    this.originId,
    this.title,
    this.undoOf,
    this.visibleInLog = true,
  });

  final String localId;
  final LibraryOriginKind originKind;
  final String? originId;
  final LibraryMutationIntent intent;
  final Set<String> fields;
  final Map<String, dynamic> before;
  final Map<String, dynamic> after;
  final Set<String> targets;
  final DateTime occurredAt;
  final String? title;
  final String? undoOf;
  final bool visibleInLog;
}

class LibraryActivityEvent {
  const LibraryActivityEvent({
    required this.operationId,
    required this.localId,
    required this.deviceId,
    required this.originKind,
    required this.intent,
    required this.fields,
    required this.before,
    required this.after,
    required this.targets,
    required this.occurredAt,
    required this.deliveryStates,
    this.originId,
    this.title,
    this.undoOf,
  });

  final String operationId;
  final String localId;
  final String deviceId;
  final LibraryOriginKind originKind;
  final String? originId;
  final LibraryMutationIntent intent;
  final Set<String> fields;
  final Map<String, dynamic> before;
  final Map<String, dynamic> after;
  final Set<String> targets;
  final DateTime occurredAt;
  final String? title;
  final String? undoOf;
  final Map<String, String> deliveryStates;
}

class LibraryUndoPreview {
  const LibraryUndoPreview({
    required this.operationId,
    required this.safeFields,
    required this.blockedFields,
    required this.before,
    required this.after,
    this.title,
  });

  final String operationId;
  final String? title;
  final Set<String> safeFields;
  final Set<String> blockedFields;
  final Map<String, dynamic> before;
  final Map<String, dynamic> after;

  bool get canUndo => safeFields.isNotEmpty;
}

class CanonicalEpisodeProgress {
  const CanonicalEpisodeProgress({
    required this.positionSeconds,
    required this.durationSeconds,
    required this.updatedAt,
    required this.completed,
    required this.watchCycle,
  });

  final int positionSeconds;
  final int? durationSeconds;
  final DateTime updatedAt;
  final bool completed;
  final int watchCycle;
}

class CanonicalStreamPreference {
  const CanonicalStreamPreference({
    this.addonId = '',
    this.sourceId = '',
    this.serverId = '',
    this.serverTitle = '',
    this.voiceoverId = '',
    this.voiceoverTitle = '',
    this.qualityId = '',
    this.qualityLabel = '',
  });

  final String addonId;
  final String sourceId;
  final String serverId;
  final String serverTitle;
  final String voiceoverId;
  final String voiceoverTitle;
  final String qualityId;
  final String qualityLabel;
}

class ProviderAccountPreview {
  const ProviderAccountPreview({
    required this.provider,
    required this.accountId,
    required this.entryCount,
    required this.localEntryCount,
    required this.createdAt,
    this.entries = const <ProviderAccountPreviewEntry>[],
  });

  final String provider;
  final String accountId;
  final int entryCount;
  final int localEntryCount;
  final DateTime createdAt;
  final List<ProviderAccountPreviewEntry> entries;
}

class ProviderAccountPreviewEntry {
  const ProviderAccountPreviewEntry({
    required this.localId,
    required this.mediaKind,
    required this.title,
    required this.changeKind,
    required this.remoteStatus,
    required this.remoteProgress,
    this.remoteScore,
    this.localStatus,
    this.localProgress,
    this.localScore,
  });

  final String localId;
  final String mediaKind;
  final String title;
  final String changeKind;
  final String remoteStatus;
  final int remoteProgress;
  final double? remoteScore;
  final String? localStatus;
  final int? localProgress;
  final double? localScore;
}

class CanonicalLibraryConflict {
  const CanonicalLibraryConflict({
    required this.conflictId,
    required this.localId,
    required this.fieldName,
    required this.localValue,
    required this.incomingValue,
    required this.createdAt,
    required this.state,
  });

  final String conflictId;
  final String localId;
  final String fieldName;
  final Object? localValue;
  final Object? incomingValue;
  final DateTime createdAt;
  final String state;

  bool get canChooseValue =>
      fieldName != 'identity' && fieldName != 'massProviderChange';
}
