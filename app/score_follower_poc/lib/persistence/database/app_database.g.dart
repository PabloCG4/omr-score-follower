// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $InstrumentsTable extends Instruments
    with TableInfo<$InstrumentsTable, InstrumentRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $InstrumentsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 128,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _baseFrequencyHzMeta = const VerificationMeta(
    'baseFrequencyHz',
  );
  @override
  late final GeneratedColumn<double> baseFrequencyHz = GeneratedColumn<double>(
    'base_frequency_hz',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(440.0),
  );
  static const VerificationMeta _transpositionSemitonesMeta =
      const VerificationMeta('transpositionSemitones');
  @override
  late final GeneratedColumn<int> transpositionSemitones = GeneratedColumn<int>(
    'transposition_semitones',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtUtcMeta = const VerificationMeta(
    'createdAtUtc',
  );
  @override
  late final GeneratedColumn<DateTime> createdAtUtc = GeneratedColumn<DateTime>(
    'created_at_utc',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtUtcMeta = const VerificationMeta(
    'updatedAtUtc',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAtUtc = GeneratedColumn<DateTime>(
    'updated_at_utc',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    baseFrequencyHz,
    transpositionSemitones,
    createdAtUtc,
    updatedAtUtc,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'instruments';
  @override
  VerificationContext validateIntegrity(
    Insertable<InstrumentRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('base_frequency_hz')) {
      context.handle(
        _baseFrequencyHzMeta,
        baseFrequencyHz.isAcceptableOrUnknown(
          data['base_frequency_hz']!,
          _baseFrequencyHzMeta,
        ),
      );
    }
    if (data.containsKey('transposition_semitones')) {
      context.handle(
        _transpositionSemitonesMeta,
        transpositionSemitones.isAcceptableOrUnknown(
          data['transposition_semitones']!,
          _transpositionSemitonesMeta,
        ),
      );
    }
    if (data.containsKey('created_at_utc')) {
      context.handle(
        _createdAtUtcMeta,
        createdAtUtc.isAcceptableOrUnknown(
          data['created_at_utc']!,
          _createdAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtUtcMeta);
    }
    if (data.containsKey('updated_at_utc')) {
      context.handle(
        _updatedAtUtcMeta,
        updatedAtUtc.isAcceptableOrUnknown(
          data['updated_at_utc']!,
          _updatedAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtUtcMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  InstrumentRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return InstrumentRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      baseFrequencyHz: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}base_frequency_hz'],
      )!,
      transpositionSemitones: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}transposition_semitones'],
      )!,
      createdAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at_utc'],
      )!,
      updatedAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at_utc'],
      )!,
    );
  }

  @override
  $InstrumentsTable createAlias(String alias) {
    return $InstrumentsTable(attachedDatabase, alias);
  }
}

