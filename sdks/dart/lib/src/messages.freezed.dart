// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'messages.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

ParticipantRef _$ParticipantRefFromJson(Map<String, dynamic> json) {
  return _ParticipantRef.fromJson(json);
}

/// @nodoc
mixin _$ParticipantRef {
  /// `HumanIdentity.id` or `AgentIdentity.id`.
  @JsonKey(name: 'participant_id')
  String get participantId => throw _privateConstructorUsedError;

  /// Whether this participant is a human or an agent.
  @JsonKey(name: 'participant_type')
  ParticipantType get participantType => throw _privateConstructorUsedError;

  /// Serializes this ParticipantRef to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of ParticipantRef
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ParticipantRefCopyWith<ParticipantRef> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ParticipantRefCopyWith<$Res> {
  factory $ParticipantRefCopyWith(
          ParticipantRef value, $Res Function(ParticipantRef) then) =
      _$ParticipantRefCopyWithImpl<$Res, ParticipantRef>;
  @useResult
  $Res call(
      {@JsonKey(name: 'participant_id') String participantId,
      @JsonKey(name: 'participant_type') ParticipantType participantType});
}

/// @nodoc
class _$ParticipantRefCopyWithImpl<$Res, $Val extends ParticipantRef>
    implements $ParticipantRefCopyWith<$Res> {
  _$ParticipantRefCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ParticipantRef
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? participantId = null,
    Object? participantType = null,
  }) {
    return _then(_value.copyWith(
      participantId: null == participantId
          ? _value.participantId
          : participantId // ignore: cast_nullable_to_non_nullable
              as String,
      participantType: null == participantType
          ? _value.participantType
          : participantType // ignore: cast_nullable_to_non_nullable
              as ParticipantType,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ParticipantRefImplCopyWith<$Res>
    implements $ParticipantRefCopyWith<$Res> {
  factory _$$ParticipantRefImplCopyWith(_$ParticipantRefImpl value,
          $Res Function(_$ParticipantRefImpl) then) =
      __$$ParticipantRefImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {@JsonKey(name: 'participant_id') String participantId,
      @JsonKey(name: 'participant_type') ParticipantType participantType});
}

/// @nodoc
class __$$ParticipantRefImplCopyWithImpl<$Res>
    extends _$ParticipantRefCopyWithImpl<$Res, _$ParticipantRefImpl>
    implements _$$ParticipantRefImplCopyWith<$Res> {
  __$$ParticipantRefImplCopyWithImpl(
      _$ParticipantRefImpl _value, $Res Function(_$ParticipantRefImpl) _then)
      : super(_value, _then);

  /// Create a copy of ParticipantRef
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? participantId = null,
    Object? participantType = null,
  }) {
    return _then(_$ParticipantRefImpl(
      participantId: null == participantId
          ? _value.participantId
          : participantId // ignore: cast_nullable_to_non_nullable
              as String,
      participantType: null == participantType
          ? _value.participantType
          : participantType // ignore: cast_nullable_to_non_nullable
              as ParticipantType,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ParticipantRefImpl implements _ParticipantRef {
  const _$ParticipantRefImpl(
      {@JsonKey(name: 'participant_id') required this.participantId,
      @JsonKey(name: 'participant_type') required this.participantType});

  factory _$ParticipantRefImpl.fromJson(Map<String, dynamic> json) =>
      _$$ParticipantRefImplFromJson(json);

  /// `HumanIdentity.id` or `AgentIdentity.id`.
  @override
  @JsonKey(name: 'participant_id')
  final String participantId;

  /// Whether this participant is a human or an agent.
  @override
  @JsonKey(name: 'participant_type')
  final ParticipantType participantType;

  @override
  String toString() {
    return 'ParticipantRef(participantId: $participantId, participantType: $participantType)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ParticipantRefImpl &&
            (identical(other.participantId, participantId) ||
                other.participantId == participantId) &&
            (identical(other.participantType, participantType) ||
                other.participantType == participantType));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, participantId, participantType);

  /// Create a copy of ParticipantRef
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ParticipantRefImplCopyWith<_$ParticipantRefImpl> get copyWith =>
      __$$ParticipantRefImplCopyWithImpl<_$ParticipantRefImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ParticipantRefImplToJson(
      this,
    );
  }
}

abstract class _ParticipantRef implements ParticipantRef {
  const factory _ParticipantRef(
      {@JsonKey(name: 'participant_id') required final String participantId,
      @JsonKey(name: 'participant_type')
      required final ParticipantType participantType}) = _$ParticipantRefImpl;

  factory _ParticipantRef.fromJson(Map<String, dynamic> json) =
      _$ParticipantRefImpl.fromJson;

  /// `HumanIdentity.id` or `AgentIdentity.id`.
  @override
  @JsonKey(name: 'participant_id')
  String get participantId;

  /// Whether this participant is a human or an agent.
  @override
  @JsonKey(name: 'participant_type')
  ParticipantType get participantType;

  /// Create a copy of ParticipantRef
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ParticipantRefImplCopyWith<_$ParticipantRefImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

ContentBlock _$ContentBlockFromJson(Map<String, dynamic> json) {
  switch (json['type']) {
    case 'text':
      return TextContent.fromJson(json);
    case 'structured':
      return StructuredContent.fromJson(json);
    case 'multipart':
      return MultipartContent.fromJson(json);

    default:
      throw CheckedFromJsonException(json, 'type', 'ContentBlock',
          'Invalid union type "${json['type']}"!');
  }
}

/// @nodoc
mixin _$ContentBlock {
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String text) text,
    required TResult Function(Map<String, dynamic> schema, dynamic data)
        structured,
    required TResult Function(List<ContentBlock> parts) multipart,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String text)? text,
    TResult? Function(Map<String, dynamic> schema, dynamic data)? structured,
    TResult? Function(List<ContentBlock> parts)? multipart,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String text)? text,
    TResult Function(Map<String, dynamic> schema, dynamic data)? structured,
    TResult Function(List<ContentBlock> parts)? multipart,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(TextContent value) text,
    required TResult Function(StructuredContent value) structured,
    required TResult Function(MultipartContent value) multipart,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(TextContent value)? text,
    TResult? Function(StructuredContent value)? structured,
    TResult? Function(MultipartContent value)? multipart,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(TextContent value)? text,
    TResult Function(StructuredContent value)? structured,
    TResult Function(MultipartContent value)? multipart,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;

  /// Serializes this ContentBlock to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ContentBlockCopyWith<$Res> {
  factory $ContentBlockCopyWith(
          ContentBlock value, $Res Function(ContentBlock) then) =
      _$ContentBlockCopyWithImpl<$Res, ContentBlock>;
}

