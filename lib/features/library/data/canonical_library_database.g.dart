// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'canonical_library_database.dart';

// ignore_for_file: type=lint
class $CanonicalMediaRecordsTable extends CanonicalMediaRecords
    with TableInfo<$CanonicalMediaRecordsTable, CanonicalMediaRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CanonicalMediaRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _localIdMeta = const VerificationMeta(
    'localId',
  );
  @override
  late final GeneratedColumn<String> localId = GeneratedColumn<String>(
    'local_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mediaKindMeta = const VerificationMeta(
    'mediaKind',
  );
  @override
  late final GeneratedColumn<String> mediaKind = GeneratedColumn<String>(
    'media_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mediaJsonMeta = const VerificationMeta(
    'mediaJson',
  );
  @override
  late final GeneratedColumn<String> mediaJson = GeneratedColumn<String>(
    'media_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMsMeta = const VerificationMeta(
    'createdAtMs',
  );
  @override
  late final GeneratedColumn<int> createdAtMs = GeneratedColumn<int>(
    'created_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMsMeta = const VerificationMeta(
    'updatedAtMs',
  );
  @override
  late final GeneratedColumn<int> updatedAtMs = GeneratedColumn<int>(
    'updated_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    localId,
    mediaKind,
    mediaJson,
    createdAtMs,
    updatedAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'canonical_media_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<CanonicalMediaRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('local_id')) {
      context.handle(
        _localIdMeta,
        localId.isAcceptableOrUnknown(data['local_id']!, _localIdMeta),
      );
    } else if (isInserting) {
      context.missing(_localIdMeta);
    }
    if (data.containsKey('media_kind')) {
      context.handle(
        _mediaKindMeta,
        mediaKind.isAcceptableOrUnknown(data['media_kind']!, _mediaKindMeta),
      );
    } else if (isInserting) {
      context.missing(_mediaKindMeta);
    }
    if (data.containsKey('media_json')) {
      context.handle(
        _mediaJsonMeta,
        mediaJson.isAcceptableOrUnknown(data['media_json']!, _mediaJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_mediaJsonMeta);
    }
    if (data.containsKey('created_at_ms')) {
      context.handle(
        _createdAtMsMeta,
        createdAtMs.isAcceptableOrUnknown(
          data['created_at_ms']!,
          _createdAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMsMeta);
    }
    if (data.containsKey('updated_at_ms')) {
      context.handle(
        _updatedAtMsMeta,
        updatedAtMs.isAcceptableOrUnknown(
          data['updated_at_ms']!,
          _updatedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {localId};
  @override
  CanonicalMediaRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CanonicalMediaRecord(
      localId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_id'],
      )!,
      mediaKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}media_kind'],
      )!,
      mediaJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}media_json'],
      )!,
      createdAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_ms'],
      )!,
      updatedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_ms'],
      )!,
    );
  }

  @override
  $CanonicalMediaRecordsTable createAlias(String alias) {
    return $CanonicalMediaRecordsTable(attachedDatabase, alias);
  }
}

