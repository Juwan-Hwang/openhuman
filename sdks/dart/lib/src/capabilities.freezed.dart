// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'capabilities.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

AgentCapability _$AgentCapabilityFromJson(Map<String, dynamic> json) {
  return _AgentCapability.fromJson(json);
}

/// @nodoc
mixin _$AgentCapability {
  /// Unique tool identifier (kebab-case, e.g., `github_create_issue`).
  String get id => throw _privateConstructorUsedError;

  /// Human-readable display name.
  String get name => throw _privateConstructorUsedError;

  /// What this tool does. Omitted from JSON when `null`.
  @JsonKey(includeIfNull: false)
  String? get description => throw _privateConstructorUsedError;

  /// Grouping label (`github`, `terminal`, `browser`, ...).
  @JsonKey(includeIfNull: false)
  String? get category => throw _privateConstructorUsedError;

  /// JSON Schema describing the expected input parameters.
  @JsonKey(name: 'input_schema', includeIfNull: false)
  Map<String, dynamic>? get inputSchema => throw _privateConstructorUsedError;

  /// JSON Schema describing the output shape.
  @JsonKey(name: 'output_schema', includeIfNull: false)
  Map<String, dynamic>? get outputSchema => throw _privateConstructorUsedError;

  /// UI rendering hints for the human client (form fields, widgets, ...).
  @JsonKey(name: 'ui_schema', includeIfNull: false)
  Map<String, dynamic>? get uiSchema => throw _privateConstructorUsedError;

  /// Required permission scopes (e.g., `repo:issues:write`).
  List<String> get permissions => throw _privateConstructorUsedError;

  /// Free-form metadata bag.
  Map<String, dynamic> get metadata => throw _privateConstructorUsedError;

  /// Serializes this AgentCapability to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of AgentCapability
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $AgentCapabilityCopyWith<AgentCapability> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $AgentCapabilityCopyWith<$Res> {
  factory $AgentCapabilityCopyWith(
          AgentCapability value, $Res Function(AgentCapability) then) =
      _$AgentCapabilityCopyWithImpl<$Res, AgentCapability>;
  @useResult
  $Res call(
      {String id,
      String name,
      @JsonKey(includeIfNull: false) String? description,
      @JsonKey(includeIfNull: false) String? category,
      @JsonKey(name: 'input_schema', includeIfNull: false)
      Map<String, dynamic>? inputSchema,
      @JsonKey(name: 'output_schema', includeIfNull: false)
      Map<String, dynamic>? outputSchema,
      @JsonKey(name: 'ui_schema', includeIfNull: false)
      Map<String, dynamic>? uiSchema,
      List<String> permissions,
      Map<String, dynamic> metadata});
}

/// @nodoc
class _$AgentCapabilityCopyWithImpl<$Res, $Val extends AgentCapability>
    implements $AgentCapabilityCopyWith<$Res> {
  _$AgentCapabilityCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of AgentCapability
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? description = freezed,
    Object? category = freezed,
    Object? inputSchema = freezed,
    Object? outputSchema = freezed,
    Object? uiSchema = freezed,
    Object? permissions = null,
    Object? metadata = null,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      description: freezed == description
          ? _value.description
          : description // ignore: cast_nullable_to_non_nullable
              as String?,
      category: freezed == category
          ? _value.category
          : category // ignore: cast_nullable_to_non_nullable
              as String?,
      inputSchema: freezed == inputSchema
          ? _value.inputSchema
          : inputSchema // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>?,
      outputSchema: freezed == outputSchema
          ? _value.outputSchema
          : outputSchema // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>?,
      uiSchema: freezed == uiSchema
          ? _value.uiSchema
          : uiSchema // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>?,
      permissions: null == permissions
          ? _value.permissions
          : permissions // ignore: cast_nullable_to_non_nullable
              as List<String>,
      metadata: null == metadata
          ? _value.metadata
          : metadata // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$AgentCapabilityImplCopyWith<$Res>
    implements $AgentCapabilityCopyWith<$Res> {
  factory _$$AgentCapabilityImplCopyWith(_$AgentCapabilityImpl value,
          $Res Function(_$AgentCapabilityImpl) then) =
      __$$AgentCapabilityImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String name,
      @JsonKey(includeIfNull: false) String? description,
      @JsonKey(includeIfNull: false) String? category,
      @JsonKey(name: 'input_schema', includeIfNull: false)
      Map<String, dynamic>? inputSchema,
      @JsonKey(name: 'output_schema', includeIfNull: false)
      Map<String, dynamic>? outputSchema,
      @JsonKey(name: 'ui_schema', includeIfNull: false)
      Map<String, dynamic>? uiSchema,
      List<String> permissions,
      Map<String, dynamic> metadata});
}