/// @nodoc
class _$ContentBlockCopyWithImpl<$Res, $Val extends ContentBlock>
    implements $ContentBlockCopyWith<$Res> {
  _$ContentBlockCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ContentBlock
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc
abstract class _$$TextContentImplCopyWith<$Res> {
  factory _$$TextContentImplCopyWith(
          _$TextContentImpl value, $Res Function(_$TextContentImpl) then) =
      __$$TextContentImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String text});
}

/// @nodoc
class __$$TextContentImplCopyWithImpl<$Res>
    extends _$ContentBlockCopyWithImpl<$Res, _$TextContentImpl>
    implements _$$TextContentImplCopyWith<$Res> {
  __$$TextContentImplCopyWithImpl(
      _$TextContentImpl _value, $Res Function(_$TextContentImpl) _then)
      : super(_value, _then);

  /// Create a copy of ContentBlock
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? text = null,
  }) {
    return _then(_$TextContentImpl(
      text: null == text
          ? _value.text
          : text // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$TextContentImpl implements TextContent {
  const _$TextContentImpl({required this.text, final String? $type})
      : $type = $type ?? 'text';

  factory _$TextContentImpl.fromJson(Map<String, dynamic> json) =>
      _$$TextContentImplFromJson(json);

  @override
  final String text;

  @JsonKey(name: 'type')
  final String $type;

  @override
  String toString() {
    return 'ContentBlock.text(text: $text)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$TextContentImpl &&
            (identical(other.text, text) || other.text == text));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, text);

  /// Create a copy of ContentBlock
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$TextContentImplCopyWith<_$TextContentImpl> get copyWith =>
      __$$TextContentImplCopyWithImpl<_$TextContentImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String text) text,
    required TResult Function(Map<String, dynamic> schema, dynamic data)
        structured,
    required TResult Function(List<ContentBlock> parts) multipart,
  }) {
    return text(this.text);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String text)? text,
    TResult? Function(Map<String, dynamic> schema, dynamic data)? structured,
    TResult? Function(List<ContentBlock> parts)? multipart,
  }) {
    return text?.call(this.text);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String text)? text,
    TResult Function(Map<String, dynamic> schema, dynamic data)? structured,
    TResult Function(List<ContentBlock> parts)? multipart,
    required TResult orElse(),
  }) {
    if (text != null) {
      return text(this.text);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(TextContent value) text,
    required TResult Function(StructuredContent value) structured,
    required TResult Function(MultipartContent value) multipart,
  }) {
    return text(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(TextContent value)? text,
    TResult? Function(StructuredContent value)? structured,
    TResult? Function(MultipartContent value)? multipart,
  }) {
    return text?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(TextContent value)? text,
    TResult Function(StructuredContent value)? structured,
    TResult Function(MultipartContent value)? multipart,
    required TResult orElse(),
  }) {
    if (text != null) {
      return text(this);
    }
    return orElse();
  }

  @override
  Map<String, dynamic> toJson() {
    return _$$TextContentImplToJson(
      this,
    );
  }
}