class InstrumentRow extends DataClass implements Insertable<InstrumentRow> {
  final int id;
  final String name;
  final double baseFrequencyHz;
  final int transpositionSemitones;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;
  const InstrumentRow({
    required this.id,
    required this.name,
    required this.baseFrequencyHz,
    required this.transpositionSemitones,
    required this.createdAtUtc,
    required this.updatedAtUtc,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['base_frequency_hz'] = Variable<double>(baseFrequencyHz);
    map['transposition_semitones'] = Variable<int>(transpositionSemitones);
    map['created_at_utc'] = Variable<DateTime>(createdAtUtc);
    map['updated_at_utc'] = Variable<DateTime>(updatedAtUtc);
    return map;
  }

  InstrumentsCompanion toCompanion(bool nullToAbsent) {
    return InstrumentsCompanion(
      id: Value(id),
      name: Value(name),
      baseFrequencyHz: Value(baseFrequencyHz),
      transpositionSemitones: Value(transpositionSemitones),
      createdAtUtc: Value(createdAtUtc),
      updatedAtUtc: Value(updatedAtUtc),
    );
  }

  factory InstrumentRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return InstrumentRow(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      baseFrequencyHz: serializer.fromJson<double>(json['baseFrequencyHz']),
      transpositionSemitones: serializer.fromJson<int>(
        json['transpositionSemitones'],
      ),
      createdAtUtc: serializer.fromJson<DateTime>(json['createdAtUtc']),
      updatedAtUtc: serializer.fromJson<DateTime>(json['updatedAtUtc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'baseFrequencyHz': serializer.toJson<double>(baseFrequencyHz),
      'transpositionSemitones': serializer.toJson<int>(transpositionSemitones),
      'createdAtUtc': serializer.toJson<DateTime>(createdAtUtc),
      'updatedAtUtc': serializer.toJson<DateTime>(updatedAtUtc),
    };
  }

  InstrumentRow copyWith({
    int? id,
    String? name,
    double? baseFrequencyHz,
    int? transpositionSemitones,
    DateTime? createdAtUtc,
    DateTime? updatedAtUtc,
  }) => InstrumentRow(
    id: id ?? this.id,
    name: name ?? this.name,
    baseFrequencyHz: baseFrequencyHz ?? this.baseFrequencyHz,
    transpositionSemitones:
        transpositionSemitones ?? this.transpositionSemitones,
    createdAtUtc: createdAtUtc ?? this.createdAtUtc,
    updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
  );
  InstrumentRow copyWithCompanion(InstrumentsCompanion data) {
    return InstrumentRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      baseFrequencyHz: data.baseFrequencyHz.present
          ? data.baseFrequencyHz.value
          : this.baseFrequencyHz,
      transpositionSemitones: data.transpositionSemitones.present
          ? data.transpositionSemitones.value
          : this.transpositionSemitones,
      createdAtUtc: data.createdAtUtc.present
          ? data.createdAtUtc.value
          : this.createdAtUtc,
      updatedAtUtc: data.updatedAtUtc.present
          ? data.updatedAtUtc.value
          : this.updatedAtUtc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('InstrumentRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('baseFrequencyHz: $baseFrequencyHz, ')
          ..write('transpositionSemitones: $transpositionSemitones, ')
          ..write('createdAtUtc: $createdAtUtc, ')
          ..write('updatedAtUtc: $updatedAtUtc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    baseFrequencyHz,
    transpositionSemitones,
    createdAtUtc,
    updatedAtUtc,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is InstrumentRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.baseFrequencyHz == this.baseFrequencyHz &&
          other.transpositionSemitones == this.transpositionSemitones &&
          other.createdAtUtc == this.createdAtUtc &&
          other.updatedAtUtc == this.updatedAtUtc);
}

class InstrumentsCompanion extends UpdateCompanion<InstrumentRow> {
  final Value<int> id;
  final Value<String> name;
  final Value<double> baseFrequencyHz;
  final Value<int> transpositionSemitones;
  final Value<DateTime> createdAtUtc;
  final Value<DateTime> updatedAtUtc;
  const InstrumentsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.baseFrequencyHz = const Value.absent(),
    this.transpositionSemitones = const Value.absent(),
    this.createdAtUtc = const Value.absent(),
    this.updatedAtUtc = const Value.absent(),
  });
  InstrumentsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.baseFrequencyHz = const Value.absent(),
    this.transpositionSemitones = const Value.absent(),
    required DateTime createdAtUtc,
    required DateTime updatedAtUtc,
  }) : name = Value(name),
       createdAtUtc = Value(createdAtUtc),
       updatedAtUtc = Value(updatedAtUtc);
  static Insertable<InstrumentRow> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<double>? baseFrequencyHz,
    Expression<int>? transpositionSemitones,
    Expression<DateTime>? createdAtUtc,
    Expression<DateTime>? updatedAtUtc,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (baseFrequencyHz != null) 'base_frequency_hz': baseFrequencyHz,
      if (transpositionSemitones != null)
        'transposition_semitones': transpositionSemitones,
      if (createdAtUtc != null) 'created_at_utc': createdAtUtc,
      if (updatedAtUtc != null) 'updated_at_utc': updatedAtUtc,
    });
  }

  InstrumentsCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<double>? baseFrequencyHz,
    Value<int>? transpositionSemitones,
    Value<DateTime>? createdAtUtc,
    Value<DateTime>? updatedAtUtc,
  }) {
    return InstrumentsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      baseFrequencyHz: baseFrequencyHz ?? this.baseFrequencyHz,
      transpositionSemitones:
          transpositionSemitones ?? this.transpositionSemitones,
      createdAtUtc: createdAtUtc ?? this.createdAtUtc,
      updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (baseFrequencyHz.present) {
      map['base_frequency_hz'] = Variable<double>(baseFrequencyHz.value);
    }
    if (transpositionSemitones.present) {
      map['transposition_semitones'] = Variable<int>(
        transpositionSemitones.value,
      );
    }
    if (createdAtUtc.present) {
      map['created_at_utc'] = Variable<DateTime>(createdAtUtc.value);
    }
    if (updatedAtUtc.present) {
      map['updated_at_utc'] = Variable<DateTime>(updatedAtUtc.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('InstrumentsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('baseFrequencyHz: $baseFrequencyHz, ')
          ..write('transpositionSemitones: $transpositionSemitones, ')
          ..write('createdAtUtc: $createdAtUtc, ')
          ..write('updatedAtUtc: $updatedAtUtc')
          ..write(')'))
        .toString();
  }
}

class $UserPreferencesRowsTable extends UserPreferencesRows
    with TableInfo<$UserPreferencesRowsTable, UserPreferencesRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UserPreferencesRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _trackingModeMeta = const VerificationMeta(
    'trackingMode',
  );
  @override
  late final GeneratedColumn<String> trackingMode = GeneratedColumn<String>(
    'tracking_mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _activeInstrumentIdMeta =
      const VerificationMeta('activeInstrumentId');
  @override
  late final GeneratedColumn<int> activeInstrumentId = GeneratedColumn<int>(
    'active_instrument_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _strictConfidenceThresholdMeta =
      const VerificationMeta('strictConfidenceThreshold');
  @override
  late final GeneratedColumn<double> strictConfidenceThreshold =
      GeneratedColumn<double>(
        'strict_confidence_threshold',
        aliasedName,
        false,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
        defaultValue: const Constant(0.55),
      );
  static const VerificationMeta _scoreIdMeta = const VerificationMeta(
    'scoreId',
  );
  @override
  late final GeneratedColumn<String> scoreId = GeneratedColumn<String>(
    'score_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('demo_four_chords'),
  );
  static const VerificationMeta _updatedAtUtcMeta = const VerificationMeta(
    'updatedAtUtc',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAtUtc = GeneratedColumn<DateTime>(
    'updated_at_utc',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    trackingMode,
    activeInstrumentId,
    strictConfidenceThreshold,
    scoreId,
    updatedAtUtc,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'user_preferences_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<UserPreferencesRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('tracking_mode')) {
      context.handle(
        _trackingModeMeta,
        trackingMode.isAcceptableOrUnknown(
          data['tracking_mode']!,
          _trackingModeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_trackingModeMeta);
    }
    if (data.containsKey('active_instrument_id')) {
      context.handle(
        _activeInstrumentIdMeta,
        activeInstrumentId.isAcceptableOrUnknown(
          data['active_instrument_id']!,
          _activeInstrumentIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_activeInstrumentIdMeta);
    }
    if (data.containsKey('strict_confidence_threshold')) {
      context.handle(
        _strictConfidenceThresholdMeta,
        strictConfidenceThreshold.isAcceptableOrUnknown(
          data['strict_confidence_threshold']!,
          _strictConfidenceThresholdMeta,
        ),
      );
    }
    if (data.containsKey('score_id')) {
      context.handle(
        _scoreIdMeta,
        scoreId.isAcceptableOrUnknown(data['score_id']!, _scoreIdMeta),
      );
    }
    if (data.containsKey('updated_at_utc')) {
      context.handle(
        _updatedAtUtcMeta,
        updatedAtUtc.isAcceptableOrUnknown(
          data['updated_at_utc']!,
          _updatedAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtUtcMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  UserPreferencesRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UserPreferencesRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      trackingMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tracking_mode'],
      )!,
      activeInstrumentId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}active_instrument_id'],
      )!,
      strictConfidenceThreshold: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}strict_confidence_threshold'],
      )!,
      scoreId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}score_id'],
      )!,
      updatedAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at_utc'],
      )!,
    );
  }

  @override
  $UserPreferencesRowsTable createAlias(String alias) {
    return $UserPreferencesRowsTable(attachedDatabase, alias);
  }
}