/// @nodoc
class __$$AgentCapabilityImplCopyWithImpl<$Res>
    extends _$AgentCapabilityCopyWithImpl<$Res, _$AgentCapabilityImpl>
    implements _$$AgentCapabilityImplCopyWith<$Res> {
  __$$AgentCapabilityImplCopyWithImpl(
      _$AgentCapabilityImpl _value, $Res Function(_$AgentCapabilityImpl) _then)
      : super(_value, _then);

  /// Create a copy of AgentCapability
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? description = freezed,
    Object? category = freezed,
    Object? inputSchema = freezed,
    Object? outputSchema = freezed,
    Object? uiSchema = freezed,
    Object? permissions = null,
    Object? metadata = null,
  }) {
    return _then(_$AgentCapabilityImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      description: freezed == description
          ? _value.description
          : description // ignore: cast_nullable_to_non_nullable
              as String?,
      category: freezed == category
          ? _value.category
          : category // ignore: cast_nullable_to_non_nullable
              as String?,
      inputSchema: freezed == inputSchema
          ? _value._inputSchema
          : inputSchema // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>?,
      outputSchema: freezed == outputSchema
          ? _value._outputSchema
          : outputSchema // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>?,
      uiSchema: freezed == uiSchema
          ? _value._uiSchema
          : uiSchema // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>?,
      permissions: null == permissions
          ? _value._permissions
          : permissions // ignore: cast_nullable_to_non_nullable
              as List<String>,
      metadata: null == metadata
          ? _value._metadata
          : metadata // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$AgentCapabilityImpl implements _AgentCapability {
  const _$AgentCapabilityImpl(
      {required this.id,
      required this.name,
      @JsonKey(includeIfNull: false) this.description,
      @JsonKey(includeIfNull: false) this.category,
      @JsonKey(name: 'input_schema', includeIfNull: false)
      final Map<String, dynamic>? inputSchema,
      @JsonKey(name: 'output_schema', includeIfNull: false)
      final Map<String, dynamic>? outputSchema,
      @JsonKey(name: 'ui_schema', includeIfNull: false)
      final Map<String, dynamic>? uiSchema,
      final List<String> permissions = const <String>[],
      final Map<String, dynamic> metadata = const <String, dynamic>{}})
      : _inputSchema = inputSchema,
        _outputSchema = outputSchema,
        _uiSchema = uiSchema,
        _permissions = permissions,
        _metadata = metadata;

  factory _$AgentCapabilityImpl.fromJson(Map<String, dynamic> json) =>
      _$$AgentCapabilityImplFromJson(json);

  /// Unique tool identifier (kebab-case, e.g., `github_create_issue`).
  @override
  final String id;

  /// Human-readable display name.
  @override
  final String name;

  /// What this tool does. Omitted from JSON when `null`.
  @override
  @JsonKey(includeIfNull: false)
  final String? description;

  /// Grouping label (`github`, `terminal`, `browser`, ...).
  @override
  @JsonKey(includeIfNull: false)
  final String? category;

  /// JSON Schema describing the expected input parameters.
  final Map<String, dynamic>? _inputSchema;

  /// JSON Schema describing the expected input parameters.
  @override
  @JsonKey(name: 'input_schema', includeIfNull: false)
  Map<String, dynamic>? get inputSchema {
    final value = _inputSchema;
    if (value == null) return null;
    if (_inputSchema is EqualUnmodifiableMapView) return _inputSchema;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(value);
  }

  /// JSON Schema describing the output shape.
  final Map<String, dynamic>? _outputSchema;

  /// JSON Schema describing the output shape.
  @override
  @JsonKey(name: 'output_schema', includeIfNull: false)
  Map<String, dynamic>? get outputSchema {
    final value = _outputSchema;
    if (value == null) return null;
    if (_outputSchema is EqualUnmodifiableMapView) return _outputSchema;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(value);
  }

  /// UI rendering hints for the human client (form fields, widgets, ...).
  final Map<String, dynamic>? _uiSchema;

  /// UI rendering hints for the human client (form fields, widgets, ...).
  @override
  @JsonKey(name: 'ui_schema', includeIfNull: false)
  Map<String, dynamic>? get uiSchema {
    final value = _uiSchema;
    if (value == null) return null;
    if (_uiSchema is EqualUnmodifiableMapView) return _uiSchema;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(value);
  }

  /// Required permission scopes (e.g., `repo:issues:write`).
  final List<String> _permissions;

  /// Required permission scopes (e.g., `repo:issues:write`).
  @override
  @JsonKey()
  List<String> get permissions {
    if (_permissions is EqualUnmodifiableListView) return _permissions;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_permissions);
  }

  /// Free-form metadata bag.
  final Map<String, dynamic> _metadata;

  /// Free-form metadata bag.
  @override
  @JsonKey()
  Map<String, dynamic> get metadata {
    if (_metadata is EqualUnmodifiableMapView) return _metadata;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_metadata);
  }

  @override
  String toString() {
    return 'AgentCapability(id: $id, name: $name, description: $description, category: $category, inputSchema: $inputSchema, outputSchema: $outputSchema, uiSchema: $uiSchema, permissions: $permissions, metadata: $metadata)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$AgentCapabilityImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.description, description) ||
                other.description == description) &&
            (identical(other.category, category) ||
                other.category == category) &&
            const DeepCollectionEquality()
                .equals(other._inputSchema, _inputSchema) &&
            const DeepCollectionEquality()
                .equals(other._outputSchema, _outputSchema) &&
            const DeepCollectionEquality().equals(other._uiSchema, _uiSchema) &&
            const DeepCollectionEquality()
                .equals(other._permissions, _permissions) &&
            const DeepCollectionEquality().equals(other._metadata, _metadata));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      name,
      description,
      category,
      const DeepCollectionEquality().hash(_inputSchema),
      const DeepCollectionEquality().hash(_outputSchema),
      const DeepCollectionEquality().hash(_uiSchema),
      const DeepCollectionEquality().hash(_permissions),
      const DeepCollectionEquality().hash(_metadata));

  /// Create a copy of AgentCapability
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$AgentCapabilityImplCopyWith<_$AgentCapabilityImpl> get copyWith =>
      __$$AgentCapabilityImplCopyWithImpl<_$AgentCapabilityImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$AgentCapabilityImplToJson(
      this,
    );
  }
}