abstract class TextContent implements ContentBlock {
  const factory TextContent({required final String text}) = _$TextContentImpl;

  factory TextContent.fromJson(Map<String, dynamic> json) =
      _$TextContentImpl.fromJson;

  String get text;

  /// Create a copy of ContentBlock
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$TextContentImplCopyWith<_$TextContentImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$StructuredContentImplCopyWith<$Res> {
  factory _$$StructuredContentImplCopyWith(_$StructuredContentImpl value,
          $Res Function(_$StructuredContentImpl) then) =
      __$$StructuredContentImplCopyWithImpl<$Res>;
  @useResult
  $Res call({Map<String, dynamic> schema, dynamic data});
}

/// @nodoc
class __$$StructuredContentImplCopyWithImpl<$Res>
    extends _$ContentBlockCopyWithImpl<$Res, _$StructuredContentImpl>
    implements _$$StructuredContentImplCopyWith<$Res> {
  __$$StructuredContentImplCopyWithImpl(_$StructuredContentImpl _value,
      $Res Function(_$StructuredContentImpl) _then)
      : super(_value, _then);

  /// Create a copy of ContentBlock
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? schema = null,
    Object? data = freezed,
  }) {
    return _then(_$StructuredContentImpl(
      schema: null == schema
          ? _value._schema
          : schema // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
      data: freezed == data
          ? _value.data
          : data // ignore: cast_nullable_to_non_nullable
              as dynamic,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$StructuredContentImpl implements StructuredContent {
  const _$StructuredContentImpl(
      {required final Map<String, dynamic> schema,
      required this.data,
      final String? $type})
      : _schema = schema,
        $type = $type ?? 'structured';

  factory _$StructuredContentImpl.fromJson(Map<String, dynamic> json) =>
      _$$StructuredContentImplFromJson(json);

  final Map<String, dynamic> _schema;
  @override
  Map<String, dynamic> get schema {
    if (_schema is EqualUnmodifiableMapView) return _schema;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_schema);
  }

  @override
  final dynamic data;

  @JsonKey(name: 'type')
  final String $type;

  @override
  String toString() {
    return 'ContentBlock.structured(schema: $schema, data: $data)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$StructuredContentImpl &&
            const DeepCollectionEquality().equals(other._schema, _schema) &&
            const DeepCollectionEquality().equals(other.data, data));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      const DeepCollectionEquality().hash(_schema),
      const DeepCollectionEquality().hash(data));

  /// Create a copy of ContentBlock
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$StructuredContentImplCopyWith<_$StructuredContentImpl> get copyWith =>
      __$$StructuredContentImplCopyWithImpl<_$StructuredContentImpl>(
          this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String text) text,
    required TResult Function(Map<String, dynamic> schema, dynamic data)
        structured,
    required TResult Function(List<ContentBlock> parts) multipart,
  }) {
    return structured(schema, data);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String text)? text,
    TResult? Function(Map<String, dynamic> schema, dynamic data)? structured,
    TResult? Function(List<ContentBlock> parts)? multipart,
  }) {
    return structured?.call(schema, data);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String text)? text,
    TResult Function(Map<String, dynamic> schema, dynamic data)? structured,
    TResult Function(List<ContentBlock> parts)? multipart,
    required TResult orElse(),
  }) {
    if (structured != null) {
      return structured(schema, data);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(TextContent value) text,
    required TResult Function(StructuredContent value) structured,
    required TResult Function(MultipartContent value) multipart,
  }) {
    return structured(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(TextContent value)? text,
    TResult? Function(StructuredContent value)? structured,
    TResult? Function(MultipartContent value)? multipart,
  }) {
    return structured?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(TextContent value)? text,
    TResult Function(StructuredContent value)? structured,
    TResult Function(MultipartContent value)? multipart,
    required TResult orElse(),
  }) {
    if (structured != null) {
      return structured(this);
    }
    return orElse();
  }

  @override
  Map<String, dynamic> toJson() {
    return _$$StructuredContentImplToJson(
      this,
    );
  }
}