class CanonicalMediaRecord extends DataClass
    implements Insertable<CanonicalMediaRecord> {
  final String localId;
  final String mediaKind;
  final String mediaJson;
  final int createdAtMs;
  final int updatedAtMs;
  const CanonicalMediaRecord({
    required this.localId,
    required this.mediaKind,
    required this.mediaJson,
    required this.createdAtMs,
    required this.updatedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['local_id'] = Variable<String>(localId);
    map['media_kind'] = Variable<String>(mediaKind);
    map['media_json'] = Variable<String>(mediaJson);
    map['created_at_ms'] = Variable<int>(createdAtMs);
    map['updated_at_ms'] = Variable<int>(updatedAtMs);
    return map;
  }

  CanonicalMediaRecordsCompanion toCompanion(bool nullToAbsent) {
    return CanonicalMediaRecordsCompanion(
      localId: Value(localId),
      mediaKind: Value(mediaKind),
      mediaJson: Value(mediaJson),
      createdAtMs: Value(createdAtMs),
      updatedAtMs: Value(updatedAtMs),
    );
  }

  factory CanonicalMediaRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CanonicalMediaRecord(
      localId: serializer.fromJson<String>(json['localId']),
      mediaKind: serializer.fromJson<String>(json['mediaKind']),
      mediaJson: serializer.fromJson<String>(json['mediaJson']),
      createdAtMs: serializer.fromJson<int>(json['createdAtMs']),
      updatedAtMs: serializer.fromJson<int>(json['updatedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'localId': serializer.toJson<String>(localId),
      'mediaKind': serializer.toJson<String>(mediaKind),
      'mediaJson': serializer.toJson<String>(mediaJson),
      'createdAtMs': serializer.toJson<int>(createdAtMs),
      'updatedAtMs': serializer.toJson<int>(updatedAtMs),
    };
  }

  CanonicalMediaRecord copyWith({
    String? localId,
    String? mediaKind,
    String? mediaJson,
    int? createdAtMs,
    int? updatedAtMs,
  }) => CanonicalMediaRecord(
    localId: localId ?? this.localId,
    mediaKind: mediaKind ?? this.mediaKind,
    mediaJson: mediaJson ?? this.mediaJson,
    createdAtMs: createdAtMs ?? this.createdAtMs,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
  );
  CanonicalMediaRecord copyWithCompanion(CanonicalMediaRecordsCompanion data) {
    return CanonicalMediaRecord(
      localId: data.localId.present ? data.localId.value : this.localId,
      mediaKind: data.mediaKind.present ? data.mediaKind.value : this.mediaKind,
      mediaJson: data.mediaJson.present ? data.mediaJson.value : this.mediaJson,
      createdAtMs: data.createdAtMs.present
          ? data.createdAtMs.value
          : this.createdAtMs,
      updatedAtMs: data.updatedAtMs.present
          ? data.updatedAtMs.value
          : this.updatedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CanonicalMediaRecord(')
          ..write('localId: $localId, ')
          ..write('mediaKind: $mediaKind, ')
          ..write('mediaJson: $mediaJson, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('updatedAtMs: $updatedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(localId, mediaKind, mediaJson, createdAtMs, updatedAtMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CanonicalMediaRecord &&
          other.localId == this.localId &&
          other.mediaKind == this.mediaKind &&
          other.mediaJson == this.mediaJson &&
          other.createdAtMs == this.createdAtMs &&
          other.updatedAtMs == this.updatedAtMs);
}

class CanonicalMediaRecordsCompanion
    extends UpdateCompanion<CanonicalMediaRecord> {
  final Value<String> localId;
  final Value<String> mediaKind;
  final Value<String> mediaJson;
  final Value<int> createdAtMs;
  final Value<int> updatedAtMs;
  final Value<int> rowid;
  const CanonicalMediaRecordsCompanion({
    this.localId = const Value.absent(),
    this.mediaKind = const Value.absent(),
    this.mediaJson = const Value.absent(),
    this.createdAtMs = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CanonicalMediaRecordsCompanion.insert({
    required String localId,
    required String mediaKind,
    required String mediaJson,
    required int createdAtMs,
    required int updatedAtMs,
    this.rowid = const Value.absent(),
  }) : localId = Value(localId),
       mediaKind = Value(mediaKind),
       mediaJson = Value(mediaJson),
       createdAtMs = Value(createdAtMs),
       updatedAtMs = Value(updatedAtMs);
  static Insertable<CanonicalMediaRecord> custom({
    Expression<String>? localId,
    Expression<String>? mediaKind,
    Expression<String>? mediaJson,
    Expression<int>? createdAtMs,
    Expression<int>? updatedAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (localId != null) 'local_id': localId,
      if (mediaKind != null) 'media_kind': mediaKind,
      if (mediaJson != null) 'media_json': mediaJson,
      if (createdAtMs != null) 'created_at_ms': createdAtMs,
      if (updatedAtMs != null) 'updated_at_ms': updatedAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CanonicalMediaRecordsCompanion copyWith({
    Value<String>? localId,
    Value<String>? mediaKind,
    Value<String>? mediaJson,
    Value<int>? createdAtMs,
    Value<int>? updatedAtMs,
    Value<int>? rowid,
  }) {
    return CanonicalMediaRecordsCompanion(
      localId: localId ?? this.localId,
      mediaKind: mediaKind ?? this.mediaKind,
      mediaJson: mediaJson ?? this.mediaJson,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (localId.present) {
      map['local_id'] = Variable<String>(localId.value);
    }
    if (mediaKind.present) {
      map['media_kind'] = Variable<String>(mediaKind.value);
    }
    if (mediaJson.present) {
      map['media_json'] = Variable<String>(mediaJson.value);
    }
    if (createdAtMs.present) {
      map['created_at_ms'] = Variable<int>(createdAtMs.value);
    }
    if (updatedAtMs.present) {
      map['updated_at_ms'] = Variable<int>(updatedAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CanonicalMediaRecordsCompanion(')
          ..write('localId: $localId, ')
          ..write('mediaKind: $mediaKind, ')
          ..write('mediaJson: $mediaJson, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MediaAliasRecordsTable extends MediaAliasRecords
    with TableInfo<$MediaAliasRecordsTable, MediaAliasRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MediaAliasRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _aliasMeta = const VerificationMeta('alias');
  @override
  late final GeneratedColumn<String> alias = GeneratedColumn<String>(
    'alias',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localIdMeta = const VerificationMeta(
    'localId',
  );
  @override
  late final GeneratedColumn<String> localId = GeneratedColumn<String>(
    'local_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES canonical_media_records (local_id)',
    ),
  );
  static const VerificationMeta _createdAtMsMeta = const VerificationMeta(
    'createdAtMs',
  );
  @override
  late final GeneratedColumn<int> createdAtMs = GeneratedColumn<int>(
    'created_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [alias, localId, createdAtMs];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'media_alias_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<MediaAliasRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('alias')) {
      context.handle(
        _aliasMeta,
        alias.isAcceptableOrUnknown(data['alias']!, _aliasMeta),
      );
    } else if (isInserting) {
      context.missing(_aliasMeta);
    }
    if (data.containsKey('local_id')) {
      context.handle(
        _localIdMeta,
        localId.isAcceptableOrUnknown(data['local_id']!, _localIdMeta),
      );
    } else if (isInserting) {
      context.missing(_localIdMeta);
    }
    if (data.containsKey('created_at_ms')) {
      context.handle(
        _createdAtMsMeta,
        createdAtMs.isAcceptableOrUnknown(
          data['created_at_ms']!,
          _createdAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {alias};
  @override
  MediaAliasRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MediaAliasRecord(
      alias: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}alias'],
      )!,
      localId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_id'],
      )!,
      createdAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_ms'],
      )!,
    );
  }

  @override
  $MediaAliasRecordsTable createAlias(String alias) {
    return $MediaAliasRecordsTable(attachedDatabase, alias);
  }
}

class MediaAliasRecord extends DataClass
    implements Insertable<MediaAliasRecord> {
  final String alias;
  final String localId;
  final int createdAtMs;
  const MediaAliasRecord({
    required this.alias,
    required this.localId,
    required this.createdAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['alias'] = Variable<String>(alias);
    map['local_id'] = Variable<String>(localId);
    map['created_at_ms'] = Variable<int>(createdAtMs);
    return map;
  }

  MediaAliasRecordsCompanion toCompanion(bool nullToAbsent) {
    return MediaAliasRecordsCompanion(
      alias: Value(alias),
      localId: Value(localId),
      createdAtMs: Value(createdAtMs),
    );
  }

  factory MediaAliasRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MediaAliasRecord(
      alias: serializer.fromJson<String>(json['alias']),
      localId: serializer.fromJson<String>(json['localId']),
      createdAtMs: serializer.fromJson<int>(json['createdAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'alias': serializer.toJson<String>(alias),
      'localId': serializer.toJson<String>(localId),
      'createdAtMs': serializer.toJson<int>(createdAtMs),
    };
  }

  MediaAliasRecord copyWith({
    String? alias,
    String? localId,
    int? createdAtMs,
  }) => MediaAliasRecord(
    alias: alias ?? this.alias,
    localId: localId ?? this.localId,
    createdAtMs: createdAtMs ?? this.createdAtMs,
  );
  MediaAliasRecord copyWithCompanion(MediaAliasRecordsCompanion data) {
    return MediaAliasRecord(
      alias: data.alias.present ? data.alias.value : this.alias,
      localId: data.localId.present ? data.localId.value : this.localId,
      createdAtMs: data.createdAtMs.present
          ? data.createdAtMs.value
          : this.createdAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MediaAliasRecord(')
          ..write('alias: $alias, ')
          ..write('localId: $localId, ')
          ..write('createdAtMs: $createdAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(alias, localId, createdAtMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MediaAliasRecord &&
          other.alias == this.alias &&
          other.localId == this.localId &&
          other.createdAtMs == this.createdAtMs);
}

class MediaAliasRecordsCompanion extends UpdateCompanion<MediaAliasRecord> {
  final Value<String> alias;
  final Value<String> localId;
  final Value<int> createdAtMs;
  final Value<int> rowid;
  const MediaAliasRecordsCompanion({
    this.alias = const Value.absent(),
    this.localId = const Value.absent(),
    this.createdAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MediaAliasRecordsCompanion.insert({
    required String alias,
    required String localId,
    required int createdAtMs,
    this.rowid = const Value.absent(),
  }) : alias = Value(alias),
       localId = Value(localId),
       createdAtMs = Value(createdAtMs);
  static Insertable<MediaAliasRecord> custom({
    Expression<String>? alias,
    Expression<String>? localId,
    Expression<int>? createdAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (alias != null) 'alias': alias,
      if (localId != null) 'local_id': localId,
      if (createdAtMs != null) 'created_at_ms': createdAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MediaAliasRecordsCompanion copyWith({
    Value<String>? alias,
    Value<String>? localId,
    Value<int>? createdAtMs,
    Value<int>? rowid,
  }) {
    return MediaAliasRecordsCompanion(
      alias: alias ?? this.alias,
      localId: localId ?? this.localId,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (alias.present) {
      map['alias'] = Variable<String>(alias.value);
    }
    if (localId.present) {
      map['local_id'] = Variable<String>(localId.value);
    }
    if (createdAtMs.present) {
      map['created_at_ms'] = Variable<int>(createdAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MediaAliasRecordsCompanion(')
          ..write('alias: $alias, ')
          ..write('localId: $localId, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProviderBindingRecordsTable extends ProviderBindingRecords
    with TableInfo<$ProviderBindingRecordsTable, ProviderBindingRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProviderBindingRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _localIdMeta = const VerificationMeta(
    'localId',
  );
  @override
  late final GeneratedColumn<String> localId = GeneratedColumn<String>(
    'local_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES canonical_media_records (local_id)',
    ),
  );
  static const VerificationMeta _providerMeta = const VerificationMeta(
    'provider',
  );
  @override
  late final GeneratedColumn<String> provider = GeneratedColumn<String>(
    'provider',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mediaKindMeta = const VerificationMeta(
    'mediaKind',
  );
  @override
  late final GeneratedColumn<String> mediaKind = GeneratedColumn<String>(
    'media_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _externalMediaIdMeta = const VerificationMeta(
    'externalMediaId',
  );
  @override
  late final GeneratedColumn<int> externalMediaId = GeneratedColumn<int>(
    'external_media_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _providerEntryIdMeta = const VerificationMeta(
    'providerEntryId',
  );
  @override
  late final GeneratedColumn<int> providerEntryId = GeneratedColumn<int>(
    'provider_entry_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _evidenceMeta = const VerificationMeta(
    'evidence',
  );
  @override
  late final GeneratedColumn<String> evidence = GeneratedColumn<String>(
    'evidence',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _verifiedAtMsMeta = const VerificationMeta(
    'verifiedAtMs',
  );
  @override
  late final GeneratedColumn<int> verifiedAtMs = GeneratedColumn<int>(
    'verified_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _quarantinedMeta = const VerificationMeta(
    'quarantined',
  );
  @override
  late final GeneratedColumn<bool> quarantined = GeneratedColumn<bool>(
    'quarantined',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("quarantined" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    localId,
    provider,
    mediaKind,
    externalMediaId,
    providerEntryId,
    evidence,
    verifiedAtMs,
    quarantined,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'provider_binding_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProviderBindingRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('local_id')) {
      context.handle(
        _localIdMeta,
        localId.isAcceptableOrUnknown(data['local_id']!, _localIdMeta),
      );
    } else if (isInserting) {
      context.missing(_localIdMeta);
    }
    if (data.containsKey('provider')) {
      context.handle(
        _providerMeta,
        provider.isAcceptableOrUnknown(data['provider']!, _providerMeta),
      );
    } else if (isInserting) {
      context.missing(_providerMeta);
    }
    if (data.containsKey('media_kind')) {
      context.handle(
        _mediaKindMeta,
        mediaKind.isAcceptableOrUnknown(data['media_kind']!, _mediaKindMeta),
      );
    } else if (isInserting) {
      context.missing(_mediaKindMeta);
    }
    if (data.containsKey('external_media_id')) {
      context.handle(
        _externalMediaIdMeta,
        externalMediaId.isAcceptableOrUnknown(
          data['external_media_id']!,
          _externalMediaIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_externalMediaIdMeta);
    }
    if (data.containsKey('provider_entry_id')) {
      context.handle(
        _providerEntryIdMeta,
        providerEntryId.isAcceptableOrUnknown(
          data['provider_entry_id']!,
          _providerEntryIdMeta,
        ),
      );
    }
    if (data.containsKey('evidence')) {
      context.handle(
        _evidenceMeta,
        evidence.isAcceptableOrUnknown(data['evidence']!, _evidenceMeta),
      );
    } else if (isInserting) {
      context.missing(_evidenceMeta);
    }
    if (data.containsKey('verified_at_ms')) {
      context.handle(
        _verifiedAtMsMeta,
        verifiedAtMs.isAcceptableOrUnknown(
          data['verified_at_ms']!,
          _verifiedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_verifiedAtMsMeta);
    }
    if (data.containsKey('quarantined')) {
      context.handle(
        _quarantinedMeta,
        quarantined.isAcceptableOrUnknown(
          data['quarantined']!,
          _quarantinedMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {provider, mediaKind, externalMediaId},
    {localId, provider},
  ];
  @override
  ProviderBindingRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProviderBindingRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      localId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_id'],
      )!,
      provider: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provider'],
      )!,
      mediaKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}media_kind'],
      )!,
      externalMediaId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}external_media_id'],
      )!,
      providerEntryId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}provider_entry_id'],
      ),
      evidence: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}evidence'],
      )!,
      verifiedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}verified_at_ms'],
      )!,
      quarantined: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}quarantined'],
      )!,
    );
  }

  @override
  $ProviderBindingRecordsTable createAlias(String alias) {
    return $ProviderBindingRecordsTable(attachedDatabase, alias);
  }
}

class ProviderBindingRecord extends DataClass
    implements Insertable<ProviderBindingRecord> {
  final int id;
  final String localId;
  final String provider;
  final String mediaKind;
  final int externalMediaId;
  final int? providerEntryId;
  final String evidence;
  final int verifiedAtMs;
  final bool quarantined;
  const ProviderBindingRecord({
    required this.id,
    required this.localId,
    required this.provider,
    required this.mediaKind,
    required this.externalMediaId,
    this.providerEntryId,
    required this.evidence,
    required this.verifiedAtMs,
    required this.quarantined,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['local_id'] = Variable<String>(localId);
    map['provider'] = Variable<String>(provider);
    map['media_kind'] = Variable<String>(mediaKind);
    map['external_media_id'] = Variable<int>(externalMediaId);
    if (!nullToAbsent || providerEntryId != null) {
      map['provider_entry_id'] = Variable<int>(providerEntryId);
    }
    map['evidence'] = Variable<String>(evidence);
    map['verified_at_ms'] = Variable<int>(verifiedAtMs);
    map['quarantined'] = Variable<bool>(quarantined);
    return map;
  }

  ProviderBindingRecordsCompanion toCompanion(bool nullToAbsent) {
    return ProviderBindingRecordsCompanion(
      id: Value(id),
      localId: Value(localId),
      provider: Value(provider),
      mediaKind: Value(mediaKind),
      externalMediaId: Value(externalMediaId),
      providerEntryId: providerEntryId == null && nullToAbsent
          ? const Value.absent()
          : Value(providerEntryId),
      evidence: Value(evidence),
      verifiedAtMs: Value(verifiedAtMs),
      quarantined: Value(quarantined),
    );
  }

  factory ProviderBindingRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProviderBindingRecord(
      id: serializer.fromJson<int>(json['id']),
      localId: serializer.fromJson<String>(json['localId']),
      provider: serializer.fromJson<String>(json['provider']),
      mediaKind: serializer.fromJson<String>(json['mediaKind']),
      externalMediaId: serializer.fromJson<int>(json['externalMediaId']),
      providerEntryId: serializer.fromJson<int?>(json['providerEntryId']),
      evidence: serializer.fromJson<String>(json['evidence']),
      verifiedAtMs: serializer.fromJson<int>(json['verifiedAtMs']),
      quarantined: serializer.fromJson<bool>(json['quarantined']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'localId': serializer.toJson<String>(localId),
      'provider': serializer.toJson<String>(provider),
      'mediaKind': serializer.toJson<String>(mediaKind),
      'externalMediaId': serializer.toJson<int>(externalMediaId),
      'providerEntryId': serializer.toJson<int?>(providerEntryId),
      'evidence': serializer.toJson<String>(evidence),
      'verifiedAtMs': serializer.toJson<int>(verifiedAtMs),
      'quarantined': serializer.toJson<bool>(quarantined),
    };
  }

  ProviderBindingRecord copyWith({
    int? id,
    String? localId,
    String? provider,
    String? mediaKind,
    int? externalMediaId,
    Value<int?> providerEntryId = const Value.absent(),
    String? evidence,
    int? verifiedAtMs,
    bool? quarantined,
  }) => ProviderBindingRecord(
    id: id ?? this.id,
    localId: localId ?? this.localId,
    provider: provider ?? this.provider,
    mediaKind: mediaKind ?? this.mediaKind,
    externalMediaId: externalMediaId ?? this.externalMediaId,
    providerEntryId: providerEntryId.present
        ? providerEntryId.value
        : this.providerEntryId,
    evidence: evidence ?? this.evidence,
    verifiedAtMs: verifiedAtMs ?? this.verifiedAtMs,
    quarantined: quarantined ?? this.quarantined,
  );
  ProviderBindingRecord copyWithCompanion(
    ProviderBindingRecordsCompanion data,
  ) {
    return ProviderBindingRecord(
      id: data.id.present ? data.id.value : this.id,
      localId: data.localId.present ? data.localId.value : this.localId,
      provider: data.provider.present ? data.provider.value : this.provider,
      mediaKind: data.mediaKind.present ? data.mediaKind.value : this.mediaKind,
      externalMediaId: data.externalMediaId.present
          ? data.externalMediaId.value
          : this.externalMediaId,
      providerEntryId: data.providerEntryId.present
          ? data.providerEntryId.value
          : this.providerEntryId,
      evidence: data.evidence.present ? data.evidence.value : this.evidence,
      verifiedAtMs: data.verifiedAtMs.present
          ? data.verifiedAtMs.value
          : this.verifiedAtMs,
      quarantined: data.quarantined.present
          ? data.quarantined.value
          : this.quarantined,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProviderBindingRecord(')
          ..write('id: $id, ')
          ..write('localId: $localId, ')
          ..write('provider: $provider, ')
          ..write('mediaKind: $mediaKind, ')
          ..write('externalMediaId: $externalMediaId, ')
          ..write('providerEntryId: $providerEntryId, ')
          ..write('evidence: $evidence, ')
          ..write('verifiedAtMs: $verifiedAtMs, ')
          ..write('quarantined: $quarantined')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    localId,
    provider,
    mediaKind,
    externalMediaId,
    providerEntryId,
    evidence,
    verifiedAtMs,
    quarantined,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProviderBindingRecord &&
          other.id == this.id &&
          other.localId == this.localId &&
          other.provider == this.provider &&
          other.mediaKind == this.mediaKind &&
          other.externalMediaId == this.externalMediaId &&
          other.providerEntryId == this.providerEntryId &&
          other.evidence == this.evidence &&
          other.verifiedAtMs == this.verifiedAtMs &&
          other.quarantined == this.quarantined);
}

class ProviderBindingRecordsCompanion
    extends UpdateCompanion<ProviderBindingRecord> {
  final Value<int> id;
  final Value<String> localId;
  final Value<String> provider;
  final Value<String> mediaKind;
  final Value<int> externalMediaId;
  final Value<int?> providerEntryId;
  final Value<String> evidence;
  final Value<int> verifiedAtMs;
  final Value<bool> quarantined;
  const ProviderBindingRecordsCompanion({
    this.id = const Value.absent(),
    this.localId = const Value.absent(),
    this.provider = const Value.absent(),
    this.mediaKind = const Value.absent(),
    this.externalMediaId = const Value.absent(),
    this.providerEntryId = const Value.absent(),
    this.evidence = const Value.absent(),
    this.verifiedAtMs = const Value.absent(),
    this.quarantined = const Value.absent(),
  });
  ProviderBindingRecordsCompanion.insert({
    this.id = const Value.absent(),
    required String localId,
    required String provider,
    required String mediaKind,
    required int externalMediaId,
    this.providerEntryId = const Value.absent(),
    required String evidence,
    required int verifiedAtMs,
    this.quarantined = const Value.absent(),
  }) : localId = Value(localId),
       provider = Value(provider),
       mediaKind = Value(mediaKind),
       externalMediaId = Value(externalMediaId),
       evidence = Value(evidence),
       verifiedAtMs = Value(verifiedAtMs);
  static Insertable<ProviderBindingRecord> custom({
    Expression<int>? id,
    Expression<String>? localId,
    Expression<String>? provider,
    Expression<String>? mediaKind,
    Expression<int>? externalMediaId,
    Expression<int>? providerEntryId,
    Expression<String>? evidence,
    Expression<int>? verifiedAtMs,
    Expression<bool>? quarantined,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (localId != null) 'local_id': localId,
      if (provider != null) 'provider': provider,
      if (mediaKind != null) 'media_kind': mediaKind,
      if (externalMediaId != null) 'external_media_id': externalMediaId,
      if (providerEntryId != null) 'provider_entry_id': providerEntryId,
      if (evidence != null) 'evidence': evidence,
      if (verifiedAtMs != null) 'verified_at_ms': verifiedAtMs,
      if (quarantined != null) 'quarantined': quarantined,
    });
  }

  ProviderBindingRecordsCompanion copyWith({
    Value<int>? id,
    Value<String>? localId,
    Value<String>? provider,
    Value<String>? mediaKind,
    Value<int>? externalMediaId,
    Value<int?>? providerEntryId,
    Value<String>? evidence,
    Value<int>? verifiedAtMs,
    Value<bool>? quarantined,
  }) {
    return ProviderBindingRecordsCompanion(
      id: id ?? this.id,
      localId: localId ?? this.localId,
      provider: provider ?? this.provider,
      mediaKind: mediaKind ?? this.mediaKind,
      externalMediaId: externalMediaId ?? this.externalMediaId,
      providerEntryId: providerEntryId ?? this.providerEntryId,
      evidence: evidence ?? this.evidence,
      verifiedAtMs: verifiedAtMs ?? this.verifiedAtMs,
      quarantined: quarantined ?? this.quarantined,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (localId.present) {
      map['local_id'] = Variable<String>(localId.value);
    }
    if (provider.present) {
      map['provider'] = Variable<String>(provider.value);
    }
    if (mediaKind.present) {
      map['media_kind'] = Variable<String>(mediaKind.value);
    }
    if (externalMediaId.present) {
      map['external_media_id'] = Variable<int>(externalMediaId.value);
    }
    if (providerEntryId.present) {
      map['provider_entry_id'] = Variable<int>(providerEntryId.value);
    }
    if (evidence.present) {
      map['evidence'] = Variable<String>(evidence.value);
    }
    if (verifiedAtMs.present) {
      map['verified_at_ms'] = Variable<int>(verifiedAtMs.value);
    }
    if (quarantined.present) {
      map['quarantined'] = Variable<bool>(quarantined.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProviderBindingRecordsCompanion(')
          ..write('id: $id, ')
          ..write('localId: $localId, ')
          ..write('provider: $provider, ')
          ..write('mediaKind: $mediaKind, ')
          ..write('externalMediaId: $externalMediaId, ')
          ..write('providerEntryId: $providerEntryId, ')
          ..write('evidence: $evidence, ')
          ..write('verifiedAtMs: $verifiedAtMs, ')
          ..write('quarantined: $quarantined')
          ..write(')'))
        .toString();
  }
}

class $CanonicalLibraryRecordsTable extends CanonicalLibraryRecords
    with TableInfo<$CanonicalLibraryRecordsTable, CanonicalLibraryRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CanonicalLibraryRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _localIdMeta = const VerificationMeta(
    'localId',
  );
  @override
  late final GeneratedColumn<String> localId = GeneratedColumn<String>(
    'local_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES canonical_media_records (local_id)',
    ),
  );
  static const VerificationMeta _inLibraryMeta = const VerificationMeta(
    'inLibrary',
  );
  @override
  late final GeneratedColumn<bool> inLibrary = GeneratedColumn<bool>(
    'in_library',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("in_library" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _progressMeta = const VerificationMeta(
    'progress',
  );
  @override
  late final GeneratedColumn<int> progress = GeneratedColumn<int>(
    'progress',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _progressVolumesMeta = const VerificationMeta(
    'progressVolumes',
  );
  @override
  late final GeneratedColumn<int> progressVolumes = GeneratedColumn<int>(
    'progress_volumes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _repeatCountMeta = const VerificationMeta(
    'repeatCount',
  );
  @override
  late final GeneratedColumn<int> repeatCount = GeneratedColumn<int>(
    'repeat_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _watchCycleMeta = const VerificationMeta(
    'watchCycle',
  );
  @override
  late final GeneratedColumn<int> watchCycle = GeneratedColumn<int>(
    'watch_cycle',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _scoreRawMeta = const VerificationMeta(
    'scoreRaw',
  );
  @override
  late final GeneratedColumn<int> scoreRaw = GeneratedColumn<int>(
    'score_raw',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _scoreFormatMeta = const VerificationMeta(
    'scoreFormat',
  );
  @override
  late final GeneratedColumn<String> scoreFormat = GeneratedColumn<String>(
    'score_format',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _favoriteMeta = const VerificationMeta(
    'favorite',
  );
  @override
  late final GeneratedColumn<bool> favorite = GeneratedColumn<bool>(
    'favorite',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("favorite" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _startedYearMeta = const VerificationMeta(
    'startedYear',
  );
  @override
  late final GeneratedColumn<int> startedYear = GeneratedColumn<int>(
    'started_year',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _startedMonthMeta = const VerificationMeta(
    'startedMonth',
  );
  @override
  late final GeneratedColumn<int> startedMonth = GeneratedColumn<int>(
    'started_month',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _startedDayMeta = const VerificationMeta(
    'startedDay',
  );
  @override
  late final GeneratedColumn<int> startedDay = GeneratedColumn<int>(
    'started_day',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _completedYearMeta = const VerificationMeta(
    'completedYear',
  );
  @override
  late final GeneratedColumn<int> completedYear = GeneratedColumn<int>(
    'completed_year',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _completedMonthMeta = const VerificationMeta(
    'completedMonth',
  );
  @override
  late final GeneratedColumn<int> completedMonth = GeneratedColumn<int>(
    'completed_month',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _completedDayMeta = const VerificationMeta(
    'completedDay',
  );
  @override
  late final GeneratedColumn<int> completedDay = GeneratedColumn<int>(
    'completed_day',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _canonicalStateJsonMeta =
      const VerificationMeta('canonicalStateJson');
  @override
  late final GeneratedColumn<String> canonicalStateJson =
      GeneratedColumn<String>(
        'canonical_state_json',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _fieldRevisionsJsonMeta =
      const VerificationMeta('fieldRevisionsJson');
  @override
  late final GeneratedColumn<String> fieldRevisionsJson =
      GeneratedColumn<String>(
        'field_revisions_json',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('{}'),
      );
  static const VerificationMeta _createdAtMsMeta = const VerificationMeta(
    'createdAtMs',
  );
  @override
  late final GeneratedColumn<int> createdAtMs = GeneratedColumn<int>(
    'created_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMsMeta = const VerificationMeta(
    'updatedAtMs',
  );
  @override
  late final GeneratedColumn<int> updatedAtMs = GeneratedColumn<int>(
    'updated_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tombstonedAtMsMeta = const VerificationMeta(
    'tombstonedAtMs',
  );
  @override
  late final GeneratedColumn<int> tombstonedAtMs = GeneratedColumn<int>(
    'tombstoned_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    localId,
    inLibrary,
    status,
    progress,
    progressVolumes,
    repeatCount,
    watchCycle,
    scoreRaw,
    scoreFormat,
    notes,
    favorite,
    startedYear,
    startedMonth,
    startedDay,
    completedYear,
    completedMonth,
    completedDay,
    canonicalStateJson,
    fieldRevisionsJson,
    createdAtMs,
    updatedAtMs,
    tombstonedAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'canonical_library_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<CanonicalLibraryRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('local_id')) {
      context.handle(
        _localIdMeta,
        localId.isAcceptableOrUnknown(data['local_id']!, _localIdMeta),
      );
    } else if (isInserting) {
      context.missing(_localIdMeta);
    }
    if (data.containsKey('in_library')) {
      context.handle(
        _inLibraryMeta,
        inLibrary.isAcceptableOrUnknown(data['in_library']!, _inLibraryMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('progress')) {
      context.handle(
        _progressMeta,
        progress.isAcceptableOrUnknown(data['progress']!, _progressMeta),
      );
    }
    if (data.containsKey('progress_volumes')) {
      context.handle(
        _progressVolumesMeta,
        progressVolumes.isAcceptableOrUnknown(
          data['progress_volumes']!,
          _progressVolumesMeta,
        ),
      );
    }
    if (data.containsKey('repeat_count')) {
      context.handle(
        _repeatCountMeta,
        repeatCount.isAcceptableOrUnknown(
          data['repeat_count']!,
          _repeatCountMeta,
        ),
      );
    }
    if (data.containsKey('watch_cycle')) {
      context.handle(
        _watchCycleMeta,
        watchCycle.isAcceptableOrUnknown(data['watch_cycle']!, _watchCycleMeta),
      );
    }
    if (data.containsKey('score_raw')) {
      context.handle(
        _scoreRawMeta,
        scoreRaw.isAcceptableOrUnknown(data['score_raw']!, _scoreRawMeta),
      );
    }
    if (data.containsKey('score_format')) {
      context.handle(
        _scoreFormatMeta,
        scoreFormat.isAcceptableOrUnknown(
          data['score_format']!,
          _scoreFormatMeta,
        ),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('favorite')) {
      context.handle(
        _favoriteMeta,
        favorite.isAcceptableOrUnknown(data['favorite']!, _favoriteMeta),
      );
    }
    if (data.containsKey('started_year')) {
      context.handle(
        _startedYearMeta,
        startedYear.isAcceptableOrUnknown(
          data['started_year']!,
          _startedYearMeta,
        ),
      );
    }
    if (data.containsKey('started_month')) {
      context.handle(
        _startedMonthMeta,
        startedMonth.isAcceptableOrUnknown(
          data['started_month']!,
          _startedMonthMeta,
        ),
      );
    }
    if (data.containsKey('started_day')) {
      context.handle(
        _startedDayMeta,
        startedDay.isAcceptableOrUnknown(data['started_day']!, _startedDayMeta),
      );
    }
    if (data.containsKey('completed_year')) {
      context.handle(
        _completedYearMeta,
        completedYear.isAcceptableOrUnknown(
          data['completed_year']!,
          _completedYearMeta,
        ),
      );
    }
    if (data.containsKey('completed_month')) {
      context.handle(
        _completedMonthMeta,
        completedMonth.isAcceptableOrUnknown(
          data['completed_month']!,
          _completedMonthMeta,
        ),
      );
    }
    if (data.containsKey('completed_day')) {
      context.handle(
        _completedDayMeta,
        completedDay.isAcceptableOrUnknown(
          data['completed_day']!,
          _completedDayMeta,
        ),
      );
    }
    if (data.containsKey('canonical_state_json')) {
      context.handle(
        _canonicalStateJsonMeta,
        canonicalStateJson.isAcceptableOrUnknown(
          data['canonical_state_json']!,
          _canonicalStateJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_canonicalStateJsonMeta);
    }
    if (data.containsKey('field_revisions_json')) {
      context.handle(
        _fieldRevisionsJsonMeta,
        fieldRevisionsJson.isAcceptableOrUnknown(
          data['field_revisions_json']!,
          _fieldRevisionsJsonMeta,
        ),
      );
    }
    if (data.containsKey('created_at_ms')) {
      context.handle(
        _createdAtMsMeta,
        createdAtMs.isAcceptableOrUnknown(
          data['created_at_ms']!,
          _createdAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMsMeta);
    }
    if (data.containsKey('updated_at_ms')) {
      context.handle(
        _updatedAtMsMeta,
        updatedAtMs.isAcceptableOrUnknown(
          data['updated_at_ms']!,
          _updatedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMsMeta);
    }
    if (data.containsKey('tombstoned_at_ms')) {
      context.handle(
        _tombstonedAtMsMeta,
        tombstonedAtMs.isAcceptableOrUnknown(
          data['tombstoned_at_ms']!,
          _tombstonedAtMsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {localId};
  @override
  CanonicalLibraryRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CanonicalLibraryRecord(
      localId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_id'],
      )!,
      inLibrary: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}in_library'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      progress: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}progress'],
      )!,
      progressVolumes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}progress_volumes'],
      )!,
      repeatCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}repeat_count'],
      )!,
      watchCycle: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}watch_cycle'],
      )!,
      scoreRaw: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}score_raw'],
      ),
      scoreFormat: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}score_format'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      )!,
      favorite: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}favorite'],
      )!,
      startedYear: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}started_year'],
      ),
      startedMonth: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}started_month'],
      ),
      startedDay: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}started_day'],
      ),
      completedYear: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}completed_year'],
      ),
      completedMonth: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}completed_month'],
      ),
      completedDay: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}completed_day'],
      ),
      canonicalStateJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}canonical_state_json'],
      )!,
      fieldRevisionsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}field_revisions_json'],
      )!,
      createdAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_ms'],
      )!,
      updatedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_ms'],
      )!,
      tombstonedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}tombstoned_at_ms'],
      ),
    );
  }

  @override
  $CanonicalLibraryRecordsTable createAlias(String alias) {
    return $CanonicalLibraryRecordsTable(attachedDatabase, alias);
  }
}

class CanonicalLibraryRecord extends DataClass
    implements Insertable<CanonicalLibraryRecord> {
  final String localId;
  final bool inLibrary;
  final String status;
  final int progress;
  final int progressVolumes;
  final int repeatCount;
  final int watchCycle;
  final int? scoreRaw;
  final String? scoreFormat;
  final String notes;
  final bool favorite;
  final int? startedYear;
  final int? startedMonth;
  final int? startedDay;
  final int? completedYear;
  final int? completedMonth;
  final int? completedDay;
  final String canonicalStateJson;
  final String fieldRevisionsJson;
  final int createdAtMs;
  final int updatedAtMs;
  final int? tombstonedAtMs;
  const CanonicalLibraryRecord({
    required this.localId,
    required this.inLibrary,
    required this.status,
    required this.progress,
    required this.progressVolumes,
    required this.repeatCount,
    required this.watchCycle,
    this.scoreRaw,
    this.scoreFormat,
    required this.notes,
    required this.favorite,
    this.startedYear,
    this.startedMonth,
    this.startedDay,
    this.completedYear,
    this.completedMonth,
    this.completedDay,
    required this.canonicalStateJson,
    required this.fieldRevisionsJson,
    required this.createdAtMs,
    required this.updatedAtMs,
    this.tombstonedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['local_id'] = Variable<String>(localId);
    map['in_library'] = Variable<bool>(inLibrary);
    map['status'] = Variable<String>(status);
    map['progress'] = Variable<int>(progress);
    map['progress_volumes'] = Variable<int>(progressVolumes);
    map['repeat_count'] = Variable<int>(repeatCount);
    map['watch_cycle'] = Variable<int>(watchCycle);
    if (!nullToAbsent || scoreRaw != null) {
      map['score_raw'] = Variable<int>(scoreRaw);
    }
    if (!nullToAbsent || scoreFormat != null) {
      map['score_format'] = Variable<String>(scoreFormat);
    }
    map['notes'] = Variable<String>(notes);
    map['favorite'] = Variable<bool>(favorite);
    if (!nullToAbsent || startedYear != null) {
      map['started_year'] = Variable<int>(startedYear);
    }
    if (!nullToAbsent || startedMonth != null) {
      map['started_month'] = Variable<int>(startedMonth);
    }
    if (!nullToAbsent || startedDay != null) {
      map['started_day'] = Variable<int>(startedDay);
    }
    if (!nullToAbsent || completedYear != null) {
      map['completed_year'] = Variable<int>(completedYear);
    }
    if (!nullToAbsent || completedMonth != null) {
      map['completed_month'] = Variable<int>(completedMonth);
    }
    if (!nullToAbsent || completedDay != null) {
      map['completed_day'] = Variable<int>(completedDay);
    }
    map['canonical_state_json'] = Variable<String>(canonicalStateJson);
    map['field_revisions_json'] = Variable<String>(fieldRevisionsJson);
    map['created_at_ms'] = Variable<int>(createdAtMs);
    map['updated_at_ms'] = Variable<int>(updatedAtMs);
    if (!nullToAbsent || tombstonedAtMs != null) {
      map['tombstoned_at_ms'] = Variable<int>(tombstonedAtMs);
    }
    return map;
  }

  CanonicalLibraryRecordsCompanion toCompanion(bool nullToAbsent) {
    return CanonicalLibraryRecordsCompanion(
      localId: Value(localId),
      inLibrary: Value(inLibrary),
      status: Value(status),
      progress: Value(progress),
      progressVolumes: Value(progressVolumes),
      repeatCount: Value(repeatCount),
      watchCycle: Value(watchCycle),
      scoreRaw: scoreRaw == null && nullToAbsent
          ? const Value.absent()
          : Value(scoreRaw),
      scoreFormat: scoreFormat == null && nullToAbsent
          ? const Value.absent()
          : Value(scoreFormat),
      notes: Value(notes),
      favorite: Value(favorite),
      startedYear: startedYear == null && nullToAbsent
          ? const Value.absent()
          : Value(startedYear),
      startedMonth: startedMonth == null && nullToAbsent
          ? const Value.absent()
          : Value(startedMonth),
      startedDay: startedDay == null && nullToAbsent
          ? const Value.absent()
          : Value(startedDay),
      completedYear: completedYear == null && nullToAbsent
          ? const Value.absent()
          : Value(completedYear),
      completedMonth: completedMonth == null && nullToAbsent
          ? const Value.absent()
          : Value(completedMonth),
      completedDay: completedDay == null && nullToAbsent
          ? const Value.absent()
          : Value(completedDay),
      canonicalStateJson: Value(canonicalStateJson),
      fieldRevisionsJson: Value(fieldRevisionsJson),
      createdAtMs: Value(createdAtMs),
      updatedAtMs: Value(updatedAtMs),
      tombstonedAtMs: tombstonedAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(tombstonedAtMs),
    );
  }

  factory CanonicalLibraryRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CanonicalLibraryRecord(
      localId: serializer.fromJson<String>(json['localId']),
      inLibrary: serializer.fromJson<bool>(json['inLibrary']),
      status: serializer.fromJson<String>(json['status']),
      progress: serializer.fromJson<int>(json['progress']),
      progressVolumes: serializer.fromJson<int>(json['progressVolumes']),
      repeatCount: serializer.fromJson<int>(json['repeatCount']),
      watchCycle: serializer.fromJson<int>(json['watchCycle']),
      scoreRaw: serializer.fromJson<int?>(json['scoreRaw']),
      scoreFormat: serializer.fromJson<String?>(json['scoreFormat']),
      notes: serializer.fromJson<String>(json['notes']),
      favorite: serializer.fromJson<bool>(json['favorite']),
      startedYear: serializer.fromJson<int?>(json['startedYear']),
      startedMonth: serializer.fromJson<int?>(json['startedMonth']),
      startedDay: serializer.fromJson<int?>(json['startedDay']),
      completedYear: serializer.fromJson<int?>(json['completedYear']),
      completedMonth: serializer.fromJson<int?>(json['completedMonth']),
      completedDay: serializer.fromJson<int?>(json['completedDay']),
      canonicalStateJson: serializer.fromJson<String>(
        json['canonicalStateJson'],
      ),
      fieldRevisionsJson: serializer.fromJson<String>(
        json['fieldRevisionsJson'],
      ),
      createdAtMs: serializer.fromJson<int>(json['createdAtMs']),
      updatedAtMs: serializer.fromJson<int>(json['updatedAtMs']),
      tombstonedAtMs: serializer.fromJson<int?>(json['tombstonedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'localId': serializer.toJson<String>(localId),
      'inLibrary': serializer.toJson<bool>(inLibrary),
      'status': serializer.toJson<String>(status),
      'progress': serializer.toJson<int>(progress),
      'progressVolumes': serializer.toJson<int>(progressVolumes),
      'repeatCount': serializer.toJson<int>(repeatCount),
      'watchCycle': serializer.toJson<int>(watchCycle),
      'scoreRaw': serializer.toJson<int?>(scoreRaw),
      'scoreFormat': serializer.toJson<String?>(scoreFormat),
      'notes': serializer.toJson<String>(notes),
      'favorite': serializer.toJson<bool>(favorite),
      'startedYear': serializer.toJson<int?>(startedYear),
      'startedMonth': serializer.toJson<int?>(startedMonth),
      'startedDay': serializer.toJson<int?>(startedDay),
      'completedYear': serializer.toJson<int?>(completedYear),
      'completedMonth': serializer.toJson<int?>(completedMonth),
      'completedDay': serializer.toJson<int?>(completedDay),
      'canonicalStateJson': serializer.toJson<String>(canonicalStateJson),
      'fieldRevisionsJson': serializer.toJson<String>(fieldRevisionsJson),
      'createdAtMs': serializer.toJson<int>(createdAtMs),
      'updatedAtMs': serializer.toJson<int>(updatedAtMs),
      'tombstonedAtMs': serializer.toJson<int?>(tombstonedAtMs),
    };
  }

  CanonicalLibraryRecord copyWith({
    String? localId,
    bool? inLibrary,
    String? status,
    int? progress,
    int? progressVolumes,
    int? repeatCount,
    int? watchCycle,
    Value<int?> scoreRaw = const Value.absent(),
    Value<String?> scoreFormat = const Value.absent(),
    String? notes,
    bool? favorite,
    Value<int?> startedYear = const Value.absent(),
    Value<int?> startedMonth = const Value.absent(),
    Value<int?> startedDay = const Value.absent(),
    Value<int?> completedYear = const Value.absent(),
    Value<int?> completedMonth = const Value.absent(),
    Value<int?> completedDay = const Value.absent(),
    String? canonicalStateJson,
    String? fieldRevisionsJson,
    int? createdAtMs,
    int? updatedAtMs,
    Value<int?> tombstonedAtMs = const Value.absent(),
  }) => CanonicalLibraryRecord(
    localId: localId ?? this.localId,
    inLibrary: inLibrary ?? this.inLibrary,
    status: status ?? this.status,
    progress: progress ?? this.progress,
    progressVolumes: progressVolumes ?? this.progressVolumes,
    repeatCount: repeatCount ?? this.repeatCount,
    watchCycle: watchCycle ?? this.watchCycle,
    scoreRaw: scoreRaw.present ? scoreRaw.value : this.scoreRaw,
    scoreFormat: scoreFormat.present ? scoreFormat.value : this.scoreFormat,
    notes: notes ?? this.notes,
    favorite: favorite ?? this.favorite,
    startedYear: startedYear.present ? startedYear.value : this.startedYear,
    startedMonth: startedMonth.present ? startedMonth.value : this.startedMonth,
    startedDay: startedDay.present ? startedDay.value : this.startedDay,
    completedYear: completedYear.present
        ? completedYear.value
        : this.completedYear,
    completedMonth: completedMonth.present
        ? completedMonth.value
        : this.completedMonth,
    completedDay: completedDay.present ? completedDay.value : this.completedDay,
    canonicalStateJson: canonicalStateJson ?? this.canonicalStateJson,
    fieldRevisionsJson: fieldRevisionsJson ?? this.fieldRevisionsJson,
    createdAtMs: createdAtMs ?? this.createdAtMs,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    tombstonedAtMs: tombstonedAtMs.present
        ? tombstonedAtMs.value
        : this.tombstonedAtMs,
  );
  CanonicalLibraryRecord copyWithCompanion(
    CanonicalLibraryRecordsCompanion data,
  ) {
    return CanonicalLibraryRecord(
      localId: data.localId.present ? data.localId.value : this.localId,
      inLibrary: data.inLibrary.present ? data.inLibrary.value : this.inLibrary,
      status: data.status.present ? data.status.value : this.status,
      progress: data.progress.present ? data.progress.value : this.progress,
      progressVolumes: data.progressVolumes.present
          ? data.progressVolumes.value
          : this.progressVolumes,
      repeatCount: data.repeatCount.present
          ? data.repeatCount.value
          : this.repeatCount,
      watchCycle: data.watchCycle.present
          ? data.watchCycle.value
          : this.watchCycle,
      scoreRaw: data.scoreRaw.present ? data.scoreRaw.value : this.scoreRaw,
      scoreFormat: data.scoreFormat.present
          ? data.scoreFormat.value
          : this.scoreFormat,
      notes: data.notes.present ? data.notes.value : this.notes,
      favorite: data.favorite.present ? data.favorite.value : this.favorite,
      startedYear: data.startedYear.present
          ? data.startedYear.value
          : this.startedYear,
      startedMonth: data.startedMonth.present
          ? data.startedMonth.value
          : this.startedMonth,
      startedDay: data.startedDay.present
          ? data.startedDay.value
          : this.startedDay,
      completedYear: data.completedYear.present
          ? data.completedYear.value
          : this.completedYear,
      completedMonth: data.completedMonth.present
          ? data.completedMonth.value
          : this.completedMonth,
      completedDay: data.completedDay.present
          ? data.completedDay.value
          : this.completedDay,
      canonicalStateJson: data.canonicalStateJson.present
          ? data.canonicalStateJson.value
          : this.canonicalStateJson,
      fieldRevisionsJson: data.fieldRevisionsJson.present
          ? data.fieldRevisionsJson.value
          : this.fieldRevisionsJson,
      createdAtMs: data.createdAtMs.present
          ? data.createdAtMs.value
          : this.createdAtMs,
      updatedAtMs: data.updatedAtMs.present
          ? data.updatedAtMs.value
          : this.updatedAtMs,
      tombstonedAtMs: data.tombstonedAtMs.present
          ? data.tombstonedAtMs.value
          : this.tombstonedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CanonicalLibraryRecord(')
          ..write('localId: $localId, ')
          ..write('inLibrary: $inLibrary, ')
          ..write('status: $status, ')
          ..write('progress: $progress, ')
          ..write('progressVolumes: $progressVolumes, ')
          ..write('repeatCount: $repeatCount, ')
          ..write('watchCycle: $watchCycle, ')
          ..write('scoreRaw: $scoreRaw, ')
          ..write('scoreFormat: $scoreFormat, ')
          ..write('notes: $notes, ')
          ..write('favorite: $favorite, ')
          ..write('startedYear: $startedYear, ')
          ..write('startedMonth: $startedMonth, ')
          ..write('startedDay: $startedDay, ')
          ..write('completedYear: $completedYear, ')
          ..write('completedMonth: $completedMonth, ')
          ..write('completedDay: $completedDay, ')
          ..write('canonicalStateJson: $canonicalStateJson, ')
          ..write('fieldRevisionsJson: $fieldRevisionsJson, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('tombstonedAtMs: $tombstonedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    localId,
    inLibrary,
    status,
    progress,
    progressVolumes,
    repeatCount,
    watchCycle,
    scoreRaw,
    scoreFormat,
    notes,
    favorite,
    startedYear,
    startedMonth,
    startedDay,
    completedYear,
    completedMonth,
    completedDay,
    canonicalStateJson,
    fieldRevisionsJson,
    createdAtMs,
    updatedAtMs,
    tombstonedAtMs,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CanonicalLibraryRecord &&
          other.localId == this.localId &&
          other.inLibrary == this.inLibrary &&
          other.status == this.status &&
          other.progress == this.progress &&
          other.progressVolumes == this.progressVolumes &&
          other.repeatCount == this.repeatCount &&
          other.watchCycle == this.watchCycle &&
          other.scoreRaw == this.scoreRaw &&
          other.scoreFormat == this.scoreFormat &&
          other.notes == this.notes &&
          other.favorite == this.favorite &&
          other.startedYear == this.startedYear &&
          other.startedMonth == this.startedMonth &&
          other.startedDay == this.startedDay &&
          other.completedYear == this.completedYear &&
          other.completedMonth == this.completedMonth &&
          other.completedDay == this.completedDay &&
          other.canonicalStateJson == this.canonicalStateJson &&
          other.fieldRevisionsJson == this.fieldRevisionsJson &&
          other.createdAtMs == this.createdAtMs &&
          other.updatedAtMs == this.updatedAtMs &&
          other.tombstonedAtMs == this.tombstonedAtMs);
}

class CanonicalLibraryRecordsCompanion
    extends UpdateCompanion<CanonicalLibraryRecord> {
  final Value<String> localId;
  final Value<bool> inLibrary;
  final Value<String> status;
  final Value<int> progress;
  final Value<int> progressVolumes;
  final Value<int> repeatCount;
  final Value<int> watchCycle;
  final Value<int?> scoreRaw;
  final Value<String?> scoreFormat;
  final Value<String> notes;
  final Value<bool> favorite;
  final Value<int?> startedYear;
  final Value<int?> startedMonth;
  final Value<int?> startedDay;
  final Value<int?> completedYear;
  final Value<int?> completedMonth;
  final Value<int?> completedDay;
  final Value<String> canonicalStateJson;
  final Value<String> fieldRevisionsJson;
  final Value<int> createdAtMs;
  final Value<int> updatedAtMs;
  final Value<int?> tombstonedAtMs;
  final Value<int> rowid;
  const CanonicalLibraryRecordsCompanion({
    this.localId = const Value.absent(),
    this.inLibrary = const Value.absent(),
    this.status = const Value.absent(),
    this.progress = const Value.absent(),
    this.progressVolumes = const Value.absent(),
    this.repeatCount = const Value.absent(),
    this.watchCycle = const Value.absent(),
    this.scoreRaw = const Value.absent(),
    this.scoreFormat = const Value.absent(),
    this.notes = const Value.absent(),
    this.favorite = const Value.absent(),
    this.startedYear = const Value.absent(),
    this.startedMonth = const Value.absent(),
    this.startedDay = const Value.absent(),
    this.completedYear = const Value.absent(),
    this.completedMonth = const Value.absent(),
    this.completedDay = const Value.absent(),
    this.canonicalStateJson = const Value.absent(),
    this.fieldRevisionsJson = const Value.absent(),
    this.createdAtMs = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.tombstonedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CanonicalLibraryRecordsCompanion.insert({
    required String localId,
    this.inLibrary = const Value.absent(),
    required String status,
    this.progress = const Value.absent(),
    this.progressVolumes = const Value.absent(),
    this.repeatCount = const Value.absent(),
    this.watchCycle = const Value.absent(),
    this.scoreRaw = const Value.absent(),
    this.scoreFormat = const Value.absent(),
    this.notes = const Value.absent(),
    this.favorite = const Value.absent(),
    this.startedYear = const Value.absent(),
    this.startedMonth = const Value.absent(),
    this.startedDay = const Value.absent(),
    this.completedYear = const Value.absent(),
    this.completedMonth = const Value.absent(),
    this.completedDay = const Value.absent(),
    required String canonicalStateJson,
    this.fieldRevisionsJson = const Value.absent(),
    required int createdAtMs,
    required int updatedAtMs,
    this.tombstonedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : localId = Value(localId),
       status = Value(status),
       canonicalStateJson = Value(canonicalStateJson),
       createdAtMs = Value(createdAtMs),
       updatedAtMs = Value(updatedAtMs);
  static Insertable<CanonicalLibraryRecord> custom({
    Expression<String>? localId,
    Expression<bool>? inLibrary,
    Expression<String>? status,
    Expression<int>? progress,
    Expression<int>? progressVolumes,
    Expression<int>? repeatCount,
    Expression<int>? watchCycle,
    Expression<int>? scoreRaw,
    Expression<String>? scoreFormat,
    Expression<String>? notes,
    Expression<bool>? favorite,
    Expression<int>? startedYear,
    Expression<int>? startedMonth,
    Expression<int>? startedDay,
    Expression<int>? completedYear,
    Expression<int>? completedMonth,
    Expression<int>? completedDay,
    Expression<String>? canonicalStateJson,
    Expression<String>? fieldRevisionsJson,
    Expression<int>? createdAtMs,
    Expression<int>? updatedAtMs,
    Expression<int>? tombstonedAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (localId != null) 'local_id': localId,
      if (inLibrary != null) 'in_library': inLibrary,
      if (status != null) 'status': status,
      if (progress != null) 'progress': progress,
      if (progressVolumes != null) 'progress_volumes': progressVolumes,
      if (repeatCount != null) 'repeat_count': repeatCount,
      if (watchCycle != null) 'watch_cycle': watchCycle,
      if (scoreRaw != null) 'score_raw': scoreRaw,
      if (scoreFormat != null) 'score_format': scoreFormat,
      if (notes != null) 'notes': notes,
      if (favorite != null) 'favorite': favorite,
      if (startedYear != null) 'started_year': startedYear,
      if (startedMonth != null) 'started_month': startedMonth,
      if (startedDay != null) 'started_day': startedDay,
      if (completedYear != null) 'completed_year': completedYear,
      if (completedMonth != null) 'completed_month': completedMonth,
      if (completedDay != null) 'completed_day': completedDay,
      if (canonicalStateJson != null)
        'canonical_state_json': canonicalStateJson,
      if (fieldRevisionsJson != null)
        'field_revisions_json': fieldRevisionsJson,
      if (createdAtMs != null) 'created_at_ms': createdAtMs,
      if (updatedAtMs != null) 'updated_at_ms': updatedAtMs,
      if (tombstonedAtMs != null) 'tombstoned_at_ms': tombstonedAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CanonicalLibraryRecordsCompanion copyWith({
    Value<String>? localId,
    Value<bool>? inLibrary,
    Value<String>? status,
    Value<int>? progress,
    Value<int>? progressVolumes,
    Value<int>? repeatCount,
    Value<int>? watchCycle,
    Value<int?>? scoreRaw,
    Value<String?>? scoreFormat,
    Value<String>? notes,
    Value<bool>? favorite,
    Value<int?>? startedYear,
    Value<int?>? startedMonth,
    Value<int?>? startedDay,
    Value<int?>? completedYear,
    Value<int?>? completedMonth,
    Value<int?>? completedDay,
    Value<String>? canonicalStateJson,
    Value<String>? fieldRevisionsJson,
    Value<int>? createdAtMs,
    Value<int>? updatedAtMs,
    Value<int?>? tombstonedAtMs,
    Value<int>? rowid,
  }) {
    return CanonicalLibraryRecordsCompanion(
      localId: localId ?? this.localId,
      inLibrary: inLibrary ?? this.inLibrary,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      progressVolumes: progressVolumes ?? this.progressVolumes,
      repeatCount: repeatCount ?? this.repeatCount,
      watchCycle: watchCycle ?? this.watchCycle,
      scoreRaw: scoreRaw ?? this.scoreRaw,
      scoreFormat: scoreFormat ?? this.scoreFormat,
      notes: notes ?? this.notes,
      favorite: favorite ?? this.favorite,
      startedYear: startedYear ?? this.startedYear,
      startedMonth: startedMonth ?? this.startedMonth,
      startedDay: startedDay ?? this.startedDay,
      completedYear: completedYear ?? this.completedYear,
      completedMonth: completedMonth ?? this.completedMonth,
      completedDay: completedDay ?? this.completedDay,
      canonicalStateJson: canonicalStateJson ?? this.canonicalStateJson,
      fieldRevisionsJson: fieldRevisionsJson ?? this.fieldRevisionsJson,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      tombstonedAtMs: tombstonedAtMs ?? this.tombstonedAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (localId.present) {
      map['local_id'] = Variable<String>(localId.value);
    }
    if (inLibrary.present) {
      map['in_library'] = Variable<bool>(inLibrary.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (progress.present) {
      map['progress'] = Variable<int>(progress.value);
    }
    if (progressVolumes.present) {
      map['progress_volumes'] = Variable<int>(progressVolumes.value);
    }
    if (repeatCount.present) {
      map['repeat_count'] = Variable<int>(repeatCount.value);
    }
    if (watchCycle.present) {
      map['watch_cycle'] = Variable<int>(watchCycle.value);
    }
    if (scoreRaw.present) {
      map['score_raw'] = Variable<int>(scoreRaw.value);
    }
    if (scoreFormat.present) {
      map['score_format'] = Variable<String>(scoreFormat.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (favorite.present) {
      map['favorite'] = Variable<bool>(favorite.value);
    }
    if (startedYear.present) {
      map['started_year'] = Variable<int>(startedYear.value);
    }
    if (startedMonth.present) {
      map['started_month'] = Variable<int>(startedMonth.value);
    }
    if (startedDay.present) {
      map['started_day'] = Variable<int>(startedDay.value);
    }
    if (completedYear.present) {
      map['completed_year'] = Variable<int>(completedYear.value);
    }
    if (completedMonth.present) {
      map['completed_month'] = Variable<int>(completedMonth.value);
    }
    if (completedDay.present) {
      map['completed_day'] = Variable<int>(completedDay.value);
    }
    if (canonicalStateJson.present) {
      map['canonical_state_json'] = Variable<String>(canonicalStateJson.value);
    }
    if (fieldRevisionsJson.present) {
      map['field_revisions_json'] = Variable<String>(fieldRevisionsJson.value);
    }
    if (createdAtMs.present) {
      map['created_at_ms'] = Variable<int>(createdAtMs.value);
    }
    if (updatedAtMs.present) {
      map['updated_at_ms'] = Variable<int>(updatedAtMs.value);
    }
    if (tombstonedAtMs.present) {
      map['tombstoned_at_ms'] = Variable<int>(tombstonedAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CanonicalLibraryRecordsCompanion(')
          ..write('localId: $localId, ')
          ..write('inLibrary: $inLibrary, ')
          ..write('status: $status, ')
          ..write('progress: $progress, ')
          ..write('progressVolumes: $progressVolumes, ')
          ..write('repeatCount: $repeatCount, ')
          ..write('watchCycle: $watchCycle, ')
          ..write('scoreRaw: $scoreRaw, ')
          ..write('scoreFormat: $scoreFormat, ')
          ..write('notes: $notes, ')
          ..write('favorite: $favorite, ')
          ..write('startedYear: $startedYear, ')
          ..write('startedMonth: $startedMonth, ')
          ..write('startedDay: $startedDay, ')
          ..write('completedYear: $completedYear, ')
          ..write('completedMonth: $completedMonth, ')
          ..write('completedDay: $completedDay, ')
          ..write('canonicalStateJson: $canonicalStateJson, ')
          ..write('fieldRevisionsJson: $fieldRevisionsJson, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('tombstonedAtMs: $tombstonedAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProviderSnapshotRecordsTable extends ProviderSnapshotRecords
    with TableInfo<$ProviderSnapshotRecordsTable, ProviderSnapshotRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProviderSnapshotRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _snapshotIdMeta = const VerificationMeta(
    'snapshotId',
  );
  @override
  late final GeneratedColumn<String> snapshotId = GeneratedColumn<String>(
    'snapshot_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localIdMeta = const VerificationMeta(
    'localId',
  );
  @override
  late final GeneratedColumn<String> localId = GeneratedColumn<String>(
    'local_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES canonical_media_records (local_id)',
    ),
  );
  static const VerificationMeta _providerMeta = const VerificationMeta(
    'provider',
  );
  @override
  late final GeneratedColumn<String> provider = GeneratedColumn<String>(
    'provider',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _providerEntryIdMeta = const VerificationMeta(
    'providerEntryId',
  );
  @override
  late final GeneratedColumn<int> providerEntryId = GeneratedColumn<int>(
    'provider_entry_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _normalizedJsonMeta = const VerificationMeta(
    'normalizedJson',
  );
  @override
  late final GeneratedColumn<String> normalizedJson = GeneratedColumn<String>(
    'normalized_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rawJsonMeta = const VerificationMeta(
    'rawJson',
  );
  @override
  late final GeneratedColumn<String> rawJson = GeneratedColumn<String>(
    'raw_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentHashMeta = const VerificationMeta(
    'contentHash',
  );
  @override
  late final GeneratedColumn<String> contentHash = GeneratedColumn<String>(
    'content_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fetchedAtMsMeta = const VerificationMeta(
    'fetchedAtMs',
  );
  @override
  late final GeneratedColumn<int> fetchedAtMs = GeneratedColumn<int>(
    'fetched_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _completeSnapshotMeta = const VerificationMeta(
    'completeSnapshot',
  );
  @override
  late final GeneratedColumn<bool> completeSnapshot = GeneratedColumn<bool>(
    'complete_snapshot',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("complete_snapshot" IN (0, 1))',
    ),
  );
  static const VerificationMeta _destructiveConfirmationCountMeta =
      const VerificationMeta('destructiveConfirmationCount');
  @override
  late final GeneratedColumn<int> destructiveConfirmationCount =
      GeneratedColumn<int>(
        'destructive_confirmation_count',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
        defaultValue: const Constant(0),
      );
  @override
  List<GeneratedColumn> get $columns => [
    snapshotId,
    localId,
    provider,
    accountId,
    providerEntryId,
    normalizedJson,
    rawJson,
    contentHash,
    fetchedAtMs,
    completeSnapshot,
    destructiveConfirmationCount,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'provider_snapshot_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProviderSnapshotRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('snapshot_id')) {
      context.handle(
        _snapshotIdMeta,
        snapshotId.isAcceptableOrUnknown(data['snapshot_id']!, _snapshotIdMeta),
      );
    } else if (isInserting) {
      context.missing(_snapshotIdMeta);
    }
    if (data.containsKey('local_id')) {
      context.handle(
        _localIdMeta,
        localId.isAcceptableOrUnknown(data['local_id']!, _localIdMeta),
      );
    } else if (isInserting) {
      context.missing(_localIdMeta);
    }
    if (data.containsKey('provider')) {
      context.handle(
        _providerMeta,
        provider.isAcceptableOrUnknown(data['provider']!, _providerMeta),
      );
    } else if (isInserting) {
      context.missing(_providerMeta);
    }
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('provider_entry_id')) {
      context.handle(
        _providerEntryIdMeta,
        providerEntryId.isAcceptableOrUnknown(
          data['provider_entry_id']!,
          _providerEntryIdMeta,
        ),
      );
    }
    if (data.containsKey('normalized_json')) {
      context.handle(
        _normalizedJsonMeta,
        normalizedJson.isAcceptableOrUnknown(
          data['normalized_json']!,
          _normalizedJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_normalizedJsonMeta);
    }
    if (data.containsKey('raw_json')) {
      context.handle(
        _rawJsonMeta,
        rawJson.isAcceptableOrUnknown(data['raw_json']!, _rawJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_rawJsonMeta);
    }
    if (data.containsKey('content_hash')) {
      context.handle(
        _contentHashMeta,
        contentHash.isAcceptableOrUnknown(
          data['content_hash']!,
          _contentHashMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_contentHashMeta);
    }
    if (data.containsKey('fetched_at_ms')) {
      context.handle(
        _fetchedAtMsMeta,
        fetchedAtMs.isAcceptableOrUnknown(
          data['fetched_at_ms']!,
          _fetchedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fetchedAtMsMeta);
    }
    if (data.containsKey('complete_snapshot')) {
      context.handle(
        _completeSnapshotMeta,
        completeSnapshot.isAcceptableOrUnknown(
          data['complete_snapshot']!,
          _completeSnapshotMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_completeSnapshotMeta);
    }
    if (data.containsKey('destructive_confirmation_count')) {
      context.handle(
        _destructiveConfirmationCountMeta,
        destructiveConfirmationCount.isAcceptableOrUnknown(
          data['destructive_confirmation_count']!,
          _destructiveConfirmationCountMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {snapshotId};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {localId, provider, accountId},
  ];
  @override
  ProviderSnapshotRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProviderSnapshotRecord(
      snapshotId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot_id'],
      )!,
      localId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_id'],
      )!,
      provider: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provider'],
      )!,
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      providerEntryId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}provider_entry_id'],
      ),
      normalizedJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}normalized_json'],
      )!,
      rawJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}raw_json'],
      )!,
      contentHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_hash'],
      )!,
      fetchedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}fetched_at_ms'],
      )!,
      completeSnapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}complete_snapshot'],
      )!,
      destructiveConfirmationCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}destructive_confirmation_count'],
      )!,
    );
  }

  @override
  $ProviderSnapshotRecordsTable createAlias(String alias) {
    return $ProviderSnapshotRecordsTable(attachedDatabase, alias);
  }
}

class ProviderSnapshotRecord extends DataClass
    implements Insertable<ProviderSnapshotRecord> {
  final String snapshotId;
  final String localId;
  final String provider;
  final String accountId;
  final int? providerEntryId;
  final String normalizedJson;
  final String rawJson;
  final String contentHash;
  final int fetchedAtMs;
  final bool completeSnapshot;
  final int destructiveConfirmationCount;
  const ProviderSnapshotRecord({
    required this.snapshotId,
    required this.localId,
    required this.provider,
    required this.accountId,
    this.providerEntryId,
    required this.normalizedJson,
    required this.rawJson,
    required this.contentHash,
    required this.fetchedAtMs,
    required this.completeSnapshot,
    required this.destructiveConfirmationCount,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['snapshot_id'] = Variable<String>(snapshotId);
    map['local_id'] = Variable<String>(localId);
    map['provider'] = Variable<String>(provider);
    map['account_id'] = Variable<String>(accountId);
    if (!nullToAbsent || providerEntryId != null) {
      map['provider_entry_id'] = Variable<int>(providerEntryId);
    }
    map['normalized_json'] = Variable<String>(normalizedJson);
    map['raw_json'] = Variable<String>(rawJson);
    map['content_hash'] = Variable<String>(contentHash);
    map['fetched_at_ms'] = Variable<int>(fetchedAtMs);
    map['complete_snapshot'] = Variable<bool>(completeSnapshot);
    map['destructive_confirmation_count'] = Variable<int>(
      destructiveConfirmationCount,
    );
    return map;
  }

  ProviderSnapshotRecordsCompanion toCompanion(bool nullToAbsent) {
    return ProviderSnapshotRecordsCompanion(
      snapshotId: Value(snapshotId),
      localId: Value(localId),
      provider: Value(provider),
      accountId: Value(accountId),
      providerEntryId: providerEntryId == null && nullToAbsent
          ? const Value.absent()
          : Value(providerEntryId),
      normalizedJson: Value(normalizedJson),
      rawJson: Value(rawJson),
      contentHash: Value(contentHash),
      fetchedAtMs: Value(fetchedAtMs),
      completeSnapshot: Value(completeSnapshot),
      destructiveConfirmationCount: Value(destructiveConfirmationCount),
    );
  }

  factory ProviderSnapshotRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProviderSnapshotRecord(
      snapshotId: serializer.fromJson<String>(json['snapshotId']),
      localId: serializer.fromJson<String>(json['localId']),
      provider: serializer.fromJson<String>(json['provider']),
      accountId: serializer.fromJson<String>(json['accountId']),
      providerEntryId: serializer.fromJson<int?>(json['providerEntryId']),
      normalizedJson: serializer.fromJson<String>(json['normalizedJson']),
      rawJson: serializer.fromJson<String>(json['rawJson']),
      contentHash: serializer.fromJson<String>(json['contentHash']),
      fetchedAtMs: serializer.fromJson<int>(json['fetchedAtMs']),
      completeSnapshot: serializer.fromJson<bool>(json['completeSnapshot']),
      destructiveConfirmationCount: serializer.fromJson<int>(
        json['destructiveConfirmationCount'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'snapshotId': serializer.toJson<String>(snapshotId),
      'localId': serializer.toJson<String>(localId),
      'provider': serializer.toJson<String>(provider),
      'accountId': serializer.toJson<String>(accountId),
      'providerEntryId': serializer.toJson<int?>(providerEntryId),
      'normalizedJson': serializer.toJson<String>(normalizedJson),
      'rawJson': serializer.toJson<String>(rawJson),
      'contentHash': serializer.toJson<String>(contentHash),
      'fetchedAtMs': serializer.toJson<int>(fetchedAtMs),
      'completeSnapshot': serializer.toJson<bool>(completeSnapshot),
      'destructiveConfirmationCount': serializer.toJson<int>(
        destructiveConfirmationCount,
      ),
    };
  }

  ProviderSnapshotRecord copyWith({
    String? snapshotId,
    String? localId,
    String? provider,
    String? accountId,
    Value<int?> providerEntryId = const Value.absent(),
    String? normalizedJson,
    String? rawJson,
    String? contentHash,
    int? fetchedAtMs,
    bool? completeSnapshot,
    int? destructiveConfirmationCount,
  }) => ProviderSnapshotRecord(
    snapshotId: snapshotId ?? this.snapshotId,
    localId: localId ?? this.localId,
    provider: provider ?? this.provider,
    accountId: accountId ?? this.accountId,
    providerEntryId: providerEntryId.present
        ? providerEntryId.value
        : this.providerEntryId,
    normalizedJson: normalizedJson ?? this.normalizedJson,
    rawJson: rawJson ?? this.rawJson,
    contentHash: contentHash ?? this.contentHash,
    fetchedAtMs: fetchedAtMs ?? this.fetchedAtMs,
    completeSnapshot: completeSnapshot ?? this.completeSnapshot,
    destructiveConfirmationCount:
        destructiveConfirmationCount ?? this.destructiveConfirmationCount,
  );
  ProviderSnapshotRecord copyWithCompanion(
    ProviderSnapshotRecordsCompanion data,
  ) {
    return ProviderSnapshotRecord(
      snapshotId: data.snapshotId.present
          ? data.snapshotId.value
          : this.snapshotId,
      localId: data.localId.present ? data.localId.value : this.localId,
      provider: data.provider.present ? data.provider.value : this.provider,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      providerEntryId: data.providerEntryId.present
          ? data.providerEntryId.value
          : this.providerEntryId,
      normalizedJson: data.normalizedJson.present
          ? data.normalizedJson.value
          : this.normalizedJson,
      rawJson: data.rawJson.present ? data.rawJson.value : this.rawJson,
      contentHash: data.contentHash.present
          ? data.contentHash.value
          : this.contentHash,
      fetchedAtMs: data.fetchedAtMs.present
          ? data.fetchedAtMs.value
          : this.fetchedAtMs,
      completeSnapshot: data.completeSnapshot.present
          ? data.completeSnapshot.value
          : this.completeSnapshot,
      destructiveConfirmationCount: data.destructiveConfirmationCount.present
          ? data.destructiveConfirmationCount.value
          : this.destructiveConfirmationCount,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProviderSnapshotRecord(')
          ..write('snapshotId: $snapshotId, ')
          ..write('localId: $localId, ')
          ..write('provider: $provider, ')
          ..write('accountId: $accountId, ')
          ..write('providerEntryId: $providerEntryId, ')
          ..write('normalizedJson: $normalizedJson, ')
          ..write('rawJson: $rawJson, ')
          ..write('contentHash: $contentHash, ')
          ..write('fetchedAtMs: $fetchedAtMs, ')
          ..write('completeSnapshot: $completeSnapshot, ')
          ..write('destructiveConfirmationCount: $destructiveConfirmationCount')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    snapshotId,
    localId,
    provider,
    accountId,
    providerEntryId,
    normalizedJson,
    rawJson,
    contentHash,
    fetchedAtMs,
    completeSnapshot,
    destructiveConfirmationCount,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProviderSnapshotRecord &&
          other.snapshotId == this.snapshotId &&
          other.localId == this.localId &&
          other.provider == this.provider &&
          other.accountId == this.accountId &&
          other.providerEntryId == this.providerEntryId &&
          other.normalizedJson == this.normalizedJson &&
          other.rawJson == this.rawJson &&
          other.contentHash == this.contentHash &&
          other.fetchedAtMs == this.fetchedAtMs &&
          other.completeSnapshot == this.completeSnapshot &&
          other.destructiveConfirmationCount ==
              this.destructiveConfirmationCount);
}

class ProviderSnapshotRecordsCompanion
    extends UpdateCompanion<ProviderSnapshotRecord> {
  final Value<String> snapshotId;
  final Value<String> localId;
  final Value<String> provider;
  final Value<String> accountId;
  final Value<int?> providerEntryId;
  final Value<String> normalizedJson;
  final Value<String> rawJson;
  final Value<String> contentHash;
  final Value<int> fetchedAtMs;
  final Value<bool> completeSnapshot;
  final Value<int> destructiveConfirmationCount;
  final Value<int> rowid;
  const ProviderSnapshotRecordsCompanion({
    this.snapshotId = const Value.absent(),
    this.localId = const Value.absent(),
    this.provider = const Value.absent(),
    this.accountId = const Value.absent(),
    this.providerEntryId = const Value.absent(),
    this.normalizedJson = const Value.absent(),
    this.rawJson = const Value.absent(),
    this.contentHash = const Value.absent(),
    this.fetchedAtMs = const Value.absent(),
    this.completeSnapshot = const Value.absent(),
    this.destructiveConfirmationCount = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProviderSnapshotRecordsCompanion.insert({
    required String snapshotId,
    required String localId,
    required String provider,
    required String accountId,
    this.providerEntryId = const Value.absent(),
    required String normalizedJson,
    required String rawJson,
    required String contentHash,
    required int fetchedAtMs,
    required bool completeSnapshot,
    this.destructiveConfirmationCount = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : snapshotId = Value(snapshotId),
       localId = Value(localId),
       provider = Value(provider),
       accountId = Value(accountId),
       normalizedJson = Value(normalizedJson),
       rawJson = Value(rawJson),
       contentHash = Value(contentHash),
       fetchedAtMs = Value(fetchedAtMs),
       completeSnapshot = Value(completeSnapshot);
  static Insertable<ProviderSnapshotRecord> custom({
    Expression<String>? snapshotId,
    Expression<String>? localId,
    Expression<String>? provider,
    Expression<String>? accountId,
    Expression<int>? providerEntryId,
    Expression<String>? normalizedJson,
    Expression<String>? rawJson,
    Expression<String>? contentHash,
    Expression<int>? fetchedAtMs,
    Expression<bool>? completeSnapshot,
    Expression<int>? destructiveConfirmationCount,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (snapshotId != null) 'snapshot_id': snapshotId,
      if (localId != null) 'local_id': localId,
      if (provider != null) 'provider': provider,
      if (accountId != null) 'account_id': accountId,
      if (providerEntryId != null) 'provider_entry_id': providerEntryId,
      if (normalizedJson != null) 'normalized_json': normalizedJson,
      if (rawJson != null) 'raw_json': rawJson,
      if (contentHash != null) 'content_hash': contentHash,
      if (fetchedAtMs != null) 'fetched_at_ms': fetchedAtMs,
      if (completeSnapshot != null) 'complete_snapshot': completeSnapshot,
      if (destructiveConfirmationCount != null)
        'destructive_confirmation_count': destructiveConfirmationCount,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProviderSnapshotRecordsCompanion copyWith({
    Value<String>? snapshotId,
    Value<String>? localId,
    Value<String>? provider,
    Value<String>? accountId,
    Value<int?>? providerEntryId,
    Value<String>? normalizedJson,
    Value<String>? rawJson,
    Value<String>? contentHash,
    Value<int>? fetchedAtMs,
    Value<bool>? completeSnapshot,
    Value<int>? destructiveConfirmationCount,
    Value<int>? rowid,
  }) {
    return ProviderSnapshotRecordsCompanion(
      snapshotId: snapshotId ?? this.snapshotId,
      localId: localId ?? this.localId,
      provider: provider ?? this.provider,
      accountId: accountId ?? this.accountId,
      providerEntryId: providerEntryId ?? this.providerEntryId,
      normalizedJson: normalizedJson ?? this.normalizedJson,
      rawJson: rawJson ?? this.rawJson,
      contentHash: contentHash ?? this.contentHash,
      fetchedAtMs: fetchedAtMs ?? this.fetchedAtMs,
      completeSnapshot: completeSnapshot ?? this.completeSnapshot,
      destructiveConfirmationCount:
          destructiveConfirmationCount ?? this.destructiveConfirmationCount,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (snapshotId.present) {
      map['snapshot_id'] = Variable<String>(snapshotId.value);
    }
    if (localId.present) {
      map['local_id'] = Variable<String>(localId.value);
    }
    if (provider.present) {
      map['provider'] = Variable<String>(provider.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (providerEntryId.present) {
      map['provider_entry_id'] = Variable<int>(providerEntryId.value);
    }
    if (normalizedJson.present) {
      map['normalized_json'] = Variable<String>(normalizedJson.value);
    }
    if (rawJson.present) {
      map['raw_json'] = Variable<String>(rawJson.value);
    }
    if (contentHash.present) {
      map['content_hash'] = Variable<String>(contentHash.value);
    }
    if (fetchedAtMs.present) {
      map['fetched_at_ms'] = Variable<int>(fetchedAtMs.value);
    }
    if (completeSnapshot.present) {
      map['complete_snapshot'] = Variable<bool>(completeSnapshot.value);
    }
    if (destructiveConfirmationCount.present) {
      map['destructive_confirmation_count'] = Variable<int>(
        destructiveConfirmationCount.value,
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProviderSnapshotRecordsCompanion(')
          ..write('snapshotId: $snapshotId, ')
          ..write('localId: $localId, ')
          ..write('provider: $provider, ')
          ..write('accountId: $accountId, ')
          ..write('providerEntryId: $providerEntryId, ')
          ..write('normalizedJson: $normalizedJson, ')
          ..write('rawJson: $rawJson, ')
          ..write('contentHash: $contentHash, ')
          ..write('fetchedAtMs: $fetchedAtMs, ')
          ..write('completeSnapshot: $completeSnapshot, ')
          ..write(
            'destructiveConfirmationCount: $destructiveConfirmationCount, ',
          )
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $EpisodeStateRecordsTable extends EpisodeStateRecords
    with TableInfo<$EpisodeStateRecordsTable, EpisodeStateRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EpisodeStateRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _episodeStateIdMeta = const VerificationMeta(
    'episodeStateId',
  );
  @override
  late final GeneratedColumn<String> episodeStateId = GeneratedColumn<String>(
    'episode_state_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localIdMeta = const VerificationMeta(
    'localId',
  );
  @override
  late final GeneratedColumn<String> localId = GeneratedColumn<String>(
    'local_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES canonical_media_records (local_id)',
    ),
  );
  static const VerificationMeta _seasonNumberMeta = const VerificationMeta(
    'seasonNumber',
  );
  @override
  late final GeneratedColumn<int> seasonNumber = GeneratedColumn<int>(
    'season_number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _episodeNumberMeta = const VerificationMeta(
    'episodeNumber',
  );
  @override
  late final GeneratedColumn<double> episodeNumber = GeneratedColumn<double>(
    'episode_number',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionSecondsMeta = const VerificationMeta(
    'positionSeconds',
  );
  @override
  late final GeneratedColumn<int> positionSeconds = GeneratedColumn<int>(
    'position_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _durationSecondsMeta = const VerificationMeta(
    'durationSeconds',
  );
  @override
  late final GeneratedColumn<int> durationSeconds = GeneratedColumn<int>(
    'duration_seconds',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _completedMeta = const VerificationMeta(
    'completed',
  );
  @override
  late final GeneratedColumn<bool> completed = GeneratedColumn<bool>(
    'completed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("completed" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _watchCycleMeta = const VerificationMeta(
    'watchCycle',
  );
  @override
  late final GeneratedColumn<int> watchCycle = GeneratedColumn<int>(
    'watch_cycle',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _updatedAtMsMeta = const VerificationMeta(
    'updatedAtMs',
  );
  @override
  late final GeneratedColumn<int> updatedAtMs = GeneratedColumn<int>(
    'updated_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    episodeStateId,
    localId,
    seasonNumber,
    episodeNumber,
    positionSeconds,
    durationSeconds,
    completed,
    watchCycle,
    updatedAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'episode_state_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<EpisodeStateRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('episode_state_id')) {
      context.handle(
        _episodeStateIdMeta,
        episodeStateId.isAcceptableOrUnknown(
          data['episode_state_id']!,
          _episodeStateIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_episodeStateIdMeta);
    }
    if (data.containsKey('local_id')) {
      context.handle(
        _localIdMeta,
        localId.isAcceptableOrUnknown(data['local_id']!, _localIdMeta),
      );
    } else if (isInserting) {
      context.missing(_localIdMeta);
    }
    if (data.containsKey('season_number')) {
      context.handle(
        _seasonNumberMeta,
        seasonNumber.isAcceptableOrUnknown(
          data['season_number']!,
          _seasonNumberMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_seasonNumberMeta);
    }
    if (data.containsKey('episode_number')) {
      context.handle(
        _episodeNumberMeta,
        episodeNumber.isAcceptableOrUnknown(
          data['episode_number']!,
          _episodeNumberMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_episodeNumberMeta);
    }
    if (data.containsKey('position_seconds')) {
      context.handle(
        _positionSecondsMeta,
        positionSeconds.isAcceptableOrUnknown(
          data['position_seconds']!,
          _positionSecondsMeta,
        ),
      );
    }
    if (data.containsKey('duration_seconds')) {
      context.handle(
        _durationSecondsMeta,
        durationSeconds.isAcceptableOrUnknown(
          data['duration_seconds']!,
          _durationSecondsMeta,
        ),
      );
    }
    if (data.containsKey('completed')) {
      context.handle(
        _completedMeta,
        completed.isAcceptableOrUnknown(data['completed']!, _completedMeta),
      );
    }
    if (data.containsKey('watch_cycle')) {
      context.handle(
        _watchCycleMeta,
        watchCycle.isAcceptableOrUnknown(data['watch_cycle']!, _watchCycleMeta),
      );
    }
    if (data.containsKey('updated_at_ms')) {
      context.handle(
        _updatedAtMsMeta,
        updatedAtMs.isAcceptableOrUnknown(
          data['updated_at_ms']!,
          _updatedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {episodeStateId};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {localId, seasonNumber, episodeNumber, watchCycle},
  ];
  @override
  EpisodeStateRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EpisodeStateRecord(
      episodeStateId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}episode_state_id'],
      )!,
      localId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_id'],
      )!,
      seasonNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}season_number'],
      )!,
      episodeNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}episode_number'],
      )!,
      positionSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position_seconds'],
      )!,
      durationSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_seconds'],
      ),
      completed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}completed'],
      )!,
      watchCycle: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}watch_cycle'],
      )!,
      updatedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_ms'],
      )!,
    );
  }

  @override
  $EpisodeStateRecordsTable createAlias(String alias) {
    return $EpisodeStateRecordsTable(attachedDatabase, alias);
  }
}

class EpisodeStateRecord extends DataClass
    implements Insertable<EpisodeStateRecord> {
  final String episodeStateId;
  final String localId;
  final int seasonNumber;
  final double episodeNumber;
  final int positionSeconds;
  final int? durationSeconds;
  final bool completed;
  final int watchCycle;
  final int updatedAtMs;
  const EpisodeStateRecord({
    required this.episodeStateId,
    required this.localId,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.positionSeconds,
    this.durationSeconds,
    required this.completed,
    required this.watchCycle,
    required this.updatedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['episode_state_id'] = Variable<String>(episodeStateId);
    map['local_id'] = Variable<String>(localId);
    map['season_number'] = Variable<int>(seasonNumber);
    map['episode_number'] = Variable<double>(episodeNumber);
    map['position_seconds'] = Variable<int>(positionSeconds);
    if (!nullToAbsent || durationSeconds != null) {
      map['duration_seconds'] = Variable<int>(durationSeconds);
    }
    map['completed'] = Variable<bool>(completed);
    map['watch_cycle'] = Variable<int>(watchCycle);
    map['updated_at_ms'] = Variable<int>(updatedAtMs);
    return map;
  }

  EpisodeStateRecordsCompanion toCompanion(bool nullToAbsent) {
    return EpisodeStateRecordsCompanion(
      episodeStateId: Value(episodeStateId),
      localId: Value(localId),
      seasonNumber: Value(seasonNumber),
      episodeNumber: Value(episodeNumber),
      positionSeconds: Value(positionSeconds),
      durationSeconds: durationSeconds == null && nullToAbsent
          ? const Value.absent()
          : Value(durationSeconds),
      completed: Value(completed),
      watchCycle: Value(watchCycle),
      updatedAtMs: Value(updatedAtMs),
    );
  }

  factory EpisodeStateRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EpisodeStateRecord(
      episodeStateId: serializer.fromJson<String>(json['episodeStateId']),
      localId: serializer.fromJson<String>(json['localId']),
      seasonNumber: serializer.fromJson<int>(json['seasonNumber']),
      episodeNumber: serializer.fromJson<double>(json['episodeNumber']),
      positionSeconds: serializer.fromJson<int>(json['positionSeconds']),
      durationSeconds: serializer.fromJson<int?>(json['durationSeconds']),
      completed: serializer.fromJson<bool>(json['completed']),
      watchCycle: serializer.fromJson<int>(json['watchCycle']),
      updatedAtMs: serializer.fromJson<int>(json['updatedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'episodeStateId': serializer.toJson<String>(episodeStateId),
      'localId': serializer.toJson<String>(localId),
      'seasonNumber': serializer.toJson<int>(seasonNumber),
      'episodeNumber': serializer.toJson<double>(episodeNumber),
      'positionSeconds': serializer.toJson<int>(positionSeconds),
      'durationSeconds': serializer.toJson<int?>(durationSeconds),
      'completed': serializer.toJson<bool>(completed),
      'watchCycle': serializer.toJson<int>(watchCycle),
      'updatedAtMs': serializer.toJson<int>(updatedAtMs),
    };
  }

  EpisodeStateRecord copyWith({
    String? episodeStateId,
    String? localId,
    int? seasonNumber,
    double? episodeNumber,
    int? positionSeconds,
    Value<int?> durationSeconds = const Value.absent(),
    bool? completed,
    int? watchCycle,
    int? updatedAtMs,
  }) => EpisodeStateRecord(
    episodeStateId: episodeStateId ?? this.episodeStateId,
    localId: localId ?? this.localId,
    seasonNumber: seasonNumber ?? this.seasonNumber,
    episodeNumber: episodeNumber ?? this.episodeNumber,
    positionSeconds: positionSeconds ?? this.positionSeconds,
    durationSeconds: durationSeconds.present
        ? durationSeconds.value
        : this.durationSeconds,
    completed: completed ?? this.completed,
    watchCycle: watchCycle ?? this.watchCycle,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
  );
  EpisodeStateRecord copyWithCompanion(EpisodeStateRecordsCompanion data) {
    return EpisodeStateRecord(
      episodeStateId: data.episodeStateId.present
          ? data.episodeStateId.value
          : this.episodeStateId,
      localId: data.localId.present ? data.localId.value : this.localId,
      seasonNumber: data.seasonNumber.present
          ? data.seasonNumber.value
          : this.seasonNumber,
      episodeNumber: data.episodeNumber.present
          ? data.episodeNumber.value
          : this.episodeNumber,
      positionSeconds: data.positionSeconds.present
          ? data.positionSeconds.value
          : this.positionSeconds,
      durationSeconds: data.durationSeconds.present
          ? data.durationSeconds.value
          : this.durationSeconds,
      completed: data.completed.present ? data.completed.value : this.completed,
      watchCycle: data.watchCycle.present
          ? data.watchCycle.value
          : this.watchCycle,
      updatedAtMs: data.updatedAtMs.present
          ? data.updatedAtMs.value
          : this.updatedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EpisodeStateRecord(')
          ..write('episodeStateId: $episodeStateId, ')
          ..write('localId: $localId, ')
          ..write('seasonNumber: $seasonNumber, ')
          ..write('episodeNumber: $episodeNumber, ')
          ..write('positionSeconds: $positionSeconds, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('completed: $completed, ')
          ..write('watchCycle: $watchCycle, ')
          ..write('updatedAtMs: $updatedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    episodeStateId,
    localId,
    seasonNumber,
    episodeNumber,
    positionSeconds,
    durationSeconds,
    completed,
    watchCycle,
    updatedAtMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EpisodeStateRecord &&
          other.episodeStateId == this.episodeStateId &&
          other.localId == this.localId &&
          other.seasonNumber == this.seasonNumber &&
          other.episodeNumber == this.episodeNumber &&
          other.positionSeconds == this.positionSeconds &&
          other.durationSeconds == this.durationSeconds &&
          other.completed == this.completed &&
          other.watchCycle == this.watchCycle &&
          other.updatedAtMs == this.updatedAtMs);
}

class EpisodeStateRecordsCompanion extends UpdateCompanion<EpisodeStateRecord> {
  final Value<String> episodeStateId;
  final Value<String> localId;
  final Value<int> seasonNumber;
  final Value<double> episodeNumber;
  final Value<int> positionSeconds;
  final Value<int?> durationSeconds;
  final Value<bool> completed;
  final Value<int> watchCycle;
  final Value<int> updatedAtMs;
  final Value<int> rowid;
  const EpisodeStateRecordsCompanion({
    this.episodeStateId = const Value.absent(),
    this.localId = const Value.absent(),
    this.seasonNumber = const Value.absent(),
    this.episodeNumber = const Value.absent(),
    this.positionSeconds = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    this.completed = const Value.absent(),
    this.watchCycle = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EpisodeStateRecordsCompanion.insert({
    required String episodeStateId,
    required String localId,
    required int seasonNumber,
    required double episodeNumber,
    this.positionSeconds = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    this.completed = const Value.absent(),
    this.watchCycle = const Value.absent(),
    required int updatedAtMs,
    this.rowid = const Value.absent(),
  }) : episodeStateId = Value(episodeStateId),
       localId = Value(localId),
       seasonNumber = Value(seasonNumber),
       episodeNumber = Value(episodeNumber),
       updatedAtMs = Value(updatedAtMs);
  static Insertable<EpisodeStateRecord> custom({
    Expression<String>? episodeStateId,
    Expression<String>? localId,
    Expression<int>? seasonNumber,
    Expression<double>? episodeNumber,
    Expression<int>? positionSeconds,
    Expression<int>? durationSeconds,
    Expression<bool>? completed,
    Expression<int>? watchCycle,
    Expression<int>? updatedAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (episodeStateId != null) 'episode_state_id': episodeStateId,
      if (localId != null) 'local_id': localId,
      if (seasonNumber != null) 'season_number': seasonNumber,
      if (episodeNumber != null) 'episode_number': episodeNumber,
      if (positionSeconds != null) 'position_seconds': positionSeconds,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
      if (completed != null) 'completed': completed,
      if (watchCycle != null) 'watch_cycle': watchCycle,
      if (updatedAtMs != null) 'updated_at_ms': updatedAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EpisodeStateRecordsCompanion copyWith({
    Value<String>? episodeStateId,
    Value<String>? localId,
    Value<int>? seasonNumber,
    Value<double>? episodeNumber,
    Value<int>? positionSeconds,
    Value<int?>? durationSeconds,
    Value<bool>? completed,
    Value<int>? watchCycle,
    Value<int>? updatedAtMs,
    Value<int>? rowid,
  }) {
    return EpisodeStateRecordsCompanion(
      episodeStateId: episodeStateId ?? this.episodeStateId,
      localId: localId ?? this.localId,
      seasonNumber: seasonNumber ?? this.seasonNumber,
      episodeNumber: episodeNumber ?? this.episodeNumber,
      positionSeconds: positionSeconds ?? this.positionSeconds,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      completed: completed ?? this.completed,
      watchCycle: watchCycle ?? this.watchCycle,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (episodeStateId.present) {
      map['episode_state_id'] = Variable<String>(episodeStateId.value);
    }
    if (localId.present) {
      map['local_id'] = Variable<String>(localId.value);
    }
    if (seasonNumber.present) {
      map['season_number'] = Variable<int>(seasonNumber.value);
    }
    if (episodeNumber.present) {
      map['episode_number'] = Variable<double>(episodeNumber.value);
    }
    if (positionSeconds.present) {
      map['position_seconds'] = Variable<int>(positionSeconds.value);
    }
    if (durationSeconds.present) {
      map['duration_seconds'] = Variable<int>(durationSeconds.value);
    }
    if (completed.present) {
      map['completed'] = Variable<bool>(completed.value);
    }
    if (watchCycle.present) {
      map['watch_cycle'] = Variable<int>(watchCycle.value);
    }
    if (updatedAtMs.present) {
      map['updated_at_ms'] = Variable<int>(updatedAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EpisodeStateRecordsCompanion(')
          ..write('episodeStateId: $episodeStateId, ')
          ..write('localId: $localId, ')
          ..write('seasonNumber: $seasonNumber, ')
          ..write('episodeNumber: $episodeNumber, ')
          ..write('positionSeconds: $positionSeconds, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('completed: $completed, ')
          ..write('watchCycle: $watchCycle, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StreamPreferenceRecordsTable extends StreamPreferenceRecords
    with TableInfo<$StreamPreferenceRecordsTable, StreamPreferenceRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StreamPreferenceRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _preferenceIdMeta = const VerificationMeta(
    'preferenceId',
  );
  @override
  late final GeneratedColumn<String> preferenceId = GeneratedColumn<String>(
    'preference_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localIdMeta = const VerificationMeta(
    'localId',
  );
  @override
  late final GeneratedColumn<String> localId = GeneratedColumn<String>(
    'local_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES canonical_media_records (local_id)',
    ),
  );
  static const VerificationMeta _seasonNumberMeta = const VerificationMeta(
    'seasonNumber',
  );
  @override
  late final GeneratedColumn<int> seasonNumber = GeneratedColumn<int>(
    'season_number',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _episodeNumberMeta = const VerificationMeta(
    'episodeNumber',
  );
  @override
  late final GeneratedColumn<double> episodeNumber = GeneratedColumn<double>(
    'episode_number',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _addonIdMeta = const VerificationMeta(
    'addonId',
  );
  @override
  late final GeneratedColumn<String> addonId = GeneratedColumn<String>(
    'addon_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _sourceIdMeta = const VerificationMeta(
    'sourceId',
  );
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
    'source_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _serverIdMeta = const VerificationMeta(
    'serverId',
  );
  @override
  late final GeneratedColumn<String> serverId = GeneratedColumn<String>(
    'server_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _serverTitleMeta = const VerificationMeta(
    'serverTitle',
  );
  @override
  late final GeneratedColumn<String> serverTitle = GeneratedColumn<String>(
    'server_title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _voiceoverIdMeta = const VerificationMeta(
    'voiceoverId',
  );
  @override
  late final GeneratedColumn<String> voiceoverId = GeneratedColumn<String>(
    'voiceover_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _voiceoverTitleMeta = const VerificationMeta(
    'voiceoverTitle',
  );
  @override
  late final GeneratedColumn<String> voiceoverTitle = GeneratedColumn<String>(
    'voiceover_title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _qualityIdMeta = const VerificationMeta(
    'qualityId',
  );
  @override
  late final GeneratedColumn<String> qualityId = GeneratedColumn<String>(
    'quality_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _qualityLabelMeta = const VerificationMeta(
    'qualityLabel',
  );
  @override
  late final GeneratedColumn<String> qualityLabel = GeneratedColumn<String>(
    'quality_label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _updatedAtMsMeta = const VerificationMeta(
    'updatedAtMs',
  );
  @override
  late final GeneratedColumn<int> updatedAtMs = GeneratedColumn<int>(
    'updated_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    preferenceId,
    localId,
    seasonNumber,
    episodeNumber,
    addonId,
    sourceId,
    serverId,
    serverTitle,
    voiceoverId,
    voiceoverTitle,
    qualityId,
    qualityLabel,
    updatedAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stream_preference_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<StreamPreferenceRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('preference_id')) {
      context.handle(
        _preferenceIdMeta,
        preferenceId.isAcceptableOrUnknown(
          data['preference_id']!,
          _preferenceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_preferenceIdMeta);
    }
    if (data.containsKey('local_id')) {
      context.handle(
        _localIdMeta,
        localId.isAcceptableOrUnknown(data['local_id']!, _localIdMeta),
      );
    } else if (isInserting) {
      context.missing(_localIdMeta);
    }
    if (data.containsKey('season_number')) {
      context.handle(
        _seasonNumberMeta,
        seasonNumber.isAcceptableOrUnknown(
          data['season_number']!,
          _seasonNumberMeta,
        ),
      );
    }
    if (data.containsKey('episode_number')) {
      context.handle(
        _episodeNumberMeta,
        episodeNumber.isAcceptableOrUnknown(
          data['episode_number']!,
          _episodeNumberMeta,
        ),
      );
    }
    if (data.containsKey('addon_id')) {
      context.handle(
        _addonIdMeta,
        addonId.isAcceptableOrUnknown(data['addon_id']!, _addonIdMeta),
      );
    }
    if (data.containsKey('source_id')) {
      context.handle(
        _sourceIdMeta,
        sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta),
      );
    }
    if (data.containsKey('server_id')) {
      context.handle(
        _serverIdMeta,
        serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta),
      );
    }
    if (data.containsKey('server_title')) {
      context.handle(
        _serverTitleMeta,
        serverTitle.isAcceptableOrUnknown(
          data['server_title']!,
          _serverTitleMeta,
        ),
      );
    }
    if (data.containsKey('voiceover_id')) {
      context.handle(
        _voiceoverIdMeta,
        voiceoverId.isAcceptableOrUnknown(
          data['voiceover_id']!,
          _voiceoverIdMeta,
        ),
      );
    }
    if (data.containsKey('voiceover_title')) {
      context.handle(
        _voiceoverTitleMeta,
        voiceoverTitle.isAcceptableOrUnknown(
          data['voiceover_title']!,
          _voiceoverTitleMeta,
        ),
      );
    }
    if (data.containsKey('quality_id')) {
      context.handle(
        _qualityIdMeta,
        qualityId.isAcceptableOrUnknown(data['quality_id']!, _qualityIdMeta),
      );
    }
    if (data.containsKey('quality_label')) {
      context.handle(
        _qualityLabelMeta,
        qualityLabel.isAcceptableOrUnknown(
          data['quality_label']!,
          _qualityLabelMeta,
        ),
      );
    }
    if (data.containsKey('updated_at_ms')) {
      context.handle(
        _updatedAtMsMeta,
        updatedAtMs.isAcceptableOrUnknown(
          data['updated_at_ms']!,
          _updatedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {preferenceId};
  @override
  StreamPreferenceRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StreamPreferenceRecord(
      preferenceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}preference_id'],
      )!,
      localId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_id'],
      )!,
      seasonNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}season_number'],
      ),
      episodeNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}episode_number'],
      ),
      addonId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}addon_id'],
      )!,
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_id'],
      )!,
      serverId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_id'],
      )!,
      serverTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_title'],
      )!,
      voiceoverId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}voiceover_id'],
      )!,
      voiceoverTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}voiceover_title'],
      )!,
      qualityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}quality_id'],
      )!,
      qualityLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}quality_label'],
      )!,
      updatedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_ms'],
      )!,
    );
  }

  @override
  $StreamPreferenceRecordsTable createAlias(String alias) {
    return $StreamPreferenceRecordsTable(attachedDatabase, alias);
  }
}

class StreamPreferenceRecord extends DataClass
    implements Insertable<StreamPreferenceRecord> {
  final String preferenceId;
  final String localId;
  final int? seasonNumber;
  final double? episodeNumber;
  final String addonId;
  final String sourceId;
  final String serverId;
  final String serverTitle;
  final String voiceoverId;
  final String voiceoverTitle;
  final String qualityId;
  final String qualityLabel;
  final int updatedAtMs;
  const StreamPreferenceRecord({
    required this.preferenceId,
    required this.localId,
    this.seasonNumber,
    this.episodeNumber,
    required this.addonId,
    required this.sourceId,
    required this.serverId,
    required this.serverTitle,
    required this.voiceoverId,
    required this.voiceoverTitle,
    required this.qualityId,
    required this.qualityLabel,
    required this.updatedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['preference_id'] = Variable<String>(preferenceId);
    map['local_id'] = Variable<String>(localId);
    if (!nullToAbsent || seasonNumber != null) {
      map['season_number'] = Variable<int>(seasonNumber);
    }
    if (!nullToAbsent || episodeNumber != null) {
      map['episode_number'] = Variable<double>(episodeNumber);
    }
    map['addon_id'] = Variable<String>(addonId);
    map['source_id'] = Variable<String>(sourceId);
    map['server_id'] = Variable<String>(serverId);
    map['server_title'] = Variable<String>(serverTitle);
    map['voiceover_id'] = Variable<String>(voiceoverId);
    map['voiceover_title'] = Variable<String>(voiceoverTitle);
    map['quality_id'] = Variable<String>(qualityId);
    map['quality_label'] = Variable<String>(qualityLabel);
    map['updated_at_ms'] = Variable<int>(updatedAtMs);
    return map;
  }

  StreamPreferenceRecordsCompanion toCompanion(bool nullToAbsent) {
    return StreamPreferenceRecordsCompanion(
      preferenceId: Value(preferenceId),
      localId: Value(localId),
      seasonNumber: seasonNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(seasonNumber),
      episodeNumber: episodeNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(episodeNumber),
      addonId: Value(addonId),
      sourceId: Value(sourceId),
      serverId: Value(serverId),
      serverTitle: Value(serverTitle),
      voiceoverId: Value(voiceoverId),
      voiceoverTitle: Value(voiceoverTitle),
      qualityId: Value(qualityId),
      qualityLabel: Value(qualityLabel),
      updatedAtMs: Value(updatedAtMs),
    );
  }

  factory StreamPreferenceRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StreamPreferenceRecord(
      preferenceId: serializer.fromJson<String>(json['preferenceId']),
      localId: serializer.fromJson<String>(json['localId']),
      seasonNumber: serializer.fromJson<int?>(json['seasonNumber']),
      episodeNumber: serializer.fromJson<double?>(json['episodeNumber']),
      addonId: serializer.fromJson<String>(json['addonId']),
      sourceId: serializer.fromJson<String>(json['sourceId']),
      serverId: serializer.fromJson<String>(json['serverId']),
      serverTitle: serializer.fromJson<String>(json['serverTitle']),
      voiceoverId: serializer.fromJson<String>(json['voiceoverId']),
      voiceoverTitle: serializer.fromJson<String>(json['voiceoverTitle']),
      qualityId: serializer.fromJson<String>(json['qualityId']),
      qualityLabel: serializer.fromJson<String>(json['qualityLabel']),
      updatedAtMs: serializer.fromJson<int>(json['updatedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'preferenceId': serializer.toJson<String>(preferenceId),
      'localId': serializer.toJson<String>(localId),
      'seasonNumber': serializer.toJson<int?>(seasonNumber),
      'episodeNumber': serializer.toJson<double?>(episodeNumber),
      'addonId': serializer.toJson<String>(addonId),
      'sourceId': serializer.toJson<String>(sourceId),
      'serverId': serializer.toJson<String>(serverId),
      'serverTitle': serializer.toJson<String>(serverTitle),
      'voiceoverId': serializer.toJson<String>(voiceoverId),
      'voiceoverTitle': serializer.toJson<String>(voiceoverTitle),
      'qualityId': serializer.toJson<String>(qualityId),
      'qualityLabel': serializer.toJson<String>(qualityLabel),
      'updatedAtMs': serializer.toJson<int>(updatedAtMs),
    };
  }

  StreamPreferenceRecord copyWith({
    String? preferenceId,
    String? localId,
    Value<int?> seasonNumber = const Value.absent(),
    Value<double?> episodeNumber = const Value.absent(),
    String? addonId,
    String? sourceId,
    String? serverId,
    String? serverTitle,
    String? voiceoverId,
    String? voiceoverTitle,
    String? qualityId,
    String? qualityLabel,
    int? updatedAtMs,
  }) => StreamPreferenceRecord(
    preferenceId: preferenceId ?? this.preferenceId,
    localId: localId ?? this.localId,
    seasonNumber: seasonNumber.present ? seasonNumber.value : this.seasonNumber,
    episodeNumber: episodeNumber.present
        ? episodeNumber.value
        : this.episodeNumber,
    addonId: addonId ?? this.addonId,
    sourceId: sourceId ?? this.sourceId,
    serverId: serverId ?? this.serverId,
    serverTitle: serverTitle ?? this.serverTitle,
    voiceoverId: voiceoverId ?? this.voiceoverId,
    voiceoverTitle: voiceoverTitle ?? this.voiceoverTitle,
    qualityId: qualityId ?? this.qualityId,
    qualityLabel: qualityLabel ?? this.qualityLabel,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
  );
  StreamPreferenceRecord copyWithCompanion(
    StreamPreferenceRecordsCompanion data,
  ) {
    return StreamPreferenceRecord(
      preferenceId: data.preferenceId.present
          ? data.preferenceId.value
          : this.preferenceId,
      localId: data.localId.present ? data.localId.value : this.localId,
      seasonNumber: data.seasonNumber.present
          ? data.seasonNumber.value
          : this.seasonNumber,
      episodeNumber: data.episodeNumber.present
          ? data.episodeNumber.value
          : this.episodeNumber,
      addonId: data.addonId.present ? data.addonId.value : this.addonId,
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      serverTitle: data.serverTitle.present
          ? data.serverTitle.value
          : this.serverTitle,
      voiceoverId: data.voiceoverId.present
          ? data.voiceoverId.value
          : this.voiceoverId,
      voiceoverTitle: data.voiceoverTitle.present
          ? data.voiceoverTitle.value
          : this.voiceoverTitle,
      qualityId: data.qualityId.present ? data.qualityId.value : this.qualityId,
      qualityLabel: data.qualityLabel.present
          ? data.qualityLabel.value
          : this.qualityLabel,
      updatedAtMs: data.updatedAtMs.present
          ? data.updatedAtMs.value
          : this.updatedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StreamPreferenceRecord(')
          ..write('preferenceId: $preferenceId, ')
          ..write('localId: $localId, ')
          ..write('seasonNumber: $seasonNumber, ')
          ..write('episodeNumber: $episodeNumber, ')
          ..write('addonId: $addonId, ')
          ..write('sourceId: $sourceId, ')
          ..write('serverId: $serverId, ')
          ..write('serverTitle: $serverTitle, ')
          ..write('voiceoverId: $voiceoverId, ')
          ..write('voiceoverTitle: $voiceoverTitle, ')
          ..write('qualityId: $qualityId, ')
          ..write('qualityLabel: $qualityLabel, ')
          ..write('updatedAtMs: $updatedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    preferenceId,
    localId,
    seasonNumber,
    episodeNumber,
    addonId,
    sourceId,
    serverId,
    serverTitle,
    voiceoverId,
    voiceoverTitle,
    qualityId,
    qualityLabel,
    updatedAtMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StreamPreferenceRecord &&
          other.preferenceId == this.preferenceId &&
          other.localId == this.localId &&
          other.seasonNumber == this.seasonNumber &&
          other.episodeNumber == this.episodeNumber &&
          other.addonId == this.addonId &&
          other.sourceId == this.sourceId &&
          other.serverId == this.serverId &&
          other.serverTitle == this.serverTitle &&
          other.voiceoverId == this.voiceoverId &&
          other.voiceoverTitle == this.voiceoverTitle &&
          other.qualityId == this.qualityId &&
          other.qualityLabel == this.qualityLabel &&
          other.updatedAtMs == this.updatedAtMs);
}

class StreamPreferenceRecordsCompanion
    extends UpdateCompanion<StreamPreferenceRecord> {
  final Value<String> preferenceId;
  final Value<String> localId;
  final Value<int?> seasonNumber;
  final Value<double?> episodeNumber;
  final Value<String> addonId;
  final Value<String> sourceId;
  final Value<String> serverId;
  final Value<String> serverTitle;
  final Value<String> voiceoverId;
  final Value<String> voiceoverTitle;
  final Value<String> qualityId;
  final Value<String> qualityLabel;
  final Value<int> updatedAtMs;
  final Value<int> rowid;
  const StreamPreferenceRecordsCompanion({
    this.preferenceId = const Value.absent(),
    this.localId = const Value.absent(),
    this.seasonNumber = const Value.absent(),
    this.episodeNumber = const Value.absent(),
    this.addonId = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.serverId = const Value.absent(),
    this.serverTitle = const Value.absent(),
    this.voiceoverId = const Value.absent(),
    this.voiceoverTitle = const Value.absent(),
    this.qualityId = const Value.absent(),
    this.qualityLabel = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StreamPreferenceRecordsCompanion.insert({
    required String preferenceId,
    required String localId,
    this.seasonNumber = const Value.absent(),
    this.episodeNumber = const Value.absent(),
    this.addonId = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.serverId = const Value.absent(),
    this.serverTitle = const Value.absent(),
    this.voiceoverId = const Value.absent(),
    this.voiceoverTitle = const Value.absent(),
    this.qualityId = const Value.absent(),
    this.qualityLabel = const Value.absent(),
    required int updatedAtMs,
    this.rowid = const Value.absent(),
  }) : preferenceId = Value(preferenceId),
       localId = Value(localId),
       updatedAtMs = Value(updatedAtMs);
  static Insertable<StreamPreferenceRecord> custom({
    Expression<String>? preferenceId,
    Expression<String>? localId,
    Expression<int>? seasonNumber,
    Expression<double>? episodeNumber,
    Expression<String>? addonId,
    Expression<String>? sourceId,
    Expression<String>? serverId,
    Expression<String>? serverTitle,
    Expression<String>? voiceoverId,
    Expression<String>? voiceoverTitle,
    Expression<String>? qualityId,
    Expression<String>? qualityLabel,
    Expression<int>? updatedAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (preferenceId != null) 'preference_id': preferenceId,
      if (localId != null) 'local_id': localId,
      if (seasonNumber != null) 'season_number': seasonNumber,
      if (episodeNumber != null) 'episode_number': episodeNumber,
      if (addonId != null) 'addon_id': addonId,
      if (sourceId != null) 'source_id': sourceId,
      if (serverId != null) 'server_id': serverId,
      if (serverTitle != null) 'server_title': serverTitle,
      if (voiceoverId != null) 'voiceover_id': voiceoverId,
      if (voiceoverTitle != null) 'voiceover_title': voiceoverTitle,
      if (qualityId != null) 'quality_id': qualityId,
      if (qualityLabel != null) 'quality_label': qualityLabel,
      if (updatedAtMs != null) 'updated_at_ms': updatedAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StreamPreferenceRecordsCompanion copyWith({
    Value<String>? preferenceId,
    Value<String>? localId,
    Value<int?>? seasonNumber,
    Value<double?>? episodeNumber,
    Value<String>? addonId,
    Value<String>? sourceId,
    Value<String>? serverId,
    Value<String>? serverTitle,
    Value<String>? voiceoverId,
    Value<String>? voiceoverTitle,
    Value<String>? qualityId,
    Value<String>? qualityLabel,
    Value<int>? updatedAtMs,
    Value<int>? rowid,
  }) {
    return StreamPreferenceRecordsCompanion(
      preferenceId: preferenceId ?? this.preferenceId,
      localId: localId ?? this.localId,
      seasonNumber: seasonNumber ?? this.seasonNumber,
      episodeNumber: episodeNumber ?? this.episodeNumber,
      addonId: addonId ?? this.addonId,
      sourceId: sourceId ?? this.sourceId,
      serverId: serverId ?? this.serverId,
      serverTitle: serverTitle ?? this.serverTitle,
      voiceoverId: voiceoverId ?? this.voiceoverId,
      voiceoverTitle: voiceoverTitle ?? this.voiceoverTitle,
      qualityId: qualityId ?? this.qualityId,
      qualityLabel: qualityLabel ?? this.qualityLabel,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (preferenceId.present) {
      map['preference_id'] = Variable<String>(preferenceId.value);
    }
    if (localId.present) {
      map['local_id'] = Variable<String>(localId.value);
    }
    if (seasonNumber.present) {
      map['season_number'] = Variable<int>(seasonNumber.value);
    }
    if (episodeNumber.present) {
      map['episode_number'] = Variable<double>(episodeNumber.value);
    }
    if (addonId.present) {
      map['addon_id'] = Variable<String>(addonId.value);
    }
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (serverId.present) {
      map['server_id'] = Variable<String>(serverId.value);
    }
    if (serverTitle.present) {
      map['server_title'] = Variable<String>(serverTitle.value);
    }
    if (voiceoverId.present) {
      map['voiceover_id'] = Variable<String>(voiceoverId.value);
    }
    if (voiceoverTitle.present) {
      map['voiceover_title'] = Variable<String>(voiceoverTitle.value);
    }
    if (qualityId.present) {
      map['quality_id'] = Variable<String>(qualityId.value);
    }
    if (qualityLabel.present) {
      map['quality_label'] = Variable<String>(qualityLabel.value);
    }
    if (updatedAtMs.present) {
      map['updated_at_ms'] = Variable<int>(updatedAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StreamPreferenceRecordsCompanion(')
          ..write('preferenceId: $preferenceId, ')
          ..write('localId: $localId, ')
          ..write('seasonNumber: $seasonNumber, ')
          ..write('episodeNumber: $episodeNumber, ')
          ..write('addonId: $addonId, ')
          ..write('sourceId: $sourceId, ')
          ..write('serverId: $serverId, ')
          ..write('serverTitle: $serverTitle, ')
          ..write('voiceoverId: $voiceoverId, ')
          ..write('voiceoverTitle: $voiceoverTitle, ')
          ..write('qualityId: $qualityId, ')
          ..write('qualityLabel: $qualityLabel, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LibraryOperationRecordsTable extends LibraryOperationRecords
    with TableInfo<$LibraryOperationRecordsTable, LibraryOperationRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LibraryOperationRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _operationIdMeta = const VerificationMeta(
    'operationId',
  );
  @override
  late final GeneratedColumn<String> operationId = GeneratedColumn<String>(
    'operation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localIdMeta = const VerificationMeta(
    'localId',
  );
  @override
  late final GeneratedColumn<String> localId = GeneratedColumn<String>(
    'local_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES canonical_media_records (local_id)',
    ),
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _originKindMeta = const VerificationMeta(
    'originKind',
  );
  @override
  late final GeneratedColumn<String> originKind = GeneratedColumn<String>(
    'origin_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _originIdMeta = const VerificationMeta(
    'originId',
  );
  @override
  late final GeneratedColumn<String> originId = GeneratedColumn<String>(
    'origin_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _intentMeta = const VerificationMeta('intent');
  @override
  late final GeneratedColumn<String> intent = GeneratedColumn<String>(
    'intent',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fieldsJsonMeta = const VerificationMeta(
    'fieldsJson',
  );
  @override
  late final GeneratedColumn<String> fieldsJson = GeneratedColumn<String>(
    'fields_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _beforeJsonMeta = const VerificationMeta(
    'beforeJson',
  );
  @override
  late final GeneratedColumn<String> beforeJson = GeneratedColumn<String>(
    'before_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _afterJsonMeta = const VerificationMeta(
    'afterJson',
  );
  @override
  late final GeneratedColumn<String> afterJson = GeneratedColumn<String>(
    'after_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _baseRevisionsJsonMeta = const VerificationMeta(
    'baseRevisionsJson',
  );
  @override
  late final GeneratedColumn<String> baseRevisionsJson =
      GeneratedColumn<String>(
        'base_revisions_json',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _resultingRevisionsJsonMeta =
      const VerificationMeta('resultingRevisionsJson');
  @override
  late final GeneratedColumn<String> resultingRevisionsJson =
      GeneratedColumn<String>(
        'resulting_revisions_json',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _targetsJsonMeta = const VerificationMeta(
    'targetsJson',
  );
  @override
  late final GeneratedColumn<String> targetsJson = GeneratedColumn<String>(
    'targets_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _undoOfMeta = const VerificationMeta('undoOf');
  @override
  late final GeneratedColumn<String> undoOf = GeneratedColumn<String>(
    'undo_of',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _visibleInLogMeta = const VerificationMeta(
    'visibleInLog',
  );
  @override
  late final GeneratedColumn<bool> visibleInLog = GeneratedColumn<bool>(
    'visible_in_log',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("visible_in_log" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _occurredAtMsMeta = const VerificationMeta(
    'occurredAtMs',
  );
  @override
  late final GeneratedColumn<int> occurredAtMs = GeneratedColumn<int>(
    'occurred_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    operationId,
    localId,
    deviceId,
    originKind,
    originId,
    intent,
    fieldsJson,
    beforeJson,
    afterJson,
    baseRevisionsJson,
    resultingRevisionsJson,
    targetsJson,
    undoOf,
    title,
    visibleInLog,
    occurredAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'library_operation_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<LibraryOperationRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('operation_id')) {
      context.handle(
        _operationIdMeta,
        operationId.isAcceptableOrUnknown(
          data['operation_id']!,
          _operationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_operationIdMeta);
    }
    if (data.containsKey('local_id')) {
      context.handle(
        _localIdMeta,
        localId.isAcceptableOrUnknown(data['local_id']!, _localIdMeta),
      );
    } else if (isInserting) {
      context.missing(_localIdMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('origin_kind')) {
      context.handle(
        _originKindMeta,
        originKind.isAcceptableOrUnknown(data['origin_kind']!, _originKindMeta),
      );
    } else if (isInserting) {
      context.missing(_originKindMeta);
    }
    if (data.containsKey('origin_id')) {
      context.handle(
        _originIdMeta,
        originId.isAcceptableOrUnknown(data['origin_id']!, _originIdMeta),
      );
    }
    if (data.containsKey('intent')) {
      context.handle(
        _intentMeta,
        intent.isAcceptableOrUnknown(data['intent']!, _intentMeta),
      );
    } else if (isInserting) {
      context.missing(_intentMeta);
    }
    if (data.containsKey('fields_json')) {
      context.handle(
        _fieldsJsonMeta,
        fieldsJson.isAcceptableOrUnknown(data['fields_json']!, _fieldsJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_fieldsJsonMeta);
    }
    if (data.containsKey('before_json')) {
      context.handle(
        _beforeJsonMeta,
        beforeJson.isAcceptableOrUnknown(data['before_json']!, _beforeJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_beforeJsonMeta);
    }
    if (data.containsKey('after_json')) {
      context.handle(
        _afterJsonMeta,
        afterJson.isAcceptableOrUnknown(data['after_json']!, _afterJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_afterJsonMeta);
    }
    if (data.containsKey('base_revisions_json')) {
      context.handle(
        _baseRevisionsJsonMeta,
        baseRevisionsJson.isAcceptableOrUnknown(
          data['base_revisions_json']!,
          _baseRevisionsJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_baseRevisionsJsonMeta);
    }
    if (data.containsKey('resulting_revisions_json')) {
      context.handle(
        _resultingRevisionsJsonMeta,
        resultingRevisionsJson.isAcceptableOrUnknown(
          data['resulting_revisions_json']!,
          _resultingRevisionsJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_resultingRevisionsJsonMeta);
    }
    if (data.containsKey('targets_json')) {
      context.handle(
        _targetsJsonMeta,
        targetsJson.isAcceptableOrUnknown(
          data['targets_json']!,
          _targetsJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_targetsJsonMeta);
    }
    if (data.containsKey('undo_of')) {
      context.handle(
        _undoOfMeta,
        undoOf.isAcceptableOrUnknown(data['undo_of']!, _undoOfMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('visible_in_log')) {
      context.handle(
        _visibleInLogMeta,
        visibleInLog.isAcceptableOrUnknown(
          data['visible_in_log']!,
          _visibleInLogMeta,
        ),
      );
    }
    if (data.containsKey('occurred_at_ms')) {
      context.handle(
        _occurredAtMsMeta,
        occurredAtMs.isAcceptableOrUnknown(
          data['occurred_at_ms']!,
          _occurredAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_occurredAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {operationId};
  @override
  LibraryOperationRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LibraryOperationRecord(
      operationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation_id'],
      )!,
      localId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_id'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      originKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin_kind'],
      )!,
      originId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin_id'],
      ),
      intent: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}intent'],
      )!,
      fieldsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fields_json'],
      )!,
      beforeJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}before_json'],
      )!,
      afterJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}after_json'],
      )!,
      baseRevisionsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}base_revisions_json'],
      )!,
      resultingRevisionsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}resulting_revisions_json'],
      )!,
      targetsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}targets_json'],
      )!,
      undoOf: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}undo_of'],
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      ),
      visibleInLog: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}visible_in_log'],
      )!,
      occurredAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}occurred_at_ms'],
      )!,
    );
  }

  @override
  $LibraryOperationRecordsTable createAlias(String alias) {
    return $LibraryOperationRecordsTable(attachedDatabase, alias);
  }
}

class LibraryOperationRecord extends DataClass
    implements Insertable<LibraryOperationRecord> {
  final String operationId;
  final String localId;
  final String deviceId;
  final String originKind;
  final String? originId;
  final String intent;
  final String fieldsJson;
  final String beforeJson;
  final String afterJson;
  final String baseRevisionsJson;
  final String resultingRevisionsJson;
  final String targetsJson;
  final String? undoOf;
  final String? title;
  final bool visibleInLog;
  final int occurredAtMs;
  const LibraryOperationRecord({
    required this.operationId,
    required this.localId,
    required this.deviceId,
    required this.originKind,
    this.originId,
    required this.intent,
    required this.fieldsJson,
    required this.beforeJson,
    required this.afterJson,
    required this.baseRevisionsJson,
    required this.resultingRevisionsJson,
    required this.targetsJson,
    this.undoOf,
    this.title,
    required this.visibleInLog,
    required this.occurredAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['operation_id'] = Variable<String>(operationId);
    map['local_id'] = Variable<String>(localId);
    map['device_id'] = Variable<String>(deviceId);
    map['origin_kind'] = Variable<String>(originKind);
    if (!nullToAbsent || originId != null) {
      map['origin_id'] = Variable<String>(originId);
    }
    map['intent'] = Variable<String>(intent);
    map['fields_json'] = Variable<String>(fieldsJson);
    map['before_json'] = Variable<String>(beforeJson);
    map['after_json'] = Variable<String>(afterJson);
    map['base_revisions_json'] = Variable<String>(baseRevisionsJson);
    map['resulting_revisions_json'] = Variable<String>(resultingRevisionsJson);
    map['targets_json'] = Variable<String>(targetsJson);
    if (!nullToAbsent || undoOf != null) {
      map['undo_of'] = Variable<String>(undoOf);
    }
    if (!nullToAbsent || title != null) {
      map['title'] = Variable<String>(title);
    }
    map['visible_in_log'] = Variable<bool>(visibleInLog);
    map['occurred_at_ms'] = Variable<int>(occurredAtMs);
    return map;
  }

  LibraryOperationRecordsCompanion toCompanion(bool nullToAbsent) {
    return LibraryOperationRecordsCompanion(
      operationId: Value(operationId),
      localId: Value(localId),
      deviceId: Value(deviceId),
      originKind: Value(originKind),
      originId: originId == null && nullToAbsent
          ? const Value.absent()
          : Value(originId),
      intent: Value(intent),
      fieldsJson: Value(fieldsJson),
      beforeJson: Value(beforeJson),
      afterJson: Value(afterJson),
      baseRevisionsJson: Value(baseRevisionsJson),
      resultingRevisionsJson: Value(resultingRevisionsJson),
      targetsJson: Value(targetsJson),
      undoOf: undoOf == null && nullToAbsent
          ? const Value.absent()
          : Value(undoOf),
      title: title == null && nullToAbsent
          ? const Value.absent()
          : Value(title),
      visibleInLog: Value(visibleInLog),
      occurredAtMs: Value(occurredAtMs),
    );
  }

  factory LibraryOperationRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LibraryOperationRecord(
      operationId: serializer.fromJson<String>(json['operationId']),
      localId: serializer.fromJson<String>(json['localId']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      originKind: serializer.fromJson<String>(json['originKind']),
      originId: serializer.fromJson<String?>(json['originId']),
      intent: serializer.fromJson<String>(json['intent']),
      fieldsJson: serializer.fromJson<String>(json['fieldsJson']),
      beforeJson: serializer.fromJson<String>(json['beforeJson']),
      afterJson: serializer.fromJson<String>(json['afterJson']),
      baseRevisionsJson: serializer.fromJson<String>(json['baseRevisionsJson']),
      resultingRevisionsJson: serializer.fromJson<String>(
        json['resultingRevisionsJson'],
      ),
      targetsJson: serializer.fromJson<String>(json['targetsJson']),
      undoOf: serializer.fromJson<String?>(json['undoOf']),
      title: serializer.fromJson<String?>(json['title']),
      visibleInLog: serializer.fromJson<bool>(json['visibleInLog']),
      occurredAtMs: serializer.fromJson<int>(json['occurredAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'operationId': serializer.toJson<String>(operationId),
      'localId': serializer.toJson<String>(localId),
      'deviceId': serializer.toJson<String>(deviceId),
      'originKind': serializer.toJson<String>(originKind),
      'originId': serializer.toJson<String?>(originId),
      'intent': serializer.toJson<String>(intent),
      'fieldsJson': serializer.toJson<String>(fieldsJson),
      'beforeJson': serializer.toJson<String>(beforeJson),
      'afterJson': serializer.toJson<String>(afterJson),
      'baseRevisionsJson': serializer.toJson<String>(baseRevisionsJson),
      'resultingRevisionsJson': serializer.toJson<String>(
        resultingRevisionsJson,
      ),
      'targetsJson': serializer.toJson<String>(targetsJson),
      'undoOf': serializer.toJson<String?>(undoOf),
      'title': serializer.toJson<String?>(title),
      'visibleInLog': serializer.toJson<bool>(visibleInLog),
      'occurredAtMs': serializer.toJson<int>(occurredAtMs),
    };
  }

  LibraryOperationRecord copyWith({
    String? operationId,
    String? localId,
    String? deviceId,
    String? originKind,
    Value<String?> originId = const Value.absent(),
    String? intent,
    String? fieldsJson,
    String? beforeJson,
    String? afterJson,
    String? baseRevisionsJson,
    String? resultingRevisionsJson,
    String? targetsJson,
    Value<String?> undoOf = const Value.absent(),
    Value<String?> title = const Value.absent(),
    bool? visibleInLog,
    int? occurredAtMs,
  }) => LibraryOperationRecord(
    operationId: operationId ?? this.operationId,
    localId: localId ?? this.localId,
    deviceId: deviceId ?? this.deviceId,
    originKind: originKind ?? this.originKind,
    originId: originId.present ? originId.value : this.originId,
    intent: intent ?? this.intent,
    fieldsJson: fieldsJson ?? this.fieldsJson,
    beforeJson: beforeJson ?? this.beforeJson,
    afterJson: afterJson ?? this.afterJson,
    baseRevisionsJson: baseRevisionsJson ?? this.baseRevisionsJson,
    resultingRevisionsJson:
        resultingRevisionsJson ?? this.resultingRevisionsJson,
    targetsJson: targetsJson ?? this.targetsJson,
    undoOf: undoOf.present ? undoOf.value : this.undoOf,
    title: title.present ? title.value : this.title,
    visibleInLog: visibleInLog ?? this.visibleInLog,
    occurredAtMs: occurredAtMs ?? this.occurredAtMs,
  );
  LibraryOperationRecord copyWithCompanion(
    LibraryOperationRecordsCompanion data,
  ) {
    return LibraryOperationRecord(
      operationId: data.operationId.present
          ? data.operationId.value
          : this.operationId,
      localId: data.localId.present ? data.localId.value : this.localId,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      originKind: data.originKind.present
          ? data.originKind.value
          : this.originKind,
      originId: data.originId.present ? data.originId.value : this.originId,
      intent: data.intent.present ? data.intent.value : this.intent,
      fieldsJson: data.fieldsJson.present
          ? data.fieldsJson.value
          : this.fieldsJson,
      beforeJson: data.beforeJson.present
          ? data.beforeJson.value
          : this.beforeJson,
      afterJson: data.afterJson.present ? data.afterJson.value : this.afterJson,
      baseRevisionsJson: data.baseRevisionsJson.present
          ? data.baseRevisionsJson.value
          : this.baseRevisionsJson,
      resultingRevisionsJson: data.resultingRevisionsJson.present
          ? data.resultingRevisionsJson.value
          : this.resultingRevisionsJson,
      targetsJson: data.targetsJson.present
          ? data.targetsJson.value
          : this.targetsJson,
      undoOf: data.undoOf.present ? data.undoOf.value : this.undoOf,
      title: data.title.present ? data.title.value : this.title,
      visibleInLog: data.visibleInLog.present
          ? data.visibleInLog.value
          : this.visibleInLog,
      occurredAtMs: data.occurredAtMs.present
          ? data.occurredAtMs.value
          : this.occurredAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LibraryOperationRecord(')
          ..write('operationId: $operationId, ')
          ..write('localId: $localId, ')
          ..write('deviceId: $deviceId, ')
          ..write('originKind: $originKind, ')
          ..write('originId: $originId, ')
          ..write('intent: $intent, ')
          ..write('fieldsJson: $fieldsJson, ')
          ..write('beforeJson: $beforeJson, ')
          ..write('afterJson: $afterJson, ')
          ..write('baseRevisionsJson: $baseRevisionsJson, ')
          ..write('resultingRevisionsJson: $resultingRevisionsJson, ')
          ..write('targetsJson: $targetsJson, ')
          ..write('undoOf: $undoOf, ')
          ..write('title: $title, ')
          ..write('visibleInLog: $visibleInLog, ')
          ..write('occurredAtMs: $occurredAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    operationId,
    localId,
    deviceId,
    originKind,
    originId,
    intent,
    fieldsJson,
    beforeJson,
    afterJson,
    baseRevisionsJson,
    resultingRevisionsJson,
    targetsJson,
    undoOf,
    title,
    visibleInLog,
    occurredAtMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LibraryOperationRecord &&
          other.operationId == this.operationId &&
          other.localId == this.localId &&
          other.deviceId == this.deviceId &&
          other.originKind == this.originKind &&
          other.originId == this.originId &&
          other.intent == this.intent &&
          other.fieldsJson == this.fieldsJson &&
          other.beforeJson == this.beforeJson &&
          other.afterJson == this.afterJson &&
          other.baseRevisionsJson == this.baseRevisionsJson &&
          other.resultingRevisionsJson == this.resultingRevisionsJson &&
          other.targetsJson == this.targetsJson &&
          other.undoOf == this.undoOf &&
          other.title == this.title &&
          other.visibleInLog == this.visibleInLog &&
          other.occurredAtMs == this.occurredAtMs);
}

class LibraryOperationRecordsCompanion
    extends UpdateCompanion<LibraryOperationRecord> {
  final Value<String> operationId;
  final Value<String> localId;
  final Value<String> deviceId;
  final Value<String> originKind;
  final Value<String?> originId;
  final Value<String> intent;
  final Value<String> fieldsJson;
  final Value<String> beforeJson;
  final Value<String> afterJson;
  final Value<String> baseRevisionsJson;
  final Value<String> resultingRevisionsJson;
  final Value<String> targetsJson;
  final Value<String?> undoOf;
  final Value<String?> title;
  final Value<bool> visibleInLog;
  final Value<int> occurredAtMs;
  final Value<int> rowid;
  const LibraryOperationRecordsCompanion({
    this.operationId = const Value.absent(),
    this.localId = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.originKind = const Value.absent(),
    this.originId = const Value.absent(),
    this.intent = const Value.absent(),
    this.fieldsJson = const Value.absent(),
    this.beforeJson = const Value.absent(),
    this.afterJson = const Value.absent(),
    this.baseRevisionsJson = const Value.absent(),
    this.resultingRevisionsJson = const Value.absent(),
    this.targetsJson = const Value.absent(),
    this.undoOf = const Value.absent(),
    this.title = const Value.absent(),
    this.visibleInLog = const Value.absent(),
    this.occurredAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LibraryOperationRecordsCompanion.insert({
    required String operationId,
    required String localId,
    required String deviceId,
    required String originKind,
    this.originId = const Value.absent(),
    required String intent,
    required String fieldsJson,
    required String beforeJson,
    required String afterJson,
    required String baseRevisionsJson,
    required String resultingRevisionsJson,
    required String targetsJson,
    this.undoOf = const Value.absent(),
    this.title = const Value.absent(),
    this.visibleInLog = const Value.absent(),
    required int occurredAtMs,
    this.rowid = const Value.absent(),
  }) : operationId = Value(operationId),
       localId = Value(localId),
       deviceId = Value(deviceId),
       originKind = Value(originKind),
       intent = Value(intent),
       fieldsJson = Value(fieldsJson),
       beforeJson = Value(beforeJson),
       afterJson = Value(afterJson),
       baseRevisionsJson = Value(baseRevisionsJson),
       resultingRevisionsJson = Value(resultingRevisionsJson),
       targetsJson = Value(targetsJson),
       occurredAtMs = Value(occurredAtMs);
  static Insertable<LibraryOperationRecord> custom({
    Expression<String>? operationId,
    Expression<String>? localId,
    Expression<String>? deviceId,
    Expression<String>? originKind,
    Expression<String>? originId,
    Expression<String>? intent,
    Expression<String>? fieldsJson,
    Expression<String>? beforeJson,
    Expression<String>? afterJson,
    Expression<String>? baseRevisionsJson,
    Expression<String>? resultingRevisionsJson,
    Expression<String>? targetsJson,
    Expression<String>? undoOf,
    Expression<String>? title,
    Expression<bool>? visibleInLog,
    Expression<int>? occurredAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (operationId != null) 'operation_id': operationId,
      if (localId != null) 'local_id': localId,
      if (deviceId != null) 'device_id': deviceId,
      if (originKind != null) 'origin_kind': originKind,
      if (originId != null) 'origin_id': originId,
      if (intent != null) 'intent': intent,
      if (fieldsJson != null) 'fields_json': fieldsJson,
      if (beforeJson != null) 'before_json': beforeJson,
      if (afterJson != null) 'after_json': afterJson,
      if (baseRevisionsJson != null) 'base_revisions_json': baseRevisionsJson,
      if (resultingRevisionsJson != null)
        'resulting_revisions_json': resultingRevisionsJson,
      if (targetsJson != null) 'targets_json': targetsJson,
      if (undoOf != null) 'undo_of': undoOf,
      if (title != null) 'title': title,
      if (visibleInLog != null) 'visible_in_log': visibleInLog,
      if (occurredAtMs != null) 'occurred_at_ms': occurredAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LibraryOperationRecordsCompanion copyWith({
    Value<String>? operationId,
    Value<String>? localId,
    Value<String>? deviceId,
    Value<String>? originKind,
    Value<String?>? originId,
    Value<String>? intent,
    Value<String>? fieldsJson,
    Value<String>? beforeJson,
    Value<String>? afterJson,
    Value<String>? baseRevisionsJson,
    Value<String>? resultingRevisionsJson,
    Value<String>? targetsJson,
    Value<String?>? undoOf,
    Value<String?>? title,
    Value<bool>? visibleInLog,
    Value<int>? occurredAtMs,
    Value<int>? rowid,
  }) {
    return LibraryOperationRecordsCompanion(
      operationId: operationId ?? this.operationId,
      localId: localId ?? this.localId,
      deviceId: deviceId ?? this.deviceId,
      originKind: originKind ?? this.originKind,
      originId: originId ?? this.originId,
      intent: intent ?? this.intent,
      fieldsJson: fieldsJson ?? this.fieldsJson,
      beforeJson: beforeJson ?? this.beforeJson,
      afterJson: afterJson ?? this.afterJson,
      baseRevisionsJson: baseRevisionsJson ?? this.baseRevisionsJson,
      resultingRevisionsJson:
          resultingRevisionsJson ?? this.resultingRevisionsJson,
      targetsJson: targetsJson ?? this.targetsJson,
      undoOf: undoOf ?? this.undoOf,
      title: title ?? this.title,
      visibleInLog: visibleInLog ?? this.visibleInLog,
      occurredAtMs: occurredAtMs ?? this.occurredAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (operationId.present) {
      map['operation_id'] = Variable<String>(operationId.value);
    }
    if (localId.present) {
      map['local_id'] = Variable<String>(localId.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (originKind.present) {
      map['origin_kind'] = Variable<String>(originKind.value);
    }
    if (originId.present) {
      map['origin_id'] = Variable<String>(originId.value);
    }
    if (intent.present) {
      map['intent'] = Variable<String>(intent.value);
    }
    if (fieldsJson.present) {
      map['fields_json'] = Variable<String>(fieldsJson.value);
    }
    if (beforeJson.present) {
      map['before_json'] = Variable<String>(beforeJson.value);
    }
    if (afterJson.present) {
      map['after_json'] = Variable<String>(afterJson.value);
    }
    if (baseRevisionsJson.present) {
      map['base_revisions_json'] = Variable<String>(baseRevisionsJson.value);
    }
    if (resultingRevisionsJson.present) {
      map['resulting_revisions_json'] = Variable<String>(
        resultingRevisionsJson.value,
      );
    }
    if (targetsJson.present) {
      map['targets_json'] = Variable<String>(targetsJson.value);
    }
    if (undoOf.present) {
      map['undo_of'] = Variable<String>(undoOf.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (visibleInLog.present) {
      map['visible_in_log'] = Variable<bool>(visibleInLog.value);
    }
    if (occurredAtMs.present) {
      map['occurred_at_ms'] = Variable<int>(occurredAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LibraryOperationRecordsCompanion(')
          ..write('operationId: $operationId, ')
          ..write('localId: $localId, ')
          ..write('deviceId: $deviceId, ')
          ..write('originKind: $originKind, ')
          ..write('originId: $originId, ')
          ..write('intent: $intent, ')
          ..write('fieldsJson: $fieldsJson, ')
          ..write('beforeJson: $beforeJson, ')
          ..write('afterJson: $afterJson, ')
          ..write('baseRevisionsJson: $baseRevisionsJson, ')
          ..write('resultingRevisionsJson: $resultingRevisionsJson, ')
          ..write('targetsJson: $targetsJson, ')
          ..write('undoOf: $undoOf, ')
          ..write('title: $title, ')
          ..write('visibleInLog: $visibleInLog, ')
          ..write('occurredAtMs: $occurredAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OutboxDeliveryRecordsTable extends OutboxDeliveryRecords
    with TableInfo<$OutboxDeliveryRecordsTable, OutboxDeliveryRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutboxDeliveryRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _deliveryIdMeta = const VerificationMeta(
    'deliveryId',
  );
  @override
  late final GeneratedColumn<String> deliveryId = GeneratedColumn<String>(
    'delivery_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _operationIdMeta = const VerificationMeta(
    'operationId',
  );
  @override
  late final GeneratedColumn<String> operationId = GeneratedColumn<String>(
    'operation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES library_operation_records (operation_id)',
    ),
  );
  static const VerificationMeta _targetMeta = const VerificationMeta('target');
  @override
  late final GeneratedColumn<String> target = GeneratedColumn<String>(
    'target',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _nextAttemptAtMsMeta = const VerificationMeta(
    'nextAttemptAtMs',
  );
  @override
  late final GeneratedColumn<int> nextAttemptAtMs = GeneratedColumn<int>(
    'next_attempt_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deliveredAtMsMeta = const VerificationMeta(
    'deliveredAtMs',
  );
  @override
  late final GeneratedColumn<int> deliveredAtMs = GeneratedColumn<int>(
    'delivered_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _confirmedAtMsMeta = const VerificationMeta(
    'confirmedAtMs',
  );
  @override
  late final GeneratedColumn<int> confirmedAtMs = GeneratedColumn<int>(
    'confirmed_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    deliveryId,
    operationId,
    target,
    accountId,
    state,
    attempts,
    nextAttemptAtMs,
    deliveredAtMs,
    confirmedAtMs,
    lastError,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbox_delivery_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<OutboxDeliveryRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('delivery_id')) {
      context.handle(
        _deliveryIdMeta,
        deliveryId.isAcceptableOrUnknown(data['delivery_id']!, _deliveryIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deliveryIdMeta);
    }
    if (data.containsKey('operation_id')) {
      context.handle(
        _operationIdMeta,
        operationId.isAcceptableOrUnknown(
          data['operation_id']!,
          _operationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_operationIdMeta);
    }
    if (data.containsKey('target')) {
      context.handle(
        _targetMeta,
        target.isAcceptableOrUnknown(data['target']!, _targetMeta),
      );
    } else if (isInserting) {
      context.missing(_targetMeta);
    }
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('next_attempt_at_ms')) {
      context.handle(
        _nextAttemptAtMsMeta,
        nextAttemptAtMs.isAcceptableOrUnknown(
          data['next_attempt_at_ms']!,
          _nextAttemptAtMsMeta,
        ),
      );
    }
    if (data.containsKey('delivered_at_ms')) {
      context.handle(
        _deliveredAtMsMeta,
        deliveredAtMs.isAcceptableOrUnknown(
          data['delivered_at_ms']!,
          _deliveredAtMsMeta,
        ),
      );
    }
    if (data.containsKey('confirmed_at_ms')) {
      context.handle(
        _confirmedAtMsMeta,
        confirmedAtMs.isAcceptableOrUnknown(
          data['confirmed_at_ms']!,
          _confirmedAtMsMeta,
        ),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {deliveryId};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {operationId, target, accountId},
  ];
  @override
  OutboxDeliveryRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboxDeliveryRecord(
      deliveryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}delivery_id'],
      )!,
      operationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation_id'],
      )!,
      target: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target'],
      )!,
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      ),
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      nextAttemptAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}next_attempt_at_ms'],
      ),
      deliveredAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}delivered_at_ms'],
      ),
      confirmedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}confirmed_at_ms'],
      ),
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
    );
  }

  @override
  $OutboxDeliveryRecordsTable createAlias(String alias) {
    return $OutboxDeliveryRecordsTable(attachedDatabase, alias);
  }
}

class OutboxDeliveryRecord extends DataClass
    implements Insertable<OutboxDeliveryRecord> {
  final String deliveryId;
  final String operationId;
  final String target;
  final String? accountId;
  final String state;
  final int attempts;
  final int? nextAttemptAtMs;
  final int? deliveredAtMs;
  final int? confirmedAtMs;
  final String? lastError;
  const OutboxDeliveryRecord({
    required this.deliveryId,
    required this.operationId,
    required this.target,
    this.accountId,
    required this.state,
    required this.attempts,
    this.nextAttemptAtMs,
    this.deliveredAtMs,
    this.confirmedAtMs,
    this.lastError,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['delivery_id'] = Variable<String>(deliveryId);
    map['operation_id'] = Variable<String>(operationId);
    map['target'] = Variable<String>(target);
    if (!nullToAbsent || accountId != null) {
      map['account_id'] = Variable<String>(accountId);
    }
    map['state'] = Variable<String>(state);
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || nextAttemptAtMs != null) {
      map['next_attempt_at_ms'] = Variable<int>(nextAttemptAtMs);
    }
    if (!nullToAbsent || deliveredAtMs != null) {
      map['delivered_at_ms'] = Variable<int>(deliveredAtMs);
    }
    if (!nullToAbsent || confirmedAtMs != null) {
      map['confirmed_at_ms'] = Variable<int>(confirmedAtMs);
    }
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    return map;
  }

  OutboxDeliveryRecordsCompanion toCompanion(bool nullToAbsent) {
    return OutboxDeliveryRecordsCompanion(
      deliveryId: Value(deliveryId),
      operationId: Value(operationId),
      target: Value(target),
      accountId: accountId == null && nullToAbsent
          ? const Value.absent()
          : Value(accountId),
      state: Value(state),
      attempts: Value(attempts),
      nextAttemptAtMs: nextAttemptAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(nextAttemptAtMs),
      deliveredAtMs: deliveredAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(deliveredAtMs),
      confirmedAtMs: confirmedAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(confirmedAtMs),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
    );
  }

  factory OutboxDeliveryRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboxDeliveryRecord(
      deliveryId: serializer.fromJson<String>(json['deliveryId']),
      operationId: serializer.fromJson<String>(json['operationId']),
      target: serializer.fromJson<String>(json['target']),
      accountId: serializer.fromJson<String?>(json['accountId']),
      state: serializer.fromJson<String>(json['state']),
      attempts: serializer.fromJson<int>(json['attempts']),
      nextAttemptAtMs: serializer.fromJson<int?>(json['nextAttemptAtMs']),
      deliveredAtMs: serializer.fromJson<int?>(json['deliveredAtMs']),
      confirmedAtMs: serializer.fromJson<int?>(json['confirmedAtMs']),
      lastError: serializer.fromJson<String?>(json['lastError']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'deliveryId': serializer.toJson<String>(deliveryId),
      'operationId': serializer.toJson<String>(operationId),
      'target': serializer.toJson<String>(target),
      'accountId': serializer.toJson<String?>(accountId),
      'state': serializer.toJson<String>(state),
      'attempts': serializer.toJson<int>(attempts),
      'nextAttemptAtMs': serializer.toJson<int?>(nextAttemptAtMs),
      'deliveredAtMs': serializer.toJson<int?>(deliveredAtMs),
      'confirmedAtMs': serializer.toJson<int?>(confirmedAtMs),
      'lastError': serializer.toJson<String?>(lastError),
    };
  }

  OutboxDeliveryRecord copyWith({
    String? deliveryId,
    String? operationId,
    String? target,
    Value<String?> accountId = const Value.absent(),
    String? state,
    int? attempts,
    Value<int?> nextAttemptAtMs = const Value.absent(),
    Value<int?> deliveredAtMs = const Value.absent(),
    Value<int?> confirmedAtMs = const Value.absent(),
    Value<String?> lastError = const Value.absent(),
  }) => OutboxDeliveryRecord(
    deliveryId: deliveryId ?? this.deliveryId,
    operationId: operationId ?? this.operationId,
    target: target ?? this.target,
    accountId: accountId.present ? accountId.value : this.accountId,
    state: state ?? this.state,
    attempts: attempts ?? this.attempts,
    nextAttemptAtMs: nextAttemptAtMs.present
        ? nextAttemptAtMs.value
        : this.nextAttemptAtMs,
    deliveredAtMs: deliveredAtMs.present
        ? deliveredAtMs.value
        : this.deliveredAtMs,
    confirmedAtMs: confirmedAtMs.present
        ? confirmedAtMs.value
        : this.confirmedAtMs,
    lastError: lastError.present ? lastError.value : this.lastError,
  );
  OutboxDeliveryRecord copyWithCompanion(OutboxDeliveryRecordsCompanion data) {
    return OutboxDeliveryRecord(
      deliveryId: data.deliveryId.present
          ? data.deliveryId.value
          : this.deliveryId,
      operationId: data.operationId.present
          ? data.operationId.value
          : this.operationId,
      target: data.target.present ? data.target.value : this.target,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      state: data.state.present ? data.state.value : this.state,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      nextAttemptAtMs: data.nextAttemptAtMs.present
          ? data.nextAttemptAtMs.value
          : this.nextAttemptAtMs,
      deliveredAtMs: data.deliveredAtMs.present
          ? data.deliveredAtMs.value
          : this.deliveredAtMs,
      confirmedAtMs: data.confirmedAtMs.present
          ? data.confirmedAtMs.value
          : this.confirmedAtMs,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboxDeliveryRecord(')
          ..write('deliveryId: $deliveryId, ')
          ..write('operationId: $operationId, ')
          ..write('target: $target, ')
          ..write('accountId: $accountId, ')
          ..write('state: $state, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAtMs: $nextAttemptAtMs, ')
          ..write('deliveredAtMs: $deliveredAtMs, ')
          ..write('confirmedAtMs: $confirmedAtMs, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    deliveryId,
    operationId,
    target,
    accountId,
    state,
    attempts,
    nextAttemptAtMs,
    deliveredAtMs,
    confirmedAtMs,
    lastError,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboxDeliveryRecord &&
          other.deliveryId == this.deliveryId &&
          other.operationId == this.operationId &&
          other.target == this.target &&
          other.accountId == this.accountId &&
          other.state == this.state &&
          other.attempts == this.attempts &&
          other.nextAttemptAtMs == this.nextAttemptAtMs &&
          other.deliveredAtMs == this.deliveredAtMs &&
          other.confirmedAtMs == this.confirmedAtMs &&
          other.lastError == this.lastError);
}

class OutboxDeliveryRecordsCompanion
    extends UpdateCompanion<OutboxDeliveryRecord> {
  final Value<String> deliveryId;
  final Value<String> operationId;
  final Value<String> target;
  final Value<String?> accountId;
  final Value<String> state;
  final Value<int> attempts;
  final Value<int?> nextAttemptAtMs;
  final Value<int?> deliveredAtMs;
  final Value<int?> confirmedAtMs;
  final Value<String?> lastError;
  final Value<int> rowid;
  const OutboxDeliveryRecordsCompanion({
    this.deliveryId = const Value.absent(),
    this.operationId = const Value.absent(),
    this.target = const Value.absent(),
    this.accountId = const Value.absent(),
    this.state = const Value.absent(),
    this.attempts = const Value.absent(),
    this.nextAttemptAtMs = const Value.absent(),
    this.deliveredAtMs = const Value.absent(),
    this.confirmedAtMs = const Value.absent(),
    this.lastError = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OutboxDeliveryRecordsCompanion.insert({
    required String deliveryId,
    required String operationId,
    required String target,
    this.accountId = const Value.absent(),
    required String state,
    this.attempts = const Value.absent(),
    this.nextAttemptAtMs = const Value.absent(),
    this.deliveredAtMs = const Value.absent(),
    this.confirmedAtMs = const Value.absent(),
    this.lastError = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : deliveryId = Value(deliveryId),
       operationId = Value(operationId),
       target = Value(target),
       state = Value(state);
  static Insertable<OutboxDeliveryRecord> custom({
    Expression<String>? deliveryId,
    Expression<String>? operationId,
    Expression<String>? target,
    Expression<String>? accountId,
    Expression<String>? state,
    Expression<int>? attempts,
    Expression<int>? nextAttemptAtMs,
    Expression<int>? deliveredAtMs,
    Expression<int>? confirmedAtMs,
    Expression<String>? lastError,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (deliveryId != null) 'delivery_id': deliveryId,
      if (operationId != null) 'operation_id': operationId,
      if (target != null) 'target': target,
      if (accountId != null) 'account_id': accountId,
      if (state != null) 'state': state,
      if (attempts != null) 'attempts': attempts,
      if (nextAttemptAtMs != null) 'next_attempt_at_ms': nextAttemptAtMs,
      if (deliveredAtMs != null) 'delivered_at_ms': deliveredAtMs,
      if (confirmedAtMs != null) 'confirmed_at_ms': confirmedAtMs,
      if (lastError != null) 'last_error': lastError,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OutboxDeliveryRecordsCompanion copyWith({
    Value<String>? deliveryId,
    Value<String>? operationId,
    Value<String>? target,
    Value<String?>? accountId,
    Value<String>? state,
    Value<int>? attempts,
    Value<int?>? nextAttemptAtMs,
    Value<int?>? deliveredAtMs,
    Value<int?>? confirmedAtMs,
    Value<String?>? lastError,
    Value<int>? rowid,
  }) {
    return OutboxDeliveryRecordsCompanion(
      deliveryId: deliveryId ?? this.deliveryId,
      operationId: operationId ?? this.operationId,
      target: target ?? this.target,
      accountId: accountId ?? this.accountId,
      state: state ?? this.state,
      attempts: attempts ?? this.attempts,
      nextAttemptAtMs: nextAttemptAtMs ?? this.nextAttemptAtMs,
      deliveredAtMs: deliveredAtMs ?? this.deliveredAtMs,
      confirmedAtMs: confirmedAtMs ?? this.confirmedAtMs,
      lastError: lastError ?? this.lastError,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (deliveryId.present) {
      map['delivery_id'] = Variable<String>(deliveryId.value);
    }
    if (operationId.present) {
      map['operation_id'] = Variable<String>(operationId.value);
    }
    if (target.present) {
      map['target'] = Variable<String>(target.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (nextAttemptAtMs.present) {
      map['next_attempt_at_ms'] = Variable<int>(nextAttemptAtMs.value);
    }
    if (deliveredAtMs.present) {
      map['delivered_at_ms'] = Variable<int>(deliveredAtMs.value);
    }
    if (confirmedAtMs.present) {
      map['confirmed_at_ms'] = Variable<int>(confirmedAtMs.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutboxDeliveryRecordsCompanion(')
          ..write('deliveryId: $deliveryId, ')
          ..write('operationId: $operationId, ')
          ..write('target: $target, ')
          ..write('accountId: $accountId, ')
          ..write('state: $state, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAtMs: $nextAttemptAtMs, ')
          ..write('deliveredAtMs: $deliveredAtMs, ')
          ..write('confirmedAtMs: $confirmedAtMs, ')
          ..write('lastError: $lastError, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LibraryConflictRecordsTable extends LibraryConflictRecords
    with TableInfo<$LibraryConflictRecordsTable, LibraryConflictRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LibraryConflictRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _conflictIdMeta = const VerificationMeta(
    'conflictId',
  );
  @override
  late final GeneratedColumn<String> conflictId = GeneratedColumn<String>(
    'conflict_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localIdMeta = const VerificationMeta(
    'localId',
  );
  @override
  late final GeneratedColumn<String> localId = GeneratedColumn<String>(
    'local_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES canonical_media_records (local_id)',
    ),
  );
  static const VerificationMeta _fieldNameMeta = const VerificationMeta(
    'fieldName',
  );
  @override
  late final GeneratedColumn<String> fieldName = GeneratedColumn<String>(
    'field_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localValueJsonMeta = const VerificationMeta(
    'localValueJson',
  );
  @override
  late final GeneratedColumn<String> localValueJson = GeneratedColumn<String>(
    'local_value_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _incomingValueJsonMeta = const VerificationMeta(
    'incomingValueJson',
  );
  @override
  late final GeneratedColumn<String> incomingValueJson =
      GeneratedColumn<String>(
        'incoming_value_json',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _localOperationIdMeta = const VerificationMeta(
    'localOperationId',
  );
  @override
  late final GeneratedColumn<String> localOperationId = GeneratedColumn<String>(
    'local_operation_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _incomingOperationIdMeta =
      const VerificationMeta('incomingOperationId');
  @override
  late final GeneratedColumn<String> incomingOperationId =
      GeneratedColumn<String>(
        'incoming_operation_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('open'),
  );
  static const VerificationMeta _createdAtMsMeta = const VerificationMeta(
    'createdAtMs',
  );
  @override
  late final GeneratedColumn<int> createdAtMs = GeneratedColumn<int>(
    'created_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _resolvedAtMsMeta = const VerificationMeta(
    'resolvedAtMs',
  );
  @override
  late final GeneratedColumn<int> resolvedAtMs = GeneratedColumn<int>(
    'resolved_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    conflictId,
    localId,
    fieldName,
    localValueJson,
    incomingValueJson,
    localOperationId,
    incomingOperationId,
    state,
    createdAtMs,
    resolvedAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'library_conflict_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<LibraryConflictRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('conflict_id')) {
      context.handle(
        _conflictIdMeta,
        conflictId.isAcceptableOrUnknown(data['conflict_id']!, _conflictIdMeta),
      );
    } else if (isInserting) {
      context.missing(_conflictIdMeta);
    }
    if (data.containsKey('local_id')) {
      context.handle(
        _localIdMeta,
        localId.isAcceptableOrUnknown(data['local_id']!, _localIdMeta),
      );
    } else if (isInserting) {
      context.missing(_localIdMeta);
    }
    if (data.containsKey('field_name')) {
      context.handle(
        _fieldNameMeta,
        fieldName.isAcceptableOrUnknown(data['field_name']!, _fieldNameMeta),
      );
    } else if (isInserting) {
      context.missing(_fieldNameMeta);
    }
    if (data.containsKey('local_value_json')) {
      context.handle(
        _localValueJsonMeta,
        localValueJson.isAcceptableOrUnknown(
          data['local_value_json']!,
          _localValueJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_localValueJsonMeta);
    }
    if (data.containsKey('incoming_value_json')) {
      context.handle(
        _incomingValueJsonMeta,
        incomingValueJson.isAcceptableOrUnknown(
          data['incoming_value_json']!,
          _incomingValueJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_incomingValueJsonMeta);
    }
    if (data.containsKey('local_operation_id')) {
      context.handle(
        _localOperationIdMeta,
        localOperationId.isAcceptableOrUnknown(
          data['local_operation_id']!,
          _localOperationIdMeta,
        ),
      );
    }
    if (data.containsKey('incoming_operation_id')) {
      context.handle(
        _incomingOperationIdMeta,
        incomingOperationId.isAcceptableOrUnknown(
          data['incoming_operation_id']!,
          _incomingOperationIdMeta,
        ),
      );
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    }
    if (data.containsKey('created_at_ms')) {
      context.handle(
        _createdAtMsMeta,
        createdAtMs.isAcceptableOrUnknown(
          data['created_at_ms']!,
          _createdAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMsMeta);
    }
    if (data.containsKey('resolved_at_ms')) {
      context.handle(
        _resolvedAtMsMeta,
        resolvedAtMs.isAcceptableOrUnknown(
          data['resolved_at_ms']!,
          _resolvedAtMsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {conflictId};
  @override
  LibraryConflictRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LibraryConflictRecord(
      conflictId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conflict_id'],
      )!,
      localId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_id'],
      )!,
      fieldName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}field_name'],
      )!,
      localValueJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_value_json'],
      )!,
      incomingValueJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}incoming_value_json'],
      )!,
      localOperationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_operation_id'],
      ),
      incomingOperationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}incoming_operation_id'],
      ),
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      createdAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_ms'],
      )!,
      resolvedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}resolved_at_ms'],
      ),
    );
  }

  @override
  $LibraryConflictRecordsTable createAlias(String alias) {
    return $LibraryConflictRecordsTable(attachedDatabase, alias);
  }
}

class LibraryConflictRecord extends DataClass
    implements Insertable<LibraryConflictRecord> {
  final String conflictId;
  final String localId;
  final String fieldName;
  final String localValueJson;
  final String incomingValueJson;
  final String? localOperationId;
  final String? incomingOperationId;
  final String state;
  final int createdAtMs;
  final int? resolvedAtMs;
  const LibraryConflictRecord({
    required this.conflictId,
    required this.localId,
    required this.fieldName,
    required this.localValueJson,
    required this.incomingValueJson,
    this.localOperationId,
    this.incomingOperationId,
    required this.state,
    required this.createdAtMs,
    this.resolvedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['conflict_id'] = Variable<String>(conflictId);
    map['local_id'] = Variable<String>(localId);
    map['field_name'] = Variable<String>(fieldName);
    map['local_value_json'] = Variable<String>(localValueJson);
    map['incoming_value_json'] = Variable<String>(incomingValueJson);
    if (!nullToAbsent || localOperationId != null) {
      map['local_operation_id'] = Variable<String>(localOperationId);
    }
    if (!nullToAbsent || incomingOperationId != null) {
      map['incoming_operation_id'] = Variable<String>(incomingOperationId);
    }
    map['state'] = Variable<String>(state);
    map['created_at_ms'] = Variable<int>(createdAtMs);
    if (!nullToAbsent || resolvedAtMs != null) {
      map['resolved_at_ms'] = Variable<int>(resolvedAtMs);
    }
    return map;
  }

  LibraryConflictRecordsCompanion toCompanion(bool nullToAbsent) {
    return LibraryConflictRecordsCompanion(
      conflictId: Value(conflictId),
      localId: Value(localId),
      fieldName: Value(fieldName),
      localValueJson: Value(localValueJson),
      incomingValueJson: Value(incomingValueJson),
      localOperationId: localOperationId == null && nullToAbsent
          ? const Value.absent()
          : Value(localOperationId),
      incomingOperationId: incomingOperationId == null && nullToAbsent
          ? const Value.absent()
          : Value(incomingOperationId),
      state: Value(state),
      createdAtMs: Value(createdAtMs),
      resolvedAtMs: resolvedAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(resolvedAtMs),
    );
  }

  factory LibraryConflictRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LibraryConflictRecord(
      conflictId: serializer.fromJson<String>(json['conflictId']),
      localId: serializer.fromJson<String>(json['localId']),
      fieldName: serializer.fromJson<String>(json['fieldName']),
      localValueJson: serializer.fromJson<String>(json['localValueJson']),
      incomingValueJson: serializer.fromJson<String>(json['incomingValueJson']),
      localOperationId: serializer.fromJson<String?>(json['localOperationId']),
      incomingOperationId: serializer.fromJson<String?>(
        json['incomingOperationId'],
      ),
      state: serializer.fromJson<String>(json['state']),
      createdAtMs: serializer.fromJson<int>(json['createdAtMs']),
      resolvedAtMs: serializer.fromJson<int?>(json['resolvedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'conflictId': serializer.toJson<String>(conflictId),
      'localId': serializer.toJson<String>(localId),
      'fieldName': serializer.toJson<String>(fieldName),
      'localValueJson': serializer.toJson<String>(localValueJson),
      'incomingValueJson': serializer.toJson<String>(incomingValueJson),
      'localOperationId': serializer.toJson<String?>(localOperationId),
      'incomingOperationId': serializer.toJson<String?>(incomingOperationId),
      'state': serializer.toJson<String>(state),
      'createdAtMs': serializer.toJson<int>(createdAtMs),
      'resolvedAtMs': serializer.toJson<int?>(resolvedAtMs),
    };
  }

  LibraryConflictRecord copyWith({
    String? conflictId,
    String? localId,
    String? fieldName,
    String? localValueJson,
    String? incomingValueJson,
    Value<String?> localOperationId = const Value.absent(),
    Value<String?> incomingOperationId = const Value.absent(),
    String? state,
    int? createdAtMs,
    Value<int?> resolvedAtMs = const Value.absent(),
  }) => LibraryConflictRecord(
    conflictId: conflictId ?? this.conflictId,
    localId: localId ?? this.localId,
    fieldName: fieldName ?? this.fieldName,
    localValueJson: localValueJson ?? this.localValueJson,
    incomingValueJson: incomingValueJson ?? this.incomingValueJson,
    localOperationId: localOperationId.present
        ? localOperationId.value
        : this.localOperationId,
    incomingOperationId: incomingOperationId.present
        ? incomingOperationId.value
        : this.incomingOperationId,
    state: state ?? this.state,
    createdAtMs: createdAtMs ?? this.createdAtMs,
    resolvedAtMs: resolvedAtMs.present ? resolvedAtMs.value : this.resolvedAtMs,
  );
  LibraryConflictRecord copyWithCompanion(
    LibraryConflictRecordsCompanion data,
  ) {
    return LibraryConflictRecord(
      conflictId: data.conflictId.present
          ? data.conflictId.value
          : this.conflictId,
      localId: data.localId.present ? data.localId.value : this.localId,
      fieldName: data.fieldName.present ? data.fieldName.value : this.fieldName,
      localValueJson: data.localValueJson.present
          ? data.localValueJson.value
          : this.localValueJson,
      incomingValueJson: data.incomingValueJson.present
          ? data.incomingValueJson.value
          : this.incomingValueJson,
      localOperationId: data.localOperationId.present
          ? data.localOperationId.value
          : this.localOperationId,
      incomingOperationId: data.incomingOperationId.present
          ? data.incomingOperationId.value
          : this.incomingOperationId,
      state: data.state.present ? data.state.value : this.state,
      createdAtMs: data.createdAtMs.present
          ? data.createdAtMs.value
          : this.createdAtMs,
      resolvedAtMs: data.resolvedAtMs.present
          ? data.resolvedAtMs.value
          : this.resolvedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LibraryConflictRecord(')
          ..write('conflictId: $conflictId, ')
          ..write('localId: $localId, ')
          ..write('fieldName: $fieldName, ')
          ..write('localValueJson: $localValueJson, ')
          ..write('incomingValueJson: $incomingValueJson, ')
          ..write('localOperationId: $localOperationId, ')
          ..write('incomingOperationId: $incomingOperationId, ')
          ..write('state: $state, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('resolvedAtMs: $resolvedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    conflictId,
    localId,
    fieldName,
    localValueJson,
    incomingValueJson,
    localOperationId,
    incomingOperationId,
    state,
    createdAtMs,
    resolvedAtMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LibraryConflictRecord &&
          other.conflictId == this.conflictId &&
          other.localId == this.localId &&
          other.fieldName == this.fieldName &&
          other.localValueJson == this.localValueJson &&
          other.incomingValueJson == this.incomingValueJson &&
          other.localOperationId == this.localOperationId &&
          other.incomingOperationId == this.incomingOperationId &&
          other.state == this.state &&
          other.createdAtMs == this.createdAtMs &&
          other.resolvedAtMs == this.resolvedAtMs);
}

class LibraryConflictRecordsCompanion
    extends UpdateCompanion<LibraryConflictRecord> {
  final Value<String> conflictId;
  final Value<String> localId;
  final Value<String> fieldName;
  final Value<String> localValueJson;
  final Value<String> incomingValueJson;
  final Value<String?> localOperationId;
  final Value<String?> incomingOperationId;
  final Value<String> state;
  final Value<int> createdAtMs;
  final Value<int?> resolvedAtMs;
  final Value<int> rowid;
  const LibraryConflictRecordsCompanion({
    this.conflictId = const Value.absent(),
    this.localId = const Value.absent(),
    this.fieldName = const Value.absent(),
    this.localValueJson = const Value.absent(),
    this.incomingValueJson = const Value.absent(),
    this.localOperationId = const Value.absent(),
    this.incomingOperationId = const Value.absent(),
    this.state = const Value.absent(),
    this.createdAtMs = const Value.absent(),
    this.resolvedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LibraryConflictRecordsCompanion.insert({
    required String conflictId,
    required String localId,
    required String fieldName,
    required String localValueJson,
    required String incomingValueJson,
    this.localOperationId = const Value.absent(),
    this.incomingOperationId = const Value.absent(),
    this.state = const Value.absent(),
    required int createdAtMs,
    this.resolvedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : conflictId = Value(conflictId),
       localId = Value(localId),
       fieldName = Value(fieldName),
       localValueJson = Value(localValueJson),
       incomingValueJson = Value(incomingValueJson),
       createdAtMs = Value(createdAtMs);
  static Insertable<LibraryConflictRecord> custom({
    Expression<String>? conflictId,
    Expression<String>? localId,
    Expression<String>? fieldName,
    Expression<String>? localValueJson,
    Expression<String>? incomingValueJson,
    Expression<String>? localOperationId,
    Expression<String>? incomingOperationId,
    Expression<String>? state,
    Expression<int>? createdAtMs,
    Expression<int>? resolvedAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (conflictId != null) 'conflict_id': conflictId,
      if (localId != null) 'local_id': localId,
      if (fieldName != null) 'field_name': fieldName,
      if (localValueJson != null) 'local_value_json': localValueJson,
      if (incomingValueJson != null) 'incoming_value_json': incomingValueJson,
      if (localOperationId != null) 'local_operation_id': localOperationId,
      if (incomingOperationId != null)
        'incoming_operation_id': incomingOperationId,
      if (state != null) 'state': state,
      if (createdAtMs != null) 'created_at_ms': createdAtMs,
      if (resolvedAtMs != null) 'resolved_at_ms': resolvedAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LibraryConflictRecordsCompanion copyWith({
    Value<String>? conflictId,
    Value<String>? localId,
    Value<String>? fieldName,
    Value<String>? localValueJson,
    Value<String>? incomingValueJson,
    Value<String?>? localOperationId,
    Value<String?>? incomingOperationId,
    Value<String>? state,
    Value<int>? createdAtMs,
    Value<int?>? resolvedAtMs,
    Value<int>? rowid,
  }) {
    return LibraryConflictRecordsCompanion(
      conflictId: conflictId ?? this.conflictId,
      localId: localId ?? this.localId,
      fieldName: fieldName ?? this.fieldName,
      localValueJson: localValueJson ?? this.localValueJson,
      incomingValueJson: incomingValueJson ?? this.incomingValueJson,
      localOperationId: localOperationId ?? this.localOperationId,
      incomingOperationId: incomingOperationId ?? this.incomingOperationId,
      state: state ?? this.state,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      resolvedAtMs: resolvedAtMs ?? this.resolvedAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (conflictId.present) {
      map['conflict_id'] = Variable<String>(conflictId.value);
    }
    if (localId.present) {
      map['local_id'] = Variable<String>(localId.value);
    }
    if (fieldName.present) {
      map['field_name'] = Variable<String>(fieldName.value);
    }
    if (localValueJson.present) {
      map['local_value_json'] = Variable<String>(localValueJson.value);
    }
    if (incomingValueJson.present) {
      map['incoming_value_json'] = Variable<String>(incomingValueJson.value);
    }
    if (localOperationId.present) {
      map['local_operation_id'] = Variable<String>(localOperationId.value);
    }
    if (incomingOperationId.present) {
      map['incoming_operation_id'] = Variable<String>(
        incomingOperationId.value,
      );
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (createdAtMs.present) {
      map['created_at_ms'] = Variable<int>(createdAtMs.value);
    }
    if (resolvedAtMs.present) {
      map['resolved_at_ms'] = Variable<int>(resolvedAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LibraryConflictRecordsCompanion(')
          ..write('conflictId: $conflictId, ')
          ..write('localId: $localId, ')
          ..write('fieldName: $fieldName, ')
          ..write('localValueJson: $localValueJson, ')
          ..write('incomingValueJson: $incomingValueJson, ')
          ..write('localOperationId: $localOperationId, ')
          ..write('incomingOperationId: $incomingOperationId, ')
          ..write('state: $state, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('resolvedAtMs: $resolvedAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncCursorRecordsTable extends SyncCursorRecords
    with TableInfo<$SyncCursorRecordsTable, SyncCursorRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncCursorRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _scopeMeta = const VerificationMeta('scope');
  @override
  late final GeneratedColumn<String> scope = GeneratedColumn<String>(
    'scope',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cursorMeta = const VerificationMeta('cursor');
  @override
  late final GeneratedColumn<String> cursor = GeneratedColumn<String>(
    'cursor',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _metadataJsonMeta = const VerificationMeta(
    'metadataJson',
  );
  @override
  late final GeneratedColumn<String> metadataJson = GeneratedColumn<String>(
    'metadata_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _updatedAtMsMeta = const VerificationMeta(
    'updatedAtMs',
  );
  @override
  late final GeneratedColumn<int> updatedAtMs = GeneratedColumn<int>(
    'updated_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    scope,
    cursor,
    metadataJson,
    updatedAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_cursor_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncCursorRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('scope')) {
      context.handle(
        _scopeMeta,
        scope.isAcceptableOrUnknown(data['scope']!, _scopeMeta),
      );
    } else if (isInserting) {
      context.missing(_scopeMeta);
    }
    if (data.containsKey('cursor')) {
      context.handle(
        _cursorMeta,
        cursor.isAcceptableOrUnknown(data['cursor']!, _cursorMeta),
      );
    } else if (isInserting) {
      context.missing(_cursorMeta);
    }
    if (data.containsKey('metadata_json')) {
      context.handle(
        _metadataJsonMeta,
        metadataJson.isAcceptableOrUnknown(
          data['metadata_json']!,
          _metadataJsonMeta,
        ),
      );
    }
    if (data.containsKey('updated_at_ms')) {
      context.handle(
        _updatedAtMsMeta,
        updatedAtMs.isAcceptableOrUnknown(
          data['updated_at_ms']!,
          _updatedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {scope};
  @override
  SyncCursorRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncCursorRecord(
      scope: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope'],
      )!,
      cursor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cursor'],
      )!,
      metadataJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}metadata_json'],
      )!,
      updatedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_ms'],
      )!,
    );
  }

  @override
  $SyncCursorRecordsTable createAlias(String alias) {
    return $SyncCursorRecordsTable(attachedDatabase, alias);
  }
}

class SyncCursorRecord extends DataClass
    implements Insertable<SyncCursorRecord> {
  final String scope;
  final String cursor;
  final String metadataJson;
  final int updatedAtMs;
  const SyncCursorRecord({
    required this.scope,
    required this.cursor,
    required this.metadataJson,
    required this.updatedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['scope'] = Variable<String>(scope);
    map['cursor'] = Variable<String>(cursor);
    map['metadata_json'] = Variable<String>(metadataJson);
    map['updated_at_ms'] = Variable<int>(updatedAtMs);
    return map;
  }

  SyncCursorRecordsCompanion toCompanion(bool nullToAbsent) {
    return SyncCursorRecordsCompanion(
      scope: Value(scope),
      cursor: Value(cursor),
      metadataJson: Value(metadataJson),
      updatedAtMs: Value(updatedAtMs),
    );
  }

  factory SyncCursorRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncCursorRecord(
      scope: serializer.fromJson<String>(json['scope']),
      cursor: serializer.fromJson<String>(json['cursor']),
      metadataJson: serializer.fromJson<String>(json['metadataJson']),
      updatedAtMs: serializer.fromJson<int>(json['updatedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'scope': serializer.toJson<String>(scope),
      'cursor': serializer.toJson<String>(cursor),
      'metadataJson': serializer.toJson<String>(metadataJson),
      'updatedAtMs': serializer.toJson<int>(updatedAtMs),
    };
  }

  SyncCursorRecord copyWith({
    String? scope,
    String? cursor,
    String? metadataJson,
    int? updatedAtMs,
  }) => SyncCursorRecord(
    scope: scope ?? this.scope,
    cursor: cursor ?? this.cursor,
    metadataJson: metadataJson ?? this.metadataJson,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
  );
  SyncCursorRecord copyWithCompanion(SyncCursorRecordsCompanion data) {
    return SyncCursorRecord(
      scope: data.scope.present ? data.scope.value : this.scope,
      cursor: data.cursor.present ? data.cursor.value : this.cursor,
      metadataJson: data.metadataJson.present
          ? data.metadataJson.value
          : this.metadataJson,
      updatedAtMs: data.updatedAtMs.present
          ? data.updatedAtMs.value
          : this.updatedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncCursorRecord(')
          ..write('scope: $scope, ')
          ..write('cursor: $cursor, ')
          ..write('metadataJson: $metadataJson, ')
          ..write('updatedAtMs: $updatedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(scope, cursor, metadataJson, updatedAtMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncCursorRecord &&
          other.scope == this.scope &&
          other.cursor == this.cursor &&
          other.metadataJson == this.metadataJson &&
          other.updatedAtMs == this.updatedAtMs);
}

class SyncCursorRecordsCompanion extends UpdateCompanion<SyncCursorRecord> {
  final Value<String> scope;
  final Value<String> cursor;
  final Value<String> metadataJson;
  final Value<int> updatedAtMs;
  final Value<int> rowid;
  const SyncCursorRecordsCompanion({
    this.scope = const Value.absent(),
    this.cursor = const Value.absent(),
    this.metadataJson = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncCursorRecordsCompanion.insert({
    required String scope,
    required String cursor,
    this.metadataJson = const Value.absent(),
    required int updatedAtMs,
    this.rowid = const Value.absent(),
  }) : scope = Value(scope),
       cursor = Value(cursor),
       updatedAtMs = Value(updatedAtMs);
  static Insertable<SyncCursorRecord> custom({
    Expression<String>? scope,
    Expression<String>? cursor,
    Expression<String>? metadataJson,
    Expression<int>? updatedAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (scope != null) 'scope': scope,
      if (cursor != null) 'cursor': cursor,
      if (metadataJson != null) 'metadata_json': metadataJson,
      if (updatedAtMs != null) 'updated_at_ms': updatedAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncCursorRecordsCompanion copyWith({
    Value<String>? scope,
    Value<String>? cursor,
    Value<String>? metadataJson,
    Value<int>? updatedAtMs,
    Value<int>? rowid,
  }) {
    return SyncCursorRecordsCompanion(
      scope: scope ?? this.scope,
      cursor: cursor ?? this.cursor,
      metadataJson: metadataJson ?? this.metadataJson,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (scope.present) {
      map['scope'] = Variable<String>(scope.value);
    }
    if (cursor.present) {
      map['cursor'] = Variable<String>(cursor.value);
    }
    if (metadataJson.present) {
      map['metadata_json'] = Variable<String>(metadataJson.value);
    }
    if (updatedAtMs.present) {
      map['updated_at_ms'] = Variable<int>(updatedAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncCursorRecordsCompanion(')
          ..write('scope: $scope, ')
          ..write('cursor: $cursor, ')
          ..write('metadataJson: $metadataJson, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProviderHealthRecordsTable extends ProviderHealthRecords
    with TableInfo<$ProviderHealthRecordsTable, ProviderHealthRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProviderHealthRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _providerMeta = const VerificationMeta(
    'provider',
  );
  @override
  late final GeneratedColumn<String> provider = GeneratedColumn<String>(
    'provider',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _healthJsonMeta = const VerificationMeta(
    'healthJson',
  );
  @override
  late final GeneratedColumn<String> healthJson = GeneratedColumn<String>(
    'health_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMsMeta = const VerificationMeta(
    'updatedAtMs',
  );
  @override
  late final GeneratedColumn<int> updatedAtMs = GeneratedColumn<int>(
    'updated_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [provider, healthJson, updatedAtMs];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'provider_health_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProviderHealthRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('provider')) {
      context.handle(
        _providerMeta,
        provider.isAcceptableOrUnknown(data['provider']!, _providerMeta),
      );
    } else if (isInserting) {
      context.missing(_providerMeta);
    }
    if (data.containsKey('health_json')) {
      context.handle(
        _healthJsonMeta,
        healthJson.isAcceptableOrUnknown(data['health_json']!, _healthJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_healthJsonMeta);
    }
    if (data.containsKey('updated_at_ms')) {
      context.handle(
        _updatedAtMsMeta,
        updatedAtMs.isAcceptableOrUnknown(
          data['updated_at_ms']!,
          _updatedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {provider};
  @override
  ProviderHealthRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProviderHealthRecord(
      provider: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provider'],
      )!,
      healthJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}health_json'],
      )!,
      updatedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_ms'],
      )!,
    );
  }

  @override
  $ProviderHealthRecordsTable createAlias(String alias) {
    return $ProviderHealthRecordsTable(attachedDatabase, alias);
  }
}

class ProviderHealthRecord extends DataClass
    implements Insertable<ProviderHealthRecord> {
  final String provider;
  final String healthJson;
  final int updatedAtMs;
  const ProviderHealthRecord({
    required this.provider,
    required this.healthJson,
    required this.updatedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['provider'] = Variable<String>(provider);
    map['health_json'] = Variable<String>(healthJson);
    map['updated_at_ms'] = Variable<int>(updatedAtMs);
    return map;
  }

  ProviderHealthRecordsCompanion toCompanion(bool nullToAbsent) {
    return ProviderHealthRecordsCompanion(
      provider: Value(provider),
      healthJson: Value(healthJson),
      updatedAtMs: Value(updatedAtMs),
    );
  }

  factory ProviderHealthRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProviderHealthRecord(
      provider: serializer.fromJson<String>(json['provider']),
      healthJson: serializer.fromJson<String>(json['healthJson']),
      updatedAtMs: serializer.fromJson<int>(json['updatedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'provider': serializer.toJson<String>(provider),
      'healthJson': serializer.toJson<String>(healthJson),
      'updatedAtMs': serializer.toJson<int>(updatedAtMs),
    };
  }

  ProviderHealthRecord copyWith({
    String? provider,
    String? healthJson,
    int? updatedAtMs,
  }) => ProviderHealthRecord(
    provider: provider ?? this.provider,
    healthJson: healthJson ?? this.healthJson,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
  );
  ProviderHealthRecord copyWithCompanion(ProviderHealthRecordsCompanion data) {
    return ProviderHealthRecord(
      provider: data.provider.present ? data.provider.value : this.provider,
      healthJson: data.healthJson.present
          ? data.healthJson.value
          : this.healthJson,
      updatedAtMs: data.updatedAtMs.present
          ? data.updatedAtMs.value
          : this.updatedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProviderHealthRecord(')
          ..write('provider: $provider, ')
          ..write('healthJson: $healthJson, ')
          ..write('updatedAtMs: $updatedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(provider, healthJson, updatedAtMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProviderHealthRecord &&
          other.provider == this.provider &&
          other.healthJson == this.healthJson &&
          other.updatedAtMs == this.updatedAtMs);
}

class ProviderHealthRecordsCompanion
    extends UpdateCompanion<ProviderHealthRecord> {
  final Value<String> provider;
  final Value<String> healthJson;
  final Value<int> updatedAtMs;
  final Value<int> rowid;
  const ProviderHealthRecordsCompanion({
    this.provider = const Value.absent(),
    this.healthJson = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProviderHealthRecordsCompanion.insert({
    required String provider,
    required String healthJson,
    required int updatedAtMs,
    this.rowid = const Value.absent(),
  }) : provider = Value(provider),
       healthJson = Value(healthJson),
       updatedAtMs = Value(updatedAtMs);
  static Insertable<ProviderHealthRecord> custom({
    Expression<String>? provider,
    Expression<String>? healthJson,
    Expression<int>? updatedAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (provider != null) 'provider': provider,
      if (healthJson != null) 'health_json': healthJson,
      if (updatedAtMs != null) 'updated_at_ms': updatedAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProviderHealthRecordsCompanion copyWith({
    Value<String>? provider,
    Value<String>? healthJson,
    Value<int>? updatedAtMs,
    Value<int>? rowid,
  }) {
    return ProviderHealthRecordsCompanion(
      provider: provider ?? this.provider,
      healthJson: healthJson ?? this.healthJson,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (provider.present) {
      map['provider'] = Variable<String>(provider.value);
    }
    if (healthJson.present) {
      map['health_json'] = Variable<String>(healthJson.value);
    }
    if (updatedAtMs.present) {
      map['updated_at_ms'] = Variable<int>(updatedAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProviderHealthRecordsCompanion(')
          ..write('provider: $provider, ')
          ..write('healthJson: $healthJson, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LegacyBucketRecordsTable extends LegacyBucketRecords
    with TableInfo<$LegacyBucketRecordsTable, LegacyBucketRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LegacyBucketRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _bucketMeta = const VerificationMeta('bucket');
  @override
  late final GeneratedColumn<String> bucket = GeneratedColumn<String>(
    'bucket',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueJsonMeta = const VerificationMeta(
    'valueJson',
  );
  @override
  late final GeneratedColumn<String> valueJson = GeneratedColumn<String>(
    'value_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMsMeta = const VerificationMeta(
    'updatedAtMs',
  );
  @override
  late final GeneratedColumn<int> updatedAtMs = GeneratedColumn<int>(
    'updated_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [bucket, valueJson, updatedAtMs];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'legacy_bucket_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<LegacyBucketRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('bucket')) {
      context.handle(
        _bucketMeta,
        bucket.isAcceptableOrUnknown(data['bucket']!, _bucketMeta),
      );
    } else if (isInserting) {
      context.missing(_bucketMeta);
    }
    if (data.containsKey('value_json')) {
      context.handle(
        _valueJsonMeta,
        valueJson.isAcceptableOrUnknown(data['value_json']!, _valueJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_valueJsonMeta);
    }
    if (data.containsKey('updated_at_ms')) {
      context.handle(
        _updatedAtMsMeta,
        updatedAtMs.isAcceptableOrUnknown(
          data['updated_at_ms']!,
          _updatedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {bucket};
  @override
  LegacyBucketRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LegacyBucketRecord(
      bucket: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}bucket'],
      )!,
      valueJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value_json'],
      )!,
      updatedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_ms'],
      )!,
    );
  }

  @override
  $LegacyBucketRecordsTable createAlias(String alias) {
    return $LegacyBucketRecordsTable(attachedDatabase, alias);
  }
}

class LegacyBucketRecord extends DataClass
    implements Insertable<LegacyBucketRecord> {
  final String bucket;
  final String valueJson;
  final int updatedAtMs;
  const LegacyBucketRecord({
    required this.bucket,
    required this.valueJson,
    required this.updatedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['bucket'] = Variable<String>(bucket);
    map['value_json'] = Variable<String>(valueJson);
    map['updated_at_ms'] = Variable<int>(updatedAtMs);
    return map;
  }

  LegacyBucketRecordsCompanion toCompanion(bool nullToAbsent) {
    return LegacyBucketRecordsCompanion(
      bucket: Value(bucket),
      valueJson: Value(valueJson),
      updatedAtMs: Value(updatedAtMs),
    );
  }

  factory LegacyBucketRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LegacyBucketRecord(
      bucket: serializer.fromJson<String>(json['bucket']),
      valueJson: serializer.fromJson<String>(json['valueJson']),
      updatedAtMs: serializer.fromJson<int>(json['updatedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'bucket': serializer.toJson<String>(bucket),
      'valueJson': serializer.toJson<String>(valueJson),
      'updatedAtMs': serializer.toJson<int>(updatedAtMs),
    };
  }

  LegacyBucketRecord copyWith({
    String? bucket,
    String? valueJson,
    int? updatedAtMs,
  }) => LegacyBucketRecord(
    bucket: bucket ?? this.bucket,
    valueJson: valueJson ?? this.valueJson,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
  );
  LegacyBucketRecord copyWithCompanion(LegacyBucketRecordsCompanion data) {
    return LegacyBucketRecord(
      bucket: data.bucket.present ? data.bucket.value : this.bucket,
      valueJson: data.valueJson.present ? data.valueJson.value : this.valueJson,
      updatedAtMs: data.updatedAtMs.present
          ? data.updatedAtMs.value
          : this.updatedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LegacyBucketRecord(')
          ..write('bucket: $bucket, ')
          ..write('valueJson: $valueJson, ')
          ..write('updatedAtMs: $updatedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(bucket, valueJson, updatedAtMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LegacyBucketRecord &&
          other.bucket == this.bucket &&
          other.valueJson == this.valueJson &&
          other.updatedAtMs == this.updatedAtMs);
}

class LegacyBucketRecordsCompanion extends UpdateCompanion<LegacyBucketRecord> {
  final Value<String> bucket;
  final Value<String> valueJson;
  final Value<int> updatedAtMs;
  final Value<int> rowid;
  const LegacyBucketRecordsCompanion({
    this.bucket = const Value.absent(),
    this.valueJson = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LegacyBucketRecordsCompanion.insert({
    required String bucket,
    required String valueJson,
    required int updatedAtMs,
    this.rowid = const Value.absent(),
  }) : bucket = Value(bucket),
       valueJson = Value(valueJson),
       updatedAtMs = Value(updatedAtMs);
  static Insertable<LegacyBucketRecord> custom({
    Expression<String>? bucket,
    Expression<String>? valueJson,
    Expression<int>? updatedAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (bucket != null) 'bucket': bucket,
      if (valueJson != null) 'value_json': valueJson,
      if (updatedAtMs != null) 'updated_at_ms': updatedAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LegacyBucketRecordsCompanion copyWith({
    Value<String>? bucket,
    Value<String>? valueJson,
    Value<int>? updatedAtMs,
    Value<int>? rowid,
  }) {
    return LegacyBucketRecordsCompanion(
      bucket: bucket ?? this.bucket,
      valueJson: valueJson ?? this.valueJson,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (bucket.present) {
      map['bucket'] = Variable<String>(bucket.value);
    }
    if (valueJson.present) {
      map['value_json'] = Variable<String>(valueJson.value);
    }
    if (updatedAtMs.present) {
      map['updated_at_ms'] = Variable<int>(updatedAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LegacyBucketRecordsCompanion(')
          ..write('bucket: $bucket, ')
          ..write('valueJson: $valueJson, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$CanonicalLibraryDatabase extends GeneratedDatabase {
  _$CanonicalLibraryDatabase(QueryExecutor e) : super(e);
  $CanonicalLibraryDatabaseManager get managers =>
      $CanonicalLibraryDatabaseManager(this);
  late final $CanonicalMediaRecordsTable canonicalMediaRecords =
      $CanonicalMediaRecordsTable(this);
  late final $MediaAliasRecordsTable mediaAliasRecords =
      $MediaAliasRecordsTable(this);
  late final $ProviderBindingRecordsTable providerBindingRecords =
      $ProviderBindingRecordsTable(this);
  late final $CanonicalLibraryRecordsTable canonicalLibraryRecords =
      $CanonicalLibraryRecordsTable(this);
  late final $ProviderSnapshotRecordsTable providerSnapshotRecords =
      $ProviderSnapshotRecordsTable(this);
  late final $EpisodeStateRecordsTable episodeStateRecords =
      $EpisodeStateRecordsTable(this);
  late final $StreamPreferenceRecordsTable streamPreferenceRecords =
      $StreamPreferenceRecordsTable(this);
  late final $LibraryOperationRecordsTable libraryOperationRecords =
      $LibraryOperationRecordsTable(this);
  late final $OutboxDeliveryRecordsTable outboxDeliveryRecords =
      $OutboxDeliveryRecordsTable(this);
  late final $LibraryConflictRecordsTable libraryConflictRecords =
      $LibraryConflictRecordsTable(this);
  late final $SyncCursorRecordsTable syncCursorRecords =
      $SyncCursorRecordsTable(this);
  late final $ProviderHealthRecordsTable providerHealthRecords =
      $ProviderHealthRecordsTable(this);
  late final $LegacyBucketRecordsTable legacyBucketRecords =
      $LegacyBucketRecordsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    canonicalMediaRecords,
    mediaAliasRecords,
    providerBindingRecords,
    canonicalLibraryRecords,
    providerSnapshotRecords,
    episodeStateRecords,
    streamPreferenceRecords,
    libraryOperationRecords,
    outboxDeliveryRecords,
    libraryConflictRecords,
    syncCursorRecords,
    providerHealthRecords,
    legacyBucketRecords,
  ];
}

typedef $$CanonicalMediaRecordsTableCreateCompanionBuilder =
    CanonicalMediaRecordsCompanion Function({
      required String localId,
      required String mediaKind,
      required String mediaJson,
      required int createdAtMs,
      required int updatedAtMs,
      Value<int> rowid,
    });
typedef $$CanonicalMediaRecordsTableUpdateCompanionBuilder =
    CanonicalMediaRecordsCompanion Function({
      Value<String> localId,
      Value<String> mediaKind,
      Value<String> mediaJson,
      Value<int> createdAtMs,
      Value<int> updatedAtMs,
      Value<int> rowid,
    });

final class $$CanonicalMediaRecordsTableReferences
    extends
        BaseReferences<
          _$CanonicalLibraryDatabase,
          $CanonicalMediaRecordsTable,
          CanonicalMediaRecord
        > {
  $$CanonicalMediaRecordsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$MediaAliasRecordsTable, List<MediaAliasRecord>>
  _mediaAliasRecordsRefsTable(_$CanonicalLibraryDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.mediaAliasRecords,
        aliasName:
            'canonical_media_records__local_id__media_alias_records__local_id',
      );

  $$MediaAliasRecordsTableProcessedTableManager get mediaAliasRecordsRefs {
    final manager =
        $$MediaAliasRecordsTableTableManager(
          $_db,
          $_db.mediaAliasRecords,
        ).filter(
          (f) => f.localId.localId.sqlEquals($_itemColumn<String>('local_id')!),
        );

    final cache = $_typedResult.readTableOrNull(
      _mediaAliasRecordsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $ProviderBindingRecordsTable,
    List<ProviderBindingRecord>
  >
  _providerBindingRecordsRefsTable(
    _$CanonicalLibraryDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.providerBindingRecords,
    aliasName:
        'canonical_media_records__local_id__provider_binding_records__local_id',
  );

  $$ProviderBindingRecordsTableProcessedTableManager
  get providerBindingRecordsRefs {
    final manager =
        $$ProviderBindingRecordsTableTableManager(
          $_db,
          $_db.providerBindingRecords,
        ).filter(
          (f) => f.localId.localId.sqlEquals($_itemColumn<String>('local_id')!),
        );

    final cache = $_typedResult.readTableOrNull(
      _providerBindingRecordsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $CanonicalLibraryRecordsTable,
    List<CanonicalLibraryRecord>
  >
  _canonicalLibraryRecordsRefsTable(
    _$CanonicalLibraryDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.canonicalLibraryRecords,
    aliasName:
        'canonical_media_records__local_id__canonical_library_records__local_id',
  );

  $$CanonicalLibraryRecordsTableProcessedTableManager
  get canonicalLibraryRecordsRefs {
    final manager =
        $$CanonicalLibraryRecordsTableTableManager(
          $_db,
          $_db.canonicalLibraryRecords,
        ).filter(
          (f) => f.localId.localId.sqlEquals($_itemColumn<String>('local_id')!),
        );

    final cache = $_typedResult.readTableOrNull(
      _canonicalLibraryRecordsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $ProviderSnapshotRecordsTable,
    List<ProviderSnapshotRecord>
  >
  _providerSnapshotRecordsRefsTable(
    _$CanonicalLibraryDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.providerSnapshotRecords,
    aliasName:
        'canonical_media_records__local_id__provider_snapshot_records__local_id',
  );

  $$ProviderSnapshotRecordsTableProcessedTableManager
  get providerSnapshotRecordsRefs {
    final manager =
        $$ProviderSnapshotRecordsTableTableManager(
          $_db,
          $_db.providerSnapshotRecords,
        ).filter(
          (f) => f.localId.localId.sqlEquals($_itemColumn<String>('local_id')!),
        );

    final cache = $_typedResult.readTableOrNull(
      _providerSnapshotRecordsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $EpisodeStateRecordsTable,
    List<EpisodeStateRecord>
  >
  _episodeStateRecordsRefsTable(
    _$CanonicalLibraryDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.episodeStateRecords,
    aliasName:
        'canonical_media_records__local_id__episode_state_records__local_id',
  );

  $$EpisodeStateRecordsTableProcessedTableManager get episodeStateRecordsRefs {
    final manager =
        $$EpisodeStateRecordsTableTableManager(
          $_db,
          $_db.episodeStateRecords,
        ).filter(
          (f) => f.localId.localId.sqlEquals($_itemColumn<String>('local_id')!),
        );

    final cache = $_typedResult.readTableOrNull(
      _episodeStateRecordsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $StreamPreferenceRecordsTable,
    List<StreamPreferenceRecord>
  >
  _streamPreferenceRecordsRefsTable(
    _$CanonicalLibraryDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.streamPreferenceRecords,
    aliasName:
        'canonical_media_records__local_id__stream_preference_records__local_id',
  );

  $$StreamPreferenceRecordsTableProcessedTableManager
  get streamPreferenceRecordsRefs {
    final manager =
        $$StreamPreferenceRecordsTableTableManager(
          $_db,
          $_db.streamPreferenceRecords,
        ).filter(
          (f) => f.localId.localId.sqlEquals($_itemColumn<String>('local_id')!),
        );

    final cache = $_typedResult.readTableOrNull(
      _streamPreferenceRecordsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $LibraryOperationRecordsTable,
    List<LibraryOperationRecord>
  >
  _libraryOperationRecordsRefsTable(
    _$CanonicalLibraryDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.libraryOperationRecords,
    aliasName:
        'canonical_media_records__local_id__library_operation_records__local_id',
  );

  $$LibraryOperationRecordsTableProcessedTableManager
  get libraryOperationRecordsRefs {
    final manager =
        $$LibraryOperationRecordsTableTableManager(
          $_db,
          $_db.libraryOperationRecords,
        ).filter(
          (f) => f.localId.localId.sqlEquals($_itemColumn<String>('local_id')!),
        );

    final cache = $_typedResult.readTableOrNull(
      _libraryOperationRecordsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $LibraryConflictRecordsTable,
    List<LibraryConflictRecord>
  >
  _libraryConflictRecordsRefsTable(
    _$CanonicalLibraryDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.libraryConflictRecords,
    aliasName:
        'canonical_media_records__local_id__library_conflict_records__local_id',
  );

  $$LibraryConflictRecordsTableProcessedTableManager
  get libraryConflictRecordsRefs {
    final manager =
        $$LibraryConflictRecordsTableTableManager(
          $_db,
          $_db.libraryConflictRecords,
        ).filter(
          (f) => f.localId.localId.sqlEquals($_itemColumn<String>('local_id')!),
        );

    final cache = $_typedResult.readTableOrNull(
      _libraryConflictRecordsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$CanonicalMediaRecordsTableFilterComposer
    extends Composer<_$CanonicalLibraryDatabase, $CanonicalMediaRecordsTable> {
  $$CanonicalMediaRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get localId => $composableBuilder(
    column: $table.localId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mediaKind => $composableBuilder(
    column: $table.mediaKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mediaJson => $composableBuilder(
    column: $table.mediaJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> mediaAliasRecordsRefs(
    Expression<bool> Function($$MediaAliasRecordsTableFilterComposer f) f,
  ) {
    final $$MediaAliasRecordsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.localId,
      referencedTable: $db.mediaAliasRecords,
      getReferencedColumn: (t) => t.localId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MediaAliasRecordsTableFilterComposer(
            $db: $db,
            $table: $db.mediaAliasRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> providerBindingRecordsRefs(
    Expression<bool> Function($$ProviderBindingRecordsTableFilterComposer f) f,
  ) {
    final $$ProviderBindingRecordsTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.localId,
          referencedTable: $db.providerBindingRecords,
          getReferencedColumn: (t) => t.localId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ProviderBindingRecordsTableFilterComposer(
                $db: $db,
                $table: $db.providerBindingRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<bool> canonicalLibraryRecordsRefs(
    Expression<bool> Function($$CanonicalLibraryRecordsTableFilterComposer f) f,
  ) {
    final $$CanonicalLibraryRecordsTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.localId,
          referencedTable: $db.canonicalLibraryRecords,
          getReferencedColumn: (t) => t.localId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$CanonicalLibraryRecordsTableFilterComposer(
                $db: $db,
                $table: $db.canonicalLibraryRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<bool> providerSnapshotRecordsRefs(
    Expression<bool> Function($$ProviderSnapshotRecordsTableFilterComposer f) f,
  ) {
    final $$ProviderSnapshotRecordsTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.localId,
          referencedTable: $db.providerSnapshotRecords,
          getReferencedColumn: (t) => t.localId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ProviderSnapshotRecordsTableFilterComposer(
                $db: $db,
                $table: $db.providerSnapshotRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<bool> episodeStateRecordsRefs(
    Expression<bool> Function($$EpisodeStateRecordsTableFilterComposer f) f,
  ) {
    final $$EpisodeStateRecordsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.localId,
      referencedTable: $db.episodeStateRecords,
      getReferencedColumn: (t) => t.localId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EpisodeStateRecordsTableFilterComposer(
            $db: $db,
            $table: $db.episodeStateRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> streamPreferenceRecordsRefs(
    Expression<bool> Function($$StreamPreferenceRecordsTableFilterComposer f) f,
  ) {
    final $$StreamPreferenceRecordsTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.localId,
          referencedTable: $db.streamPreferenceRecords,
          getReferencedColumn: (t) => t.localId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$StreamPreferenceRecordsTableFilterComposer(
                $db: $db,
                $table: $db.streamPreferenceRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<bool> libraryOperationRecordsRefs(
    Expression<bool> Function($$LibraryOperationRecordsTableFilterComposer f) f,
  ) {
    final $$LibraryOperationRecordsTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.localId,
          referencedTable: $db.libraryOperationRecords,
          getReferencedColumn: (t) => t.localId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$LibraryOperationRecordsTableFilterComposer(
                $db: $db,
                $table: $db.libraryOperationRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<bool> libraryConflictRecordsRefs(
    Expression<bool> Function($$LibraryConflictRecordsTableFilterComposer f) f,
  ) {
    final $$LibraryConflictRecordsTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.localId,
          referencedTable: $db.libraryConflictRecords,
          getReferencedColumn: (t) => t.localId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$LibraryConflictRecordsTableFilterComposer(
                $db: $db,
                $table: $db.libraryConflictRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$CanonicalMediaRecordsTableOrderingComposer
    extends Composer<_$CanonicalLibraryDatabase, $CanonicalMediaRecordsTable> {
  $$CanonicalMediaRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get localId => $composableBuilder(
    column: $table.localId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mediaKind => $composableBuilder(
    column: $table.mediaKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mediaJson => $composableBuilder(
    column: $table.mediaJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CanonicalMediaRecordsTableAnnotationComposer
    extends Composer<_$CanonicalLibraryDatabase, $CanonicalMediaRecordsTable> {
  $$CanonicalMediaRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get localId =>
      $composableBuilder(column: $table.localId, builder: (column) => column);

  GeneratedColumn<String> get mediaKind =>
      $composableBuilder(column: $table.mediaKind, builder: (column) => column);

  GeneratedColumn<String> get mediaJson =>
      $composableBuilder(column: $table.mediaJson, builder: (column) => column);

  GeneratedColumn<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => column,
  );

  Expression<T> mediaAliasRecordsRefs<T extends Object>(
    Expression<T> Function($$MediaAliasRecordsTableAnnotationComposer a) f,
  ) {
    final $$MediaAliasRecordsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.localId,
          referencedTable: $db.mediaAliasRecords,
          getReferencedColumn: (t) => t.localId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$MediaAliasRecordsTableAnnotationComposer(
                $db: $db,
                $table: $db.mediaAliasRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> providerBindingRecordsRefs<T extends Object>(
    Expression<T> Function($$ProviderBindingRecordsTableAnnotationComposer a) f,
  ) {
    final $$ProviderBindingRecordsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.localId,
          referencedTable: $db.providerBindingRecords,
          getReferencedColumn: (t) => t.localId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ProviderBindingRecordsTableAnnotationComposer(
                $db: $db,
                $table: $db.providerBindingRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> canonicalLibraryRecordsRefs<T extends Object>(
    Expression<T> Function($$CanonicalLibraryRecordsTableAnnotationComposer a)
    f,
  ) {
    final $$CanonicalLibraryRecordsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.localId,
          referencedTable: $db.canonicalLibraryRecords,
          getReferencedColumn: (t) => t.localId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$CanonicalLibraryRecordsTableAnnotationComposer(
                $db: $db,
                $table: $db.canonicalLibraryRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> providerSnapshotRecordsRefs<T extends Object>(
    Expression<T> Function($$ProviderSnapshotRecordsTableAnnotationComposer a)
    f,
  ) {
    final $$ProviderSnapshotRecordsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.localId,
          referencedTable: $db.providerSnapshotRecords,
          getReferencedColumn: (t) => t.localId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ProviderSnapshotRecordsTableAnnotationComposer(
                $db: $db,
                $table: $db.providerSnapshotRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> episodeStateRecordsRefs<T extends Object>(
    Expression<T> Function($$EpisodeStateRecordsTableAnnotationComposer a) f,
  ) {
    final $$EpisodeStateRecordsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.localId,
          referencedTable: $db.episodeStateRecords,
          getReferencedColumn: (t) => t.localId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$EpisodeStateRecordsTableAnnotationComposer(
                $db: $db,
                $table: $db.episodeStateRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> streamPreferenceRecordsRefs<T extends Object>(
    Expression<T> Function($$StreamPreferenceRecordsTableAnnotationComposer a)
    f,
  ) {
    final $$StreamPreferenceRecordsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.localId,
          referencedTable: $db.streamPreferenceRecords,
          getReferencedColumn: (t) => t.localId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$StreamPreferenceRecordsTableAnnotationComposer(
                $db: $db,
                $table: $db.streamPreferenceRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> libraryOperationRecordsRefs<T extends Object>(
    Expression<T> Function($$LibraryOperationRecordsTableAnnotationComposer a)
    f,
  ) {
    final $$LibraryOperationRecordsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.localId,
          referencedTable: $db.libraryOperationRecords,
          getReferencedColumn: (t) => t.localId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$LibraryOperationRecordsTableAnnotationComposer(
                $db: $db,
                $table: $db.libraryOperationRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> libraryConflictRecordsRefs<T extends Object>(
    Expression<T> Function($$LibraryConflictRecordsTableAnnotationComposer a) f,
  ) {
    final $$LibraryConflictRecordsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.localId,
          referencedTable: $db.libraryConflictRecords,
          getReferencedColumn: (t) => t.localId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$LibraryConflictRecordsTableAnnotationComposer(
                $db: $db,
                $table: $db.libraryConflictRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$CanonicalMediaRecordsTableTableManager
    extends
        RootTableManager<
          _$CanonicalLibraryDatabase,
          $CanonicalMediaRecordsTable,
          CanonicalMediaRecord,
          $$CanonicalMediaRecordsTableFilterComposer,
          $$CanonicalMediaRecordsTableOrderingComposer,
          $$CanonicalMediaRecordsTableAnnotationComposer,
          $$CanonicalMediaRecordsTableCreateCompanionBuilder,
          $$CanonicalMediaRecordsTableUpdateCompanionBuilder,
          (CanonicalMediaRecord, $$CanonicalMediaRecordsTableReferences),
          CanonicalMediaRecord,
          PrefetchHooks Function({
            bool mediaAliasRecordsRefs,
            bool providerBindingRecordsRefs,
            bool canonicalLibraryRecordsRefs,
            bool providerSnapshotRecordsRefs,
            bool episodeStateRecordsRefs,
            bool streamPreferenceRecordsRefs,
            bool libraryOperationRecordsRefs,
            bool libraryConflictRecordsRefs,
          })
        > {
  $$CanonicalMediaRecordsTableTableManager(
    _$CanonicalLibraryDatabase db,
    $CanonicalMediaRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CanonicalMediaRecordsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$CanonicalMediaRecordsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$CanonicalMediaRecordsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> localId = const Value.absent(),
                Value<String> mediaKind = const Value.absent(),
                Value<String> mediaJson = const Value.absent(),
                Value<int> createdAtMs = const Value.absent(),
                Value<int> updatedAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CanonicalMediaRecordsCompanion(
                localId: localId,
                mediaKind: mediaKind,
                mediaJson: mediaJson,
                createdAtMs: createdAtMs,
                updatedAtMs: updatedAtMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String localId,
                required String mediaKind,
                required String mediaJson,
                required int createdAtMs,
                required int updatedAtMs,
                Value<int> rowid = const Value.absent(),
              }) => CanonicalMediaRecordsCompanion.insert(
                localId: localId,
                mediaKind: mediaKind,
                mediaJson: mediaJson,
                createdAtMs: createdAtMs,
                updatedAtMs: updatedAtMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$CanonicalMediaRecordsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                mediaAliasRecordsRefs = false,
                providerBindingRecordsRefs = false,
                canonicalLibraryRecordsRefs = false,
                providerSnapshotRecordsRefs = false,
                episodeStateRecordsRefs = false,
                streamPreferenceRecordsRefs = false,
                libraryOperationRecordsRefs = false,
                libraryConflictRecordsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (mediaAliasRecordsRefs) db.mediaAliasRecords,
                    if (providerBindingRecordsRefs) db.providerBindingRecords,
                    if (canonicalLibraryRecordsRefs) db.canonicalLibraryRecords,
                    if (providerSnapshotRecordsRefs) db.providerSnapshotRecords,
                    if (episodeStateRecordsRefs) db.episodeStateRecords,
                    if (streamPreferenceRecordsRefs) db.streamPreferenceRecords,
                    if (libraryOperationRecordsRefs) db.libraryOperationRecords,
                    if (libraryConflictRecordsRefs) db.libraryConflictRecords,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (mediaAliasRecordsRefs)
                        await $_getPrefetchedData<
                          CanonicalMediaRecord,
                          $CanonicalMediaRecordsTable,
                          MediaAliasRecord
                        >(
                          currentTable: table,
                          referencedTable:
                              $$CanonicalMediaRecordsTableReferences
                                  ._mediaAliasRecordsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CanonicalMediaRecordsTableReferences(
                                db,
                                table,
                                p0,
                              ).mediaAliasRecordsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.localId == item.localId,
                              ),
                          typedResults: items,
                        ),
                      if (providerBindingRecordsRefs)
                        await $_getPrefetchedData<
                          CanonicalMediaRecord,
                          $CanonicalMediaRecordsTable,
                          ProviderBindingRecord
                        >(
                          currentTable: table,
                          referencedTable:
                              $$CanonicalMediaRecordsTableReferences
                                  ._providerBindingRecordsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CanonicalMediaRecordsTableReferences(
                                db,
                                table,
                                p0,
                              ).providerBindingRecordsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.localId == item.localId,
                              ),
                          typedResults: items,
                        ),
                      if (canonicalLibraryRecordsRefs)
                        await $_getPrefetchedData<
                          CanonicalMediaRecord,
                          $CanonicalMediaRecordsTable,
                          CanonicalLibraryRecord
                        >(
                          currentTable: table,
                          referencedTable:
                              $$CanonicalMediaRecordsTableReferences
                                  ._canonicalLibraryRecordsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CanonicalMediaRecordsTableReferences(
                                db,
                                table,
                                p0,
                              ).canonicalLibraryRecordsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.localId == item.localId,
                              ),
                          typedResults: items,
                        ),
                      if (providerSnapshotRecordsRefs)
                        await $_getPrefetchedData<
                          CanonicalMediaRecord,
                          $CanonicalMediaRecordsTable,
                          ProviderSnapshotRecord
                        >(
                          currentTable: table,
                          referencedTable:
                              $$CanonicalMediaRecordsTableReferences
                                  ._providerSnapshotRecordsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CanonicalMediaRecordsTableReferences(
                                db,
                                table,
                                p0,
                              ).providerSnapshotRecordsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.localId == item.localId,
                              ),
                          typedResults: items,
                        ),
                      if (episodeStateRecordsRefs)
                        await $_getPrefetchedData<
                          CanonicalMediaRecord,
                          $CanonicalMediaRecordsTable,
                          EpisodeStateRecord
                        >(
                          currentTable: table,
                          referencedTable:
                              $$CanonicalMediaRecordsTableReferences
                                  ._episodeStateRecordsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CanonicalMediaRecordsTableReferences(
                                db,
                                table,
                                p0,
                              ).episodeStateRecordsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.localId == item.localId,
                              ),
                          typedResults: items,
                        ),
                      if (streamPreferenceRecordsRefs)
                        await $_getPrefetchedData<
                          CanonicalMediaRecord,
                          $CanonicalMediaRecordsTable,
                          StreamPreferenceRecord
                        >(
                          currentTable: table,
                          referencedTable:
                              $$CanonicalMediaRecordsTableReferences
                                  ._streamPreferenceRecordsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CanonicalMediaRecordsTableReferences(
                                db,
                                table,
                                p0,
                              ).streamPreferenceRecordsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.localId == item.localId,
                              ),
                          typedResults: items,
                        ),
                      if (libraryOperationRecordsRefs)
                        await $_getPrefetchedData<
                          CanonicalMediaRecord,
                          $CanonicalMediaRecordsTable,
                          LibraryOperationRecord
                        >(
                          currentTable: table,
                          referencedTable:
                              $$CanonicalMediaRecordsTableReferences
                                  ._libraryOperationRecordsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CanonicalMediaRecordsTableReferences(
                                db,
                                table,
                                p0,
                              ).libraryOperationRecordsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.localId == item.localId,
                              ),
                          typedResults: items,
                        ),
                      if (libraryConflictRecordsRefs)
                        await $_getPrefetchedData<
                          CanonicalMediaRecord,
                          $CanonicalMediaRecordsTable,
                          LibraryConflictRecord
                        >(
                          currentTable: table,
                          referencedTable:
                              $$CanonicalMediaRecordsTableReferences
                                  ._libraryConflictRecordsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CanonicalMediaRecordsTableReferences(
                                db,
                                table,
                                p0,
                              ).libraryConflictRecordsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.localId == item.localId,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$CanonicalMediaRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$CanonicalLibraryDatabase,
      $CanonicalMediaRecordsTable,
      CanonicalMediaRecord,
      $$CanonicalMediaRecordsTableFilterComposer,
      $$CanonicalMediaRecordsTableOrderingComposer,
      $$CanonicalMediaRecordsTableAnnotationComposer,
      $$CanonicalMediaRecordsTableCreateCompanionBuilder,
      $$CanonicalMediaRecordsTableUpdateCompanionBuilder,
      (CanonicalMediaRecord, $$CanonicalMediaRecordsTableReferences),
      CanonicalMediaRecord,
      PrefetchHooks Function({
        bool mediaAliasRecordsRefs,
        bool providerBindingRecordsRefs,
        bool canonicalLibraryRecordsRefs,
        bool providerSnapshotRecordsRefs,
        bool episodeStateRecordsRefs,
        bool streamPreferenceRecordsRefs,
        bool libraryOperationRecordsRefs,
        bool libraryConflictRecordsRefs,
      })
    >;
typedef $$MediaAliasRecordsTableCreateCompanionBuilder =
    MediaAliasRecordsCompanion Function({
      required String alias,
      required String localId,
      required int createdAtMs,
      Value<int> rowid,
    });
typedef $$MediaAliasRecordsTableUpdateCompanionBuilder =
    MediaAliasRecordsCompanion Function({
      Value<String> alias,
      Value<String> localId,
      Value<int> createdAtMs,
      Value<int> rowid,
    });

final class $$MediaAliasRecordsTableReferences
    extends
        BaseReferences<
          _$CanonicalLibraryDatabase,
          $MediaAliasRecordsTable,
          MediaAliasRecord
        > {
  $$MediaAliasRecordsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $CanonicalMediaRecordsTable _localIdTable(
    _$CanonicalLibraryDatabase db,
  ) => db.canonicalMediaRecords.createAlias(
    'media_alias_records__local_id__canonical_media_records__local_id',
  );

  $$CanonicalMediaRecordsTableProcessedTableManager get localId {
    final $_column = $_itemColumn<String>('local_id')!;

    final manager = $$CanonicalMediaRecordsTableTableManager(
      $_db,
      $_db.canonicalMediaRecords,
    ).filter((f) => f.localId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_localIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$MediaAliasRecordsTableFilterComposer
    extends Composer<_$CanonicalLibraryDatabase, $MediaAliasRecordsTable> {
  $$MediaAliasRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get alias => $composableBuilder(
    column: $table.alias,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnFilters(column),
  );

  $$CanonicalMediaRecordsTableFilterComposer get localId {
    final $$CanonicalMediaRecordsTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.localId,
          referencedTable: $db.canonicalMediaRecords,
          getReferencedColumn: (t) => t.localId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$CanonicalMediaRecordsTableFilterComposer(
                $db: $db,
                $table: $db.canonicalMediaRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$MediaAliasRecordsTableOrderingComposer
    extends Composer<_$CanonicalLibraryDatabase, $MediaAliasRecordsTable> {
  $$MediaAliasRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get alias => $composableBuilder(
    column: $table.alias,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  $$CanonicalMediaRecordsTableOrderingComposer get localId {
    final $$CanonicalMediaRecordsTableOrderingComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.localId,
          referencedTable: $db.canonicalMediaRecords,
          getReferencedColumn: (t) => t.localId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$CanonicalMediaRecordsTableOrderingComposer(
                $db: $db,
                $table: $db.canonicalMediaRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$MediaAliasRecordsTableAnnotationComposer
    extends Composer<_$CanonicalLibraryDatabase, $MediaAliasRecordsTable> {
  $$MediaAliasRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get alias =>
      $composableBuilder(column: $table.alias, builder: (column) => column);

  GeneratedColumn<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => column,
  );

  $$CanonicalMediaRecordsTableAnnotationComposer get localId {
    final $$CanonicalMediaRecordsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.localId,
          referencedTable: $db.canonicalMediaRecords,
          getReferencedColumn: (t) => t.localId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$CanonicalMediaRecordsTableAnnotationComposer(
                $db: $db,
                $table: $db.canonicalMediaRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$MediaAliasRecordsTableTableManager
    extends
        RootTableManager<
          _$CanonicalLibraryDatabase,
          $MediaAliasRecordsTable,
          MediaAliasRecord,
          $$MediaAliasRecordsTableFilterComposer,
          $$MediaAliasRecordsTableOrderingComposer,
          $$MediaAliasRecordsTableAnnotationComposer,
          $$MediaAliasRecordsTableCreateCompanionBuilder,
          $$MediaAliasRecordsTableUpdateCompanionBuilder,
          (MediaAliasRecord, $$MediaAliasRecordsTableReferences),
          MediaAliasRecord,
          PrefetchHooks Function({bool localId})
        > {
  $$MediaAliasRecordsTableTableManager(
    _$CanonicalLibraryDatabase db,
    $MediaAliasRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MediaAliasRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MediaAliasRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MediaAliasRecordsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> alias = const Value.absent(),
                Value<String> localId = const Value.absent(),
                Value<int> createdAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MediaAliasRecordsCompanion(
                alias: alias,
                localId: localId,
                createdAtMs: createdAtMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String alias,
                required String localId,
                required int createdAtMs,
                Value<int> rowid = const Value.absent(),
              }) => MediaAliasRecordsCompanion.insert(
                alias: alias,
                localId: localId,
                createdAtMs: createdAtMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$MediaAliasRecordsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({localId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (localId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.localId,
                                referencedTable:
                                    $$MediaAliasRecordsTableReferences
                                        ._localIdTable(db),
                                referencedColumn:
                                    $$MediaAliasRecordsTableReferences
                                        ._localIdTable(db)
                                        .localId,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$MediaAliasRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$CanonicalLibraryDatabase,
      $MediaAliasRecordsTable,
      MediaAliasRecord,
      $$MediaAliasRecordsTableFilterComposer,
      $$MediaAliasRecordsTableOrderingComposer,
      $$MediaAliasRecordsTableAnnotationComposer,
      $$MediaAliasRecordsTableCreateCompanionBuilder,
      $$MediaAliasRecordsTableUpdateCompanionBuilder,
      (MediaAliasRecord, $$MediaAliasRecordsTableReferences),
      MediaAliasRecord,
      PrefetchHooks Function({bool localId})
    >;
typedef $$ProviderBindingRecordsTableCreateCompanionBuilder =
    ProviderBindingRecordsCompanion Function({
      Value<int> id,
      required String localId,
      required String provider,
      required String mediaKind,
      required int externalMediaId,
      Value<int?> providerEntryId,
      required String evidence,
      required int verifiedAtMs,
      Value<bool> quarantined,
    });
typedef $$ProviderBindingRecordsTableUpdateCompanionBuilder =
    ProviderBindingRecordsCompanion Function({
      Value<int> id,
      Value<String> localId,
      Value<String> provider,
      Value<String> mediaKind,
      Value<int> externalMediaId,
      Value<int?> providerEntryId,
      Value<String> evidence,
      Value<int> verifiedAtMs,
      Value<bool> quarantined,
    });

final class $$ProviderBindingRecordsTableReferences
    extends
        BaseReferences<
          _$CanonicalLibraryDatabase,
          $ProviderBindingRecordsTable,
          ProviderBindingRecord
        > {
  $$ProviderBindingRecordsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $CanonicalMediaRecordsTable _localIdTable(
    _$CanonicalLibraryDatabase db,
  ) => db.canonicalMediaRecords.createAlias(
    'provider_binding_records__local_id__canonical_media_records__local_id',
  );

  $$CanonicalMediaRecordsTableProcessedTableManager get localId {
    final $_column = $_itemColumn<String>('local_id')!;

    final manager = $$CanonicalMediaRecordsTableTableManager(
      $_db,
      $_db.canonicalMediaRecords,
    ).filter((f) => f.localId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_localIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ProviderBindingRecordsTableFilterComposer
    extends Composer<_$CanonicalLibraryDatabase, $ProviderBindingRecordsTable> {
  $$ProviderBindingRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get provider => $composableBuilder(
    column: $table.provider,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mediaKind => $composableBuilder(
    column: $table.mediaKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get externalMediaId => $composableBuilder(
    column: $table.externalMediaId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get providerEntryId => $composableBuilder(
    column: $table.providerEntryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get evidence => $composableBuilder(
    column: $table.evidence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get verifiedAtMs => $composableBuilder(
    column: $table.verifiedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get quarantined => $composableBuilder(
    column: $table.quarantined,
    builder: (column) => ColumnFilters(column),
  );

  $$CanonicalMediaRecordsTableFilterComposer get localId {
    final $$CanonicalMediaRecordsTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.localId,
          referencedTable: $db.canonicalMediaRecords,
          getReferencedColumn: (t) => t.localId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$CanonicalMediaRecordsTableFilterComposer(
                $db: $db,
                $table: $db.canonicalMediaRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$ProviderBindingRecordsTableOrderingComposer
    extends Composer<_$CanonicalLibraryDatabase, $ProviderBindingRecordsTable> {
  $$ProviderBindingRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get provider => $composableBuilder(
    column: $table.provider,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mediaKind => $composableBuilder(
    column: $table.mediaKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get externalMediaId => $composableBuilder(
    column: $table.externalMediaId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get providerEntryId => $composableBuilder(
    column: $table.providerEntryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get evidence => $composableBuilder(
    column: $table.evidence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get verifiedAtMs => $composableBuilder(
    column: $table.verifiedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get quarantined => $composableBuilder(
    column: $table.quarantined,
    builder: (column) => ColumnOrderings(column),
  );

  $$CanonicalMediaRecordsTableOrderingComposer get localId {
    final $$CanonicalMediaRecordsTableOrderingComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.localId,
          referencedTable: $db.canonicalMediaRecords,
          getReferencedColumn: (t) => t.localId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$CanonicalMediaRecordsTableOrderingComposer(
                $db: $db,
                $table: $db.canonicalMediaRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$ProviderBindingRecordsTableAnnotationComposer
    extends Composer<_$CanonicalLibraryDatabase, $ProviderBindingRecordsTable> {
  $$ProviderBindingRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get provider =>
      $composableBuilder(column: $table.provider, builder: (column) => column);

  GeneratedColumn<String> get mediaKind =>
      $composableBuilder(column: $table.mediaKind, builder: (column) => column);

  GeneratedColumn<int> get externalMediaId => $composableBuilder(
    column: $table.externalMediaId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get providerEntryId => $composableBuilder(
    column: $table.providerEntryId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get evidence =>
      $composableBuilder(column: $table.evidence, builder: (column) => column);

  GeneratedColumn<int> get verifiedAtMs => $composableBuilder(
    column: $table.verifiedAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get quarantined => $composableBuilder(
    column: $table.quarantined,
    builder: (column) => column,
  );

  $$CanonicalMediaRecordsTableAnnotationComposer get localId {
    final $$CanonicalMediaRecordsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.localId,
          referencedTable: $db.canonicalMediaRecords,
          getReferencedColumn: (t) => t.localId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$CanonicalMediaRecordsTableAnnotationComposer(
                $db: $db,
                $table: $db.canonicalMediaRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$ProviderBindingRecordsTableTableManager
    extends
        RootTableManager<
          _$CanonicalLibraryDatabase,
          $ProviderBindingRecordsTable,
          ProviderBindingRecord,
          $$ProviderBindingRecordsTableFilterComposer,
          $$ProviderBindingRecordsTableOrderingComposer,
          $$ProviderBindingRecordsTableAnnotationComposer,
          $$ProviderBindingRecordsTableCreateCompanionBuilder,
          $$ProviderBindingRecordsTableUpdateCompanionBuilder,
          (ProviderBindingRecord, $$ProviderBindingRecordsTableReferences),
          ProviderBindingRecord,
          PrefetchHooks Function({bool localId})
        > {
  $$ProviderBindingRecordsTableTableManager(
    _$CanonicalLibraryDatabase db,
    $ProviderBindingRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProviderBindingRecordsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$ProviderBindingRecordsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ProviderBindingRecordsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> localId = const Value.absent(),
                Value<String> provider = const Value.absent(),
                Value<String> mediaKind = const Value.absent(),
                Value<int> externalMediaId = const Value.absent(),
                Value<int?> providerEntryId = const Value.absent(),
                Value<String> evidence = const Value.absent(),
                Value<int> verifiedAtMs = const Value.absent(),
                Value<bool> quarantined = const Value.absent(),
              }) => ProviderBindingRecordsCompanion(
                id: id,
                localId: localId,
                provider: provider,
                mediaKind: mediaKind,
                externalMediaId: externalMediaId,
                providerEntryId: providerEntryId,
                evidence: evidence,
                verifiedAtMs: verifiedAtMs,
                quarantined: quarantined,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String localId,
                required String provider,
                required String mediaKind,
                required int externalMediaId,
                Value<int?> providerEntryId = const Value.absent(),
                required String evidence,
                required int verifiedAtMs,
                Value<bool> quarantined = const Value.absent(),
              }) => ProviderBindingRecordsCompanion.insert(
                id: id,
                localId: localId,
                provider: provider,
                mediaKind: mediaKind,
                externalMediaId: externalMediaId,
                providerEntryId: providerEntryId,
                evidence: evidence,
                verifiedAtMs: verifiedAtMs,
                quarantined: quarantined,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ProviderBindingRecordsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({localId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (localId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.localId,
                                referencedTable:
                                    $$ProviderBindingRecordsTableReferences
                                        ._localIdTable(db),
                                referencedColumn:
                                    $$ProviderBindingRecordsTableReferences
                                        ._localIdTable(db)
                                        .localId,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ProviderBindingRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$CanonicalLibraryDatabase,
      $ProviderBindingRecordsTable,
      ProviderBindingRecord,
      $$ProviderBindingRecordsTableFilterComposer,
      $$ProviderBindingRecordsTableOrderingComposer,
      $$ProviderBindingRecordsTableAnnotationComposer,
      $$ProviderBindingRecordsTableCreateCompanionBuilder,
      $$ProviderBindingRecordsTableUpdateCompanionBuilder,
      (ProviderBindingRecord, $$ProviderBindingRecordsTableReferences),
      ProviderBindingRecord,
      PrefetchHooks Function({bool localId})
    >;
typedef $$CanonicalLibraryRecordsTableCreateCompanionBuilder =
    CanonicalLibraryRecordsCompanion Function({
      required String localId,
      Value<bool> inLibrary,
      required String status,
      Value<int> progress,
      Value<int> progressVolumes,
      Value<int> repeatCount,
      Value<int> watchCycle,
      Value<int?> scoreRaw,
      Value<String?> scoreFormat,
      Value<String> notes,
      Value<bool> favorite,
      Value<int?> startedYear,
      Value<int?> startedMonth,
      Value<int?> startedDay,
      Value<int?> completedYear,
      Value<int?> completedMonth,
      Value<int?> completedDay,
      required String canonicalStateJson,
      Value<String> fieldRevisionsJson,
      required int createdAtMs,
      required int updatedAtMs,
      Value<int?> tombstonedAtMs,
      Value<int> rowid,
    });
typedef $$CanonicalLibraryRecordsTableUpdateCompanionBuilder =
    CanonicalLibraryRecordsCompanion Function({
      Value<String> localId,
      Value<bool> inLibrary,
      Value<String> status,
      Value<int> progress,
      Value<int> progressVolumes,
      Value<int> repeatCount,
      Value<int> watchCycle,
      Value<int?> scoreRaw,
      Value<String?> scoreFormat,
      Value<String> notes,
      Value<bool> favorite,
      Value<int?> startedYear,
      Value<int?> startedMonth,
      Value<int?> startedDay,
      Value<int?> completedYear,
      Value<int?> completedMonth,
      Value<int?> completedDay,
      Value<String> canonicalStateJson,
      Value<String> fieldRevisionsJson,
      Value<int> createdAtMs,
      Value<int> updatedAtMs,
      Value<int?> tombstonedAtMs,
      Value<int> rowid,
    });

final class $$CanonicalLibraryRecordsTableReferences
    extends
        BaseReferences<
          _$CanonicalLibraryDatabase,
          $CanonicalLibraryRecordsTable,
          CanonicalLibraryRecord
        > {
  $$CanonicalLibraryRecordsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $CanonicalMediaRecordsTable _localIdTable(
    _$CanonicalLibraryDatabase db,
  ) => db.canonicalMediaRecords.createAlias(
    'canonical_library_records__local_id__canonical_media_records__local_id',
  );

  $$CanonicalMediaRecordsTableProcessedTableManager get localId {
    final $_column = $_itemColumn<String>('local_id')!;

    final manager = $$CanonicalMediaRecordsTableTableManager(
      $_db,
      $_db.canonicalMediaRecords,
    ).filter((f) => f.localId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_localIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$CanonicalLibraryRecordsTableFilterComposer
    extends
        Composer<_$CanonicalLibraryDatabase, $CanonicalLibraryRecordsTable> {
  $$CanonicalLibraryRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<bool> get inLibrary => $composableBuilder(
    column: $table.inLibrary,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get progress => $composableBuilder(
    column: $table.progress,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get progressVolumes => $composableBuilder(
    column: $table.progressVolumes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get repeatCount => $composableBuilder(
    column: $table.repeatCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get watchCycle => $composableBuilder(
    column: $table.watchCycle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get scoreRaw => $composableBuilder(
    column: $table.scoreRaw,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scoreFormat => $composableBuilder(
    column: $table.scoreFormat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get favorite => $composableBuilder(
    column: $table.favorite,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startedYear => $composableBuilder(
    column: $table.startedYear,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startedMonth => $composableBuilder(
    column: $table.startedMonth,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startedDay => $composableBuilder(
    column: $table.startedDay,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get completedYear => $composableBuilder(
    column: $table.completedYear,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get completedMonth => $composableBuilder(
    column: $table.completedMonth,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get completedDay => $composableBuilder(
    column: $table.completedDay,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get canonicalStateJson => $composableBuilder(
    column: $table.canonicalStateJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fieldRevisionsJson => $composableBuilder(
    column: $table.fieldRevisionsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tombstonedAtMs => $composableBuilder(
    column: $table.tombstonedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  $$CanonicalMediaRecordsTableFilterComposer get localId {
    final $$CanonicalMediaRecordsTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.localId,
          referencedTable: $db.canonicalMediaRecords,
          getReferencedColumn: (t) => t.localId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$CanonicalMediaRecordsTableFilterComposer(
                $db: $db,
                $table: $db.canonicalMediaRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$CanonicalLibraryRecordsTableOrderingComposer
    extends
        Composer<_$CanonicalLibraryDatabase, $CanonicalLibraryRecordsTable> {
  $$CanonicalLibraryRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<bool> get inLibrary => $composableBuilder(
    column: $table.inLibrary,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get progress => $composableBuilder(
    column: $table.progress,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get progressVolumes => $composableBuilder(
    column: $table.progressVolumes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get repeatCount => $composableBuilder(
    column: $table.repeatCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get watchCycle => $composableBuilder(
    column: $table.watchCycle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get scoreRaw => $composableBuilder(
    column: $table.scoreRaw,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scoreFormat => $composableBuilder(
    column: $table.scoreFormat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get favorite => $composableBuilder(
    column: $table.favorite,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startedYear => $composableBuilder(
    column: $table.startedYear,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startedMonth => $composableBuilder(
    column: $table.startedMonth,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startedDay => $composableBuilder(
    column: $table.startedDay,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get completedYear => $composableBuilder(
    column: $table.completedYear,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get completedMonth => $composableBuilder(
    column: $table.completedMonth,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get completedDay => $composableBuilder(
    column: $table.completedDay,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get canonicalStateJson => $composableBuilder(
    column: $table.canonicalStateJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fieldRevisionsJson => $composableBuilder(
    column: $table.fieldRevisionsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tombstonedAtMs => $composableBuilder(
    column: $table.tombstonedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  $$CanonicalMediaRecordsTableOrderingComposer get localId {
    final $$CanonicalMediaRecordsTableOrderingComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.localId,
          referencedTable: $db.canonicalMediaRecords,
          getReferencedColumn: (t) => t.localId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$CanonicalMediaRecordsTableOrderingComposer(
                $db: $db,
                $table: $db.canonicalMediaRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$CanonicalLibraryRecordsTableAnnotationComposer
    extends
        Composer<_$CanonicalLibraryDatabase, $CanonicalLibraryRecordsTable> {
  $$CanonicalLibraryRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<bool> get inLibrary =>
      $composableBuilder(column: $table.inLibrary, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get progress =>
      $composableBuilder(column: $table.progress, builder: (column) => column);

  GeneratedColumn<int> get progressVolumes => $composableBuilder(
    column: $table.progressVolumes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get repeatCount => $composableBuilder(
    column: $table.repeatCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get watchCycle => $composableBuilder(
    column: $table.watchCycle,
    builder: (column) => column,
  );

  GeneratedColumn<int> get scoreRaw =>
      $composableBuilder(column: $table.scoreRaw, builder: (column) => column);

  GeneratedColumn<String> get scoreFormat => $composableBuilder(
    column: $table.scoreFormat,
    builder: (column) => column,
  );

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<bool> get favorite =>
      $composableBuilder(column: $table.favorite, builder: (column) => column);

  GeneratedColumn<int> get startedYear => $composableBuilder(
    column: $table.startedYear,
    builder: (column) => column,
  );

  GeneratedColumn<int> get startedMonth => $composableBuilder(
    column: $table.startedMonth,
    builder: (column) => column,
  );

  GeneratedColumn<int> get startedDay => $composableBuilder(
    column: $table.startedDay,
    builder: (column) => column,
  );

  GeneratedColumn<int> get completedYear => $composableBuilder(
    column: $table.completedYear,
    builder: (column) => column,
  );

  GeneratedColumn<int> get completedMonth => $composableBuilder(
    column: $table.completedMonth,
    builder: (column) => column,
  );

  GeneratedColumn<int> get completedDay => $composableBuilder(
    column: $table.completedDay,
    builder: (column) => column,
  );

  GeneratedColumn<String> get canonicalStateJson => $composableBuilder(
    column: $table.canonicalStateJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get fieldRevisionsJson => $composableBuilder(
    column: $table.fieldRevisionsJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get tombstonedAtMs => $composableBuilder(
    column: $table.tombstonedAtMs,
    builder: (column) => column,
  );

  $$CanonicalMediaRecordsTableAnnotationComposer get localId {
    final $$CanonicalMediaRecordsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.localId,
          referencedTable: $db.canonicalMediaRecords,
          getReferencedColumn: (t) => t.localId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$CanonicalMediaRecordsTableAnnotationComposer(
                $db: $db,
                $table: $db.canonicalMediaRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$CanonicalLibraryRecordsTableTableManager
    extends
        RootTableManager<
          _$CanonicalLibraryDatabase,
          $CanonicalLibraryRecordsTable,
          CanonicalLibraryRecord,
          $$CanonicalLibraryRecordsTableFilterComposer,
          $$CanonicalLibraryRecordsTableOrderingComposer,
          $$CanonicalLibraryRecordsTableAnnotationComposer,
          $$CanonicalLibraryRecordsTableCreateCompanionBuilder,
          $$CanonicalLibraryRecordsTableUpdateCompanionBuilder,
          (CanonicalLibraryRecord, $$CanonicalLibraryRecordsTableReferences),
          CanonicalLibraryRecord,
          PrefetchHooks Function({bool localId})
        > {
  $$CanonicalLibraryRecordsTableTableManager(
    _$CanonicalLibraryDatabase db,
    $CanonicalLibraryRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CanonicalLibraryRecordsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$CanonicalLibraryRecordsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$CanonicalLibraryRecordsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> localId = const Value.absent(),
                Value<bool> inLibrary = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> progress = const Value.absent(),
                Value<int> progressVolumes = const Value.absent(),
                Value<int> repeatCount = const Value.absent(),
                Value<int> watchCycle = const Value.absent(),
                Value<int?> scoreRaw = const Value.absent(),
                Value<String?> scoreFormat = const Value.absent(),
                Value<String> notes = const Value.absent(),
                Value<bool> favorite = const Value.absent(),
                Value<int?> startedYear = const Value.absent(),
                Value<int?> startedMonth = const Value.absent(),
                Value<int?> startedDay = const Value.absent(),
                Value<int?> completedYear = const Value.absent(),
                Value<int?> completedMonth = const Value.absent(),
                Value<int?> completedDay = const Value.absent(),
                Value<String> canonicalStateJson = const Value.absent(),
                Value<String> fieldRevisionsJson = const Value.absent(),
                Value<int> createdAtMs = const Value.absent(),
                Value<int> updatedAtMs = const Value.absent(),
                Value<int?> tombstonedAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CanonicalLibraryRecordsCompanion(
                localId: localId,
                inLibrary: inLibrary,
                status: status,
                progress: progress,
                progressVolumes: progressVolumes,
                repeatCount: repeatCount,
                watchCycle: watchCycle,
                scoreRaw: scoreRaw,
                scoreFormat: scoreFormat,
                notes: notes,
                favorite: favorite,
                startedYear: startedYear,
                startedMonth: startedMonth,
                startedDay: startedDay,
                completedYear: completedYear,
                completedMonth: completedMonth,
                completedDay: completedDay,
                canonicalStateJson: canonicalStateJson,
                fieldRevisionsJson: fieldRevisionsJson,
                createdAtMs: createdAtMs,
                updatedAtMs: updatedAtMs,
                tombstonedAtMs: tombstonedAtMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String localId,
                Value<bool> inLibrary = const Value.absent(),
                required String status,
                Value<int> progress = const Value.absent(),
                Value<int> progressVolumes = const Value.absent(),
                Value<int> repeatCount = const Value.absent(),
                Value<int> watchCycle = const Value.absent(),
                Value<int?> scoreRaw = const Value.absent(),
                Value<String?> scoreFormat = const Value.absent(),
                Value<String> notes = const Value.absent(),
                Value<bool> favorite = const Value.absent(),
                Value<int?> startedYear = const Value.absent(),
                Value<int?> startedMonth = const Value.absent(),
                Value<int?> startedDay = const Value.absent(),
                Value<int?> completedYear = const Value.absent(),
                Value<int?> completedMonth = const Value.absent(),
                Value<int?> completedDay = const Value.absent(),
                required String canonicalStateJson,
                Value<String> fieldRevisionsJson = const Value.absent(),
                required int createdAtMs,
                required int updatedAtMs,
                Value<int?> tombstonedAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CanonicalLibraryRecordsCompanion.insert(
                localId: localId,
                inLibrary: inLibrary,
                status: status,
                progress: progress,
                progressVolumes: progressVolumes,
                repeatCount: repeatCount,
                watchCycle: watchCycle,
                scoreRaw: scoreRaw,
                scoreFormat: scoreFormat,
                notes: notes,
                favorite: favorite,
                startedYear: startedYear,
                startedMonth: startedMonth,
                startedDay: startedDay,
                completedYear: completedYear,
                completedMonth: completedMonth,
                completedDay: completedDay,
                canonicalStateJson: canonicalStateJson,
                fieldRevisionsJson: fieldRevisionsJson,
                createdAtMs: createdAtMs,
                updatedAtMs: updatedAtMs,
                tombstonedAtMs: tombstonedAtMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$CanonicalLibraryRecordsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({localId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (localId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.localId,
                                referencedTable:
                                    $$CanonicalLibraryRecordsTableReferences
                                        ._localIdTable(db),
                                referencedColumn:
                                    $$CanonicalLibraryRecordsTableReferences
                                        ._localIdTable(db)
                                        .localId,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$CanonicalLibraryRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$CanonicalLibraryDatabase,
      $CanonicalLibraryRecordsTable,
      CanonicalLibraryRecord,
      $$CanonicalLibraryRecordsTableFilterComposer,
      $$CanonicalLibraryRecordsTableOrderingComposer,
      $$CanonicalLibraryRecordsTableAnnotationComposer,
      $$CanonicalLibraryRecordsTableCreateCompanionBuilder,
      $$CanonicalLibraryRecordsTableUpdateCompanionBuilder,
      (CanonicalLibraryRecord, $$CanonicalLibraryRecordsTableReferences),
      CanonicalLibraryRecord,
      PrefetchHooks Function({bool localId})
    >;
typedef $$ProviderSnapshotRecordsTableCreateCompanionBuilder =
    ProviderSnapshotRecordsCompanion Function({
      required String snapshotId,
      required String localId,
      required String provider,
      required String accountId,
      Value<int?> providerEntryId,
      required String normalizedJson,
      required String rawJson,
      required String contentHash,
      required int fetchedAtMs,
      required bool completeSnapshot,
      Value<int> destructiveConfirmationCount,
      Value<int> rowid,
    });
typedef $$ProviderSnapshotRecordsTableUpdateCompanionBuilder =
    ProviderSnapshotRecordsCompanion Function({
      Value<String> snapshotId,
      Value<String> localId,
      Value<String> provider,
      Value<String> accountId,
      Value<int?> providerEntryId,
      Value<String> normalizedJson,
      Value<String> rawJson,
      Value<String> contentHash,
      Value<int> fetchedAtMs,
      Value<bool> completeSnapshot,
      Value<int> destructiveConfirmationCount,
      Value<int> rowid,
    });

final class $$ProviderSnapshotRecordsTableReferences
    extends
        BaseReferences<
          _$CanonicalLibraryDatabase,
          $ProviderSnapshotRecordsTable,
          ProviderSnapshotRecord
        > {
  $$ProviderSnapshotRecordsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $CanonicalMediaRecordsTable _localIdTable(
    _$CanonicalLibraryDatabase db,
  ) => db.canonicalMediaRecords.createAlias(
    'provider_snapshot_records__local_id__canonical_media_records__local_id',
  );

  $$CanonicalMediaRecordsTableProcessedTableManager get localId {
    final $_column = $_itemColumn<String>('local_id')!;

    final manager = $$CanonicalMediaRecordsTableTableManager(
      $_db,
      $_db.canonicalMediaRecords,
    ).filter((f) => f.localId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_localIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ProviderSnapshotRecordsTableFilterComposer
    extends
        Composer<_$CanonicalLibraryDatabase, $ProviderSnapshotRecordsTable> {
  $$ProviderSnapshotRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get snapshotId => $composableBuilder(
    column: $table.snapshotId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get provider => $composableBuilder(
    column: $table.provider,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get providerEntryId => $composableBuilder(
    column: $table.providerEntryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get normalizedJson => $composableBuilder(
    column: $table.normalizedJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rawJson => $composableBuilder(
    column: $table.rawJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fetchedAtMs => $composableBuilder(
    column: $table.fetchedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get completeSnapshot => $composableBuilder(
    column: $table.completeSnapshot,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get destructiveConfirmationCount => $composableBuilder(
    column: $table.destructiveConfirmationCount,
    builder: (column) => ColumnFilters(column),
  );

  $$CanonicalMediaRecordsTableFilterComposer get localId {
    final $$CanonicalMediaRecordsTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.localId,
          referencedTable: $db.canonicalMediaRecords,
          getReferencedColumn: (t) => t.localId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$CanonicalMediaRecordsTableFilterComposer(
                $db: $db,
                $table: $db.canonicalMediaRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$ProviderSnapshotRecordsTableOrderingComposer
    extends
        Composer<_$CanonicalLibraryDatabase, $ProviderSnapshotRecordsTable> {
  $$ProviderSnapshotRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get snapshotId => $composableBuilder(
    column: $table.snapshotId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get provider => $composableBuilder(
    column: $table.provider,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get providerEntryId => $composableBuilder(
    column: $table.providerEntryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get normalizedJson => $composableBuilder(
    column: $table.normalizedJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rawJson => $composableBuilder(
    column: $table.rawJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fetchedAtMs => $composableBuilder(
    column: $table.fetchedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get completeSnapshot => $composableBuilder(
    column: $table.completeSnapshot,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get destructiveConfirmationCount => $composableBuilder(
    column: $table.destructiveConfirmationCount,
    builder: (column) => ColumnOrderings(column),
  );

  $$CanonicalMediaRecordsTableOrderingComposer get localId {
    final $$CanonicalMediaRecordsTableOrderingComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.localId,
          referencedTable: $db.canonicalMediaRecords,
          getReferencedColumn: (t) => t.localId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$CanonicalMediaRecordsTableOrderingComposer(
                $db: $db,
                $table: $db.canonicalMediaRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$ProviderSnapshotRecordsTableAnnotationComposer
    extends
        Composer<_$CanonicalLibraryDatabase, $ProviderSnapshotRecordsTable> {
  $$ProviderSnapshotRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get snapshotId => $composableBuilder(
    column: $table.snapshotId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get provider =>
      $composableBuilder(column: $table.provider, builder: (column) => column);

  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<int> get providerEntryId => $composableBuilder(
    column: $table.providerEntryId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get normalizedJson => $composableBuilder(
    column: $table.normalizedJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get rawJson =>
      $composableBuilder(column: $table.rawJson, builder: (column) => column);

  GeneratedColumn<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => column,
  );

  GeneratedColumn<int> get fetchedAtMs => $composableBuilder(
    column: $table.fetchedAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get completeSnapshot => $composableBuilder(
    column: $table.completeSnapshot,
    builder: (column) => column,
  );

  GeneratedColumn<int> get destructiveConfirmationCount => $composableBuilder(
    column: $table.destructiveConfirmationCount,
    builder: (column) => column,
  );

  $$CanonicalMediaRecordsTableAnnotationComposer get localId {
    final $$CanonicalMediaRecordsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.localId,
          referencedTable: $db.canonicalMediaRecords,
          getReferencedColumn: (t) => t.localId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$CanonicalMediaRecordsTableAnnotationComposer(
                $db: $db,
                $table: $db.canonicalMediaRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$ProviderSnapshotRecordsTableTableManager
    extends
        RootTableManager<
          _$CanonicalLibraryDatabase,
          $ProviderSnapshotRecordsTable,
          ProviderSnapshotRecord,
          $$ProviderSnapshotRecordsTableFilterComposer,
          $$ProviderSnapshotRecordsTableOrderingComposer,
          $$ProviderSnapshotRecordsTableAnnotationComposer,
          $$ProviderSnapshotRecordsTableCreateCompanionBuilder,
          $$ProviderSnapshotRecordsTableUpdateCompanionBuilder,
          (ProviderSnapshotRecord, $$ProviderSnapshotRecordsTableReferences),
          ProviderSnapshotRecord,
          PrefetchHooks Function({bool localId})
        > {
  $$ProviderSnapshotRecordsTableTableManager(
    _$CanonicalLibraryDatabase db,
    $ProviderSnapshotRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProviderSnapshotRecordsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$ProviderSnapshotRecordsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ProviderSnapshotRecordsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> snapshotId = const Value.absent(),
                Value<String> localId = const Value.absent(),
                Value<String> provider = const Value.absent(),
                Value<String> accountId = const Value.absent(),
                Value<int?> providerEntryId = const Value.absent(),
                Value<String> normalizedJson = const Value.absent(),
                Value<String> rawJson = const Value.absent(),
                Value<String> contentHash = const Value.absent(),
                Value<int> fetchedAtMs = const Value.absent(),
                Value<bool> completeSnapshot = const Value.absent(),
                Value<int> destructiveConfirmationCount = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProviderSnapshotRecordsCompanion(
                snapshotId: snapshotId,
                localId: localId,
                provider: provider,
                accountId: accountId,
                providerEntryId: providerEntryId,
                normalizedJson: normalizedJson,
                rawJson: rawJson,
                contentHash: contentHash,
                fetchedAtMs: fetchedAtMs,
                completeSnapshot: completeSnapshot,
                destructiveConfirmationCount: destructiveConfirmationCount,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String snapshotId,
                required String localId,
                required String provider,
                required String accountId,
                Value<int?> providerEntryId = const Value.absent(),
                required String normalizedJson,
                required String rawJson,
                required String contentHash,
                required int fetchedAtMs,
                required bool completeSnapshot,
                Value<int> destructiveConfirmationCount = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProviderSnapshotRecordsCompanion.insert(
                snapshotId: snapshotId,
                localId: localId,
                provider: provider,
                accountId: accountId,
                providerEntryId: providerEntryId,
                normalizedJson: normalizedJson,
                rawJson: rawJson,
                contentHash: contentHash,
                fetchedAtMs: fetchedAtMs,
                completeSnapshot: completeSnapshot,
                destructiveConfirmationCount: destructiveConfirmationCount,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ProviderSnapshotRecordsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({localId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (localId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.localId,
                                referencedTable:
                                    $$ProviderSnapshotRecordsTableReferences
                                        ._localIdTable(db),
                                referencedColumn:
                                    $$ProviderSnapshotRecordsTableReferences
                                        ._localIdTable(db)
                                        .localId,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ProviderSnapshotRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$CanonicalLibraryDatabase,
      $ProviderSnapshotRecordsTable,
      ProviderSnapshotRecord,
      $$ProviderSnapshotRecordsTableFilterComposer,
      $$ProviderSnapshotRecordsTableOrderingComposer,
      $$ProviderSnapshotRecordsTableAnnotationComposer,
      $$ProviderSnapshotRecordsTableCreateCompanionBuilder,
      $$ProviderSnapshotRecordsTableUpdateCompanionBuilder,
      (ProviderSnapshotRecord, $$ProviderSnapshotRecordsTableReferences),
      ProviderSnapshotRecord,
      PrefetchHooks Function({bool localId})
    >;
typedef $$EpisodeStateRecordsTableCreateCompanionBuilder =
    EpisodeStateRecordsCompanion Function({
      required String episodeStateId,
      required String localId,
      required int seasonNumber,
      required double episodeNumber,
      Value<int> positionSeconds,
      Value<int?> durationSeconds,
      Value<bool> completed,
      Value<int> watchCycle,
      required int updatedAtMs,
      Value<int> rowid,
    });
typedef $$EpisodeStateRecordsTableUpdateCompanionBuilder =
    EpisodeStateRecordsCompanion Function({
      Value<String> episodeStateId,
      Value<String> localId,
      Value<int> seasonNumber,
      Value<double> episodeNumber,
      Value<int> positionSeconds,
      Value<int?> durationSeconds,
      Value<bool> completed,
      Value<int> watchCycle,
      Value<int> updatedAtMs,
      Value<int> rowid,
    });

final class $$EpisodeStateRecordsTableReferences
    extends
        BaseReferences<
          _$CanonicalLibraryDatabase,
          $EpisodeStateRecordsTable,
          EpisodeStateRecord
        > {
  $$EpisodeStateRecordsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $CanonicalMediaRecordsTable _localIdTable(
    _$CanonicalLibraryDatabase db,
  ) => db.canonicalMediaRecords.createAlias(
    'episode_state_records__local_id__canonical_media_records__local_id',
  );

  $$CanonicalMediaRecordsTableProcessedTableManager get localId {
    final $_column = $_itemColumn<String>('local_id')!;

    final manager = $$CanonicalMediaRecordsTableTableManager(
      $_db,
      $_db.canonicalMediaRecords,
    ).filter((f) => f.localId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_localIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$EpisodeStateRecordsTableFilterComposer
    extends Composer<_$CanonicalLibraryDatabase, $EpisodeStateRecordsTable> {
  $$EpisodeStateRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get episodeStateId => $composableBuilder(
    column: $table.episodeStateId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get seasonNumber => $composableBuilder(
    column: $table.seasonNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get episodeNumber => $composableBuilder(
    column: $table.episodeNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get positionSeconds => $composableBuilder(
    column: $table.positionSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get completed => $composableBuilder(
    column: $table.completed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get watchCycle => $composableBuilder(
    column: $table.watchCycle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  $$CanonicalMediaRecordsTableFilterComposer get localId {
    final $$CanonicalMediaRecordsTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.localId,
          referencedTable: $db.canonicalMediaRecords,
          getReferencedColumn: (t) => t.localId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$CanonicalMediaRecordsTableFilterComposer(
                $db: $db,
                $table: $db.canonicalMediaRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$EpisodeStateRecordsTableOrderingComposer
    extends Composer<_$CanonicalLibraryDatabase, $EpisodeStateRecordsTable> {
  $$EpisodeStateRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get episodeStateId => $composableBuilder(
    column: $table.episodeStateId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get seasonNumber => $composableBuilder(
    column: $table.seasonNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get episodeNumber => $composableBuilder(
    column: $table.episodeNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get positionSeconds => $composableBuilder(
    column: $table.positionSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get completed => $composableBuilder(
    column: $table.completed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get watchCycle => $composableBuilder(
    column: $table.watchCycle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  $$CanonicalMediaRecordsTableOrderingComposer get localId {
    final $$CanonicalMediaRecordsTableOrderingComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.localId,
          referencedTable: $db.canonicalMediaRecords,
          getReferencedColumn: (t) => t.localId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$CanonicalMediaRecordsTableOrderingComposer(
                $db: $db,
                $table: $db.canonicalMediaRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$EpisodeStateRecordsTableAnnotationComposer
    extends Composer<_$CanonicalLibraryDatabase, $EpisodeStateRecordsTable> {
  $$EpisodeStateRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get episodeStateId => $composableBuilder(
    column: $table.episodeStateId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get seasonNumber => $composableBuilder(
    column: $table.seasonNumber,
    builder: (column) => column,
  );

  GeneratedColumn<double> get episodeNumber => $composableBuilder(
    column: $table.episodeNumber,
    builder: (column) => column,
  );

  GeneratedColumn<int> get positionSeconds => $composableBuilder(
    column: $table.positionSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get completed =>
      $composableBuilder(column: $table.completed, builder: (column) => column);

  GeneratedColumn<int> get watchCycle => $composableBuilder(
    column: $table.watchCycle,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => column,
  );

  $$CanonicalMediaRecordsTableAnnotationComposer get localId {
    final $$CanonicalMediaRecordsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.localId,
          referencedTable: $db.canonicalMediaRecords,
          getReferencedColumn: (t) => t.localId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$CanonicalMediaRecordsTableAnnotationComposer(
                $db: $db,
                $table: $db.canonicalMediaRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$EpisodeStateRecordsTableTableManager
    extends
        RootTableManager<
          _$CanonicalLibraryDatabase,
          $EpisodeStateRecordsTable,
          EpisodeStateRecord,
          $$EpisodeStateRecordsTableFilterComposer,
          $$EpisodeStateRecordsTableOrderingComposer,
          $$EpisodeStateRecordsTableAnnotationComposer,
          $$EpisodeStateRecordsTableCreateCompanionBuilder,
          $$EpisodeStateRecordsTableUpdateCompanionBuilder,
          (EpisodeStateRecord, $$EpisodeStateRecordsTableReferences),
          EpisodeStateRecord,
          PrefetchHooks Function({bool localId})
        > {
  $$EpisodeStateRecordsTableTableManager(
    _$CanonicalLibraryDatabase db,
    $EpisodeStateRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EpisodeStateRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EpisodeStateRecordsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$EpisodeStateRecordsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> episodeStateId = const Value.absent(),
                Value<String> localId = const Value.absent(),
                Value<int> seasonNumber = const Value.absent(),
                Value<double> episodeNumber = const Value.absent(),
                Value<int> positionSeconds = const Value.absent(),
                Value<int?> durationSeconds = const Value.absent(),
                Value<bool> completed = const Value.absent(),
                Value<int> watchCycle = const Value.absent(),
                Value<int> updatedAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EpisodeStateRecordsCompanion(
                episodeStateId: episodeStateId,
                localId: localId,
                seasonNumber: seasonNumber,
                episodeNumber: episodeNumber,
                positionSeconds: positionSeconds,
                durationSeconds: durationSeconds,
                completed: completed,
                watchCycle: watchCycle,
                updatedAtMs: updatedAtMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String episodeStateId,
                required String localId,
                required int seasonNumber,
                required double episodeNumber,
                Value<int> positionSeconds = const Value.absent(),
                Value<int?> durationSeconds = const Value.absent(),
                Value<bool> completed = const Value.absent(),
                Value<int> watchCycle = const Value.absent(),
                required int updatedAtMs,
                Value<int> rowid = const Value.absent(),
              }) => EpisodeStateRecordsCompanion.insert(
                episodeStateId: episodeStateId,
                localId: localId,
                seasonNumber: seasonNumber,
                episodeNumber: episodeNumber,
                positionSeconds: positionSeconds,
                durationSeconds: durationSeconds,
                completed: completed,
                watchCycle: watchCycle,
                updatedAtMs: updatedAtMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$EpisodeStateRecordsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({localId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (localId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.localId,
                                referencedTable:
                                    $$EpisodeStateRecordsTableReferences
                                        ._localIdTable(db),
                                referencedColumn:
                                    $$EpisodeStateRecordsTableReferences
                                        ._localIdTable(db)
                                        .localId,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$EpisodeStateRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$CanonicalLibraryDatabase,
      $EpisodeStateRecordsTable,
      EpisodeStateRecord,
      $$EpisodeStateRecordsTableFilterComposer,
      $$EpisodeStateRecordsTableOrderingComposer,
      $$EpisodeStateRecordsTableAnnotationComposer,
      $$EpisodeStateRecordsTableCreateCompanionBuilder,
      $$EpisodeStateRecordsTableUpdateCompanionBuilder,
      (EpisodeStateRecord, $$EpisodeStateRecordsTableReferences),
      EpisodeStateRecord,
      PrefetchHooks Function({bool localId})
    >;
typedef $$StreamPreferenceRecordsTableCreateCompanionBuilder =
    StreamPreferenceRecordsCompanion Function({
      required String preferenceId,
      required String localId,
      Value<int?> seasonNumber,
      Value<double?> episodeNumber,
      Value<String> addonId,
      Value<String> sourceId,
      Value<String> serverId,
      Value<String> serverTitle,
      Value<String> voiceoverId,
      Value<String> voiceoverTitle,
      Value<String> qualityId,
      Value<String> qualityLabel,
      required int updatedAtMs,
      Value<int> rowid,
    });
typedef $$StreamPreferenceRecordsTableUpdateCompanionBuilder =
    StreamPreferenceRecordsCompanion Function({
      Value<String> preferenceId,
      Value<String> localId,
      Value<int?> seasonNumber,
      Value<double?> episodeNumber,
      Value<String> addonId,
      Value<String> sourceId,
      Value<String> serverId,
      Value<String> serverTitle,
      Value<String> voiceoverId,
      Value<String> voiceoverTitle,
      Value<String> qualityId,
      Value<String> qualityLabel,
      Value<int> updatedAtMs,
      Value<int> rowid,
    });

final class $$StreamPreferenceRecordsTableReferences
    extends
        BaseReferences<
          _$CanonicalLibraryDatabase,
          $StreamPreferenceRecordsTable,
          StreamPreferenceRecord
        > {
  $$StreamPreferenceRecordsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $CanonicalMediaRecordsTable _localIdTable(
    _$CanonicalLibraryDatabase db,
  ) => db.canonicalMediaRecords.createAlias(
    'stream_preference_records__local_id__canonical_media_records__local_id',
  );

  $$CanonicalMediaRecordsTableProcessedTableManager get localId {
    final $_column = $_itemColumn<String>('local_id')!;

    final manager = $$CanonicalMediaRecordsTableTableManager(
      $_db,
      $_db.canonicalMediaRecords,
    ).filter((f) => f.localId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_localIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$StreamPreferenceRecordsTableFilterComposer
    extends
        Composer<_$CanonicalLibraryDatabase, $StreamPreferenceRecordsTable> {
  $$StreamPreferenceRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get preferenceId => $composableBuilder(
    column: $table.preferenceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get seasonNumber => $composableBuilder(
    column: $table.seasonNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get episodeNumber => $composableBuilder(
    column: $table.episodeNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get addonId => $composableBuilder(
    column: $table.addonId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serverTitle => $composableBuilder(
    column: $table.serverTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get voiceoverId => $composableBuilder(
    column: $table.voiceoverId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get voiceoverTitle => $composableBuilder(
    column: $table.voiceoverTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get qualityId => $composableBuilder(
    column: $table.qualityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get qualityLabel => $composableBuilder(
    column: $table.qualityLabel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  $$CanonicalMediaRecordsTableFilterComposer get localId {
    final $$CanonicalMediaRecordsTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.localId,
          referencedTable: $db.canonicalMediaRecords,
          getReferencedColumn: (t) => t.localId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$CanonicalMediaRecordsTableFilterComposer(
                $db: $db,
                $table: $db.canonicalMediaRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$StreamPreferenceRecordsTableOrderingComposer
    extends
        Composer<_$CanonicalLibraryDatabase, $StreamPreferenceRecordsTable> {
  $$StreamPreferenceRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get preferenceId => $composableBuilder(
    column: $table.preferenceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get seasonNumber => $composableBuilder(
    column: $table.seasonNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get episodeNumber => $composableBuilder(
    column: $table.episodeNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get addonId => $composableBuilder(
    column: $table.addonId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serverTitle => $composableBuilder(
    column: $table.serverTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get voiceoverId => $composableBuilder(
    column: $table.voiceoverId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get voiceoverTitle => $composableBuilder(
    column: $table.voiceoverTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get qualityId => $composableBuilder(
    column: $table.qualityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get qualityLabel => $composableBuilder(
    column: $table.qualityLabel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  $$CanonicalMediaRecordsTableOrderingComposer get localId {
    final $$CanonicalMediaRecordsTableOrderingComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.localId,
          referencedTable: $db.canonicalMediaRecords,
          getReferencedColumn: (t) => t.localId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$CanonicalMediaRecordsTableOrderingComposer(
                $db: $db,
                $table: $db.canonicalMediaRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$StreamPreferenceRecordsTableAnnotationComposer
    extends
        Composer<_$CanonicalLibraryDatabase, $StreamPreferenceRecordsTable> {
  $$StreamPreferenceRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get preferenceId => $composableBuilder(
    column: $table.preferenceId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get seasonNumber => $composableBuilder(
    column: $table.seasonNumber,
    builder: (column) => column,
  );

  GeneratedColumn<double> get episodeNumber => $composableBuilder(
    column: $table.episodeNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get addonId =>
      $composableBuilder(column: $table.addonId, builder: (column) => column);

  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<String> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<String> get serverTitle => $composableBuilder(
    column: $table.serverTitle,
    builder: (column) => column,
  );

  GeneratedColumn<String> get voiceoverId => $composableBuilder(
    column: $table.voiceoverId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get voiceoverTitle => $composableBuilder(
    column: $table.voiceoverTitle,
    builder: (column) => column,
  );

  GeneratedColumn<String> get qualityId =>
      $composableBuilder(column: $table.qualityId, builder: (column) => column);

  GeneratedColumn<String> get qualityLabel => $composableBuilder(
    column: $table.qualityLabel,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => column,
  );

  $$CanonicalMediaRecordsTableAnnotationComposer get localId {
    final $$CanonicalMediaRecordsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.localId,
          referencedTable: $db.canonicalMediaRecords,
          getReferencedColumn: (t) => t.localId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$CanonicalMediaRecordsTableAnnotationComposer(
                $db: $db,
                $table: $db.canonicalMediaRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$StreamPreferenceRecordsTableTableManager
    extends
        RootTableManager<
          _$CanonicalLibraryDatabase,
          $StreamPreferenceRecordsTable,
          StreamPreferenceRecord,
          $$StreamPreferenceRecordsTableFilterComposer,
          $$StreamPreferenceRecordsTableOrderingComposer,
          $$StreamPreferenceRecordsTableAnnotationComposer,
          $$StreamPreferenceRecordsTableCreateCompanionBuilder,
          $$StreamPreferenceRecordsTableUpdateCompanionBuilder,
          (StreamPreferenceRecord, $$StreamPreferenceRecordsTableReferences),
          StreamPreferenceRecord,
          PrefetchHooks Function({bool localId})
        > {
  $$StreamPreferenceRecordsTableTableManager(
    _$CanonicalLibraryDatabase db,
    $StreamPreferenceRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StreamPreferenceRecordsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$StreamPreferenceRecordsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$StreamPreferenceRecordsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> preferenceId = const Value.absent(),
                Value<String> localId = const Value.absent(),
                Value<int?> seasonNumber = const Value.absent(),
                Value<double?> episodeNumber = const Value.absent(),
                Value<String> addonId = const Value.absent(),
                Value<String> sourceId = const Value.absent(),
                Value<String> serverId = const Value.absent(),
                Value<String> serverTitle = const Value.absent(),
                Value<String> voiceoverId = const Value.absent(),
                Value<String> voiceoverTitle = const Value.absent(),
                Value<String> qualityId = const Value.absent(),
                Value<String> qualityLabel = const Value.absent(),
                Value<int> updatedAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StreamPreferenceRecordsCompanion(
                preferenceId: preferenceId,
                localId: localId,
                seasonNumber: seasonNumber,
                episodeNumber: episodeNumber,
                addonId: addonId,
                sourceId: sourceId,
                serverId: serverId,
                serverTitle: serverTitle,
                voiceoverId: voiceoverId,
                voiceoverTitle: voiceoverTitle,
                qualityId: qualityId,
                qualityLabel: qualityLabel,
                updatedAtMs: updatedAtMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String preferenceId,
                required String localId,
                Value<int?> seasonNumber = const Value.absent(),
                Value<double?> episodeNumber = const Value.absent(),
                Value<String> addonId = const Value.absent(),
                Value<String> sourceId = const Value.absent(),
                Value<String> serverId = const Value.absent(),
                Value<String> serverTitle = const Value.absent(),
                Value<String> voiceoverId = const Value.absent(),
                Value<String> voiceoverTitle = const Value.absent(),
                Value<String> qualityId = const Value.absent(),
                Value<String> qualityLabel = const Value.absent(),
                required int updatedAtMs,
                Value<int> rowid = const Value.absent(),
              }) => StreamPreferenceRecordsCompanion.insert(
                preferenceId: preferenceId,
                localId: localId,
                seasonNumber: seasonNumber,
                episodeNumber: episodeNumber,
                addonId: addonId,
                sourceId: sourceId,
                serverId: serverId,
                serverTitle: serverTitle,
                voiceoverId: voiceoverId,
                voiceoverTitle: voiceoverTitle,
                qualityId: qualityId,
                qualityLabel: qualityLabel,
                updatedAtMs: updatedAtMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$StreamPreferenceRecordsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({localId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (localId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.localId,
                                referencedTable:
                                    $$StreamPreferenceRecordsTableReferences
                                        ._localIdTable(db),
                                referencedColumn:
                                    $$StreamPreferenceRecordsTableReferences
                                        ._localIdTable(db)
                                        .localId,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$StreamPreferenceRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$CanonicalLibraryDatabase,
      $StreamPreferenceRecordsTable,
      StreamPreferenceRecord,
      $$StreamPreferenceRecordsTableFilterComposer,
      $$StreamPreferenceRecordsTableOrderingComposer,
      $$StreamPreferenceRecordsTableAnnotationComposer,
      $$StreamPreferenceRecordsTableCreateCompanionBuilder,
      $$StreamPreferenceRecordsTableUpdateCompanionBuilder,
      (StreamPreferenceRecord, $$StreamPreferenceRecordsTableReferences),
      StreamPreferenceRecord,
      PrefetchHooks Function({bool localId})
    >;
typedef $$LibraryOperationRecordsTableCreateCompanionBuilder =
    LibraryOperationRecordsCompanion Function({
      required String operationId,
      required String localId,
      required String deviceId,
      required String originKind,
      Value<String?> originId,
      required String intent,
      required String fieldsJson,
      required String beforeJson,
      required String afterJson,
      required String baseRevisionsJson,
      required String resultingRevisionsJson,
      required String targetsJson,
      Value<String?> undoOf,
      Value<String?> title,
      Value<bool> visibleInLog,
      required int occurredAtMs,
      Value<int> rowid,
    });
typedef $$LibraryOperationRecordsTableUpdateCompanionBuilder =
    LibraryOperationRecordsCompanion Function({
      Value<String> operationId,
      Value<String> localId,
      Value<String> deviceId,
      Value<String> originKind,
      Value<String?> originId,
      Value<String> intent,
      Value<String> fieldsJson,
      Value<String> beforeJson,
      Value<String> afterJson,
      Value<String> baseRevisionsJson,
      Value<String> resultingRevisionsJson,
      Value<String> targetsJson,
      Value<String?> undoOf,
      Value<String?> title,
      Value<bool> visibleInLog,
      Value<int> occurredAtMs,
      Value<int> rowid,
    });

final class $$LibraryOperationRecordsTableReferences
    extends
        BaseReferences<
          _$CanonicalLibraryDatabase,
          $LibraryOperationRecordsTable,
          LibraryOperationRecord
        > {
  $$LibraryOperationRecordsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $CanonicalMediaRecordsTable _localIdTable(
    _$CanonicalLibraryDatabase db,
  ) => db.canonicalMediaRecords.createAlias(
    'library_operation_records__local_id__canonical_media_records__local_id',
  );

  $$CanonicalMediaRecordsTableProcessedTableManager get localId {
    final $_column = $_itemColumn<String>('local_id')!;

    final manager = $$CanonicalMediaRecordsTableTableManager(
      $_db,
      $_db.canonicalMediaRecords,
    ).filter((f) => f.localId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_localIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<
    $OutboxDeliveryRecordsTable,
    List<OutboxDeliveryRecord>
  >
  _outboxDeliveryRecordsRefsTable(
    _$CanonicalLibraryDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.outboxDeliveryRecords,
    aliasName:
        'library_operation_records__operation_id__outbox_delivery_records__operation_id',
  );

  $$OutboxDeliveryRecordsTableProcessedTableManager
  get outboxDeliveryRecordsRefs {
    final manager =
        $$OutboxDeliveryRecordsTableTableManager(
          $_db,
          $_db.outboxDeliveryRecords,
        ).filter(
          (f) => f.operationId.operationId.sqlEquals(
            $_itemColumn<String>('operation_id')!,
          ),
        );

    final cache = $_typedResult.readTableOrNull(
      _outboxDeliveryRecordsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$LibraryOperationRecordsTableFilterComposer
    extends
        Composer<_$CanonicalLibraryDatabase, $LibraryOperationRecordsTable> {
  $$LibraryOperationRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get originKind => $composableBuilder(
    column: $table.originKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get originId => $composableBuilder(
    column: $table.originId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get intent => $composableBuilder(
    column: $table.intent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fieldsJson => $composableBuilder(
    column: $table.fieldsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get beforeJson => $composableBuilder(
    column: $table.beforeJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get afterJson => $composableBuilder(
    column: $table.afterJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get baseRevisionsJson => $composableBuilder(
    column: $table.baseRevisionsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get resultingRevisionsJson => $composableBuilder(
    column: $table.resultingRevisionsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetsJson => $composableBuilder(
    column: $table.targetsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get undoOf => $composableBuilder(
    column: $table.undoOf,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get visibleInLog => $composableBuilder(
    column: $table.visibleInLog,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get occurredAtMs => $composableBuilder(
    column: $table.occurredAtMs,
    builder: (column) => ColumnFilters(column),
  );

  $$CanonicalMediaRecordsTableFilterComposer get localId {
    final $$CanonicalMediaRecordsTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.localId,
          referencedTable: $db.canonicalMediaRecords,
          getReferencedColumn: (t) => t.localId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$CanonicalMediaRecordsTableFilterComposer(
                $db: $db,
                $table: $db.canonicalMediaRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }

  Expression<bool> outboxDeliveryRecordsRefs(
    Expression<bool> Function($$OutboxDeliveryRecordsTableFilterComposer f) f,
  ) {
    final $$OutboxDeliveryRecordsTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.operationId,
          referencedTable: $db.outboxDeliveryRecords,
          getReferencedColumn: (t) => t.operationId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$OutboxDeliveryRecordsTableFilterComposer(
                $db: $db,
                $table: $db.outboxDeliveryRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$LibraryOperationRecordsTableOrderingComposer
    extends
        Composer<_$CanonicalLibraryDatabase, $LibraryOperationRecordsTable> {
  $$LibraryOperationRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originKind => $composableBuilder(
    column: $table.originKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originId => $composableBuilder(
    column: $table.originId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get intent => $composableBuilder(
    column: $table.intent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fieldsJson => $composableBuilder(
    column: $table.fieldsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get beforeJson => $composableBuilder(
    column: $table.beforeJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get afterJson => $composableBuilder(
    column: $table.afterJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get baseRevisionsJson => $composableBuilder(
    column: $table.baseRevisionsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get resultingRevisionsJson => $composableBuilder(
    column: $table.resultingRevisionsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetsJson => $composableBuilder(
    column: $table.targetsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get undoOf => $composableBuilder(
    column: $table.undoOf,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get visibleInLog => $composableBuilder(
    column: $table.visibleInLog,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get occurredAtMs => $composableBuilder(
    column: $table.occurredAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  $$CanonicalMediaRecordsTableOrderingComposer get localId {
    final $$CanonicalMediaRecordsTableOrderingComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.localId,
          referencedTable: $db.canonicalMediaRecords,
          getReferencedColumn: (t) => t.localId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$CanonicalMediaRecordsTableOrderingComposer(
                $db: $db,
                $table: $db.canonicalMediaRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$LibraryOperationRecordsTableAnnotationComposer
    extends
        Composer<_$CanonicalLibraryDatabase, $LibraryOperationRecordsTable> {
  $$LibraryOperationRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get originKind => $composableBuilder(
    column: $table.originKind,
    builder: (column) => column,
  );

  GeneratedColumn<String> get originId =>
      $composableBuilder(column: $table.originId, builder: (column) => column);

  GeneratedColumn<String> get intent =>
      $composableBuilder(column: $table.intent, builder: (column) => column);

  GeneratedColumn<String> get fieldsJson => $composableBuilder(
    column: $table.fieldsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get beforeJson => $composableBuilder(
    column: $table.beforeJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get afterJson =>
      $composableBuilder(column: $table.afterJson, builder: (column) => column);

  GeneratedColumn<String> get baseRevisionsJson => $composableBuilder(
    column: $table.baseRevisionsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get resultingRevisionsJson => $composableBuilder(
    column: $table.resultingRevisionsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get targetsJson => $composableBuilder(
    column: $table.targetsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get undoOf =>
      $composableBuilder(column: $table.undoOf, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<bool> get visibleInLog => $composableBuilder(
    column: $table.visibleInLog,
    builder: (column) => column,
  );

  GeneratedColumn<int> get occurredAtMs => $composableBuilder(
    column: $table.occurredAtMs,
    builder: (column) => column,
  );

  $$CanonicalMediaRecordsTableAnnotationComposer get localId {
    final $$CanonicalMediaRecordsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.localId,
          referencedTable: $db.canonicalMediaRecords,
          getReferencedColumn: (t) => t.localId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$CanonicalMediaRecordsTableAnnotationComposer(
                $db: $db,
                $table: $db.canonicalMediaRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }

  Expression<T> outboxDeliveryRecordsRefs<T extends Object>(
    Expression<T> Function($$OutboxDeliveryRecordsTableAnnotationComposer a) f,
  ) {
    final $$OutboxDeliveryRecordsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.operationId,
          referencedTable: $db.outboxDeliveryRecords,
          getReferencedColumn: (t) => t.operationId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$OutboxDeliveryRecordsTableAnnotationComposer(
                $db: $db,
                $table: $db.outboxDeliveryRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$LibraryOperationRecordsTableTableManager
    extends
        RootTableManager<
          _$CanonicalLibraryDatabase,
          $LibraryOperationRecordsTable,
          LibraryOperationRecord,
          $$LibraryOperationRecordsTableFilterComposer,
          $$LibraryOperationRecordsTableOrderingComposer,
          $$LibraryOperationRecordsTableAnnotationComposer,
          $$LibraryOperationRecordsTableCreateCompanionBuilder,
          $$LibraryOperationRecordsTableUpdateCompanionBuilder,
          (LibraryOperationRecord, $$LibraryOperationRecordsTableReferences),
          LibraryOperationRecord,
          PrefetchHooks Function({bool localId, bool outboxDeliveryRecordsRefs})
        > {
  $$LibraryOperationRecordsTableTableManager(
    _$CanonicalLibraryDatabase db,
    $LibraryOperationRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LibraryOperationRecordsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$LibraryOperationRecordsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$LibraryOperationRecordsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> operationId = const Value.absent(),
                Value<String> localId = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> originKind = const Value.absent(),
                Value<String?> originId = const Value.absent(),
                Value<String> intent = const Value.absent(),
                Value<String> fieldsJson = const Value.absent(),
                Value<String> beforeJson = const Value.absent(),
                Value<String> afterJson = const Value.absent(),
                Value<String> baseRevisionsJson = const Value.absent(),
                Value<String> resultingRevisionsJson = const Value.absent(),
                Value<String> targetsJson = const Value.absent(),
                Value<String?> undoOf = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<bool> visibleInLog = const Value.absent(),
                Value<int> occurredAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LibraryOperationRecordsCompanion(
                operationId: operationId,
                localId: localId,
                deviceId: deviceId,
                originKind: originKind,
                originId: originId,
                intent: intent,
                fieldsJson: fieldsJson,
                beforeJson: beforeJson,
                afterJson: afterJson,
                baseRevisionsJson: baseRevisionsJson,
                resultingRevisionsJson: resultingRevisionsJson,
                targetsJson: targetsJson,
                undoOf: undoOf,
                title: title,
                visibleInLog: visibleInLog,
                occurredAtMs: occurredAtMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String operationId,
                required String localId,
                required String deviceId,
                required String originKind,
                Value<String?> originId = const Value.absent(),
                required String intent,
                required String fieldsJson,
                required String beforeJson,
                required String afterJson,
                required String baseRevisionsJson,
                required String resultingRevisionsJson,
                required String targetsJson,
                Value<String?> undoOf = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<bool> visibleInLog = const Value.absent(),
                required int occurredAtMs,
                Value<int> rowid = const Value.absent(),
              }) => LibraryOperationRecordsCompanion.insert(
                operationId: operationId,
                localId: localId,
                deviceId: deviceId,
                originKind: originKind,
                originId: originId,
                intent: intent,
                fieldsJson: fieldsJson,
                beforeJson: beforeJson,
                afterJson: afterJson,
                baseRevisionsJson: baseRevisionsJson,
                resultingRevisionsJson: resultingRevisionsJson,
                targetsJson: targetsJson,
                undoOf: undoOf,
                title: title,
                visibleInLog: visibleInLog,
                occurredAtMs: occurredAtMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$LibraryOperationRecordsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({localId = false, outboxDeliveryRecordsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (outboxDeliveryRecordsRefs) db.outboxDeliveryRecords,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (localId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.localId,
                                    referencedTable:
                                        $$LibraryOperationRecordsTableReferences
                                            ._localIdTable(db),
                                    referencedColumn:
                                        $$LibraryOperationRecordsTableReferences
                                            ._localIdTable(db)
                                            .localId,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (outboxDeliveryRecordsRefs)
                        await $_getPrefetchedData<
                          LibraryOperationRecord,
                          $LibraryOperationRecordsTable,
                          OutboxDeliveryRecord
                        >(
                          currentTable: table,
                          referencedTable:
                              $$LibraryOperationRecordsTableReferences
                                  ._outboxDeliveryRecordsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$LibraryOperationRecordsTableReferences(
                                db,
                                table,
                                p0,
                              ).outboxDeliveryRecordsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.operationId == item.operationId,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$LibraryOperationRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$CanonicalLibraryDatabase,
      $LibraryOperationRecordsTable,
      LibraryOperationRecord,
      $$LibraryOperationRecordsTableFilterComposer,
      $$LibraryOperationRecordsTableOrderingComposer,
      $$LibraryOperationRecordsTableAnnotationComposer,
      $$LibraryOperationRecordsTableCreateCompanionBuilder,
      $$LibraryOperationRecordsTableUpdateCompanionBuilder,
      (LibraryOperationRecord, $$LibraryOperationRecordsTableReferences),
      LibraryOperationRecord,
      PrefetchHooks Function({bool localId, bool outboxDeliveryRecordsRefs})
    >;
typedef $$OutboxDeliveryRecordsTableCreateCompanionBuilder =
    OutboxDeliveryRecordsCompanion Function({
      required String deliveryId,
      required String operationId,
      required String target,
      Value<String?> accountId,
      required String state,
      Value<int> attempts,
      Value<int?> nextAttemptAtMs,
      Value<int?> deliveredAtMs,
      Value<int?> confirmedAtMs,
      Value<String?> lastError,
      Value<int> rowid,
    });
typedef $$OutboxDeliveryRecordsTableUpdateCompanionBuilder =
    OutboxDeliveryRecordsCompanion Function({
      Value<String> deliveryId,
      Value<String> operationId,
      Value<String> target,
      Value<String?> accountId,
      Value<String> state,
      Value<int> attempts,
      Value<int?> nextAttemptAtMs,
      Value<int?> deliveredAtMs,
      Value<int?> confirmedAtMs,
      Value<String?> lastError,
      Value<int> rowid,
    });

final class $$OutboxDeliveryRecordsTableReferences
    extends
        BaseReferences<
          _$CanonicalLibraryDatabase,
          $OutboxDeliveryRecordsTable,
          OutboxDeliveryRecord
        > {
  $$OutboxDeliveryRecordsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $LibraryOperationRecordsTable _operationIdTable(
    _$CanonicalLibraryDatabase db,
  ) => db.libraryOperationRecords.createAlias(
    'outbox_delivery_records__operation_id__library_operation_records__operation_id',
  );

  $$LibraryOperationRecordsTableProcessedTableManager get operationId {
    final $_column = $_itemColumn<String>('operation_id')!;

    final manager = $$LibraryOperationRecordsTableTableManager(
      $_db,
      $_db.libraryOperationRecords,
    ).filter((f) => f.operationId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_operationIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$OutboxDeliveryRecordsTableFilterComposer
    extends Composer<_$CanonicalLibraryDatabase, $OutboxDeliveryRecordsTable> {
  $$OutboxDeliveryRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get deliveryId => $composableBuilder(
    column: $table.deliveryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get target => $composableBuilder(
    column: $table.target,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get nextAttemptAtMs => $composableBuilder(
    column: $table.nextAttemptAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deliveredAtMs => $composableBuilder(
    column: $table.deliveredAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get confirmedAtMs => $composableBuilder(
    column: $table.confirmedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  $$LibraryOperationRecordsTableFilterComposer get operationId {
    final $$LibraryOperationRecordsTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.operationId,
          referencedTable: $db.libraryOperationRecords,
          getReferencedColumn: (t) => t.operationId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$LibraryOperationRecordsTableFilterComposer(
                $db: $db,
                $table: $db.libraryOperationRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$OutboxDeliveryRecordsTableOrderingComposer
    extends Composer<_$CanonicalLibraryDatabase, $OutboxDeliveryRecordsTable> {
  $$OutboxDeliveryRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get deliveryId => $composableBuilder(
    column: $table.deliveryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get target => $composableBuilder(
    column: $table.target,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get nextAttemptAtMs => $composableBuilder(
    column: $table.nextAttemptAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deliveredAtMs => $composableBuilder(
    column: $table.deliveredAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get confirmedAtMs => $composableBuilder(
    column: $table.confirmedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  $$LibraryOperationRecordsTableOrderingComposer get operationId {
    final $$LibraryOperationRecordsTableOrderingComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.operationId,
          referencedTable: $db.libraryOperationRecords,
          getReferencedColumn: (t) => t.operationId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$LibraryOperationRecordsTableOrderingComposer(
                $db: $db,
                $table: $db.libraryOperationRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$OutboxDeliveryRecordsTableAnnotationComposer
    extends Composer<_$CanonicalLibraryDatabase, $OutboxDeliveryRecordsTable> {
  $$OutboxDeliveryRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get deliveryId => $composableBuilder(
    column: $table.deliveryId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get target =>
      $composableBuilder(column: $table.target, builder: (column) => column);

  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<int> get nextAttemptAtMs => $composableBuilder(
    column: $table.nextAttemptAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get deliveredAtMs => $composableBuilder(
    column: $table.deliveredAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get confirmedAtMs => $composableBuilder(
    column: $table.confirmedAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  $$LibraryOperationRecordsTableAnnotationComposer get operationId {
    final $$LibraryOperationRecordsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.operationId,
          referencedTable: $db.libraryOperationRecords,
          getReferencedColumn: (t) => t.operationId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$LibraryOperationRecordsTableAnnotationComposer(
                $db: $db,
                $table: $db.libraryOperationRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$OutboxDeliveryRecordsTableTableManager
    extends
        RootTableManager<
          _$CanonicalLibraryDatabase,
          $OutboxDeliveryRecordsTable,
          OutboxDeliveryRecord,
          $$OutboxDeliveryRecordsTableFilterComposer,
          $$OutboxDeliveryRecordsTableOrderingComposer,
          $$OutboxDeliveryRecordsTableAnnotationComposer,
          $$OutboxDeliveryRecordsTableCreateCompanionBuilder,
          $$OutboxDeliveryRecordsTableUpdateCompanionBuilder,
          (OutboxDeliveryRecord, $$OutboxDeliveryRecordsTableReferences),
          OutboxDeliveryRecord,
          PrefetchHooks Function({bool operationId})
        > {
  $$OutboxDeliveryRecordsTableTableManager(
    _$CanonicalLibraryDatabase db,
    $OutboxDeliveryRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutboxDeliveryRecordsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$OutboxDeliveryRecordsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$OutboxDeliveryRecordsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> deliveryId = const Value.absent(),
                Value<String> operationId = const Value.absent(),
                Value<String> target = const Value.absent(),
                Value<String?> accountId = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<int?> nextAttemptAtMs = const Value.absent(),
                Value<int?> deliveredAtMs = const Value.absent(),
                Value<int?> confirmedAtMs = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OutboxDeliveryRecordsCompanion(
                deliveryId: deliveryId,
                operationId: operationId,
                target: target,
                accountId: accountId,
                state: state,
                attempts: attempts,
                nextAttemptAtMs: nextAttemptAtMs,
                deliveredAtMs: deliveredAtMs,
                confirmedAtMs: confirmedAtMs,
                lastError: lastError,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String deliveryId,
                required String operationId,
                required String target,
                Value<String?> accountId = const Value.absent(),
                required String state,
                Value<int> attempts = const Value.absent(),
                Value<int?> nextAttemptAtMs = const Value.absent(),
                Value<int?> deliveredAtMs = const Value.absent(),
                Value<int?> confirmedAtMs = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OutboxDeliveryRecordsCompanion.insert(
                deliveryId: deliveryId,
                operationId: operationId,
                target: target,
                accountId: accountId,
                state: state,
                attempts: attempts,
                nextAttemptAtMs: nextAttemptAtMs,
                deliveredAtMs: deliveredAtMs,
                confirmedAtMs: confirmedAtMs,
                lastError: lastError,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$OutboxDeliveryRecordsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({operationId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (operationId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.operationId,
                                referencedTable:
                                    $$OutboxDeliveryRecordsTableReferences
                                        ._operationIdTable(db),
                                referencedColumn:
                                    $$OutboxDeliveryRecordsTableReferences
                                        ._operationIdTable(db)
                                        .operationId,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$OutboxDeliveryRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$CanonicalLibraryDatabase,
      $OutboxDeliveryRecordsTable,
      OutboxDeliveryRecord,
      $$OutboxDeliveryRecordsTableFilterComposer,
      $$OutboxDeliveryRecordsTableOrderingComposer,
      $$OutboxDeliveryRecordsTableAnnotationComposer,
      $$OutboxDeliveryRecordsTableCreateCompanionBuilder,
      $$OutboxDeliveryRecordsTableUpdateCompanionBuilder,
      (OutboxDeliveryRecord, $$OutboxDeliveryRecordsTableReferences),
      OutboxDeliveryRecord,
      PrefetchHooks Function({bool operationId})
    >;
typedef $$LibraryConflictRecordsTableCreateCompanionBuilder =
    LibraryConflictRecordsCompanion Function({
      required String conflictId,
      required String localId,
      required String fieldName,
      required String localValueJson,
      required String incomingValueJson,
      Value<String?> localOperationId,
      Value<String?> incomingOperationId,
      Value<String> state,
      required int createdAtMs,
      Value<int?> resolvedAtMs,
      Value<int> rowid,
    });
typedef $$LibraryConflictRecordsTableUpdateCompanionBuilder =
    LibraryConflictRecordsCompanion Function({
      Value<String> conflictId,
      Value<String> localId,
      Value<String> fieldName,
      Value<String> localValueJson,
      Value<String> incomingValueJson,
      Value<String?> localOperationId,
      Value<String?> incomingOperationId,
      Value<String> state,
      Value<int> createdAtMs,
      Value<int?> resolvedAtMs,
      Value<int> rowid,
    });

final class $$LibraryConflictRecordsTableReferences
    extends
        BaseReferences<
          _$CanonicalLibraryDatabase,
          $LibraryConflictRecordsTable,
          LibraryConflictRecord
        > {
  $$LibraryConflictRecordsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $CanonicalMediaRecordsTable _localIdTable(
    _$CanonicalLibraryDatabase db,
  ) => db.canonicalMediaRecords.createAlias(
    'library_conflict_records__local_id__canonical_media_records__local_id',
  );

  $$CanonicalMediaRecordsTableProcessedTableManager get localId {
    final $_column = $_itemColumn<String>('local_id')!;

    final manager = $$CanonicalMediaRecordsTableTableManager(
      $_db,
      $_db.canonicalMediaRecords,
    ).filter((f) => f.localId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_localIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$LibraryConflictRecordsTableFilterComposer
    extends Composer<_$CanonicalLibraryDatabase, $LibraryConflictRecordsTable> {
  $$LibraryConflictRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get conflictId => $composableBuilder(
    column: $table.conflictId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fieldName => $composableBuilder(
    column: $table.fieldName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localValueJson => $composableBuilder(
    column: $table.localValueJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get incomingValueJson => $composableBuilder(
    column: $table.incomingValueJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localOperationId => $composableBuilder(
    column: $table.localOperationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get incomingOperationId => $composableBuilder(
    column: $table.incomingOperationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get resolvedAtMs => $composableBuilder(
    column: $table.resolvedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  $$CanonicalMediaRecordsTableFilterComposer get localId {
    final $$CanonicalMediaRecordsTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.localId,
          referencedTable: $db.canonicalMediaRecords,
          getReferencedColumn: (t) => t.localId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$CanonicalMediaRecordsTableFilterComposer(
                $db: $db,
                $table: $db.canonicalMediaRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$LibraryConflictRecordsTableOrderingComposer
    extends Composer<_$CanonicalLibraryDatabase, $LibraryConflictRecordsTable> {
  $$LibraryConflictRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get conflictId => $composableBuilder(
    column: $table.conflictId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fieldName => $composableBuilder(
    column: $table.fieldName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localValueJson => $composableBuilder(
    column: $table.localValueJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get incomingValueJson => $composableBuilder(
    column: $table.incomingValueJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localOperationId => $composableBuilder(
    column: $table.localOperationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get incomingOperationId => $composableBuilder(
    column: $table.incomingOperationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get resolvedAtMs => $composableBuilder(
    column: $table.resolvedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  $$CanonicalMediaRecordsTableOrderingComposer get localId {
    final $$CanonicalMediaRecordsTableOrderingComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.localId,
          referencedTable: $db.canonicalMediaRecords,
          getReferencedColumn: (t) => t.localId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$CanonicalMediaRecordsTableOrderingComposer(
                $db: $db,
                $table: $db.canonicalMediaRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$LibraryConflictRecordsTableAnnotationComposer
    extends Composer<_$CanonicalLibraryDatabase, $LibraryConflictRecordsTable> {
  $$LibraryConflictRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get conflictId => $composableBuilder(
    column: $table.conflictId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get fieldName =>
      $composableBuilder(column: $table.fieldName, builder: (column) => column);

  GeneratedColumn<String> get localValueJson => $composableBuilder(
    column: $table.localValueJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get incomingValueJson => $composableBuilder(
    column: $table.incomingValueJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get localOperationId => $composableBuilder(
    column: $table.localOperationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get incomingOperationId => $composableBuilder(
    column: $table.incomingOperationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get resolvedAtMs => $composableBuilder(
    column: $table.resolvedAtMs,
    builder: (column) => column,
  );

  $$CanonicalMediaRecordsTableAnnotationComposer get localId {
    final $$CanonicalMediaRecordsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.localId,
          referencedTable: $db.canonicalMediaRecords,
          getReferencedColumn: (t) => t.localId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$CanonicalMediaRecordsTableAnnotationComposer(
                $db: $db,
                $table: $db.canonicalMediaRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$LibraryConflictRecordsTableTableManager
    extends
        RootTableManager<
          _$CanonicalLibraryDatabase,
          $LibraryConflictRecordsTable,
          LibraryConflictRecord,
          $$LibraryConflictRecordsTableFilterComposer,
          $$LibraryConflictRecordsTableOrderingComposer,
          $$LibraryConflictRecordsTableAnnotationComposer,
          $$LibraryConflictRecordsTableCreateCompanionBuilder,
          $$LibraryConflictRecordsTableUpdateCompanionBuilder,
          (LibraryConflictRecord, $$LibraryConflictRecordsTableReferences),
          LibraryConflictRecord,
          PrefetchHooks Function({bool localId})
        > {
  $$LibraryConflictRecordsTableTableManager(
    _$CanonicalLibraryDatabase db,
    $LibraryConflictRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LibraryConflictRecordsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$LibraryConflictRecordsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$LibraryConflictRecordsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> conflictId = const Value.absent(),
                Value<String> localId = const Value.absent(),
                Value<String> fieldName = const Value.absent(),
                Value<String> localValueJson = const Value.absent(),
                Value<String> incomingValueJson = const Value.absent(),
                Value<String?> localOperationId = const Value.absent(),
                Value<String?> incomingOperationId = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<int> createdAtMs = const Value.absent(),
                Value<int?> resolvedAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LibraryConflictRecordsCompanion(
                conflictId: conflictId,
                localId: localId,
                fieldName: fieldName,
                localValueJson: localValueJson,
                incomingValueJson: incomingValueJson,
                localOperationId: localOperationId,
                incomingOperationId: incomingOperationId,
                state: state,
                createdAtMs: createdAtMs,
                resolvedAtMs: resolvedAtMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String conflictId,
                required String localId,
                required String fieldName,
                required String localValueJson,
                required String incomingValueJson,
                Value<String?> localOperationId = const Value.absent(),
                Value<String?> incomingOperationId = const Value.absent(),
                Value<String> state = const Value.absent(),
                required int createdAtMs,
                Value<int?> resolvedAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LibraryConflictRecordsCompanion.insert(
                conflictId: conflictId,
                localId: localId,
                fieldName: fieldName,
                localValueJson: localValueJson,
                incomingValueJson: incomingValueJson,
                localOperationId: localOperationId,
                incomingOperationId: incomingOperationId,
                state: state,
                createdAtMs: createdAtMs,
                resolvedAtMs: resolvedAtMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$LibraryConflictRecordsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({localId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (localId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.localId,
                                referencedTable:
                                    $$LibraryConflictRecordsTableReferences
                                        ._localIdTable(db),
                                referencedColumn:
                                    $$LibraryConflictRecordsTableReferences
                                        ._localIdTable(db)
                                        .localId,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$LibraryConflictRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$CanonicalLibraryDatabase,
      $LibraryConflictRecordsTable,
      LibraryConflictRecord,
      $$LibraryConflictRecordsTableFilterComposer,
      $$LibraryConflictRecordsTableOrderingComposer,
      $$LibraryConflictRecordsTableAnnotationComposer,
      $$LibraryConflictRecordsTableCreateCompanionBuilder,
      $$LibraryConflictRecordsTableUpdateCompanionBuilder,
      (LibraryConflictRecord, $$LibraryConflictRecordsTableReferences),
      LibraryConflictRecord,
      PrefetchHooks Function({bool localId})
    >;
typedef $$SyncCursorRecordsTableCreateCompanionBuilder =
    SyncCursorRecordsCompanion Function({
      required String scope,
      required String cursor,
      Value<String> metadataJson,
      required int updatedAtMs,
      Value<int> rowid,
    });
typedef $$SyncCursorRecordsTableUpdateCompanionBuilder =
    SyncCursorRecordsCompanion Function({
      Value<String> scope,
      Value<String> cursor,
      Value<String> metadataJson,
      Value<int> updatedAtMs,
      Value<int> rowid,
    });

class $$SyncCursorRecordsTableFilterComposer
    extends Composer<_$CanonicalLibraryDatabase, $SyncCursorRecordsTable> {
  $$SyncCursorRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cursor => $composableBuilder(
    column: $table.cursor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncCursorRecordsTableOrderingComposer
    extends Composer<_$CanonicalLibraryDatabase, $SyncCursorRecordsTable> {
  $$SyncCursorRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cursor => $composableBuilder(
    column: $table.cursor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncCursorRecordsTableAnnotationComposer
    extends Composer<_$CanonicalLibraryDatabase, $SyncCursorRecordsTable> {
  $$SyncCursorRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get scope =>
      $composableBuilder(column: $table.scope, builder: (column) => column);

  GeneratedColumn<String> get cursor =>
      $composableBuilder(column: $table.cursor, builder: (column) => column);

  GeneratedColumn<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => column,
  );
}

class $$SyncCursorRecordsTableTableManager
    extends
        RootTableManager<
          _$CanonicalLibraryDatabase,
          $SyncCursorRecordsTable,
          SyncCursorRecord,
          $$SyncCursorRecordsTableFilterComposer,
          $$SyncCursorRecordsTableOrderingComposer,
          $$SyncCursorRecordsTableAnnotationComposer,
          $$SyncCursorRecordsTableCreateCompanionBuilder,
          $$SyncCursorRecordsTableUpdateCompanionBuilder,
          (
            SyncCursorRecord,
            BaseReferences<
              _$CanonicalLibraryDatabase,
              $SyncCursorRecordsTable,
              SyncCursorRecord
            >,
          ),
          SyncCursorRecord,
          PrefetchHooks Function()
        > {
  $$SyncCursorRecordsTableTableManager(
    _$CanonicalLibraryDatabase db,
    $SyncCursorRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncCursorRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncCursorRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncCursorRecordsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> scope = const Value.absent(),
                Value<String> cursor = const Value.absent(),
                Value<String> metadataJson = const Value.absent(),
                Value<int> updatedAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncCursorRecordsCompanion(
                scope: scope,
                cursor: cursor,
                metadataJson: metadataJson,
                updatedAtMs: updatedAtMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String scope,
                required String cursor,
                Value<String> metadataJson = const Value.absent(),
                required int updatedAtMs,
                Value<int> rowid = const Value.absent(),
              }) => SyncCursorRecordsCompanion.insert(
                scope: scope,
                cursor: cursor,
                metadataJson: metadataJson,
                updatedAtMs: updatedAtMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncCursorRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$CanonicalLibraryDatabase,
      $SyncCursorRecordsTable,
      SyncCursorRecord,
      $$SyncCursorRecordsTableFilterComposer,
      $$SyncCursorRecordsTableOrderingComposer,
      $$SyncCursorRecordsTableAnnotationComposer,
      $$SyncCursorRecordsTableCreateCompanionBuilder,
      $$SyncCursorRecordsTableUpdateCompanionBuilder,
      (
        SyncCursorRecord,
        BaseReferences<
          _$CanonicalLibraryDatabase,
          $SyncCursorRecordsTable,
          SyncCursorRecord
        >,
      ),
      SyncCursorRecord,
      PrefetchHooks Function()
    >;
typedef $$ProviderHealthRecordsTableCreateCompanionBuilder =
    ProviderHealthRecordsCompanion Function({
      required String provider,
      required String healthJson,
      required int updatedAtMs,
      Value<int> rowid,
    });
typedef $$ProviderHealthRecordsTableUpdateCompanionBuilder =
    ProviderHealthRecordsCompanion Function({
      Value<String> provider,
      Value<String> healthJson,
      Value<int> updatedAtMs,
      Value<int> rowid,
    });

class $$ProviderHealthRecordsTableFilterComposer
    extends Composer<_$CanonicalLibraryDatabase, $ProviderHealthRecordsTable> {
  $$ProviderHealthRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get provider => $composableBuilder(
    column: $table.provider,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get healthJson => $composableBuilder(
    column: $table.healthJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ProviderHealthRecordsTableOrderingComposer
    extends Composer<_$CanonicalLibraryDatabase, $ProviderHealthRecordsTable> {
  $$ProviderHealthRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get provider => $composableBuilder(
    column: $table.provider,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get healthJson => $composableBuilder(
    column: $table.healthJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProviderHealthRecordsTableAnnotationComposer
    extends Composer<_$CanonicalLibraryDatabase, $ProviderHealthRecordsTable> {
  $$ProviderHealthRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get provider =>
      $composableBuilder(column: $table.provider, builder: (column) => column);

  GeneratedColumn<String> get healthJson => $composableBuilder(
    column: $table.healthJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => column,
  );
}

class $$ProviderHealthRecordsTableTableManager
    extends
        RootTableManager<
          _$CanonicalLibraryDatabase,
          $ProviderHealthRecordsTable,
          ProviderHealthRecord,
          $$ProviderHealthRecordsTableFilterComposer,
          $$ProviderHealthRecordsTableOrderingComposer,
          $$ProviderHealthRecordsTableAnnotationComposer,
          $$ProviderHealthRecordsTableCreateCompanionBuilder,
          $$ProviderHealthRecordsTableUpdateCompanionBuilder,
          (
            ProviderHealthRecord,
            BaseReferences<
              _$CanonicalLibraryDatabase,
              $ProviderHealthRecordsTable,
              ProviderHealthRecord
            >,
          ),
          ProviderHealthRecord,
          PrefetchHooks Function()
        > {
  $$ProviderHealthRecordsTableTableManager(
    _$CanonicalLibraryDatabase db,
    $ProviderHealthRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProviderHealthRecordsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$ProviderHealthRecordsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ProviderHealthRecordsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> provider = const Value.absent(),
                Value<String> healthJson = const Value.absent(),
                Value<int> updatedAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProviderHealthRecordsCompanion(
                provider: provider,
                healthJson: healthJson,
                updatedAtMs: updatedAtMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String provider,
                required String healthJson,
                required int updatedAtMs,
                Value<int> rowid = const Value.absent(),
              }) => ProviderHealthRecordsCompanion.insert(
                provider: provider,
                healthJson: healthJson,
                updatedAtMs: updatedAtMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProviderHealthRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$CanonicalLibraryDatabase,
      $ProviderHealthRecordsTable,
      ProviderHealthRecord,
      $$ProviderHealthRecordsTableFilterComposer,
      $$ProviderHealthRecordsTableOrderingComposer,
      $$ProviderHealthRecordsTableAnnotationComposer,
      $$ProviderHealthRecordsTableCreateCompanionBuilder,
      $$ProviderHealthRecordsTableUpdateCompanionBuilder,
      (
        ProviderHealthRecord,
        BaseReferences<
          _$CanonicalLibraryDatabase,
          $ProviderHealthRecordsTable,
          ProviderHealthRecord
        >,
      ),
      ProviderHealthRecord,
      PrefetchHooks Function()
    >;
typedef $$LegacyBucketRecordsTableCreateCompanionBuilder =
    LegacyBucketRecordsCompanion Function({
      required String bucket,
      required String valueJson,
      required int updatedAtMs,
      Value<int> rowid,
    });
typedef $$LegacyBucketRecordsTableUpdateCompanionBuilder =
    LegacyBucketRecordsCompanion Function({
      Value<String> bucket,
      Value<String> valueJson,
      Value<int> updatedAtMs,
      Value<int> rowid,
    });

class $$LegacyBucketRecordsTableFilterComposer
    extends Composer<_$CanonicalLibraryDatabase, $LegacyBucketRecordsTable> {
  $$LegacyBucketRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get bucket => $composableBuilder(
    column: $table.bucket,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get valueJson => $composableBuilder(
    column: $table.valueJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LegacyBucketRecordsTableOrderingComposer
    extends Composer<_$CanonicalLibraryDatabase, $LegacyBucketRecordsTable> {
  $$LegacyBucketRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get bucket => $composableBuilder(
    column: $table.bucket,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get valueJson => $composableBuilder(
    column: $table.valueJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LegacyBucketRecordsTableAnnotationComposer
    extends Composer<_$CanonicalLibraryDatabase, $LegacyBucketRecordsTable> {
  $$LegacyBucketRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get bucket =>
      $composableBuilder(column: $table.bucket, builder: (column) => column);

  GeneratedColumn<String> get valueJson =>
      $composableBuilder(column: $table.valueJson, builder: (column) => column);

  GeneratedColumn<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => column,
  );
}

class $$LegacyBucketRecordsTableTableManager
    extends
        RootTableManager<
          _$CanonicalLibraryDatabase,
          $LegacyBucketRecordsTable,
          LegacyBucketRecord,
          $$LegacyBucketRecordsTableFilterComposer,
          $$LegacyBucketRecordsTableOrderingComposer,
          $$LegacyBucketRecordsTableAnnotationComposer,
          $$LegacyBucketRecordsTableCreateCompanionBuilder,
          $$LegacyBucketRecordsTableUpdateCompanionBuilder,
          (
            LegacyBucketRecord,
            BaseReferences<
              _$CanonicalLibraryDatabase,
              $LegacyBucketRecordsTable,
              LegacyBucketRecord
            >,
          ),
          LegacyBucketRecord,
          PrefetchHooks Function()
        > {
  $$LegacyBucketRecordsTableTableManager(
    _$CanonicalLibraryDatabase db,
    $LegacyBucketRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LegacyBucketRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LegacyBucketRecordsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$LegacyBucketRecordsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> bucket = const Value.absent(),
                Value<String> valueJson = const Value.absent(),
                Value<int> updatedAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LegacyBucketRecordsCompanion(
                bucket: bucket,
                valueJson: valueJson,
                updatedAtMs: updatedAtMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String bucket,
                required String valueJson,
                required int updatedAtMs,
                Value<int> rowid = const Value.absent(),
              }) => LegacyBucketRecordsCompanion.insert(
                bucket: bucket,
                valueJson: valueJson,
                updatedAtMs: updatedAtMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LegacyBucketRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$CanonicalLibraryDatabase,
      $LegacyBucketRecordsTable,
      LegacyBucketRecord,
      $$LegacyBucketRecordsTableFilterComposer,
      $$LegacyBucketRecordsTableOrderingComposer,
      $$LegacyBucketRecordsTableAnnotationComposer,
      $$LegacyBucketRecordsTableCreateCompanionBuilder,
      $$LegacyBucketRecordsTableUpdateCompanionBuilder,
      (
        LegacyBucketRecord,
        BaseReferences<
          _$CanonicalLibraryDatabase,
          $LegacyBucketRecordsTable,
          LegacyBucketRecord
        >,
      ),
      LegacyBucketRecord,
      PrefetchHooks Function()
    >;

class $CanonicalLibraryDatabaseManager {
  final _$CanonicalLibraryDatabase _db;
  $CanonicalLibraryDatabaseManager(this._db);
  $$CanonicalMediaRecordsTableTableManager get canonicalMediaRecords =>
      $$CanonicalMediaRecordsTableTableManager(_db, _db.canonicalMediaRecords);
  $$MediaAliasRecordsTableTableManager get mediaAliasRecords =>
      $$MediaAliasRecordsTableTableManager(_db, _db.mediaAliasRecords);
  $$ProviderBindingRecordsTableTableManager get providerBindingRecords =>
      $$ProviderBindingRecordsTableTableManager(
        _db,
        _db.providerBindingRecords,
      );
  $$CanonicalLibraryRecordsTableTableManager get canonicalLibraryRecords =>
      $$CanonicalLibraryRecordsTableTableManager(
        _db,
        _db.canonicalLibraryRecords,
      );
  $$ProviderSnapshotRecordsTableTableManager get providerSnapshotRecords =>
      $$ProviderSnapshotRecordsTableTableManager(
        _db,
        _db.providerSnapshotRecords,
      );
  $$EpisodeStateRecordsTableTableManager get episodeStateRecords =>
      $$EpisodeStateRecordsTableTableManager(_db, _db.episodeStateRecords);
  $$StreamPreferenceRecordsTableTableManager get streamPreferenceRecords =>
      $$StreamPreferenceRecordsTableTableManager(
        _db,
        _db.streamPreferenceRecords,
      );
  $$LibraryOperationRecordsTableTableManager get libraryOperationRecords =>
      $$LibraryOperationRecordsTableTableManager(
        _db,
        _db.libraryOperationRecords,
      );
  $$OutboxDeliveryRecordsTableTableManager get outboxDeliveryRecords =>
      $$OutboxDeliveryRecordsTableTableManager(_db, _db.outboxDeliveryRecords);
  $$LibraryConflictRecordsTableTableManager get libraryConflictRecords =>
      $$LibraryConflictRecordsTableTableManager(
        _db,
        _db.libraryConflictRecords,
      );
  $$SyncCursorRecordsTableTableManager get syncCursorRecords =>
      $$SyncCursorRecordsTableTableManager(_db, _db.syncCursorRecords);
  $$ProviderHealthRecordsTableTableManager get providerHealthRecords =>
      $$ProviderHealthRecordsTableTableManager(_db, _db.providerHealthRecords);
  $$LegacyBucketRecordsTableTableManager get legacyBucketRecords =>
      $$LegacyBucketRecordsTableTableManager(_db, _db.legacyBucketRecords);
}