abstract class _AgentCapability implements AgentCapability {
  const factory _AgentCapability(
      {required final String id,
      required final String name,
      @JsonKey(includeIfNull: false) final String? description,
      @JsonKey(includeIfNull: false) final String? category,
      @JsonKey(name: 'input_schema', includeIfNull: false)
      final Map<String, dynamic>? inputSchema,
      @JsonKey(name: 'output_schema', includeIfNull: false)
      final Map<String, dynamic>? outputSchema,
      @JsonKey(name: 'ui_schema', includeIfNull: false)
      final Map<String, dynamic>? uiSchema,
      final List<String> permissions,
      final Map<String, dynamic> metadata}) = _$AgentCapabilityImpl;

  factory _AgentCapability.fromJson(Map<String, dynamic> json) =
      _$AgentCapabilityImpl.fromJson;

  /// Unique tool identifier (kebab-case, e.g., `github_create_issue`).
  @override
  String get id;

  /// Human-readable display name.
  @override
  String get name;

  /// What this tool does. Omitted from JSON when `null`.
  @override
  @JsonKey(includeIfNull: false)
  String? get description;

  /// Grouping label (`github`, `terminal`, `browser`, ...).
  @override
  @JsonKey(includeIfNull: false)
  String? get category;

  /// JSON Schema describing the expected input parameters.
  @override
  @JsonKey(name: 'input_schema', includeIfNull: false)
  Map<String, dynamic>? get inputSchema;

  /// JSON Schema describing the output shape.
  @override
  @JsonKey(name: 'output_schema', includeIfNull: false)
  Map<String, dynamic>? get outputSchema;

  /// UI rendering hints for the human client (form fields, widgets, ...).
  @override
  @JsonKey(name: 'ui_schema', includeIfNull: false)
  Map<String, dynamic>? get uiSchema;

  /// Required permission scopes (e.g., `repo:issues:write`).
  @override
  List<String> get permissions;

  /// Free-form metadata bag.
  @override
  Map<String, dynamic> get metadata;