abstract class StructuredContent implements ContentBlock {
  const factory StructuredContent(
      {required final Map<String, dynamic> schema,
      required final dynamic data}) = _$StructuredContentImpl;

  factory StructuredContent.fromJson(Map<String, dynamic> json) =
      _$StructuredContentImpl.fromJson;

  Map<String, dynamic> get schema;
  dynamic get data;

  /// Create a copy of ContentBlock
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$StructuredContentImplCopyWith<_$StructuredContentImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$MultipartContentImplCopyWith<$Res> {
  factory _$$MultipartContentImplCopyWith(_$MultipartContentImpl value,
          $Res Function(_$MultipartContentImpl) then) =
      __$$MultipartContentImplCopyWithImpl<$Res>;
  @useResult
  $Res call({List<ContentBlock> parts});
}

/// @nodoc
class __$$MultipartContentImplCopyWithImpl<$Res>
    extends _$ContentBlockCopyWithImpl<$Res, _$MultipartContentImpl>
    implements _$$MultipartContentImplCopyWith<$Res> {
  __$$MultipartContentImplCopyWithImpl(_$MultipartContentImpl _value,
      $Res Function(_$MultipartContentImpl) _then)
      : super(_value, _then);

  /// Create a copy of ContentBlock
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? parts = null,
  }) {
    return _then(_$MultipartContentImpl(
      parts: null == parts
          ? _value._parts
          : parts // ignore: cast_nullable_to_non_nullable
              as List<ContentBlock>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$MultipartContentImpl implements MultipartContent {
  const _$MultipartContentImpl(
      {required final List<ContentBlock> parts, final String? $type})
      : _parts = parts,
        $type = $type ?? 'multipart';

  factory _$MultipartContentImpl.fromJson(Map<String, dynamic> json) =>
      _$$MultipartContentImplFromJson(json);

  final List<ContentBlock> _parts;
  @override
  List<ContentBlock> get parts {
    if (_parts is EqualUnmodifiableListView) return _parts;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_parts);
  }

  @JsonKey(name: 'type')
  final String $type;

  @override
  String toString() {
    return 'ContentBlock.multipart(parts: $parts)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MultipartContentImpl &&
            const DeepCollectionEquality().equals(other._parts, _parts));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode =>
      Object.hash(runtimeType, const DeepCollectionEquality().hash(_parts));

  /// Create a copy of ContentBlock
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$MultipartContentImplCopyWith<_$MultipartContentImpl> get copyWith =>
      __$$MultipartContentImplCopyWithImpl<_$MultipartContentImpl>(
          this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String text) text,
    required TResult Function(Map<String, dynamic> schema, dynamic data)
        structured,
    required TResult Function(List<ContentBlock> parts) multipart,
  }) {
    return multipart(parts);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String text)? text,
    TResult? Function(Map<String, dynamic> schema, dynamic data)? structured,
    TResult? Function(List<ContentBlock> parts)? multipart,
  }) {
    return multipart?.call(parts);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String text)? text,
    TResult Function(Map<String, dynamic> schema, dynamic data)? structured,
    TResult Function(List<ContentBlock> parts)? multipart,
    required TResult orElse(),
  }) {
    if (multipart != null) {
      return multipart(parts);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(TextContent value) text,
    required TResult Function(StructuredContent value) structured,
    required TResult Function(MultipartContent value) multipart,
  }) {
    return multipart(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(TextContent value)? text,
    TResult? Function(StructuredContent value)? structured,
    TResult? Function(MultipartContent value)? multipart,
  }) {
    return multipart?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(TextContent value)? text,
    TResult Function(StructuredContent value)? structured,
    TResult Function(MultipartContent value)? multipart,
    required TResult orElse(),
  }) {
    if (multipart != null) {
      return multipart(this);
    }
    return orElse();
  }

  @override
  Map<String, dynamic> toJson() {
    return _$$MultipartContentImplToJson(
      this,
    );
  }
}