class UserPreferencesRow extends DataClass
    implements Insertable<UserPreferencesRow> {
  final int id;
  final String trackingMode;
  final int activeInstrumentId;
  final double strictConfidenceThreshold;
  final String scoreId;
  final DateTime updatedAtUtc;
  const UserPreferencesRow({
    required this.id,
    required this.trackingMode,
    required this.activeInstrumentId,
    required this.strictConfidenceThreshold,
    required this.scoreId,
    required this.updatedAtUtc,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['tracking_mode'] = Variable<String>(trackingMode);
    map['active_instrument_id'] = Variable<int>(activeInstrumentId);
    map['strict_confidence_threshold'] = Variable<double>(
      strictConfidenceThreshold,
    );
    map['score_id'] = Variable<String>(scoreId);
    map['updated_at_utc'] = Variable<DateTime>(updatedAtUtc);
    return map;
  }

  UserPreferencesRowsCompanion toCompanion(bool nullToAbsent) {
    return UserPreferencesRowsCompanion(
      id: Value(id),
      trackingMode: Value(trackingMode),
      activeInstrumentId: Value(activeInstrumentId),
      strictConfidenceThreshold: Value(strictConfidenceThreshold),
      scoreId: Value(scoreId),
      updatedAtUtc: Value(updatedAtUtc),
    );
  }

  factory UserPreferencesRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UserPreferencesRow(
      id: serializer.fromJson<int>(json['id']),
      trackingMode: serializer.fromJson<String>(json['trackingMode']),
      activeInstrumentId: serializer.fromJson<int>(json['activeInstrumentId']),
      strictConfidenceThreshold: serializer.fromJson<double>(
        json['strictConfidenceThreshold'],
      ),
      scoreId: serializer.fromJson<String>(json['scoreId']),
      updatedAtUtc: serializer.fromJson<DateTime>(json['updatedAtUtc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'trackingMode': serializer.toJson<String>(trackingMode),
      'activeInstrumentId': serializer.toJson<int>(activeInstrumentId),
      'strictConfidenceThreshold': serializer.toJson<double>(
        strictConfidenceThreshold,
      ),
      'scoreId': serializer.toJson<String>(scoreId),
      'updatedAtUtc': serializer.toJson<DateTime>(updatedAtUtc),
    };
  }

  UserPreferencesRow copyWith({
    int? id,
    String? trackingMode,
    int? activeInstrumentId,
    double? strictConfidenceThreshold,
    String? scoreId,
    DateTime? updatedAtUtc,
  }) => UserPreferencesRow(
    id: id ?? this.id,
    trackingMode: trackingMode ?? this.trackingMode,
    activeInstrumentId: activeInstrumentId ?? this.activeInstrumentId,
    strictConfidenceThreshold:
        strictConfidenceThreshold ?? this.strictConfidenceThreshold,
    scoreId: scoreId ?? this.scoreId,
    updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
  );
  UserPreferencesRow copyWithCompanion(UserPreferencesRowsCompanion data) {
    return UserPreferencesRow(
      id: data.id.present ? data.id.value : this.id,
      trackingMode: data.trackingMode.present
          ? data.trackingMode.value
          : this.trackingMode,
      activeInstrumentId: data.activeInstrumentId.present
          ? data.activeInstrumentId.value
          : this.activeInstrumentId,
      strictConfidenceThreshold: data.strictConfidenceThreshold.present
          ? data.strictConfidenceThreshold.value
          : this.strictConfidenceThreshold,
      scoreId: data.scoreId.present ? data.scoreId.value : this.scoreId,
      updatedAtUtc: data.updatedAtUtc.present
          ? data.updatedAtUtc.value
          : this.updatedAtUtc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UserPreferencesRow(')
          ..write('id: $id, ')
          ..write('trackingMode: $trackingMode, ')
          ..write('activeInstrumentId: $activeInstrumentId, ')
          ..write('strictConfidenceThreshold: $strictConfidenceThreshold, ')
          ..write('scoreId: $scoreId, ')
          ..write('updatedAtUtc: $updatedAtUtc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    trackingMode,
    activeInstrumentId,
    strictConfidenceThreshold,
    scoreId,
    updatedAtUtc,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UserPreferencesRow &&
          other.id == this.id &&
          other.trackingMode == this.trackingMode &&
          other.activeInstrumentId == this.activeInstrumentId &&
          other.strictConfidenceThreshold == this.strictConfidenceThreshold &&
          other.scoreId == this.scoreId &&
          other.updatedAtUtc == this.updatedAtUtc);
}

class UserPreferencesRowsCompanion extends UpdateCompanion<UserPreferencesRow> {
  final Value<int> id;
  final Value<String> trackingMode;
  final Value<int> activeInstrumentId;
  final Value<double> strictConfidenceThreshold;
  final Value<String> scoreId;
  final Value<DateTime> updatedAtUtc;
  const UserPreferencesRowsCompanion({
    this.id = const Value.absent(),
    this.trackingMode = const Value.absent(),
    this.activeInstrumentId = const Value.absent(),
    this.strictConfidenceThreshold = const Value.absent(),
    this.scoreId = const Value.absent(),
    this.updatedAtUtc = const Value.absent(),
  });
  UserPreferencesRowsCompanion.insert({
    this.id = const Value.absent(),
    required String trackingMode,
    required int activeInstrumentId,
    this.strictConfidenceThreshold = const Value.absent(),
    this.scoreId = const Value.absent(),
    required DateTime updatedAtUtc,
  }) : trackingMode = Value(trackingMode),
       activeInstrumentId = Value(activeInstrumentId),
       updatedAtUtc = Value(updatedAtUtc);
  static Insertable<UserPreferencesRow> custom({
    Expression<int>? id,
    Expression<String>? trackingMode,
    Expression<int>? activeInstrumentId,
    Expression<double>? strictConfidenceThreshold,
    Expression<String>? scoreId,
    Expression<DateTime>? updatedAtUtc,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (trackingMode != null) 'tracking_mode': trackingMode,
      if (activeInstrumentId != null)
        'active_instrument_id': activeInstrumentId,
      if (strictConfidenceThreshold != null)
        'strict_confidence_threshold': strictConfidenceThreshold,
      if (scoreId != null) 'score_id': scoreId,
      if (updatedAtUtc != null) 'updated_at_utc': updatedAtUtc,
    });
  }

  UserPreferencesRowsCompanion copyWith({
    Value<int>? id,
    Value<String>? trackingMode,
    Value<int>? activeInstrumentId,
    Value<double>? strictConfidenceThreshold,
    Value<String>? scoreId,
    Value<DateTime>? updatedAtUtc,
  }) {
    return UserPreferencesRowsCompanion(
      id: id ?? this.id,
      trackingMode: trackingMode ?? this.trackingMode,
      activeInstrumentId: activeInstrumentId ?? this.activeInstrumentId,
      strictConfidenceThreshold:
          strictConfidenceThreshold ?? this.strictConfidenceThreshold,
      scoreId: scoreId ?? this.scoreId,
      updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (trackingMode.present) {
      map['tracking_mode'] = Variable<String>(trackingMode.value);
    }
    if (activeInstrumentId.present) {
      map['active_instrument_id'] = Variable<int>(activeInstrumentId.value);
    }
    if (strictConfidenceThreshold.present) {
      map['strict_confidence_threshold'] = Variable<double>(
        strictConfidenceThreshold.value,
      );
    }
    if (scoreId.present) {
      map['score_id'] = Variable<String>(scoreId.value);
    }
    if (updatedAtUtc.present) {
      map['updated_at_utc'] = Variable<DateTime>(updatedAtUtc.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UserPreferencesRowsCompanion(')
          ..write('id: $id, ')
          ..write('trackingMode: $trackingMode, ')
          ..write('activeInstrumentId: $activeInstrumentId, ')
          ..write('strictConfidenceThreshold: $strictConfidenceThreshold, ')
          ..write('scoreId: $scoreId, ')
          ..write('updatedAtUtc: $updatedAtUtc')
          ..write(')'))
        .toString();
  }
}

class $ScoreDocumentsTable extends ScoreDocuments
    with TableInfo<$ScoreDocumentsTable, ScoreDocumentRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ScoreDocumentsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 256,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _originalPdfLocalPathMeta =
      const VerificationMeta('originalPdfLocalPath');
  @override
  late final GeneratedColumn<String> originalPdfLocalPath =
      GeneratedColumn<String>(
        'original_pdf_local_path',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _structuralDataLocalPathMeta =
      const VerificationMeta('structuralDataLocalPath');
  @override
  late final GeneratedColumn<String> structuralDataLocalPath =
      GeneratedColumn<String>(
        'structural_data_local_path',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _createdAtUtcMeta = const VerificationMeta(
    'createdAtUtc',
  );
  @override
  late final GeneratedColumn<DateTime> createdAtUtc = GeneratedColumn<DateTime>(
    'created_at_utc',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtUtcMeta = const VerificationMeta(
    'updatedAtUtc',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAtUtc = GeneratedColumn<DateTime>(
    'updated_at_utc',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    originalPdfLocalPath,
    structuralDataLocalPath,
    createdAtUtc,
    updatedAtUtc,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'score_documents';
  @override
  VerificationContext validateIntegrity(
    Insertable<ScoreDocumentRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('original_pdf_local_path')) {
      context.handle(
        _originalPdfLocalPathMeta,
        originalPdfLocalPath.isAcceptableOrUnknown(
          data['original_pdf_local_path']!,
          _originalPdfLocalPathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_originalPdfLocalPathMeta);
    }
    if (data.containsKey('structural_data_local_path')) {
      context.handle(
        _structuralDataLocalPathMeta,
        structuralDataLocalPath.isAcceptableOrUnknown(
          data['structural_data_local_path']!,
          _structuralDataLocalPathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_structuralDataLocalPathMeta);
    }
    if (data.containsKey('created_at_utc')) {
      context.handle(
        _createdAtUtcMeta,
        createdAtUtc.isAcceptableOrUnknown(
          data['created_at_utc']!,
          _createdAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtUtcMeta);
    }
    if (data.containsKey('updated_at_utc')) {
      context.handle(
        _updatedAtUtcMeta,
        updatedAtUtc.isAcceptableOrUnknown(
          data['updated_at_utc']!,
          _updatedAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtUtcMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ScoreDocumentRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ScoreDocumentRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      originalPdfLocalPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}original_pdf_local_path'],
      )!,
      structuralDataLocalPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}structural_data_local_path'],
      )!,
      createdAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at_utc'],
      )!,
      updatedAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at_utc'],
      )!,
    );
  }

  @override
  $ScoreDocumentsTable createAlias(String alias) {
    return $ScoreDocumentsTable(attachedDatabase, alias);
  }
}

class ScoreDocumentRow extends DataClass
    implements Insertable<ScoreDocumentRow> {
  final int id;
  final String title;

  /// Relative to the application documents directory (never absolute).
  final String originalPdfLocalPath;
  final String structuralDataLocalPath;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;
  const ScoreDocumentRow({
    required this.id,
    required this.title,
    required this.originalPdfLocalPath,
    required this.structuralDataLocalPath,
    required this.createdAtUtc,
    required this.updatedAtUtc,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['title'] = Variable<String>(title);
    map['original_pdf_local_path'] = Variable<String>(originalPdfLocalPath);
    map['structural_data_local_path'] = Variable<String>(
      structuralDataLocalPath,
    );
    map['created_at_utc'] = Variable<DateTime>(createdAtUtc);
    map['updated_at_utc'] = Variable<DateTime>(updatedAtUtc);
    return map;
  }

  ScoreDocumentsCompanion toCompanion(bool nullToAbsent) {
    return ScoreDocumentsCompanion(
      id: Value(id),
      title: Value(title),
      originalPdfLocalPath: Value(originalPdfLocalPath),
      structuralDataLocalPath: Value(structuralDataLocalPath),
      createdAtUtc: Value(createdAtUtc),
      updatedAtUtc: Value(updatedAtUtc),
    );
  }

  factory ScoreDocumentRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ScoreDocumentRow(
      id: serializer.fromJson<int>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      originalPdfLocalPath: serializer.fromJson<String>(
        json['originalPdfLocalPath'],
      ),
      structuralDataLocalPath: serializer.fromJson<String>(
        json['structuralDataLocalPath'],
      ),
      createdAtUtc: serializer.fromJson<DateTime>(json['createdAtUtc']),
      updatedAtUtc: serializer.fromJson<DateTime>(json['updatedAtUtc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'title': serializer.toJson<String>(title),
      'originalPdfLocalPath': serializer.toJson<String>(originalPdfLocalPath),
      'structuralDataLocalPath': serializer.toJson<String>(
        structuralDataLocalPath,
      ),
      'createdAtUtc': serializer.toJson<DateTime>(createdAtUtc),
      'updatedAtUtc': serializer.toJson<DateTime>(updatedAtUtc),
    };
  }

  ScoreDocumentRow copyWith({
    int? id,
    String? title,
    String? originalPdfLocalPath,
    String? structuralDataLocalPath,
    DateTime? createdAtUtc,
    DateTime? updatedAtUtc,
  }) => ScoreDocumentRow(
    id: id ?? this.id,
    title: title ?? this.title,
    originalPdfLocalPath: originalPdfLocalPath ?? this.originalPdfLocalPath,
    structuralDataLocalPath:
        structuralDataLocalPath ?? this.structuralDataLocalPath,
    createdAtUtc: createdAtUtc ?? this.createdAtUtc,
    updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
  );
  ScoreDocumentRow copyWithCompanion(ScoreDocumentsCompanion data) {
    return ScoreDocumentRow(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      originalPdfLocalPath: data.originalPdfLocalPath.present
          ? data.originalPdfLocalPath.value
          : this.originalPdfLocalPath,
      structuralDataLocalPath: data.structuralDataLocalPath.present
          ? data.structuralDataLocalPath.value
          : this.structuralDataLocalPath,
      createdAtUtc: data.createdAtUtc.present
          ? data.createdAtUtc.value
          : this.createdAtUtc,
      updatedAtUtc: data.updatedAtUtc.present
          ? data.updatedAtUtc.value
          : this.updatedAtUtc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ScoreDocumentRow(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('originalPdfLocalPath: $originalPdfLocalPath, ')
          ..write('structuralDataLocalPath: $structuralDataLocalPath, ')
          ..write('createdAtUtc: $createdAtUtc, ')
          ..write('updatedAtUtc: $updatedAtUtc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    originalPdfLocalPath,
    structuralDataLocalPath,
    createdAtUtc,
    updatedAtUtc,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScoreDocumentRow &&
          other.id == this.id &&
          other.title == this.title &&
          other.originalPdfLocalPath == this.originalPdfLocalPath &&
          other.structuralDataLocalPath == this.structuralDataLocalPath &&
          other.createdAtUtc == this.createdAtUtc &&
          other.updatedAtUtc == this.updatedAtUtc);
}

class ScoreDocumentsCompanion extends UpdateCompanion<ScoreDocumentRow> {
  final Value<int> id;
  final Value<String> title;
  final Value<String> originalPdfLocalPath;
  final Value<String> structuralDataLocalPath;
  final Value<DateTime> createdAtUtc;
  final Value<DateTime> updatedAtUtc;
  const ScoreDocumentsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.originalPdfLocalPath = const Value.absent(),
    this.structuralDataLocalPath = const Value.absent(),
    this.createdAtUtc = const Value.absent(),
    this.updatedAtUtc = const Value.absent(),
  });
  ScoreDocumentsCompanion.insert({
    this.id = const Value.absent(),
    required String title,
    required String originalPdfLocalPath,
    required String structuralDataLocalPath,
    required DateTime createdAtUtc,
    required DateTime updatedAtUtc,
  }) : title = Value(title),
       originalPdfLocalPath = Value(originalPdfLocalPath),
       structuralDataLocalPath = Value(structuralDataLocalPath),
       createdAtUtc = Value(createdAtUtc),
       updatedAtUtc = Value(updatedAtUtc);
  static Insertable<ScoreDocumentRow> custom({
    Expression<int>? id,
    Expression<String>? title,
    Expression<String>? originalPdfLocalPath,
    Expression<String>? structuralDataLocalPath,
    Expression<DateTime>? createdAtUtc,
    Expression<DateTime>? updatedAtUtc,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (originalPdfLocalPath != null)
        'original_pdf_local_path': originalPdfLocalPath,
      if (structuralDataLocalPath != null)
        'structural_data_local_path': structuralDataLocalPath,
      if (createdAtUtc != null) 'created_at_utc': createdAtUtc,
      if (updatedAtUtc != null) 'updated_at_utc': updatedAtUtc,
    });
  }

  ScoreDocumentsCompanion copyWith({
    Value<int>? id,
    Value<String>? title,
    Value<String>? originalPdfLocalPath,
    Value<String>? structuralDataLocalPath,
    Value<DateTime>? createdAtUtc,
    Value<DateTime>? updatedAtUtc,
  }) {
    return ScoreDocumentsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      originalPdfLocalPath: originalPdfLocalPath ?? this.originalPdfLocalPath,
      structuralDataLocalPath:
          structuralDataLocalPath ?? this.structuralDataLocalPath,
      createdAtUtc: createdAtUtc ?? this.createdAtUtc,
      updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (originalPdfLocalPath.present) {
      map['original_pdf_local_path'] = Variable<String>(
        originalPdfLocalPath.value,
      );
    }
    if (structuralDataLocalPath.present) {
      map['structural_data_local_path'] = Variable<String>(
        structuralDataLocalPath.value,
      );
    }
    if (createdAtUtc.present) {
      map['created_at_utc'] = Variable<DateTime>(createdAtUtc.value);
    }
    if (updatedAtUtc.present) {
      map['updated_at_utc'] = Variable<DateTime>(updatedAtUtc.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ScoreDocumentsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('originalPdfLocalPath: $originalPdfLocalPath, ')
          ..write('structuralDataLocalPath: $structuralDataLocalPath, ')
          ..write('createdAtUtc: $createdAtUtc, ')
          ..write('updatedAtUtc: $updatedAtUtc')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $InstrumentsTable instruments = $InstrumentsTable(this);
  late final $UserPreferencesRowsTable userPreferencesRows =
      $UserPreferencesRowsTable(this);
  late final $ScoreDocumentsTable scoreDocuments = $ScoreDocumentsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    instruments,
    userPreferencesRows,
    scoreDocuments,
  ];
}

typedef $$InstrumentsTableCreateCompanionBuilder =
    InstrumentsCompanion Function({
      Value<int> id,
      required String name,
      Value<double> baseFrequencyHz,
      Value<int> transpositionSemitones,
      required DateTime createdAtUtc,
      required DateTime updatedAtUtc,
    });
typedef $$InstrumentsTableUpdateCompanionBuilder =
    InstrumentsCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<double> baseFrequencyHz,
      Value<int> transpositionSemitones,
      Value<DateTime> createdAtUtc,
      Value<DateTime> updatedAtUtc,
    });

class $$InstrumentsTableFilterComposer
    extends Composer<_$AppDatabase, $InstrumentsTable> {
  $$InstrumentsTableFilterComposer({
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

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get baseFrequencyHz => $composableBuilder(
    column: $table.baseFrequencyHz,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get transpositionSemitones => $composableBuilder(
    column: $table.transpositionSemitones,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => ColumnFilters(column),
  );
}

class $$InstrumentsTableOrderingComposer
    extends Composer<_$AppDatabase, $InstrumentsTable> {
  $$InstrumentsTableOrderingComposer({
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

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get baseFrequencyHz => $composableBuilder(
    column: $table.baseFrequencyHz,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get transpositionSemitones => $composableBuilder(
    column: $table.transpositionSemitones,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$InstrumentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $InstrumentsTable> {
  $$InstrumentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<double> get baseFrequencyHz => $composableBuilder(
    column: $table.baseFrequencyHz,
    builder: (column) => column,
  );

  GeneratedColumn<int> get transpositionSemitones => $composableBuilder(
    column: $table.transpositionSemitones,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => column,
  );
}

class $$InstrumentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $InstrumentsTable,
          InstrumentRow,
          $$InstrumentsTableFilterComposer,
          $$InstrumentsTableOrderingComposer,
          $$InstrumentsTableAnnotationComposer,
          $$InstrumentsTableCreateCompanionBuilder,
          $$InstrumentsTableUpdateCompanionBuilder,
          (
            InstrumentRow,
            BaseReferences<_$AppDatabase, $InstrumentsTable, InstrumentRow>,
          ),
          InstrumentRow,
          PrefetchHooks Function()
        > {
  $$InstrumentsTableTableManager(_$AppDatabase db, $InstrumentsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$InstrumentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$InstrumentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$InstrumentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<double> baseFrequencyHz = const Value.absent(),
                Value<int> transpositionSemitones = const Value.absent(),
                Value<DateTime> createdAtUtc = const Value.absent(),
                Value<DateTime> updatedAtUtc = const Value.absent(),
              }) => InstrumentsCompanion(
                id: id,
                name: name,
                baseFrequencyHz: baseFrequencyHz,
                transpositionSemitones: transpositionSemitones,
                createdAtUtc: createdAtUtc,
                updatedAtUtc: updatedAtUtc,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                Value<double> baseFrequencyHz = const Value.absent(),
                Value<int> transpositionSemitones = const Value.absent(),
                required DateTime createdAtUtc,
                required DateTime updatedAtUtc,
              }) => InstrumentsCompanion.insert(
                id: id,
                name: name,
                baseFrequencyHz: baseFrequencyHz,
                transpositionSemitones: transpositionSemitones,
                createdAtUtc: createdAtUtc,
                updatedAtUtc: updatedAtUtc,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$InstrumentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $InstrumentsTable,
      InstrumentRow,
      $$InstrumentsTableFilterComposer,
      $$InstrumentsTableOrderingComposer,
      $$InstrumentsTableAnnotationComposer,
      $$InstrumentsTableCreateCompanionBuilder,
      $$InstrumentsTableUpdateCompanionBuilder,
      (
        InstrumentRow,
        BaseReferences<_$AppDatabase, $InstrumentsTable, InstrumentRow>,
      ),
      InstrumentRow,
      PrefetchHooks Function()
    >;
typedef $$UserPreferencesRowsTableCreateCompanionBuilder =
    UserPreferencesRowsCompanion Function({
      Value<int> id,
      required String trackingMode,
      required int activeInstrumentId,
      Value<double> strictConfidenceThreshold,
      Value<String> scoreId,
      required DateTime updatedAtUtc,
    });
typedef $$UserPreferencesRowsTableUpdateCompanionBuilder =
    UserPreferencesRowsCompanion Function({
      Value<int> id,
      Value<String> trackingMode,
      Value<int> activeInstrumentId,
      Value<double> strictConfidenceThreshold,
      Value<String> scoreId,
      Value<DateTime> updatedAtUtc,
    });

class $$UserPreferencesRowsTableFilterComposer
    extends Composer<_$AppDatabase, $UserPreferencesRowsTable> {
  $$UserPreferencesRowsTableFilterComposer({
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

  ColumnFilters<String> get trackingMode => $composableBuilder(
    column: $table.trackingMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get activeInstrumentId => $composableBuilder(
    column: $table.activeInstrumentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get strictConfidenceThreshold => $composableBuilder(
    column: $table.strictConfidenceThreshold,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scoreId => $composableBuilder(
    column: $table.scoreId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => ColumnFilters(column),
  );
}

class $$UserPreferencesRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $UserPreferencesRowsTable> {
  $$UserPreferencesRowsTableOrderingComposer({
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

  ColumnOrderings<String> get trackingMode => $composableBuilder(
    column: $table.trackingMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get activeInstrumentId => $composableBuilder(
    column: $table.activeInstrumentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get strictConfidenceThreshold => $composableBuilder(
    column: $table.strictConfidenceThreshold,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scoreId => $composableBuilder(
    column: $table.scoreId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$UserPreferencesRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $UserPreferencesRowsTable> {
  $$UserPreferencesRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get trackingMode => $composableBuilder(
    column: $table.trackingMode,
    builder: (column) => column,
  );

  GeneratedColumn<int> get activeInstrumentId => $composableBuilder(
    column: $table.activeInstrumentId,
    builder: (column) => column,
  );

  GeneratedColumn<double> get strictConfidenceThreshold => $composableBuilder(
    column: $table.strictConfidenceThreshold,
    builder: (column) => column,
  );

  GeneratedColumn<String> get scoreId =>
      $composableBuilder(column: $table.scoreId, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => column,
  );
}

class $$UserPreferencesRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $UserPreferencesRowsTable,
          UserPreferencesRow,
          $$UserPreferencesRowsTableFilterComposer,
          $$UserPreferencesRowsTableOrderingComposer,
          $$UserPreferencesRowsTableAnnotationComposer,
          $$UserPreferencesRowsTableCreateCompanionBuilder,
          $$UserPreferencesRowsTableUpdateCompanionBuilder,
          (
            UserPreferencesRow,
            BaseReferences<
              _$AppDatabase,
              $UserPreferencesRowsTable,
              UserPreferencesRow
            >,
          ),
          UserPreferencesRow,
          PrefetchHooks Function()
        > {
  $$UserPreferencesRowsTableTableManager(
    _$AppDatabase db,
    $UserPreferencesRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UserPreferencesRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UserPreferencesRowsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$UserPreferencesRowsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> trackingMode = const Value.absent(),
                Value<int> activeInstrumentId = const Value.absent(),
                Value<double> strictConfidenceThreshold = const Value.absent(),
                Value<String> scoreId = const Value.absent(),
                Value<DateTime> updatedAtUtc = const Value.absent(),
              }) => UserPreferencesRowsCompanion(
                id: id,
                trackingMode: trackingMode,
                activeInstrumentId: activeInstrumentId,
                strictConfidenceThreshold: strictConfidenceThreshold,
                scoreId: scoreId,
                updatedAtUtc: updatedAtUtc,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String trackingMode,
                required int activeInstrumentId,
                Value<double> strictConfidenceThreshold = const Value.absent(),
                Value<String> scoreId = const Value.absent(),
                required DateTime updatedAtUtc,
              }) => UserPreferencesRowsCompanion.insert(
                id: id,
                trackingMode: trackingMode,
                activeInstrumentId: activeInstrumentId,
                strictConfidenceThreshold: strictConfidenceThreshold,
                scoreId: scoreId,
                updatedAtUtc: updatedAtUtc,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$UserPreferencesRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $UserPreferencesRowsTable,
      UserPreferencesRow,
      $$UserPreferencesRowsTableFilterComposer,
      $$UserPreferencesRowsTableOrderingComposer,
      $$UserPreferencesRowsTableAnnotationComposer,
      $$UserPreferencesRowsTableCreateCompanionBuilder,
      $$UserPreferencesRowsTableUpdateCompanionBuilder,
      (
        UserPreferencesRow,
        BaseReferences<
          _$AppDatabase,
          $UserPreferencesRowsTable,
          UserPreferencesRow
        >,
      ),
      UserPreferencesRow,
      PrefetchHooks Function()
    >;
typedef $$ScoreDocumentsTableCreateCompanionBuilder =
    ScoreDocumentsCompanion Function({
      Value<int> id,
      required String title,
      required String originalPdfLocalPath,
      required String structuralDataLocalPath,
      required DateTime createdAtUtc,
      required DateTime updatedAtUtc,
    });
typedef $$ScoreDocumentsTableUpdateCompanionBuilder =
    ScoreDocumentsCompanion Function({
      Value<int> id,
      Value<String> title,
      Value<String> originalPdfLocalPath,
      Value<String> structuralDataLocalPath,
      Value<DateTime> createdAtUtc,
      Value<DateTime> updatedAtUtc,
    });

class $$ScoreDocumentsTableFilterComposer
    extends Composer<_$AppDatabase, $ScoreDocumentsTable> {
  $$ScoreDocumentsTableFilterComposer({
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

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get originalPdfLocalPath => $composableBuilder(
    column: $table.originalPdfLocalPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get structuralDataLocalPath => $composableBuilder(
    column: $table.structuralDataLocalPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ScoreDocumentsTableOrderingComposer
    extends Composer<_$AppDatabase, $ScoreDocumentsTable> {
  $$ScoreDocumentsTableOrderingComposer({
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

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originalPdfLocalPath => $composableBuilder(
    column: $table.originalPdfLocalPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get structuralDataLocalPath => $composableBuilder(
    column: $table.structuralDataLocalPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ScoreDocumentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ScoreDocumentsTable> {
  $$ScoreDocumentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get originalPdfLocalPath => $composableBuilder(
    column: $table.originalPdfLocalPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get structuralDataLocalPath => $composableBuilder(
    column: $table.structuralDataLocalPath,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => column,
  );
}

class $$ScoreDocumentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ScoreDocumentsTable,
          ScoreDocumentRow,
          $$ScoreDocumentsTableFilterComposer,
          $$ScoreDocumentsTableOrderingComposer,
          $$ScoreDocumentsTableAnnotationComposer,
          $$ScoreDocumentsTableCreateCompanionBuilder,
          $$ScoreDocumentsTableUpdateCompanionBuilder,
          (
            ScoreDocumentRow,
            BaseReferences<
              _$AppDatabase,
              $ScoreDocumentsTable,
              ScoreDocumentRow
            >,
          ),
          ScoreDocumentRow,
          PrefetchHooks Function()
        > {
  $$ScoreDocumentsTableTableManager(
    _$AppDatabase db,
    $ScoreDocumentsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ScoreDocumentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ScoreDocumentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ScoreDocumentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> originalPdfLocalPath = const Value.absent(),
                Value<String> structuralDataLocalPath = const Value.absent(),
                Value<DateTime> createdAtUtc = const Value.absent(),
                Value<DateTime> updatedAtUtc = const Value.absent(),
              }) => ScoreDocumentsCompanion(
                id: id,
                title: title,
                originalPdfLocalPath: originalPdfLocalPath,
                structuralDataLocalPath: structuralDataLocalPath,
                createdAtUtc: createdAtUtc,
                updatedAtUtc: updatedAtUtc,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String title,
                required String originalPdfLocalPath,
                required String structuralDataLocalPath,
                required DateTime createdAtUtc,
                required DateTime updatedAtUtc,
              }) => ScoreDocumentsCompanion.insert(
                id: id,
                title: title,
                originalPdfLocalPath: originalPdfLocalPath,
                structuralDataLocalPath: structuralDataLocalPath,
                createdAtUtc: createdAtUtc,
                updatedAtUtc: updatedAtUtc,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ScoreDocumentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ScoreDocumentsTable,
      ScoreDocumentRow,
      $$ScoreDocumentsTableFilterComposer,
      $$ScoreDocumentsTableOrderingComposer,
      $$ScoreDocumentsTableAnnotationComposer,
      $$ScoreDocumentsTableCreateCompanionBuilder,
      $$ScoreDocumentsTableUpdateCompanionBuilder,
      (
        ScoreDocumentRow,
        BaseReferences<_$AppDatabase, $ScoreDocumentsTable, ScoreDocumentRow>,
      ),
      ScoreDocumentRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$InstrumentsTableTableManager get instruments =>
      $$InstrumentsTableTableManager(_db, _db.instruments);
  $$UserPreferencesRowsTableTableManager get userPreferencesRows =>
      $$UserPreferencesRowsTableTableManager(_db, _db.userPreferencesRows);
  $$ScoreDocumentsTableTableManager get scoreDocuments =>
      $$ScoreDocumentsTableTableManager(_db, _db.scoreDocuments);
}
