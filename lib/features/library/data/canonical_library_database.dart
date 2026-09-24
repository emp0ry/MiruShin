import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'canonical_library_database.g.dart';

class CanonicalMediaRecords extends Table {
  TextColumn get localId => text()();
  TextColumn get mediaKind => text()();
  TextColumn get mediaJson => text()();
  IntColumn get createdAtMs => integer()();
  IntColumn get updatedAtMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{localId};
}

class MediaAliasRecords extends Table {
  TextColumn get alias => text()();
  TextColumn get localId =>
      text().references(CanonicalMediaRecords, #localId)();
  IntColumn get createdAtMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{alias};
}

class ProviderBindingRecords extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get localId =>
      text().references(CanonicalMediaRecords, #localId)();
  TextColumn get provider => text()();
  TextColumn get mediaKind => text()();
  IntColumn get externalMediaId => integer()();
  IntColumn get providerEntryId => integer().nullable()();
  TextColumn get evidence => text()();
  IntColumn get verifiedAtMs => integer()();
  BoolColumn get quarantined => boolean().withDefault(const Constant(false))();

  @override
  List<Set<Column<Object>>> get uniqueKeys => <Set<Column<Object>>>[
    <Column<Object>>{provider, mediaKind, externalMediaId},
    <Column<Object>>{localId, provider},
  ];
}

class CanonicalLibraryRecords extends Table {
  TextColumn get localId =>
      text().references(CanonicalMediaRecords, #localId)();
  BoolColumn get inLibrary => boolean().withDefault(const Constant(true))();
  TextColumn get status => text()();
  IntColumn get progress => integer().withDefault(const Constant(0))();
  IntColumn get progressVolumes => integer().withDefault(const Constant(0))();
  IntColumn get repeatCount => integer().withDefault(const Constant(0))();
  IntColumn get watchCycle => integer().withDefault(const Constant(0))();
  IntColumn get scoreRaw => integer().nullable()();
  TextColumn get scoreFormat => text().nullable()();
  TextColumn get notes => text().withDefault(const Constant(''))();
  BoolColumn get favorite => boolean().withDefault(const Constant(false))();
  IntColumn get startedYear => integer().nullable()();
  IntColumn get startedMonth => integer().nullable()();
  IntColumn get startedDay => integer().nullable()();
  IntColumn get completedYear => integer().nullable()();
  IntColumn get completedMonth => integer().nullable()();
  IntColumn get completedDay => integer().nullable()();
  TextColumn get canonicalStateJson => text()();
  TextColumn get fieldRevisionsJson =>
      text().withDefault(const Constant('{}'))();
  IntColumn get createdAtMs => integer()();
  IntColumn get updatedAtMs => integer()();
  IntColumn get tombstonedAtMs => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{localId};
}

class ProviderSnapshotRecords extends Table {
  TextColumn get snapshotId => text()();
  TextColumn get localId =>
      text().references(CanonicalMediaRecords, #localId)();
  TextColumn get provider => text()();
  TextColumn get accountId => text()();
  IntColumn get providerEntryId => integer().nullable()();
  TextColumn get normalizedJson => text()();
  TextColumn get rawJson => text()();
  TextColumn get contentHash => text()();
  IntColumn get fetchedAtMs => integer()();
  BoolColumn get completeSnapshot => boolean()();
  IntColumn get destructiveConfirmationCount =>
      integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{snapshotId};

  @override
  List<Set<Column<Object>>> get uniqueKeys => <Set<Column<Object>>>[
    <Column<Object>>{localId, provider, accountId},
  ];
}

class EpisodeStateRecords extends Table {
  TextColumn get episodeStateId => text()();
  TextColumn get localId =>
      text().references(CanonicalMediaRecords, #localId)();
  IntColumn get seasonNumber => integer()();
  RealColumn get episodeNumber => real()();
  IntColumn get positionSeconds => integer().withDefault(const Constant(0))();
  IntColumn get durationSeconds => integer().nullable()();
  BoolColumn get completed => boolean().withDefault(const Constant(false))();
  IntColumn get watchCycle => integer().withDefault(const Constant(0))();
  IntColumn get updatedAtMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{episodeStateId};

  @override
  List<Set<Column<Object>>> get uniqueKeys => <Set<Column<Object>>>[
    <Column<Object>>{localId, seasonNumber, episodeNumber, watchCycle},
  ];
}

class StreamPreferenceRecords extends Table {
  TextColumn get preferenceId => text()();
  TextColumn get localId =>
      text().references(CanonicalMediaRecords, #localId)();
  IntColumn get seasonNumber => integer().nullable()();
  RealColumn get episodeNumber => real().nullable()();
  TextColumn get addonId => text().withDefault(const Constant(''))();
  TextColumn get sourceId => text().withDefault(const Constant(''))();
  TextColumn get serverId => text().withDefault(const Constant(''))();
  TextColumn get serverTitle => text().withDefault(const Constant(''))();
  TextColumn get voiceoverId => text().withDefault(const Constant(''))();
  TextColumn get voiceoverTitle => text().withDefault(const Constant(''))();
  TextColumn get qualityId => text().withDefault(const Constant(''))();
  TextColumn get qualityLabel => text().withDefault(const Constant(''))();
  IntColumn get updatedAtMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{preferenceId};
}

class LibraryOperationRecords extends Table {
  TextColumn get operationId => text()();
  TextColumn get localId =>
      text().references(CanonicalMediaRecords, #localId)();
  TextColumn get deviceId => text()();
  TextColumn get originKind => text()();
  TextColumn get originId => text().nullable()();
  TextColumn get intent => text()();
  TextColumn get fieldsJson => text()();
  TextColumn get beforeJson => text()();
  TextColumn get afterJson => text()();
  TextColumn get baseRevisionsJson => text()();
  TextColumn get resultingRevisionsJson => text()();
  TextColumn get targetsJson => text()();
  TextColumn get undoOf => text().nullable()();
  TextColumn get title => text().nullable()();
  BoolColumn get visibleInLog => boolean().withDefault(const Constant(true))();
  IntColumn get occurredAtMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{operationId};
}

class OutboxDeliveryRecords extends Table {
  TextColumn get deliveryId => text()();
  TextColumn get operationId =>
      text().references(LibraryOperationRecords, #operationId)();
  TextColumn get target => text()();
  TextColumn get accountId => text().nullable()();
  TextColumn get state => text()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  IntColumn get nextAttemptAtMs => integer().nullable()();
  IntColumn get deliveredAtMs => integer().nullable()();
  IntColumn get confirmedAtMs => integer().nullable()();
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{deliveryId};

  @override
  List<Set<Column<Object>>> get uniqueKeys => <Set<Column<Object>>>[
    <Column<Object>>{operationId, target, accountId},
  ];
}

class LibraryConflictRecords extends Table {
  TextColumn get conflictId => text()();
  TextColumn get localId =>
      text().references(CanonicalMediaRecords, #localId)();
  TextColumn get fieldName => text()();
  TextColumn get localValueJson => text()();
  TextColumn get incomingValueJson => text()();
  TextColumn get localOperationId => text().nullable()();
  TextColumn get incomingOperationId => text().nullable()();
  TextColumn get state => text().withDefault(const Constant('open'))();
  IntColumn get createdAtMs => integer()();
  IntColumn get resolvedAtMs => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{conflictId};
}

class SyncCursorRecords extends Table {
  TextColumn get scope => text()();
  TextColumn get cursor => text()();
  TextColumn get metadataJson => text().withDefault(const Constant('{}'))();
  IntColumn get updatedAtMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{scope};
}

class ProviderHealthRecords extends Table {
  TextColumn get provider => text()();
  TextColumn get healthJson => text()();
  IntColumn get updatedAtMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{provider};
}

class LegacyBucketRecords extends Table {
  TextColumn get bucket => text()();
  TextColumn get valueJson => text()();
  IntColumn get updatedAtMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{bucket};
}

@DriftDatabase(
  tables: <Type>[
    CanonicalMediaRecords,
    MediaAliasRecords,
    ProviderBindingRecords,
    CanonicalLibraryRecords,
    ProviderSnapshotRecords,
    EpisodeStateRecords,
    StreamPreferenceRecords,
    LibraryOperationRecords,
    OutboxDeliveryRecords,
    LibraryConflictRecords,
    SyncCursorRecords,
    ProviderHealthRecords,
    LegacyBucketRecords,
  ],
)
class CanonicalLibraryDatabase extends _$CanonicalLibraryDatabase {
  CanonicalLibraryDatabase([
    QueryExecutor? executor,
    String databaseName = 'mirushin_canonical_library_v1',
  ]) : super(executor ?? _openDatabase(databaseName));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator migrator) => migrator.createAll(),
    beforeOpen: (OpeningDetails details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement('PRAGMA journal_mode = WAL');
    },
  );
}

QueryExecutor _openDatabase(String databaseName) => driftDatabase(
  name: databaseName,
  native: const DriftNativeOptions(shareAcrossIsolates: true),
  web: DriftWebOptions(
    sqlite3Wasm: Uri.parse('sqlite3.wasm'),
    driftWorker: Uri.parse('drift_worker.js'),
  ),
);