abstract class MultipartContent implements ContentBlock {
  const factory MultipartContent({required final List<ContentBlock> parts}) =
      _$MultipartContentImpl;

  factory MultipartContent.fromJson(Map<String, dynamic> json) =
      _$MultipartContentImpl.fromJson;

  List<ContentBlock> get parts;

  /// Create a copy of ContentBlock
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$MultipartContentImplCopyWith<_$MultipartContentImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

Attachment _$AttachmentFromJson(Map<String, dynamic> json) {
  return _Attachment.fromJson(json);
}

/// @nodoc
mixin _$Attachment {
  /// Unique attachment ID (`att_` prefixed).
  String get id => throw _privateConstructorUsedError;

  /// Original filename.
  String get filename => throw _privateConstructorUsedError;

  /// MIME type (e.g., `"application/pdf"`, `"image/png"`).
  @JsonKey(name: 'content_type')
  String get contentType => throw _privateConstructorUsedError;

  /// File size in bytes.
  @JsonKey(name: 'size_bytes')
  int get sizeBytes => throw _privateConstructorUsedError;

  /// Download URL (time-limited presigned).
  String get url => throw _privateConstructorUsedError;

  /// Serializes this Attachment to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of Attachment
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $AttachmentCopyWith<Attachment> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $AttachmentCopyWith<$Res> {
  factory $AttachmentCopyWith(
          Attachment value, $Res Function(Attachment) then) =
      _$AttachmentCopyWithImpl<$Res, Attachment>;
  @useResult
  $Res call(
      {String id,
      String filename,
      @JsonKey(name: 'content_type') String contentType,
      @JsonKey(name: 'size_bytes') int sizeBytes,
      String url});
}

/// @nodoc
class _$AttachmentCopyWithImpl<$Res, $Val extends Attachment>
    implements $AttachmentCopyWith<$Res> {
  _$AttachmentCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of Attachment
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? filename = null,
    Object? contentType = null,
    Object? sizeBytes = null,
    Object? url = null,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      filename: null == filename
          ? _value.filename
          : filename // ignore: cast_nullable_to_non_nullable
              as String,
      contentType: null == contentType
          ? _value.contentType
          : contentType // ignore: cast_nullable_to_non_nullable
              as String,
      sizeBytes: null == sizeBytes
          ? _value.sizeBytes
          : sizeBytes // ignore: cast_nullable_to_non_nullable
              as int,
      url: null == url
          ? _value.url
          : url // ignore: cast_nullable_to_non_nullable
              as String,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$AttachmentImplCopyWith<$Res>
    implements $AttachmentCopyWith<$Res> {
  factory _$$AttachmentImplCopyWith(
          _$AttachmentImpl value, $Res Function(_$AttachmentImpl) then) =
      __$$AttachmentImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String filename,
      @JsonKey(name: 'content_type') String contentType,
      @JsonKey(name: 'size_bytes') int sizeBytes,
      String url});
}

/// @nodoc
class __$$AttachmentImplCopyWithImpl<$Res>
    extends _$AttachmentCopyWithImpl<$Res, _$AttachmentImpl>
    implements _$$AttachmentImplCopyWith<$Res> {
  __$$AttachmentImplCopyWithImpl(
      _$AttachmentImpl _value, $Res Function(_$AttachmentImpl) _then)
      : super(_value, _then);

  /// Create a copy of Attachment
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? filename = null,
    Object? contentType = null,
    Object? sizeBytes = null,
    Object? url = null,
  }) {
    return _then(_$AttachmentImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      filename: null == filename
          ? _value.filename
          : filename // ignore: cast_nullable_to_non_nullable
              as String,
      contentType: null == contentType
          ? _value.contentType
          : contentType // ignore: cast_nullable_to_non_nullable
              as String,
      sizeBytes: null == sizeBytes
          ? _value.sizeBytes
          : sizeBytes // ignore: cast_nullable_to_non_nullable
              as int,
      url: null == url
          ? _value.url
          : url // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$AttachmentImpl implements _Attachment {
  const _$AttachmentImpl(
      {required this.id,
      required this.filename,
      @JsonKey(name: 'content_type') required this.contentType,
      @JsonKey(name: 'size_bytes') required this.sizeBytes,
      required this.url});

  factory _$AttachmentImpl.fromJson(Map<String, dynamic> json) =>
      _$$AttachmentImplFromJson(json);

  /// Unique attachment ID (`att_` prefixed).
  @override
  final String id;

  /// Original filename.
  @override
  final String filename;

  /// MIME type (e.g., `"application/pdf"`, `"image/png"`).
  @override
  @JsonKey(name: 'content_type')
  final String contentType;

  /// File size in bytes.
  @override
  @JsonKey(name: 'size_bytes')
  final int sizeBytes;

  /// Download URL (time-limited presigned).
  @override
  final String url;

  @override
  String toString() {
    return 'Attachment(id: $id, filename: $filename, contentType: $contentType, sizeBytes: $sizeBytes, url: $url)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$AttachmentImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.filename, filename) ||
                other.filename == filename) &&
            (identical(other.contentType, contentType) ||
                other.contentType == contentType) &&
            (identical(other.sizeBytes, sizeBytes) ||
                other.sizeBytes == sizeBytes) &&
            (identical(other.url, url) || other.url == url));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode =>
      Object.hash(runtimeType, id, filename, contentType, sizeBytes, url);

  /// Create a copy of Attachment
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$AttachmentImplCopyWith<_$AttachmentImpl> get copyWith =>
      __$$AttachmentImplCopyWithImpl<_$AttachmentImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$AttachmentImplToJson(
      this,
    );
  }
}