  /// Create a copy of AgentCapability
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$AgentCapabilityImplCopyWith<_$AgentCapabilityImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

AgentContext _$AgentContextFromJson(Map<String, dynamic> json) {
  return _AgentContext.fromJson(json);
}

/// @nodoc
mixin _$AgentContext {
  /// The agent this context belongs to.
  @JsonKey(name: 'agent_id')
  String get agentId => throw _privateConstructorUsedError;

  /// The system prompt in use (may be truncated for display).
  @JsonKey(name: 'system_prompt', includeIfNull: false)
  String? get systemPrompt => throw _privateConstructorUsedError;

  /// Model metadata: `{ name, provider, max_tokens }`.
  @JsonKey(includeIfNull: false)
  Map<String, dynamic>? get model => throw _privateConstructorUsedError;

  /// Runtime info: `{ platform, version, session_id }`.
  @JsonKey(includeIfNull: false)
  Map<String, dynamic>? get runtime => throw _privateConstructorUsedError;

  /// Environment info: `{ repo, branch, working_directory }`.
  @JsonKey(includeIfNull: false)
  Map<String, dynamic>? get environment => throw _privateConstructorUsedError;

  /// Serializes this AgentContext to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of AgentContext
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $AgentContextCopyWith<AgentContext> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $AgentContextCopyWith<$Res> {
  factory $AgentContextCopyWith(
          AgentContext value, $Res Function(AgentContext) then) =
      _$AgentContextCopyWithImpl<$Res, AgentContext>;
  @useResult
  $Res call(
      {@JsonKey(name: 'agent_id') String agentId,
      @JsonKey(name: 'system_prompt', includeIfNull: false)
      String? systemPrompt,
      @JsonKey(includeIfNull: false) Map<String, dynamic>? model,
      @JsonKey(includeIfNull: false) Map<String, dynamic>? runtime,
      @JsonKey(includeIfNull: false) Map<String, dynamic>? environment});
}

/// @nodoc
class _$AgentContextCopyWithImpl<$Res, $Val extends AgentContext>
    implements $AgentContextCopyWith<$Res> {
  _$AgentContextCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of AgentContext
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? agentId = null,
    Object? systemPrompt = freezed,
    Object? model = freezed,
    Object? runtime = freezed,
    Object? environment = freezed,
  }) {
    return _then(_value.copyWith(
      agentId: null == agentId
          ? _value.agentId
          : agentId // ignore: cast_nullable_to_non_nullable
              as String,
      systemPrompt: freezed == systemPrompt
          ? _value.systemPrompt
          : systemPrompt // ignore: cast_nullable_to_non_nullable
              as String?,
      model: freezed == model
          ? _value.model
          : model // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>?,
      runtime: freezed == runtime
          ? _value.runtime
          : runtime // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>?,
      environment: freezed == environment
          ? _value.environment
          : environment // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$AgentContextImplCopyWith<$Res>
    implements $AgentContextCopyWith<$Res> {
  factory _$$AgentContextImplCopyWith(
          _$AgentContextImpl value, $Res Function(_$AgentContextImpl) then) =
      __$$AgentContextImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {@JsonKey(name: 'agent_id') String agentId,
      @JsonKey(name: 'system_prompt', includeIfNull: false)
      String? systemPrompt,
      @JsonKey(includeIfNull: false) Map<String, dynamic>? model,
      @JsonKey(includeIfNull: false) Map<String, dynamic>? runtime,
      @JsonKey(includeIfNull: false) Map<String, dynamic>? environment});
}

/// @nodoc
class __$$AgentContextImplCopyWithImpl<$Res>
    extends _$AgentContextCopyWithImpl<$Res, _$AgentContextImpl>
    implements _$$AgentContextImplCopyWith<$Res> {
  __$$AgentContextImplCopyWithImpl(
      _$AgentContextImpl _value, $Res Function(_$AgentContextImpl) _then)
      : super(_value, _then);

  /// Create a copy of AgentContext
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? agentId = null,
    Object? systemPrompt = freezed,
    Object? model = freezed,
    Object? runtime = freezed,
    Object? environment = freezed,
  }) {
    return _then(_$AgentContextImpl(
      agentId: null == agentId
          ? _value.agentId
          : agentId // ignore: cast_nullable_to_non_nullable
              as String,
      systemPrompt: freezed == systemPrompt
          ? _value.systemPrompt
          : systemPrompt // ignore: cast_nullable_to_non_nullable
              as String?,
      model: freezed == model
          ? _value._model
          : model // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>?,
      runtime: freezed == runtime
          ? _value._runtime
          : runtime // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>?,
      environment: freezed == environment
          ? _value._environment
          : environment // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$AgentContextImpl implements _AgentContext {
  const _$AgentContextImpl(
      {@JsonKey(name: 'agent_id') required this.agentId,
      @JsonKey(name: 'system_prompt', includeIfNull: false) this.systemPrompt,
      @JsonKey(includeIfNull: false) final Map<String, dynamic>? model,
      @JsonKey(includeIfNull: false) final Map<String, dynamic>? runtime,
      @JsonKey(includeIfNull: false) final Map<String, dynamic>? environment})
      : _model = model,
        _runtime = runtime,
        _environment = environment;

  factory _$AgentContextImpl.fromJson(Map<String, dynamic> json) =>
      _$$AgentContextImplFromJson(json);

  /// The agent this context belongs to.
  @override
  @JsonKey(name: 'agent_id')
  final String agentId;

  /// The system prompt in use (may be truncated for display).
  @override
  @JsonKey(name: 'system_prompt', includeIfNull: false)
  final String? systemPrompt;

  /// Model metadata: `{ name, provider, max_tokens }`.
  final Map<String, dynamic>? _model;

  /// Model metadata: `{ name, provider, max_tokens }`.
  @override
  @JsonKey(includeIfNull: false)
  Map<String, dynamic>? get model {
    final value = _model;
    if (value == null) return null;
    if (_model is EqualUnmodifiableMapView) return _model;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(value);
  }

  /// Runtime info: `{ platform, version, session_id }`.
  final Map<String, dynamic>? _runtime;

  /// Runtime info: `{ platform, version, session_id }`.
  @override
  @JsonKey(includeIfNull: false)
  Map<String, dynamic>? get runtime {
    final value = _runtime;
    if (value == null) return null;
    if (_runtime is EqualUnmodifiableMapView) return _runtime;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(value);
  }

  /// Environment info: `{ repo, branch, working_directory }`.
  final Map<String, dynamic>? _environment;

  /// Environment info: `{ repo, branch, working_directory }`.
  @override
  @JsonKey(includeIfNull: false)
  Map<String, dynamic>? get environment {
    final value = _environment;
    if (value == null) return null;
    if (_environment is EqualUnmodifiableMapView) return _environment;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(value);
  }

  @override
  String toString() {
    return 'AgentContext(agentId: $agentId, systemPrompt: $systemPrompt, model: $model, runtime: $runtime, environment: $environment)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$AgentContextImpl &&
            (identical(other.agentId, agentId) || other.agentId == agentId) &&
            (identical(other.systemPrompt, systemPrompt) ||
                other.systemPrompt == systemPrompt) &&
            const DeepCollectionEquality().equals(other._model, _model) &&
            const DeepCollectionEquality().equals(other._runtime, _runtime) &&
            const DeepCollectionEquality()
                .equals(other._environment, _environment));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      agentId,
      systemPrompt,
      const DeepCollectionEquality().hash(_model),
      const DeepCollectionEquality().hash(_runtime),
      const DeepCollectionEquality().hash(_environment));

  /// Create a copy of AgentContext
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$AgentContextImplCopyWith<_$AgentContextImpl> get copyWith =>
      __$$AgentContextImplCopyWithImpl<_$AgentContextImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$AgentContextImplToJson(
      this,
    );
  }
}

abstract class _AgentContext implements AgentContext {
  const factory _AgentContext(
      {@JsonKey(name: 'agent_id') required final String agentId,
      @JsonKey(name: 'system_prompt', includeIfNull: false)
      final String? systemPrompt,
      @JsonKey(includeIfNull: false) final Map<String, dynamic>? model,
      @JsonKey(includeIfNull: false) final Map<String, dynamic>? runtime,
      @JsonKey(includeIfNull: false)
      final Map<String, dynamic>? environment}) = _$AgentContextImpl;

  factory _AgentContext.fromJson(Map<String, dynamic> json) =
      _$AgentContextImpl.fromJson;

  /// The agent this context belongs to.
  @override
  @JsonKey(name: 'agent_id')
  String get agentId;

  /// The system prompt in use (may be truncated for display).
  @override
  @JsonKey(name: 'system_prompt', includeIfNull: false)
  String? get systemPrompt;

  /// Model metadata: `{ name, provider, max_tokens }`.
  @override
  @JsonKey(includeIfNull: false)
  Map<String, dynamic>? get model;

  /// Runtime info: `{ platform, version, session_id }`.
  @override
  @JsonKey(includeIfNull: false)
  Map<String, dynamic>? get runtime;

  /// Environment info: `{ repo, branch, working_directory }`.
  @override
  @JsonKey(includeIfNull: false)
  Map<String, dynamic>? get environment;

  /// Create a copy of AgentContext
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$AgentContextImplCopyWith<_$AgentContextImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

ToolInvoke _$ToolInvokeFromJson(Map<String, dynamic> json) {
  return _ToolInvoke.fromJson(json);
}

/// @nodoc
mixin _$ToolInvoke {
  /// Unique invocation ID (used to correlate request → result).
  @JsonKey(name: 'invocation_id')
  String get invocationId => throw _privateConstructorUsedError;

  /// The tool/capability being invoked.
  @JsonKey(name: 'tool_id')
  String get toolId => throw _privateConstructorUsedError;

  /// Input parameters conforming to `AgentCapability.inputSchema`.
  dynamic get input => throw _privateConstructorUsedError;

  /// Serializes this ToolInvoke to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of ToolInvoke
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ToolInvokeCopyWith<ToolInvoke> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ToolInvokeCopyWith<$Res> {
  factory $ToolInvokeCopyWith(
          ToolInvoke value, $Res Function(ToolInvoke) then) =
      _$ToolInvokeCopyWithImpl<$Res, ToolInvoke>;
  @useResult
  $Res call(
      {@JsonKey(name: 'invocation_id') String invocationId,
      @JsonKey(name: 'tool_id') String toolId,
      dynamic input});
}

/// @nodoc
class _$ToolInvokeCopyWithImpl<$Res, $Val extends ToolInvoke>
    implements $ToolInvokeCopyWith<$Res> {
  _$ToolInvokeCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ToolInvoke
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? invocationId = null,
    Object? toolId = null,
    Object? input = freezed,
  }) {
    return _then(_value.copyWith(
      invocationId: null == invocationId
          ? _value.invocationId
          : invocationId // ignore: cast_nullable_to_non_nullable
              as String,
      toolId: null == toolId
          ? _value.toolId
          : toolId // ignore: cast_nullable_to_non_nullable
              as String,
      input: freezed == input
          ? _value.input
          : input // ignore: cast_nullable_to_non_nullable
              as dynamic,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ToolInvokeImplCopyWith<$Res>
    implements $ToolInvokeCopyWith<$Res> {
  factory _$$ToolInvokeImplCopyWith(
          _$ToolInvokeImpl value, $Res Function(_$ToolInvokeImpl) then) =
      __$$ToolInvokeImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {@JsonKey(name: 'invocation_id') String invocationId,
      @JsonKey(name: 'tool_id') String toolId,
      dynamic input});
}

/// @nodoc
class __$$ToolInvokeImplCopyWithImpl<$Res>
    extends _$ToolInvokeCopyWithImpl<$Res, _$ToolInvokeImpl>
    implements _$$ToolInvokeImplCopyWith<$Res> {
  __$$ToolInvokeImplCopyWithImpl(
      _$ToolInvokeImpl _value, $Res Function(_$ToolInvokeImpl) _then)
      : super(_value, _then);

  /// Create a copy of ToolInvoke
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? invocationId = null,
    Object? toolId = null,
    Object? input = freezed,
  }) {
    return _then(_$ToolInvokeImpl(
      invocationId: null == invocationId
          ? _value.invocationId
          : invocationId // ignore: cast_nullable_to_non_nullable
              as String,
      toolId: null == toolId
          ? _value.toolId
          : toolId // ignore: cast_nullable_to_non_nullable
              as String,
      input: freezed == input
          ? _value.input
          : input // ignore: cast_nullable_to_non_nullable
              as dynamic,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ToolInvokeImpl implements _ToolInvoke {
  const _$ToolInvokeImpl(
      {@JsonKey(name: 'invocation_id') required this.invocationId,
      @JsonKey(name: 'tool_id') required this.toolId,
      required this.input});

  factory _$ToolInvokeImpl.fromJson(Map<String, dynamic> json) =>
      _$$ToolInvokeImplFromJson(json);

  /// Unique invocation ID (used to correlate request → result).
  @override
  @JsonKey(name: 'invocation_id')
  final String invocationId;

  /// The tool/capability being invoked.
  @override
  @JsonKey(name: 'tool_id')
  final String toolId;

  /// Input parameters conforming to `AgentCapability.inputSchema`.
  @override
  final dynamic input;

  @override
  String toString() {
    return 'ToolInvoke(invocationId: $invocationId, toolId: $toolId, input: $input)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ToolInvokeImpl &&
            (identical(other.invocationId, invocationId) ||
                other.invocationId == invocationId) &&
            (identical(other.toolId, toolId) || other.toolId == toolId) &&
            const DeepCollectionEquality().equals(other.input, input));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, invocationId, toolId,
      const DeepCollectionEquality().hash(input));

  /// Create a copy of ToolInvoke
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ToolInvokeImplCopyWith<_$ToolInvokeImpl> get copyWith =>
      __$$ToolInvokeImplCopyWithImpl<_$ToolInvokeImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ToolInvokeImplToJson(
      this,
    );
  }
}

abstract class _ToolInvoke implements ToolInvoke {
  const factory _ToolInvoke(
      {@JsonKey(name: 'invocation_id') required final String invocationId,
      @JsonKey(name: 'tool_id') required final String toolId,
      required final dynamic input}) = _$ToolInvokeImpl;

  factory _ToolInvoke.fromJson(Map<String, dynamic> json) =
      _$ToolInvokeImpl.fromJson;

  /// Unique invocation ID (used to correlate request → result).
  @override
  @JsonKey(name: 'invocation_id')
  String get invocationId;

  /// The tool/capability being invoked.
  @override
  @JsonKey(name: 'tool_id')
  String get toolId;

  /// Input parameters conforming to `AgentCapability.inputSchema`.
  @override
  dynamic get input;

  /// Create a copy of ToolInvoke
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ToolInvokeImplCopyWith<_$ToolInvokeImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

ToolResult _$ToolResultFromJson(Map<String, dynamic> json) {
  return _ToolResult.fromJson(json);
}

/// @nodoc
mixin _$ToolResult {
  /// Correlates to the original `ToolInvoke.invocationId`.
  @JsonKey(name: 'invocation_id')
  String get invocationId => throw _privateConstructorUsedError;

  /// The tool that was invoked.
  @JsonKey(name: 'tool_id')
  String get toolId => throw _privateConstructorUsedError;

  /// Outcome of the invocation.
  InvocationStatus get status => throw _privateConstructorUsedError;

  /// Output data conforming to `AgentCapability.outputSchema`.
  /// Omitted from JSON when `null`.
  @JsonKey(includeIfNull: false)
  dynamic get output => throw _privateConstructorUsedError;

  /// Error message if `status == error`. Omitted from JSON when `null`.
  @JsonKey(includeIfNull: false)
  String? get error => throw _privateConstructorUsedError;

  /// Serializes this ToolResult to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of ToolResult
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ToolResultCopyWith<ToolResult> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ToolResultCopyWith<$Res> {
  factory $ToolResultCopyWith(
          ToolResult value, $Res Function(ToolResult) then) =
      _$ToolResultCopyWithImpl<$Res, ToolResult>;
  @useResult
  $Res call(
      {@JsonKey(name: 'invocation_id') String invocationId,
      @JsonKey(name: 'tool_id') String toolId,
      InvocationStatus status,
      @JsonKey(includeIfNull: false) dynamic output,
      @JsonKey(includeIfNull: false) String? error});
}

/// @nodoc
class _$ToolResultCopyWithImpl<$Res, $Val extends ToolResult>
    implements $ToolResultCopyWith<$Res> {
  _$ToolResultCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ToolResult
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? invocationId = null,
    Object? toolId = null,
    Object? status = null,
    Object? output = freezed,
    Object? error = freezed,
  }) {
    return _then(_value.copyWith(
      invocationId: null == invocationId
          ? _value.invocationId
          : invocationId // ignore: cast_nullable_to_non_nullable
              as String,
      toolId: null == toolId
          ? _value.toolId
          : toolId // ignore: cast_nullable_to_non_nullable
              as String,
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as InvocationStatus,
      output: freezed == output
          ? _value.output
          : output // ignore: cast_nullable_to_non_nullable
              as dynamic,
      error: freezed == error
          ? _value.error
          : error // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ToolResultImplCopyWith<$Res>
    implements $ToolResultCopyWith<$Res> {
  factory _$$ToolResultImplCopyWith(
          _$ToolResultImpl value, $Res Function(_$ToolResultImpl) then) =
      __$$ToolResultImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {@JsonKey(name: 'invocation_id') String invocationId,
      @JsonKey(name: 'tool_id') String toolId,
      InvocationStatus status,
      @JsonKey(includeIfNull: false) dynamic output,
      @JsonKey(includeIfNull: false) String? error});
}

/// @nodoc
class __$$ToolResultImplCopyWithImpl<$Res>
    extends _$ToolResultCopyWithImpl<$Res, _$ToolResultImpl>
    implements _$$ToolResultImplCopyWith<$Res> {
  __$$ToolResultImplCopyWithImpl(
      _$ToolResultImpl _value, $Res Function(_$ToolResultImpl) _then)
      : super(_value, _then);

  /// Create a copy of ToolResult
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? invocationId = null,
    Object? toolId = null,
    Object? status = null,
    Object? output = freezed,
    Object? error = freezed,
  }) {
    return _then(_$ToolResultImpl(
      invocationId: null == invocationId
          ? _value.invocationId
          : invocationId // ignore: cast_nullable_to_non_nullable
              as String,
      toolId: null == toolId
          ? _value.toolId
          : toolId // ignore: cast_nullable_to_non_nullable
              as String,
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as InvocationStatus,
      output: freezed == output
          ? _value.output
          : output // ignore: cast_nullable_to_non_nullable
              as dynamic,
      error: freezed == error
          ? _value.error
          : error // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ToolResultImpl implements _ToolResult {
  const _$ToolResultImpl(
      {@JsonKey(name: 'invocation_id') required this.invocationId,
      @JsonKey(name: 'tool_id') required this.toolId,
      required this.status,
      @JsonKey(includeIfNull: false) this.output,
      @JsonKey(includeIfNull: false) this.error});

  factory _$ToolResultImpl.fromJson(Map<String, dynamic> json) =>
      _$$ToolResultImplFromJson(json);

  /// Correlates to the original `ToolInvoke.invocationId`.
  @override
  @JsonKey(name: 'invocation_id')
  final String invocationId;

  /// The tool that was invoked.
  @override
  @JsonKey(name: 'tool_id')
  final String toolId;

  /// Outcome of the invocation.
  @override
  final InvocationStatus status;

  /// Output data conforming to `AgentCapability.outputSchema`.
  /// Omitted from JSON when `null`.
  @override
  @JsonKey(includeIfNull: false)
  final dynamic output;

  /// Error message if `status == error`. Omitted from JSON when `null`.
  @override
  @JsonKey(includeIfNull: false)
  final String? error;

  @override
  String toString() {
    return 'ToolResult(invocationId: $invocationId, toolId: $toolId, status: $status, output: $output, error: $error)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ToolResultImpl &&
            (identical(other.invocationId, invocationId) ||
                other.invocationId == invocationId) &&
            (identical(other.toolId, toolId) || other.toolId == toolId) &&
            (identical(other.status, status) || other.status == status) &&
            const DeepCollectionEquality().equals(other.output, output) &&
            (identical(other.error, error) || other.error == error));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, invocationId, toolId, status,
      const DeepCollectionEquality().hash(output), error);

  /// Create a copy of ToolResult
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ToolResultImplCopyWith<_$ToolResultImpl> get copyWith =>
      __$$ToolResultImplCopyWithImpl<_$ToolResultImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ToolResultImplToJson(
      this,
    );
  }
}

abstract class _ToolResult implements ToolResult {
  const factory _ToolResult(
      {@JsonKey(name: 'invocation_id') required final String invocationId,
      @JsonKey(name: 'tool_id') required final String toolId,
      required final InvocationStatus status,
      @JsonKey(includeIfNull: false) final dynamic output,
      @JsonKey(includeIfNull: false) final String? error}) = _$ToolResultImpl;

  factory _ToolResult.fromJson(Map<String, dynamic> json) =
      _$ToolResultImpl.fromJson;

  /// Correlates to the original `ToolInvoke.invocationId`.
  @override
  @JsonKey(name: 'invocation_id')
  String get invocationId;

  /// The tool that was invoked.
  @override
  @JsonKey(name: 'tool_id')
  String get toolId;

  /// Outcome of the invocation.
  @override
  InvocationStatus get status;

  /// Output data conforming to `AgentCapability.outputSchema`.
  /// Omitted from JSON when `null`.
  @override
  @JsonKey(includeIfNull: false)
  dynamic get output;

  /// Error message if `status == error`. Omitted from JSON when `null`.
  @override
  @JsonKey(includeIfNull: false)
  String? get error;

  /// Create a copy of ToolResult
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ToolResultImplCopyWith<_$ToolResultImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