abstract class _Attachment implements Attachment {
  const factory _Attachment(
      {required final String id,
      required final String filename,
      @JsonKey(name: 'content_type') required final String contentType,
      @JsonKey(name: 'size_bytes') required final int sizeBytes,
      required final String url}) = _$AttachmentImpl;

  factory _Attachment.fromJson(Map<String, dynamic> json) =
      _$AttachmentImpl.fromJson;

  /// Unique attachment ID (`att_` prefixed).
  @override
  String get id;

  /// Original filename.
  @override
  String get filename;

  /// MIME type (e.g., `"application/pdf"`, `"image/png"`).
  @override
  @JsonKey(name: 'content_type')
  String get contentType;

  /// File size in bytes.
  @override
  @JsonKey(name: 'size_bytes')
  int get sizeBytes;

  /// Download URL (time-limited presigned).
  @override
  String get url;

  /// Create a copy of Attachment
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$AttachmentImplCopyWith<_$AttachmentImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

OpenHumanMessage _$OpenHumanMessageFromJson(Map<String, dynamic> json) {
  return _OpenHumanMessage.fromJson(json);
}

/// @nodoc
mixin _$OpenHumanMessage {
  /// Globally unique message ID (`msg_` prefixed, UUIDv7).
  String get id => throw _privateConstructorUsedError;

  /// Parent conversation ID (`cnv_` prefixed).
  @JsonKey(name: 'conversation_id')
  String get conversationId => throw _privateConstructorUsedError;

  /// Who sent this message.
  ParticipantRef get sender => throw _privateConstructorUsedError;

  /// The message payload (text, structured, or multipart).
  ContentBlock get content => throw _privateConstructorUsedError;

  /// Attached files (may be empty).
  List<Attachment> get attachments => throw _privateConstructorUsedError;

  /// Free-form metadata bag (model name, client message ID, trace IDs, ...).
  Map<String, dynamic> get metadata => throw _privateConstructorUsedError;

  /// Delivery lifecycle status.
  MessageStatus get status => throw _privateConstructorUsedError;

  /// Server-side creation timestamp.
  @JsonKey(name: 'created_at')
  DateTime get createdAt => throw _privateConstructorUsedError;

  /// Serializes this OpenHumanMessage to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of OpenHumanMessage
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $OpenHumanMessageCopyWith<OpenHumanMessage> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $OpenHumanMessageCopyWith<$Res> {
  factory $OpenHumanMessageCopyWith(
          OpenHumanMessage value, $Res Function(OpenHumanMessage) then) =
      _$OpenHumanMessageCopyWithImpl<$Res, OpenHumanMessage>;
  @useResult
  $Res call(
      {String id,
      @JsonKey(name: 'conversation_id') String conversationId,
      ParticipantRef sender,
      ContentBlock content,
      List<Attachment> attachments,
      Map<String, dynamic> metadata,
      MessageStatus status,
      @JsonKey(name: 'created_at') DateTime createdAt});

  $ParticipantRefCopyWith<$Res> get sender;
  $ContentBlockCopyWith<$Res> get content;
}

/// @nodoc
class _$OpenHumanMessageCopyWithImpl<$Res, $Val extends OpenHumanMessage>
    implements $OpenHumanMessageCopyWith<$Res> {
  _$OpenHumanMessageCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of OpenHumanMessage
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? conversationId = null,
    Object? sender = null,
    Object? content = null,
    Object? attachments = null,
    Object? metadata = null,
    Object? status = null,
    Object? createdAt = null,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      conversationId: null == conversationId
          ? _value.conversationId
          : conversationId // ignore: cast_nullable_to_non_nullable
              as String,
      sender: null == sender
          ? _value.sender
          : sender // ignore: cast_nullable_to_non_nullable
              as ParticipantRef,
      content: null == content
          ? _value.content
          : content // ignore: cast_nullable_to_non_nullable
              as ContentBlock,
      attachments: null == attachments
          ? _value.attachments
          : attachments // ignore: cast_nullable_to_non_nullable
              as List<Attachment>,
      metadata: null == metadata
          ? _value.metadata
          : metadata // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as MessageStatus,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ) as $Val);
  }

  /// Create a copy of OpenHumanMessage
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $ParticipantRefCopyWith<$Res> get sender {
    return $ParticipantRefCopyWith<$Res>(_value.sender, (value) {
      return _then(_value.copyWith(sender: value) as $Val);
    });
  }

  /// Create a copy of OpenHumanMessage
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $ContentBlockCopyWith<$Res> get content {
    return $ContentBlockCopyWith<$Res>(_value.content, (value) {
      return _then(_value.copyWith(content: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$OpenHumanMessageImplCopyWith<$Res>
    implements $OpenHumanMessageCopyWith<$Res> {
  factory _$$OpenHumanMessageImplCopyWith(_$OpenHumanMessageImpl value,
          $Res Function(_$OpenHumanMessageImpl) then) =
      __$$OpenHumanMessageImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      @JsonKey(name: 'conversation_id') String conversationId,
      ParticipantRef sender,
      ContentBlock content,
      List<Attachment> attachments,
      Map<String, dynamic> metadata,
      MessageStatus status,
      @JsonKey(name: 'created_at') DateTime createdAt});

  @override
  $ParticipantRefCopyWith<$Res> get sender;
  @override
  $ContentBlockCopyWith<$Res> get content;
}

/// @nodoc
class __$$OpenHumanMessageImplCopyWithImpl<$Res>
    extends _$OpenHumanMessageCopyWithImpl<$Res, _$OpenHumanMessageImpl>
    implements _$$OpenHumanMessageImplCopyWith<$Res> {
  __$$OpenHumanMessageImplCopyWithImpl(_$OpenHumanMessageImpl _value,
      $Res Function(_$OpenHumanMessageImpl) _then)
      : super(_value, _then);

  /// Create a copy of OpenHumanMessage
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? conversationId = null,
    Object? sender = null,
    Object? content = null,
    Object? attachments = null,
    Object? metadata = null,
    Object? status = null,
    Object? createdAt = null,
  }) {
    return _then(_$OpenHumanMessageImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      conversationId: null == conversationId
          ? _value.conversationId
          : conversationId // ignore: cast_nullable_to_non_nullable
              as String,
      sender: null == sender
          ? _value.sender
          : sender // ignore: cast_nullable_to_non_nullable
              as ParticipantRef,
      content: null == content
          ? _value.content
          : content // ignore: cast_nullable_to_non_nullable
              as ContentBlock,
      attachments: null == attachments
          ? _value._attachments
          : attachments // ignore: cast_nullable_to_non_nullable
              as List<Attachment>,
      metadata: null == metadata
          ? _value._metadata
          : metadata // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as MessageStatus,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$OpenHumanMessageImpl implements _OpenHumanMessage {
  const _$OpenHumanMessageImpl(
      {required this.id,
      @JsonKey(name: 'conversation_id') required this.conversationId,
      required this.sender,
      required this.content,
      final List<Attachment> attachments = const <Attachment>[],
      final Map<String, dynamic> metadata = const <String, dynamic>{},
      required this.status,
      @JsonKey(name: 'created_at') required this.createdAt})
      : _attachments = attachments,
        _metadata = metadata;

  factory _$OpenHumanMessageImpl.fromJson(Map<String, dynamic> json) =>
      _$$OpenHumanMessageImplFromJson(json);

  /// Globally unique message ID (`msg_` prefixed, UUIDv7).
  @override
  final String id;

  /// Parent conversation ID (`cnv_` prefixed).
  @override
  @JsonKey(name: 'conversation_id')
  final String conversationId;

  /// Who sent this message.
  @override
  final ParticipantRef sender;

  /// The message payload (text, structured, or multipart).
  @override
  final ContentBlock content;

  /// Attached files (may be empty).
  final List<Attachment> _attachments;

  /// Attached files (may be empty).
  @override
  @JsonKey()
  List<Attachment> get attachments {
    if (_attachments is EqualUnmodifiableListView) return _attachments;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_attachments);
  }

  /// Free-form metadata bag (model name, client message ID, trace IDs, ...).
  final Map<String, dynamic> _metadata;

  /// Free-form metadata bag (model name, client message ID, trace IDs, ...).
  @override
  @JsonKey()
  Map<String, dynamic> get metadata {
    if (_metadata is EqualUnmodifiableMapView) return _metadata;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_metadata);
  }

  /// Delivery lifecycle status.
  @override
  final MessageStatus status;

  /// Server-side creation timestamp.
  @override
  @JsonKey(name: 'created_at')
  final DateTime createdAt;

  @override
  String toString() {
    return 'OpenHumanMessage(id: $id, conversationId: $conversationId, sender: $sender, content: $content, attachments: $attachments, metadata: $metadata, status: $status, createdAt: $createdAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$OpenHumanMessageImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.conversationId, conversationId) ||
                other.conversationId == conversationId) &&
            (identical(other.sender, sender) || other.sender == sender) &&
            (identical(other.content, content) || other.content == content) &&
            const DeepCollectionEquality()
                .equals(other._attachments, _attachments) &&
            const DeepCollectionEquality().equals(other._metadata, _metadata) &&
            (identical(other.status, status) || other.status == status) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      conversationId,
      sender,
      content,
      const DeepCollectionEquality().hash(_attachments),
      const DeepCollectionEquality().hash(_metadata),
      status,
      createdAt);

  /// Create a copy of OpenHumanMessage
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$OpenHumanMessageImplCopyWith<_$OpenHumanMessageImpl> get copyWith =>
      __$$OpenHumanMessageImplCopyWithImpl<_$OpenHumanMessageImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$OpenHumanMessageImplToJson(
      this,
    );
  }
}

abstract class _OpenHumanMessage implements OpenHumanMessage {
  const factory _OpenHumanMessage(
      {required final String id,
      @JsonKey(name: 'conversation_id') required final String conversationId,
      required final ParticipantRef sender,
      required final ContentBlock content,
      final List<Attachment> attachments,
      final Map<String, dynamic> metadata,
      required final MessageStatus status,
      @JsonKey(name: 'created_at')
      required final DateTime createdAt}) = _$OpenHumanMessageImpl;

  factory _OpenHumanMessage.fromJson(Map<String, dynamic> json) =
      _$OpenHumanMessageImpl.fromJson;

  /// Globally unique message ID (`msg_` prefixed, UUIDv7).
  @override
  String get id;

  /// Parent conversation ID (`cnv_` prefixed).
  @override
  @JsonKey(name: 'conversation_id')
  String get conversationId;

  /// Who sent this message.
  @override
  ParticipantRef get sender;

  /// The message payload (text, structured, or multipart).
  @override
  ContentBlock get content;

  /// Attached files (may be empty).
  @override
  List<Attachment> get attachments;

  /// Free-form metadata bag (model name, client message ID, trace IDs, ...).
  @override
  Map<String, dynamic> get metadata;

  /// Delivery lifecycle status.
  @override
  MessageStatus get status;

  /// Server-side creation timestamp.
  @override
  @JsonKey(name: 'created_at')
  DateTime get createdAt;

  /// Create a copy of OpenHumanMessage
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$OpenHumanMessageImplCopyWith<_$OpenHumanMessageImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
