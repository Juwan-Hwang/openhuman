// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'events.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

OpenHumanEvent _$OpenHumanEventFromJson(Map<String, dynamic> json) {
  return _OpenHumanEvent.fromJson(json);
}

/// @nodoc
mixin _$OpenHumanEvent {
  /// Unique event ID (UUIDv7, `evt_` prefixed).
  ///
  /// Used for client-side deduplication (at-least-once delivery).
  @JsonKey(name: 'event_id')
  String get eventId => throw _privateConstructorUsedError;

  /// Event type string (e.g., `"message.received"`).
  ///
  /// Use [EventTypeX.fromWireName] to parse into [EventType].
  @JsonKey(name: 'event_type')
  String get eventType => throw _privateConstructorUsedError;

  /// Conversation ID this event belongs to.
  @JsonKey(name: 'conversation_id')
  String get conversationId => throw _privateConstructorUsedError;

  /// Server-side event timestamp (ISO 8601, millisecond precision).
  DateTime get timestamp => throw _privateConstructorUsedError;

  /// Event-specific payload. Structure depends on [eventType].
  ///
  /// For typed access, parse this into the corresponding data class
  /// (e.g., [MessageReceivedData.fromJson] for `message.received`).
  Map<String, dynamic> get data => throw _privateConstructorUsedError;

  /// Serializes this OpenHumanEvent to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of OpenHumanEvent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $OpenHumanEventCopyWith<OpenHumanEvent> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $OpenHumanEventCopyWith<$Res> {
  factory $OpenHumanEventCopyWith(
          OpenHumanEvent value, $Res Function(OpenHumanEvent) then) =
      _$OpenHumanEventCopyWithImpl<$Res, OpenHumanEvent>;
  @useResult
  $Res call(
      {@JsonKey(name: 'event_id') String eventId,
      @JsonKey(name: 'event_type') String eventType,
      @JsonKey(name: 'conversation_id') String conversationId,
      DateTime timestamp,
      Map<String, dynamic> data});
}

/// @nodoc
class _$OpenHumanEventCopyWithImpl<$Res, $Val extends OpenHumanEvent>
    implements $OpenHumanEventCopyWith<$Res> {
  _$OpenHumanEventCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of OpenHumanEvent
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? eventId = null,
    Object? eventType = null,
    Object? conversationId = null,
    Object? timestamp = null,
    Object? data = null,
  }) {
    return _then(_value.copyWith(
      eventId: null == eventId
          ? _value.eventId
          : eventId // ignore: cast_nullable_to_non_nullable
              as String,
      eventType: null == eventType
          ? _value.eventType
          : eventType // ignore: cast_nullable_to_non_nullable
              as String,
      conversationId: null == conversationId
          ? _value.conversationId
          : conversationId // ignore: cast_nullable_to_non_nullable
              as String,
      timestamp: null == timestamp
          ? _value.timestamp
          : timestamp // ignore: cast_nullable_to_non_nullable
              as DateTime,
      data: null == data
          ? _value.data
          : data // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$OpenHumanEventImplCopyWith<$Res>
    implements $OpenHumanEventCopyWith<$Res> {
  factory _$$OpenHumanEventImplCopyWith(_$OpenHumanEventImpl value,
          $Res Function(_$OpenHumanEventImpl) then) =
      __$$OpenHumanEventImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {@JsonKey(name: 'event_id') String eventId,
      @JsonKey(name: 'event_type') String eventType,
      @JsonKey(name: 'conversation_id') String conversationId,
      DateTime timestamp,
      Map<String, dynamic> data});
}

/// @nodoc
class __$$OpenHumanEventImplCopyWithImpl<$Res>
    extends _$OpenHumanEventCopyWithImpl<$Res, _$OpenHumanEventImpl>
    implements _$$OpenHumanEventImplCopyWith<$Res> {
  __$$OpenHumanEventImplCopyWithImpl(
      _$OpenHumanEventImpl _value, $Res Function(_$OpenHumanEventImpl) _then)
      : super(_value, _then);

  /// Create a copy of OpenHumanEvent
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? eventId = null,
    Object? eventType = null,
    Object? conversationId = null,
    Object? timestamp = null,
    Object? data = null,
  }) {
    return _then(_$OpenHumanEventImpl(
      eventId: null == eventId
          ? _value.eventId
          : eventId // ignore: cast_nullable_to_non_nullable
              as String,
      eventType: null == eventType
          ? _value.eventType
          : eventType // ignore: cast_nullable_to_non_nullable
              as String,
      conversationId: null == conversationId
          ? _value.conversationId
          : conversationId // ignore: cast_nullable_to_non_nullable
              as String,
      timestamp: null == timestamp
          ? _value.timestamp
          : timestamp // ignore: cast_nullable_to_non_nullable
              as DateTime,
      data: null == data
          ? _value._data
          : data // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$OpenHumanEventImpl implements _OpenHumanEvent {
  const _$OpenHumanEventImpl(
      {@JsonKey(name: 'event_id') required this.eventId,
      @JsonKey(name: 'event_type') required this.eventType,
      @JsonKey(name: 'conversation_id') required this.conversationId,
      required this.timestamp,
      required final Map<String, dynamic> data})
      : _data = data;

  factory _$OpenHumanEventImpl.fromJson(Map<String, dynamic> json) =>
      _$$OpenHumanEventImplFromJson(json);

  /// Unique event ID (UUIDv7, `evt_` prefixed).
  ///
  /// Used for client-side deduplication (at-least-once delivery).
  @override
  @JsonKey(name: 'event_id')
  final String eventId;

  /// Event type string (e.g., `"message.received"`).
  ///
  /// Use [EventTypeX.fromWireName] to parse into [EventType].
  @override
  @JsonKey(name: 'event_type')
  final String eventType;

  /// Conversation ID this event belongs to.
  @override
  @JsonKey(name: 'conversation_id')
  final String conversationId;

  /// Server-side event timestamp (ISO 8601, millisecond precision).
  @override
  final DateTime timestamp;

  /// Event-specific payload. Structure depends on [eventType].
  ///
  /// For typed access, parse this into the corresponding data class
  /// (e.g., [MessageReceivedData.fromJson] for `message.received`).
  final Map<String, dynamic> _data;

  /// Event-specific payload. Structure depends on [eventType].
  ///
  /// For typed access, parse this into the corresponding data class
  /// (e.g., [MessageReceivedData.fromJson] for `message.received`).
  @override
  Map<String, dynamic> get data {
    if (_data is EqualUnmodifiableMapView) return _data;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_data);
  }

  @override
  String toString() {
    return 'OpenHumanEvent(eventId: $eventId, eventType: $eventType, conversationId: $conversationId, timestamp: $timestamp, data: $data)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$OpenHumanEventImpl &&
            (identical(other.eventId, eventId) || other.eventId == eventId) &&
            (identical(other.eventType, eventType) ||
                other.eventType == eventType) &&
            (identical(other.conversationId, conversationId) ||
                other.conversationId == conversationId) &&
            (identical(other.timestamp, timestamp) ||
                other.timestamp == timestamp) &&
            const DeepCollectionEquality().equals(other._data, _data));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, eventId, eventType,
      conversationId, timestamp, const DeepCollectionEquality().hash(_data));

  /// Create a copy of OpenHumanEvent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$OpenHumanEventImplCopyWith<_$OpenHumanEventImpl> get copyWith =>
      __$$OpenHumanEventImplCopyWithImpl<_$OpenHumanEventImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$OpenHumanEventImplToJson(
      this,
    );
  }
}

abstract class _OpenHumanEvent implements OpenHumanEvent {
  const factory _OpenHumanEvent(
      {@JsonKey(name: 'event_id') required final String eventId,
      @JsonKey(name: 'event_type') required final String eventType,
      @JsonKey(name: 'conversation_id') required final String conversationId,
      required final DateTime timestamp,
      required final Map<String, dynamic> data}) = _$OpenHumanEventImpl;

  factory _OpenHumanEvent.fromJson(Map<String, dynamic> json) =
      _$OpenHumanEventImpl.fromJson;

  /// Unique event ID (UUIDv7, `evt_` prefixed).
  ///
  /// Used for client-side deduplication (at-least-once delivery).
  @override
  @JsonKey(name: 'event_id')
  String get eventId;

  /// Event type string (e.g., `"message.received"`).
  ///
  /// Use [EventTypeX.fromWireName] to parse into [EventType].
  @override
  @JsonKey(name: 'event_type')
  String get eventType;

  /// Conversation ID this event belongs to.
  @override
  @JsonKey(name: 'conversation_id')
  String get conversationId;

  /// Server-side event timestamp (ISO 8601, millisecond precision).
  @override
  DateTime get timestamp;

  /// Event-specific payload. Structure depends on [eventType].
  ///
  /// For typed access, parse this into the corresponding data class
  /// (e.g., [MessageReceivedData.fromJson] for `message.received`).
  @override
  Map<String, dynamic> get data;

  /// Create a copy of OpenHumanEvent
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$OpenHumanEventImplCopyWith<_$OpenHumanEventImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

SessionConnectedData _$SessionConnectedDataFromJson(Map<String, dynamic> json) {
  return _SessionConnectedData.fromJson(json);
}

/// @nodoc
mixin _$SessionConnectedData {
  /// The authenticated human's ID.
  @JsonKey(name: 'human_id')
  String get humanId => throw _privateConstructorUsedError;

  /// The human's display name.
  @JsonKey(name: 'display_name')
  String get displayName => throw _privateConstructorUsedError;

  /// Serializes this SessionConnectedData to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of SessionConnectedData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SessionConnectedDataCopyWith<SessionConnectedData> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SessionConnectedDataCopyWith<$Res> {
  factory $SessionConnectedDataCopyWith(SessionConnectedData value,
          $Res Function(SessionConnectedData) then) =
      _$SessionConnectedDataCopyWithImpl<$Res, SessionConnectedData>;
  @useResult
  $Res call(
      {@JsonKey(name: 'human_id') String humanId,
      @JsonKey(name: 'display_name') String displayName});
}

/// @nodoc
class _$SessionConnectedDataCopyWithImpl<$Res,
        $Val extends SessionConnectedData>
    implements $SessionConnectedDataCopyWith<$Res> {
  _$SessionConnectedDataCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SessionConnectedData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? humanId = null,
    Object? displayName = null,
  }) {
    return _then(_value.copyWith(
      humanId: null == humanId
          ? _value.humanId
          : humanId // ignore: cast_nullable_to_non_nullable
              as String,
      displayName: null == displayName
          ? _value.displayName
          : displayName // ignore: cast_nullable_to_non_nullable
              as String,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$SessionConnectedDataImplCopyWith<$Res>
    implements $SessionConnectedDataCopyWith<$Res> {
  factory _$$SessionConnectedDataImplCopyWith(_$SessionConnectedDataImpl value,
          $Res Function(_$SessionConnectedDataImpl) then) =
      __$$SessionConnectedDataImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {@JsonKey(name: 'human_id') String humanId,
      @JsonKey(name: 'display_name') String displayName});
}

/// @nodoc
class __$$SessionConnectedDataImplCopyWithImpl<$Res>
    extends _$SessionConnectedDataCopyWithImpl<$Res, _$SessionConnectedDataImpl>
    implements _$$SessionConnectedDataImplCopyWith<$Res> {
  __$$SessionConnectedDataImplCopyWithImpl(_$SessionConnectedDataImpl _value,
      $Res Function(_$SessionConnectedDataImpl) _then)
      : super(_value, _then);

  /// Create a copy of SessionConnectedData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? humanId = null,
    Object? displayName = null,
  }) {
    return _then(_$SessionConnectedDataImpl(
      humanId: null == humanId
          ? _value.humanId
          : humanId // ignore: cast_nullable_to_non_nullable
              as String,
      displayName: null == displayName
          ? _value.displayName
          : displayName // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$SessionConnectedDataImpl implements _SessionConnectedData {
  const _$SessionConnectedDataImpl(
      {@JsonKey(name: 'human_id') required this.humanId,
      @JsonKey(name: 'display_name') required this.displayName});

  factory _$SessionConnectedDataImpl.fromJson(Map<String, dynamic> json) =>
      _$$SessionConnectedDataImplFromJson(json);

  /// The authenticated human's ID.
  @override
  @JsonKey(name: 'human_id')
  final String humanId;

  /// The human's display name.
  @override
  @JsonKey(name: 'display_name')
  final String displayName;

  @override
  String toString() {
    return 'SessionConnectedData(humanId: $humanId, displayName: $displayName)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SessionConnectedDataImpl &&
            (identical(other.humanId, humanId) || other.humanId == humanId) &&
            (identical(other.displayName, displayName) ||
                other.displayName == displayName));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, humanId, displayName);

  /// Create a copy of SessionConnectedData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SessionConnectedDataImplCopyWith<_$SessionConnectedDataImpl>
      get copyWith =>
          __$$SessionConnectedDataImplCopyWithImpl<_$SessionConnectedDataImpl>(
              this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$SessionConnectedDataImplToJson(
      this,
    );
  }
}

abstract class _SessionConnectedData implements SessionConnectedData {
  const factory _SessionConnectedData(
          {@JsonKey(name: 'human_id') required final String humanId,
          @JsonKey(name: 'display_name') required final String displayName}) =
      _$SessionConnectedDataImpl;

  factory _SessionConnectedData.fromJson(Map<String, dynamic> json) =
      _$SessionConnectedDataImpl.fromJson;

  /// The authenticated human's ID.
  @override
  @JsonKey(name: 'human_id')
  String get humanId;

  /// The human's display name.
  @override
  @JsonKey(name: 'display_name')
  String get displayName;

  /// Create a copy of SessionConnectedData
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SessionConnectedDataImplCopyWith<_$SessionConnectedDataImpl>
      get copyWith => throw _privateConstructorUsedError;
}

MessageReceivedData _$MessageReceivedDataFromJson(Map<String, dynamic> json) {
  return _MessageReceivedData.fromJson(json);
}

/// @nodoc
mixin _$MessageReceivedData {
  /// The conversation this message belongs to (`cnv_` prefixed).
  @JsonKey(name: 'conversation_id')
  String get conversationId => throw _privateConstructorUsedError;

  /// Unique message ID (`msg_` prefixed).
  @JsonKey(name: 'message_id')
  String get messageId => throw _privateConstructorUsedError;

  /// The sender's participant ID (`agt_xxx` for agents).
  @JsonKey(name: 'sender_id')
  String get senderId => throw _privateConstructorUsedError;

  /// The sender's participant type (`"agent"` or `"human"`).
  @JsonKey(name: 'sender_type')
  String get senderType => throw _privateConstructorUsedError;

  /// The sender's display name (optional — for UI rendering).
  @JsonKey(name: 'sender_name')
  String? get senderName => throw _privateConstructorUsedError;

  /// The message text content.
  String get text => throw _privateConstructorUsedError;

  /// Image references attached to the message (`http(s)` or
  /// `data:image/...;base64,` URLs).
  ///
  /// Present when the agent sent vision input. Absent for plain text, so
  /// existing consumers are unaffected.
  List<String> get images => throw _privateConstructorUsedError;

  /// Serializes this MessageReceivedData to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of MessageReceivedData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $MessageReceivedDataCopyWith<MessageReceivedData> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $MessageReceivedDataCopyWith<$Res> {
  factory $MessageReceivedDataCopyWith(
          MessageReceivedData value, $Res Function(MessageReceivedData) then) =
      _$MessageReceivedDataCopyWithImpl<$Res, MessageReceivedData>;
  @useResult
  $Res call(
      {@JsonKey(name: 'conversation_id') String conversationId,
      @JsonKey(name: 'message_id') String messageId,
      @JsonKey(name: 'sender_id') String senderId,
      @JsonKey(name: 'sender_type') String senderType,
      @JsonKey(name: 'sender_name') String? senderName,
      String text,
      List<String> images});
}

/// @nodoc
class _$MessageReceivedDataCopyWithImpl<$Res, $Val extends MessageReceivedData>
    implements $MessageReceivedDataCopyWith<$Res> {
  _$MessageReceivedDataCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of MessageReceivedData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? conversationId = null,
    Object? messageId = null,
    Object? senderId = null,
    Object? senderType = null,
    Object? senderName = freezed,
    Object? text = null,
    Object? images = null,
  }) {
    return _then(_value.copyWith(
      conversationId: null == conversationId
          ? _value.conversationId
          : conversationId // ignore: cast_nullable_to_non_nullable
              as String,
      messageId: null == messageId
          ? _value.messageId
          : messageId // ignore: cast_nullable_to_non_nullable
              as String,
      senderId: null == senderId
          ? _value.senderId
          : senderId // ignore: cast_nullable_to_non_nullable
              as String,
      senderType: null == senderType
          ? _value.senderType
          : senderType // ignore: cast_nullable_to_non_nullable
              as String,
      senderName: freezed == senderName
          ? _value.senderName
          : senderName // ignore: cast_nullable_to_non_nullable
              as String?,
      text: null == text
          ? _value.text
          : text // ignore: cast_nullable_to_non_nullable
              as String,
      images: null == images
          ? _value.images
          : images // ignore: cast_nullable_to_non_nullable
              as List<String>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$MessageReceivedDataImplCopyWith<$Res>
    implements $MessageReceivedDataCopyWith<$Res> {
  factory _$$MessageReceivedDataImplCopyWith(_$MessageReceivedDataImpl value,
          $Res Function(_$MessageReceivedDataImpl) then) =
      __$$MessageReceivedDataImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {@JsonKey(name: 'conversation_id') String conversationId,
      @JsonKey(name: 'message_id') String messageId,
      @JsonKey(name: 'sender_id') String senderId,
      @JsonKey(name: 'sender_type') String senderType,
      @JsonKey(name: 'sender_name') String? senderName,
      String text,
      List<String> images});
}

/// @nodoc
class __$$MessageReceivedDataImplCopyWithImpl<$Res>
    extends _$MessageReceivedDataCopyWithImpl<$Res, _$MessageReceivedDataImpl>
    implements _$$MessageReceivedDataImplCopyWith<$Res> {
  __$$MessageReceivedDataImplCopyWithImpl(_$MessageReceivedDataImpl _value,
      $Res Function(_$MessageReceivedDataImpl) _then)
      : super(_value, _then);

  /// Create a copy of MessageReceivedData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? conversationId = null,
    Object? messageId = null,
    Object? senderId = null,
    Object? senderType = null,
    Object? senderName = freezed,
    Object? text = null,
    Object? images = null,
  }) {
    return _then(_$MessageReceivedDataImpl(
      conversationId: null == conversationId
          ? _value.conversationId
          : conversationId // ignore: cast_nullable_to_non_nullable
              as String,
      messageId: null == messageId
          ? _value.messageId
          : messageId // ignore: cast_nullable_to_non_nullable
              as String,
      senderId: null == senderId
          ? _value.senderId
          : senderId // ignore: cast_nullable_to_non_nullable
              as String,
      senderType: null == senderType
          ? _value.senderType
          : senderType // ignore: cast_nullable_to_non_nullable
              as String,
      senderName: freezed == senderName
          ? _value.senderName
          : senderName // ignore: cast_nullable_to_non_nullable
              as String?,
      text: null == text
          ? _value.text
          : text // ignore: cast_nullable_to_non_nullable
              as String,
      images: null == images
          ? _value._images
          : images // ignore: cast_nullable_to_non_nullable
              as List<String>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$MessageReceivedDataImpl implements _MessageReceivedData {
  const _$MessageReceivedDataImpl(
      {@JsonKey(name: 'conversation_id') required this.conversationId,
      @JsonKey(name: 'message_id') required this.messageId,
      @JsonKey(name: 'sender_id') required this.senderId,
      @JsonKey(name: 'sender_type') required this.senderType,
      @JsonKey(name: 'sender_name') this.senderName,
      required this.text,
      final List<String> images = const <String>[]})
      : _images = images;

  factory _$MessageReceivedDataImpl.fromJson(Map<String, dynamic> json) =>
      _$$MessageReceivedDataImplFromJson(json);

  /// The conversation this message belongs to (`cnv_` prefixed).
  @override
  @JsonKey(name: 'conversation_id')
  final String conversationId;

  /// Unique message ID (`msg_` prefixed).
  @override
  @JsonKey(name: 'message_id')
  final String messageId;

  /// The sender's participant ID (`agt_xxx` for agents).
  @override
  @JsonKey(name: 'sender_id')
  final String senderId;

  /// The sender's participant type (`"agent"` or `"human"`).
  @override
  @JsonKey(name: 'sender_type')
  final String senderType;

  /// The sender's display name (optional — for UI rendering).
  @override
  @JsonKey(name: 'sender_name')
  final String? senderName;

  /// The message text content.
  @override
  final String text;

  /// Image references attached to the message (`http(s)` or
  /// `data:image/...;base64,` URLs).
  ///
  /// Present when the agent sent vision input. Absent for plain text, so
  /// existing consumers are unaffected.
  final List<String> _images;

  /// Image references attached to the message (`http(s)` or
  /// `data:image/...;base64,` URLs).
  ///
  /// Present when the agent sent vision input. Absent for plain text, so
  /// existing consumers are unaffected.
  @override
  @JsonKey()
  List<String> get images {
    if (_images is EqualUnmodifiableListView) return _images;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_images);
  }

  @override
  String toString() {
    return 'MessageReceivedData(conversationId: $conversationId, messageId: $messageId, senderId: $senderId, senderType: $senderType, senderName: $senderName, text: $text, images: $images)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MessageReceivedDataImpl &&
            (identical(other.conversationId, conversationId) ||
                other.conversationId == conversationId) &&
            (identical(other.messageId, messageId) ||
                other.messageId == messageId) &&
            (identical(other.senderId, senderId) ||
                other.senderId == senderId) &&
            (identical(other.senderType, senderType) ||
                other.senderType == senderType) &&
            (identical(other.senderName, senderName) ||
                other.senderName == senderName) &&
            (identical(other.text, text) || other.text == text) &&
            const DeepCollectionEquality().equals(other._images, _images));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      conversationId,
      messageId,
      senderId,
      senderType,
      senderName,
      text,
      const DeepCollectionEquality().hash(_images));

  /// Create a copy of MessageReceivedData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$MessageReceivedDataImplCopyWith<_$MessageReceivedDataImpl> get copyWith =>
      __$$MessageReceivedDataImplCopyWithImpl<_$MessageReceivedDataImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$MessageReceivedDataImplToJson(
      this,
    );
  }
}

abstract class _MessageReceivedData implements MessageReceivedData {
  const factory _MessageReceivedData(
      {@JsonKey(name: 'conversation_id') required final String conversationId,
      @JsonKey(name: 'message_id') required final String messageId,
      @JsonKey(name: 'sender_id') required final String senderId,
      @JsonKey(name: 'sender_type') required final String senderType,
      @JsonKey(name: 'sender_name') final String? senderName,
      required final String text,
      final List<String> images}) = _$MessageReceivedDataImpl;

  factory _MessageReceivedData.fromJson(Map<String, dynamic> json) =
      _$MessageReceivedDataImpl.fromJson;

  /// The conversation this message belongs to (`cnv_` prefixed).
  @override
  @JsonKey(name: 'conversation_id')
  String get conversationId;

  /// Unique message ID (`msg_` prefixed).
  @override
  @JsonKey(name: 'message_id')
  String get messageId;

  /// The sender's participant ID (`agt_xxx` for agents).
  @override
  @JsonKey(name: 'sender_id')
  String get senderId;

  /// The sender's participant type (`"agent"` or `"human"`).
  @override
  @JsonKey(name: 'sender_type')
  String get senderType;

  /// The sender's display name (optional — for UI rendering).
  @override
  @JsonKey(name: 'sender_name')
  String? get senderName;

  /// The message text content.
  @override
  String get text;

  /// Image references attached to the message (`http(s)` or
  /// `data:image/...;base64,` URLs).
  ///
  /// Present when the agent sent vision input. Absent for plain text, so
  /// existing consumers are unaffected.
  @override
  List<String> get images;

  /// Create a copy of MessageReceivedData
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$MessageReceivedDataImplCopyWith<_$MessageReceivedDataImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

ReplyDeliveredData _$ReplyDeliveredDataFromJson(Map<String, dynamic> json) {
  return _ReplyDeliveredData.fromJson(json);
}

/// @nodoc
mixin _$ReplyDeliveredData {
  /// Whether the reply was delivered to a waiting SSE handler.
  bool get delivered => throw _privateConstructorUsedError;

  /// Serializes this ReplyDeliveredData to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of ReplyDeliveredData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ReplyDeliveredDataCopyWith<ReplyDeliveredData> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ReplyDeliveredDataCopyWith<$Res> {
  factory $ReplyDeliveredDataCopyWith(
          ReplyDeliveredData value, $Res Function(ReplyDeliveredData) then) =
      _$ReplyDeliveredDataCopyWithImpl<$Res, ReplyDeliveredData>;
  @useResult
  $Res call({bool delivered});
}

/// @nodoc
class _$ReplyDeliveredDataCopyWithImpl<$Res, $Val extends ReplyDeliveredData>
    implements $ReplyDeliveredDataCopyWith<$Res> {
  _$ReplyDeliveredDataCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ReplyDeliveredData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? delivered = null,
  }) {
    return _then(_value.copyWith(
      delivered: null == delivered
          ? _value.delivered
          : delivered // ignore: cast_nullable_to_non_nullable
              as bool,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ReplyDeliveredDataImplCopyWith<$Res>
    implements $ReplyDeliveredDataCopyWith<$Res> {
  factory _$$ReplyDeliveredDataImplCopyWith(_$ReplyDeliveredDataImpl value,
          $Res Function(_$ReplyDeliveredDataImpl) then) =
      __$$ReplyDeliveredDataImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({bool delivered});
}

/// @nodoc
class __$$ReplyDeliveredDataImplCopyWithImpl<$Res>
    extends _$ReplyDeliveredDataCopyWithImpl<$Res, _$ReplyDeliveredDataImpl>
    implements _$$ReplyDeliveredDataImplCopyWith<$Res> {
  __$$ReplyDeliveredDataImplCopyWithImpl(_$ReplyDeliveredDataImpl _value,
      $Res Function(_$ReplyDeliveredDataImpl) _then)
      : super(_value, _then);

  /// Create a copy of ReplyDeliveredData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? delivered = null,
  }) {
    return _then(_$ReplyDeliveredDataImpl(
      delivered: null == delivered
          ? _value.delivered
          : delivered // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ReplyDeliveredDataImpl implements _ReplyDeliveredData {
  const _$ReplyDeliveredDataImpl({required this.delivered});

  factory _$ReplyDeliveredDataImpl.fromJson(Map<String, dynamic> json) =>
      _$$ReplyDeliveredDataImplFromJson(json);

  /// Whether the reply was delivered to a waiting SSE handler.
  @override
  final bool delivered;

  @override
  String toString() {
    return 'ReplyDeliveredData(delivered: $delivered)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ReplyDeliveredDataImpl &&
            (identical(other.delivered, delivered) ||
                other.delivered == delivered));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, delivered);

  /// Create a copy of ReplyDeliveredData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ReplyDeliveredDataImplCopyWith<_$ReplyDeliveredDataImpl> get copyWith =>
      __$$ReplyDeliveredDataImplCopyWithImpl<_$ReplyDeliveredDataImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ReplyDeliveredDataImplToJson(
      this,
    );
  }
}

abstract class _ReplyDeliveredData implements ReplyDeliveredData {
  const factory _ReplyDeliveredData({required final bool delivered}) =
      _$ReplyDeliveredDataImpl;

  factory _ReplyDeliveredData.fromJson(Map<String, dynamic> json) =
      _$ReplyDeliveredDataImpl.fromJson;

  /// Whether the reply was delivered to a waiting SSE handler.
  @override
  bool get delivered;

  /// Create a copy of ReplyDeliveredData
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ReplyDeliveredDataImplCopyWith<_$ReplyDeliveredDataImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

CapabilityUpdatedData _$CapabilityUpdatedDataFromJson(
    Map<String, dynamic> json) {
  return _CapabilityUpdatedData.fromJson(json);
}

/// @nodoc
mixin _$CapabilityUpdatedData {
  /// The agent whose capabilities changed.
  @JsonKey(name: 'agent_id')
  String get agentId => throw _privateConstructorUsedError;

  /// Agent's tool list (raw JSON — see `capabilities.dart` for typed model).
  ///
  /// Each element has the shape:
  /// ```json
  /// {
  ///   "id": "github_create_issue",
  ///   "name": "Create GitHub Issue",
  ///   "description": "...",
  ///   "category": "github",
  ///   "input_schema": { ... },
  ///   "output_schema": { ... },
  ///   "ui_schema": { ... },
  ///   "permissions": ["..."],
  ///   "metadata": {}
  /// }
  /// ```
  @JsonKey(name: 'capabilities')
  List<Map<String, dynamic>> get capabilities =>
      throw _privateConstructorUsedError;

  /// Agent's runtime context (raw JSON — may be `null`).
  @JsonKey(name: 'context')
  Map<String, dynamic>? get context => throw _privateConstructorUsedError;

  /// Serializes this CapabilityUpdatedData to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of CapabilityUpdatedData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $CapabilityUpdatedDataCopyWith<CapabilityUpdatedData> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $CapabilityUpdatedDataCopyWith<$Res> {
  factory $CapabilityUpdatedDataCopyWith(CapabilityUpdatedData value,
          $Res Function(CapabilityUpdatedData) then) =
      _$CapabilityUpdatedDataCopyWithImpl<$Res, CapabilityUpdatedData>;
  @useResult
  $Res call(
      {@JsonKey(name: 'agent_id') String agentId,
      @JsonKey(name: 'capabilities') List<Map<String, dynamic>> capabilities,
      @JsonKey(name: 'context') Map<String, dynamic>? context});
}

/// @nodoc
class _$CapabilityUpdatedDataCopyWithImpl<$Res,
        $Val extends CapabilityUpdatedData>
    implements $CapabilityUpdatedDataCopyWith<$Res> {
  _$CapabilityUpdatedDataCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of CapabilityUpdatedData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? agentId = null,
    Object? capabilities = null,
    Object? context = freezed,
  }) {
    return _then(_value.copyWith(
      agentId: null == agentId
          ? _value.agentId
          : agentId // ignore: cast_nullable_to_non_nullable
              as String,
      capabilities: null == capabilities
          ? _value.capabilities
          : capabilities // ignore: cast_nullable_to_non_nullable
              as List<Map<String, dynamic>>,
      context: freezed == context
          ? _value.context
          : context // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$CapabilityUpdatedDataImplCopyWith<$Res>
    implements $CapabilityUpdatedDataCopyWith<$Res> {
  factory _$$CapabilityUpdatedDataImplCopyWith(
          _$CapabilityUpdatedDataImpl value,
          $Res Function(_$CapabilityUpdatedDataImpl) then) =
      __$$CapabilityUpdatedDataImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {@JsonKey(name: 'agent_id') String agentId,
      @JsonKey(name: 'capabilities') List<Map<String, dynamic>> capabilities,
      @JsonKey(name: 'context') Map<String, dynamic>? context});
}

/// @nodoc
class __$$CapabilityUpdatedDataImplCopyWithImpl<$Res>
    extends _$CapabilityUpdatedDataCopyWithImpl<$Res,
        _$CapabilityUpdatedDataImpl>
    implements _$$CapabilityUpdatedDataImplCopyWith<$Res> {
  __$$CapabilityUpdatedDataImplCopyWithImpl(_$CapabilityUpdatedDataImpl _value,
      $Res Function(_$CapabilityUpdatedDataImpl) _then)
      : super(_value, _then);

  /// Create a copy of CapabilityUpdatedData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? agentId = null,
    Object? capabilities = null,
    Object? context = freezed,
  }) {
    return _then(_$CapabilityUpdatedDataImpl(
      agentId: null == agentId
          ? _value.agentId
          : agentId // ignore: cast_nullable_to_non_nullable
              as String,
      capabilities: null == capabilities
          ? _value._capabilities
          : capabilities // ignore: cast_nullable_to_non_nullable
              as List<Map<String, dynamic>>,
      context: freezed == context
          ? _value._context
          : context // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$CapabilityUpdatedDataImpl implements _CapabilityUpdatedData {
  const _$CapabilityUpdatedDataImpl(
      {@JsonKey(name: 'agent_id') required this.agentId,
      @JsonKey(name: 'capabilities')
      final List<Map<String, dynamic>> capabilities =
          const <Map<String, dynamic>>[],
      @JsonKey(name: 'context') final Map<String, dynamic>? context})
      : _capabilities = capabilities,
        _context = context;

  factory _$CapabilityUpdatedDataImpl.fromJson(Map<String, dynamic> json) =>
      _$$CapabilityUpdatedDataImplFromJson(json);

  /// The agent whose capabilities changed.
  @override
  @JsonKey(name: 'agent_id')
  final String agentId;

  /// Agent's tool list (raw JSON — see `capabilities.dart` for typed model).
  ///
  /// Each element has the shape:
  /// ```json
  /// {
  ///   "id": "github_create_issue",
  ///   "name": "Create GitHub Issue",
  ///   "description": "...",
  ///   "category": "github",
  ///   "input_schema": { ... },
  ///   "output_schema": { ... },
  ///   "ui_schema": { ... },
  ///   "permissions": ["..."],
  ///   "metadata": {}
  /// }
  /// ```
  final List<Map<String, dynamic>> _capabilities;

  /// Agent's tool list (raw JSON — see `capabilities.dart` for typed model).
  ///
  /// Each element has the shape:
  /// ```json
  /// {
  ///   "id": "github_create_issue",
  ///   "name": "Create GitHub Issue",
  ///   "description": "...",
  ///   "category": "github",
  ///   "input_schema": { ... },
  ///   "output_schema": { ... },
  ///   "ui_schema": { ... },
  ///   "permissions": ["..."],
  ///   "metadata": {}
  /// }
  /// ```
  @override
  @JsonKey(name: 'capabilities')
  List<Map<String, dynamic>> get capabilities {
    if (_capabilities is EqualUnmodifiableListView) return _capabilities;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_capabilities);
  }

  /// Agent's runtime context (raw JSON — may be `null`).
  final Map<String, dynamic>? _context;

  /// Agent's runtime context (raw JSON — may be `null`).
  @override
  @JsonKey(name: 'context')
  Map<String, dynamic>? get context {
    final value = _context;
    if (value == null) return null;
    if (_context is EqualUnmodifiableMapView) return _context;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(value);
  }

  @override
  String toString() {
    return 'CapabilityUpdatedData(agentId: $agentId, capabilities: $capabilities, context: $context)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$CapabilityUpdatedDataImpl &&
            (identical(other.agentId, agentId) || other.agentId == agentId) &&
            const DeepCollectionEquality()
                .equals(other._capabilities, _capabilities) &&
            const DeepCollectionEquality().equals(other._context, _context));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      agentId,
      const DeepCollectionEquality().hash(_capabilities),
      const DeepCollectionEquality().hash(_context));

  /// Create a copy of CapabilityUpdatedData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$CapabilityUpdatedDataImplCopyWith<_$CapabilityUpdatedDataImpl>
      get copyWith => __$$CapabilityUpdatedDataImplCopyWithImpl<
          _$CapabilityUpdatedDataImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$CapabilityUpdatedDataImplToJson(
      this,
    );
  }
}

abstract class _CapabilityUpdatedData implements CapabilityUpdatedData {
  const factory _CapabilityUpdatedData(
          {@JsonKey(name: 'agent_id') required final String agentId,
          @JsonKey(name: 'capabilities')
          final List<Map<String, dynamic>> capabilities,
          @JsonKey(name: 'context') final Map<String, dynamic>? context}) =
      _$CapabilityUpdatedDataImpl;

  factory _CapabilityUpdatedData.fromJson(Map<String, dynamic> json) =
      _$CapabilityUpdatedDataImpl.fromJson;

  /// The agent whose capabilities changed.
  @override
  @JsonKey(name: 'agent_id')
  String get agentId;

  /// Agent's tool list (raw JSON — see `capabilities.dart` for typed model).
  ///
  /// Each element has the shape:
  /// ```json
  /// {
  ///   "id": "github_create_issue",
  ///   "name": "Create GitHub Issue",
  ///   "description": "...",
  ///   "category": "github",
  ///   "input_schema": { ... },
  ///   "output_schema": { ... },
  ///   "ui_schema": { ... },
  ///   "permissions": ["..."],
  ///   "metadata": {}
  /// }
  /// ```
  @override
  @JsonKey(name: 'capabilities')
  List<Map<String, dynamic>> get capabilities;

  /// Agent's runtime context (raw JSON — may be `null`).
  @override
  @JsonKey(name: 'context')
  Map<String, dynamic>? get context;

  /// Create a copy of CapabilityUpdatedData
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$CapabilityUpdatedDataImplCopyWith<_$CapabilityUpdatedDataImpl>
      get copyWith => throw _privateConstructorUsedError;
}

ToolResultData _$ToolResultDataFromJson(Map<String, dynamic> json) {
  return _ToolResultData.fromJson(json);
}

/// @nodoc
mixin _$ToolResultData {
  /// Correlates to the original `tool.invoke` request.
  @JsonKey(name: 'invocation_id')
  String get invocationId => throw _privateConstructorUsedError;

  /// The tool that was invoked.
  @JsonKey(name: 'tool_id')
  String get toolId => throw _privateConstructorUsedError;

  /// Outcome: `"success"`, `"error"`, `"timeout"`, `"cancelled"`, `"pending"`.
  String get status => throw _privateConstructorUsedError;

  /// Output data (conforming to the tool's `output_schema`).
  /// `null` on error or timeout.
  dynamic get output => throw _privateConstructorUsedError;

  /// Error message if `status` is `"error"`.
  String? get error => throw _privateConstructorUsedError;

  /// Serializes this ToolResultData to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of ToolResultData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ToolResultDataCopyWith<ToolResultData> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ToolResultDataCopyWith<$Res> {
  factory $ToolResultDataCopyWith(
          ToolResultData value, $Res Function(ToolResultData) then) =
      _$ToolResultDataCopyWithImpl<$Res, ToolResultData>;
  @useResult
  $Res call(
      {@JsonKey(name: 'invocation_id') String invocationId,
      @JsonKey(name: 'tool_id') String toolId,
      String status,
      dynamic output,
      String? error});
}

/// @nodoc
class _$ToolResultDataCopyWithImpl<$Res, $Val extends ToolResultData>
    implements $ToolResultDataCopyWith<$Res> {
  _$ToolResultDataCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ToolResultData
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
              as String,
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
abstract class _$$ToolResultDataImplCopyWith<$Res>
    implements $ToolResultDataCopyWith<$Res> {
  factory _$$ToolResultDataImplCopyWith(_$ToolResultDataImpl value,
          $Res Function(_$ToolResultDataImpl) then) =
      __$$ToolResultDataImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {@JsonKey(name: 'invocation_id') String invocationId,
      @JsonKey(name: 'tool_id') String toolId,
      String status,
      dynamic output,
      String? error});
}

/// @nodoc
class __$$ToolResultDataImplCopyWithImpl<$Res>
    extends _$ToolResultDataCopyWithImpl<$Res, _$ToolResultDataImpl>
    implements _$$ToolResultDataImplCopyWith<$Res> {
  __$$ToolResultDataImplCopyWithImpl(
      _$ToolResultDataImpl _value, $Res Function(_$ToolResultDataImpl) _then)
      : super(_value, _then);

  /// Create a copy of ToolResultData
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
    return _then(_$ToolResultDataImpl(
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
              as String,
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
class _$ToolResultDataImpl implements _ToolResultData {
  const _$ToolResultDataImpl(
      {@JsonKey(name: 'invocation_id') required this.invocationId,
      @JsonKey(name: 'tool_id') required this.toolId,
      required this.status,
      this.output,
      this.error});

  factory _$ToolResultDataImpl.fromJson(Map<String, dynamic> json) =>
      _$$ToolResultDataImplFromJson(json);

  /// Correlates to the original `tool.invoke` request.
  @override
  @JsonKey(name: 'invocation_id')
  final String invocationId;

  /// The tool that was invoked.
  @override
  @JsonKey(name: 'tool_id')
  final String toolId;

  /// Outcome: `"success"`, `"error"`, `"timeout"`, `"cancelled"`, `"pending"`.
  @override
  final String status;

  /// Output data (conforming to the tool's `output_schema`).
  /// `null` on error or timeout.
  @override
  final dynamic output;

  /// Error message if `status` is `"error"`.
  @override
  final String? error;

  @override
  String toString() {
    return 'ToolResultData(invocationId: $invocationId, toolId: $toolId, status: $status, output: $output, error: $error)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ToolResultDataImpl &&
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

  /// Create a copy of ToolResultData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ToolResultDataImplCopyWith<_$ToolResultDataImpl> get copyWith =>
      __$$ToolResultDataImplCopyWithImpl<_$ToolResultDataImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ToolResultDataImplToJson(
      this,
    );
  }
}

abstract class _ToolResultData implements ToolResultData {
  const factory _ToolResultData(
      {@JsonKey(name: 'invocation_id') required final String invocationId,
      @JsonKey(name: 'tool_id') required final String toolId,
      required final String status,
      final dynamic output,
      final String? error}) = _$ToolResultDataImpl;

  factory _ToolResultData.fromJson(Map<String, dynamic> json) =
      _$ToolResultDataImpl.fromJson;

  /// Correlates to the original `tool.invoke` request.
  @override
  @JsonKey(name: 'invocation_id')
  String get invocationId;

  /// The tool that was invoked.
  @override
  @JsonKey(name: 'tool_id')
  String get toolId;

  /// Outcome: `"success"`, `"error"`, `"timeout"`, `"cancelled"`, `"pending"`.
  @override
  String get status;

  /// Output data (conforming to the tool's `output_schema`).
  /// `null` on error or timeout.
  @override
  dynamic get output;

  /// Error message if `status` is `"error"`.
  @override
  String? get error;

  /// Create a copy of ToolResultData
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ToolResultDataImplCopyWith<_$ToolResultDataImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

ErrorData _$ErrorDataFromJson(Map<String, dynamic> json) {
  return _ErrorData.fromJson(json);
}

/// @nodoc
mixin _$ErrorData {
  /// Machine-readable error code (e.g., `"tool_not_found"`).
  String get code => throw _privateConstructorUsedError;

  /// Human-readable error message.
  String get message => throw _privateConstructorUsedError;

  /// Serializes this ErrorData to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of ErrorData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ErrorDataCopyWith<ErrorData> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ErrorDataCopyWith<$Res> {
  factory $ErrorDataCopyWith(ErrorData value, $Res Function(ErrorData) then) =
      _$ErrorDataCopyWithImpl<$Res, ErrorData>;
  @useResult
  $Res call({String code, String message});
}

/// @nodoc
class _$ErrorDataCopyWithImpl<$Res, $Val extends ErrorData>
    implements $ErrorDataCopyWith<$Res> {
  _$ErrorDataCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ErrorData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? code = null,
    Object? message = null,
  }) {
    return _then(_value.copyWith(
      code: null == code
          ? _value.code
          : code // ignore: cast_nullable_to_non_nullable
              as String,
      message: null == message
          ? _value.message
          : message // ignore: cast_nullable_to_non_nullable
              as String,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ErrorDataImplCopyWith<$Res>
    implements $ErrorDataCopyWith<$Res> {
  factory _$$ErrorDataImplCopyWith(
          _$ErrorDataImpl value, $Res Function(_$ErrorDataImpl) then) =
      __$$ErrorDataImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String code, String message});
}

/// @nodoc
class __$$ErrorDataImplCopyWithImpl<$Res>
    extends _$ErrorDataCopyWithImpl<$Res, _$ErrorDataImpl>
    implements _$$ErrorDataImplCopyWith<$Res> {
  __$$ErrorDataImplCopyWithImpl(
      _$ErrorDataImpl _value, $Res Function(_$ErrorDataImpl) _then)
      : super(_value, _then);

  /// Create a copy of ErrorData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? code = null,
    Object? message = null,
  }) {
    return _then(_$ErrorDataImpl(
      code: null == code
          ? _value.code
          : code // ignore: cast_nullable_to_non_nullable
              as String,
      message: null == message
          ? _value.message
          : message // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ErrorDataImpl implements _ErrorData {
  const _$ErrorDataImpl({required this.code, required this.message});

  factory _$ErrorDataImpl.fromJson(Map<String, dynamic> json) =>
      _$$ErrorDataImplFromJson(json);

  /// Machine-readable error code (e.g., `"tool_not_found"`).
  @override
  final String code;

  /// Human-readable error message.
  @override
  final String message;

  @override
  String toString() {
    return 'ErrorData(code: $code, message: $message)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ErrorDataImpl &&
            (identical(other.code, code) || other.code == code) &&
            (identical(other.message, message) || other.message == message));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, code, message);

  /// Create a copy of ErrorData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ErrorDataImplCopyWith<_$ErrorDataImpl> get copyWith =>
      __$$ErrorDataImplCopyWithImpl<_$ErrorDataImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ErrorDataImplToJson(
      this,
    );
  }
}

abstract class _ErrorData implements ErrorData {
  const factory _ErrorData(
      {required final String code,
      required final String message}) = _$ErrorDataImpl;

  factory _ErrorData.fromJson(Map<String, dynamic> json) =
      _$ErrorDataImpl.fromJson;

  /// Machine-readable error code (e.g., `"tool_not_found"`).
  @override
  String get code;

  /// Human-readable error message.
  @override
  String get message;

  /// Create a copy of ErrorData
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ErrorDataImplCopyWith<_$ErrorDataImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

AsyncInvocationCreatedData _$AsyncInvocationCreatedDataFromJson(
    Map<String, dynamic> json) {
  return _AsyncInvocationCreatedData.fromJson(json);
}

/// @nodoc
mixin _$AsyncInvocationCreatedData {
  /// The conversation this invocation belongs to (`cnv_` prefixed).
  ///
  /// Injected by the client from the event envelope — the server sends
  /// it as `conversation_id` on the envelope, not inside `data`.
  @JsonKey(name: 'conversation_id')
  String get conversationId => throw _privateConstructorUsedError;

  /// The async invocation to complete (`inv_` prefixed).
  @JsonKey(name: 'invocation_id')
  String get invocationId => throw _privateConstructorUsedError;

  /// Serializes this AsyncInvocationCreatedData to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of AsyncInvocationCreatedData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $AsyncInvocationCreatedDataCopyWith<AsyncInvocationCreatedData>
      get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $AsyncInvocationCreatedDataCopyWith<$Res> {
  factory $AsyncInvocationCreatedDataCopyWith(AsyncInvocationCreatedData value,
          $Res Function(AsyncInvocationCreatedData) then) =
      _$AsyncInvocationCreatedDataCopyWithImpl<$Res,
          AsyncInvocationCreatedData>;
  @useResult
  $Res call(
      {@JsonKey(name: 'conversation_id') String conversationId,
      @JsonKey(name: 'invocation_id') String invocationId});
}

/// @nodoc
class _$AsyncInvocationCreatedDataCopyWithImpl<$Res,
        $Val extends AsyncInvocationCreatedData>
    implements $AsyncInvocationCreatedDataCopyWith<$Res> {
  _$AsyncInvocationCreatedDataCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of AsyncInvocationCreatedData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? conversationId = null,
    Object? invocationId = null,
  }) {
    return _then(_value.copyWith(
      conversationId: null == conversationId
          ? _value.conversationId
          : conversationId // ignore: cast_nullable_to_non_nullable
              as String,
      invocationId: null == invocationId
          ? _value.invocationId
          : invocationId // ignore: cast_nullable_to_non_nullable
              as String,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$AsyncInvocationCreatedDataImplCopyWith<$Res>
    implements $AsyncInvocationCreatedDataCopyWith<$Res> {
  factory _$$AsyncInvocationCreatedDataImplCopyWith(
          _$AsyncInvocationCreatedDataImpl value,
          $Res Function(_$AsyncInvocationCreatedDataImpl) then) =
      __$$AsyncInvocationCreatedDataImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {@JsonKey(name: 'conversation_id') String conversationId,
      @JsonKey(name: 'invocation_id') String invocationId});
}

/// @nodoc
class __$$AsyncInvocationCreatedDataImplCopyWithImpl<$Res>
    extends _$AsyncInvocationCreatedDataCopyWithImpl<$Res,
        _$AsyncInvocationCreatedDataImpl>
    implements _$$AsyncInvocationCreatedDataImplCopyWith<$Res> {
  __$$AsyncInvocationCreatedDataImplCopyWithImpl(
      _$AsyncInvocationCreatedDataImpl _value,
      $Res Function(_$AsyncInvocationCreatedDataImpl) _then)
      : super(_value, _then);

  /// Create a copy of AsyncInvocationCreatedData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? conversationId = null,
    Object? invocationId = null,
  }) {
    return _then(_$AsyncInvocationCreatedDataImpl(
      conversationId: null == conversationId
          ? _value.conversationId
          : conversationId // ignore: cast_nullable_to_non_nullable
              as String,
      invocationId: null == invocationId
          ? _value.invocationId
          : invocationId // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$AsyncInvocationCreatedDataImpl implements _AsyncInvocationCreatedData {
  const _$AsyncInvocationCreatedDataImpl(
      {@JsonKey(name: 'conversation_id') required this.conversationId,
      @JsonKey(name: 'invocation_id') required this.invocationId});

  factory _$AsyncInvocationCreatedDataImpl.fromJson(
          Map<String, dynamic> json) =>
      _$$AsyncInvocationCreatedDataImplFromJson(json);

  /// The conversation this invocation belongs to (`cnv_` prefixed).
  ///
  /// Injected by the client from the event envelope — the server sends
  /// it as `conversation_id` on the envelope, not inside `data`.
  @override
  @JsonKey(name: 'conversation_id')
  final String conversationId;

  /// The async invocation to complete (`inv_` prefixed).
  @override
  @JsonKey(name: 'invocation_id')
  final String invocationId;

  @override
  String toString() {
    return 'AsyncInvocationCreatedData(conversationId: $conversationId, invocationId: $invocationId)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$AsyncInvocationCreatedDataImpl &&
            (identical(other.conversationId, conversationId) ||
                other.conversationId == conversationId) &&
            (identical(other.invocationId, invocationId) ||
                other.invocationId == invocationId));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, conversationId, invocationId);

  /// Create a copy of AsyncInvocationCreatedData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$AsyncInvocationCreatedDataImplCopyWith<_$AsyncInvocationCreatedDataImpl>
      get copyWith => __$$AsyncInvocationCreatedDataImplCopyWithImpl<
          _$AsyncInvocationCreatedDataImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$AsyncInvocationCreatedDataImplToJson(
      this,
    );
  }
}

abstract class _AsyncInvocationCreatedData
    implements AsyncInvocationCreatedData {
  const factory _AsyncInvocationCreatedData(
      {@JsonKey(name: 'conversation_id') required final String conversationId,
      @JsonKey(name: 'invocation_id')
      required final String invocationId}) = _$AsyncInvocationCreatedDataImpl;

  factory _AsyncInvocationCreatedData.fromJson(Map<String, dynamic> json) =
      _$AsyncInvocationCreatedDataImpl.fromJson;

  /// The conversation this invocation belongs to (`cnv_` prefixed).
  ///
  /// Injected by the client from the event envelope — the server sends
  /// it as `conversation_id` on the envelope, not inside `data`.
  @override
  @JsonKey(name: 'conversation_id')
  String get conversationId;

  /// The async invocation to complete (`inv_` prefixed).
  @override
  @JsonKey(name: 'invocation_id')
  String get invocationId;

  /// Create a copy of AsyncInvocationCreatedData
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$AsyncInvocationCreatedDataImplCopyWith<_$AsyncInvocationCreatedDataImpl>
      get copyWith => throw _privateConstructorUsedError;
}

ReplySend _$ReplySendFromJson(Map<String, dynamic> json) {
  return _ReplySend.fromJson(json);
}

/// @nodoc
mixin _$ReplySend {
  @JsonKey(name: 'conversation_id')
  String get conversationId => throw _privateConstructorUsedError;
  String get text => throw _privateConstructorUsedError;

  /// Async invocation this reply completes.
  ///
  /// Set when answering a turn delivered in async mode (see
  /// `async.invocation.created`). Without it the server falls back to
  /// the newest pending invocation for the conversation, which is wrong
  /// when several turns are open at once.
  @JsonKey(name: 'invocation_id')
  String? get invocationId => throw _privateConstructorUsedError;

  /// Serializes this ReplySend to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of ReplySend
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ReplySendCopyWith<ReplySend> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ReplySendCopyWith<$Res> {
  factory $ReplySendCopyWith(ReplySend value, $Res Function(ReplySend) then) =
      _$ReplySendCopyWithImpl<$Res, ReplySend>;
  @useResult
  $Res call(
      {@JsonKey(name: 'conversation_id') String conversationId,
      String text,
      @JsonKey(name: 'invocation_id') String? invocationId});
}

/// @nodoc
class _$ReplySendCopyWithImpl<$Res, $Val extends ReplySend>
    implements $ReplySendCopyWith<$Res> {
  _$ReplySendCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ReplySend
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? conversationId = null,
    Object? text = null,
    Object? invocationId = freezed,
  }) {
    return _then(_value.copyWith(
      conversationId: null == conversationId
          ? _value.conversationId
          : conversationId // ignore: cast_nullable_to_non_nullable
              as String,
      text: null == text
          ? _value.text
          : text // ignore: cast_nullable_to_non_nullable
              as String,
      invocationId: freezed == invocationId
          ? _value.invocationId
          : invocationId // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ReplySendImplCopyWith<$Res>
    implements $ReplySendCopyWith<$Res> {
  factory _$$ReplySendImplCopyWith(
          _$ReplySendImpl value, $Res Function(_$ReplySendImpl) then) =
      __$$ReplySendImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {@JsonKey(name: 'conversation_id') String conversationId,
      String text,
      @JsonKey(name: 'invocation_id') String? invocationId});
}

/// @nodoc
class __$$ReplySendImplCopyWithImpl<$Res>
    extends _$ReplySendCopyWithImpl<$Res, _$ReplySendImpl>
    implements _$$ReplySendImplCopyWith<$Res> {
  __$$ReplySendImplCopyWithImpl(
      _$ReplySendImpl _value, $Res Function(_$ReplySendImpl) _then)
      : super(_value, _then);

  /// Create a copy of ReplySend
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? conversationId = null,
    Object? text = null,
    Object? invocationId = freezed,
  }) {
    return _then(_$ReplySendImpl(
      conversationId: null == conversationId
          ? _value.conversationId
          : conversationId // ignore: cast_nullable_to_non_nullable
              as String,
      text: null == text
          ? _value.text
          : text // ignore: cast_nullable_to_non_nullable
              as String,
      invocationId: freezed == invocationId
          ? _value.invocationId
          : invocationId // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ReplySendImpl extends _ReplySend {
  const _$ReplySendImpl(
      {@JsonKey(name: 'conversation_id') required this.conversationId,
      required this.text,
      @JsonKey(name: 'invocation_id') this.invocationId})
      : super._();

  factory _$ReplySendImpl.fromJson(Map<String, dynamic> json) =>
      _$$ReplySendImplFromJson(json);

  @override
  @JsonKey(name: 'conversation_id')
  final String conversationId;
  @override
  final String text;

  /// Async invocation this reply completes.
  ///
  /// Set when answering a turn delivered in async mode (see
  /// `async.invocation.created`). Without it the server falls back to
  /// the newest pending invocation for the conversation, which is wrong
  /// when several turns are open at once.
  @override
  @JsonKey(name: 'invocation_id')
  final String? invocationId;

  @override
  String toString() {
    return 'ReplySend(conversationId: $conversationId, text: $text, invocationId: $invocationId)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ReplySendImpl &&
            (identical(other.conversationId, conversationId) ||
                other.conversationId == conversationId) &&
            (identical(other.text, text) || other.text == text) &&
            (identical(other.invocationId, invocationId) ||
                other.invocationId == invocationId));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode =>
      Object.hash(runtimeType, conversationId, text, invocationId);

  /// Create a copy of ReplySend
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ReplySendImplCopyWith<_$ReplySendImpl> get copyWith =>
      __$$ReplySendImplCopyWithImpl<_$ReplySendImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ReplySendImplToJson(
      this,
    );
  }
}

abstract class _ReplySend extends ReplySend {
  const factory _ReplySend(
      {@JsonKey(name: 'conversation_id') required final String conversationId,
      required final String text,
      @JsonKey(name: 'invocation_id')
      final String? invocationId}) = _$ReplySendImpl;
  const _ReplySend._() : super._();

  factory _ReplySend.fromJson(Map<String, dynamic> json) =
      _$ReplySendImpl.fromJson;

  @override
  @JsonKey(name: 'conversation_id')
  String get conversationId;
  @override
  String get text;

  /// Async invocation this reply completes.
  ///
  /// Set when answering a turn delivered in async mode (see
  /// `async.invocation.created`). Without it the server falls back to
  /// the newest pending invocation for the conversation, which is wrong
  /// when several turns are open at once.
  @override
  @JsonKey(name: 'invocation_id')
  String? get invocationId;

  /// Create a copy of ReplySend
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ReplySendImplCopyWith<_$ReplySendImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

PresenceUpdate _$PresenceUpdateFromJson(Map<String, dynamic> json) {
  return _PresenceUpdate.fromJson(json);
}

/// @nodoc
mixin _$PresenceUpdate {
  String get status => throw _privateConstructorUsedError;

  /// Serializes this PresenceUpdate to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of PresenceUpdate
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $PresenceUpdateCopyWith<PresenceUpdate> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PresenceUpdateCopyWith<$Res> {
  factory $PresenceUpdateCopyWith(
          PresenceUpdate value, $Res Function(PresenceUpdate) then) =
      _$PresenceUpdateCopyWithImpl<$Res, PresenceUpdate>;
  @useResult
  $Res call({String status});
}

/// @nodoc
class _$PresenceUpdateCopyWithImpl<$Res, $Val extends PresenceUpdate>
    implements $PresenceUpdateCopyWith<$Res> {
  _$PresenceUpdateCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of PresenceUpdate
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? status = null,
  }) {
    return _then(_value.copyWith(
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as String,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$PresenceUpdateImplCopyWith<$Res>
    implements $PresenceUpdateCopyWith<$Res> {
  factory _$$PresenceUpdateImplCopyWith(_$PresenceUpdateImpl value,
          $Res Function(_$PresenceUpdateImpl) then) =
      __$$PresenceUpdateImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String status});
}

/// @nodoc
class __$$PresenceUpdateImplCopyWithImpl<$Res>
    extends _$PresenceUpdateCopyWithImpl<$Res, _$PresenceUpdateImpl>
    implements _$$PresenceUpdateImplCopyWith<$Res> {
  __$$PresenceUpdateImplCopyWithImpl(
      _$PresenceUpdateImpl _value, $Res Function(_$PresenceUpdateImpl) _then)
      : super(_value, _then);

  /// Create a copy of PresenceUpdate
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? status = null,
  }) {
    return _then(_$PresenceUpdateImpl(
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$PresenceUpdateImpl extends _PresenceUpdate {
  const _$PresenceUpdateImpl({required this.status}) : super._();

  factory _$PresenceUpdateImpl.fromJson(Map<String, dynamic> json) =>
      _$$PresenceUpdateImplFromJson(json);

  @override
  final String status;

  @override
  String toString() {
    return 'PresenceUpdate(status: $status)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PresenceUpdateImpl &&
            (identical(other.status, status) || other.status == status));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, status);

  /// Create a copy of PresenceUpdate
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$PresenceUpdateImplCopyWith<_$PresenceUpdateImpl> get copyWith =>
      __$$PresenceUpdateImplCopyWithImpl<_$PresenceUpdateImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$PresenceUpdateImplToJson(
      this,
    );
  }
}

abstract class _PresenceUpdate extends PresenceUpdate {
  const factory _PresenceUpdate({required final String status}) =
      _$PresenceUpdateImpl;
  const _PresenceUpdate._() : super._();

  factory _PresenceUpdate.fromJson(Map<String, dynamic> json) =
      _$PresenceUpdateImpl.fromJson;

  @override
  String get status;

  /// Create a copy of PresenceUpdate
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$PresenceUpdateImplCopyWith<_$PresenceUpdateImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

CapabilityManifest _$CapabilityManifestFromJson(Map<String, dynamic> json) {
  return _CapabilityManifest.fromJson(json);
}

/// @nodoc
mixin _$CapabilityManifest {
  @JsonKey(name: 'agent_id')
  String get agentId => throw _privateConstructorUsedError;
  @JsonKey(name: 'capabilities')
  List<Map<String, dynamic>> get capabilities =>
      throw _privateConstructorUsedError;
  Map<String, dynamic>? get context => throw _privateConstructorUsedError;

  /// Serializes this CapabilityManifest to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of CapabilityManifest
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $CapabilityManifestCopyWith<CapabilityManifest> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $CapabilityManifestCopyWith<$Res> {
  factory $CapabilityManifestCopyWith(
          CapabilityManifest value, $Res Function(CapabilityManifest) then) =
      _$CapabilityManifestCopyWithImpl<$Res, CapabilityManifest>;
  @useResult
  $Res call(
      {@JsonKey(name: 'agent_id') String agentId,
      @JsonKey(name: 'capabilities') List<Map<String, dynamic>> capabilities,
      Map<String, dynamic>? context});
}

/// @nodoc
class _$CapabilityManifestCopyWithImpl<$Res, $Val extends CapabilityManifest>
    implements $CapabilityManifestCopyWith<$Res> {
  _$CapabilityManifestCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of CapabilityManifest
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? agentId = null,
    Object? capabilities = null,
    Object? context = freezed,
  }) {
    return _then(_value.copyWith(
      agentId: null == agentId
          ? _value.agentId
          : agentId // ignore: cast_nullable_to_non_nullable
              as String,
      capabilities: null == capabilities
          ? _value.capabilities
          : capabilities // ignore: cast_nullable_to_non_nullable
              as List<Map<String, dynamic>>,
      context: freezed == context
          ? _value.context
          : context // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$CapabilityManifestImplCopyWith<$Res>
    implements $CapabilityManifestCopyWith<$Res> {
  factory _$$CapabilityManifestImplCopyWith(_$CapabilityManifestImpl value,
          $Res Function(_$CapabilityManifestImpl) then) =
      __$$CapabilityManifestImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {@JsonKey(name: 'agent_id') String agentId,
      @JsonKey(name: 'capabilities') List<Map<String, dynamic>> capabilities,
      Map<String, dynamic>? context});
}

/// @nodoc
class __$$CapabilityManifestImplCopyWithImpl<$Res>
    extends _$CapabilityManifestCopyWithImpl<$Res, _$CapabilityManifestImpl>
    implements _$$CapabilityManifestImplCopyWith<$Res> {
  __$$CapabilityManifestImplCopyWithImpl(_$CapabilityManifestImpl _value,
      $Res Function(_$CapabilityManifestImpl) _then)
      : super(_value, _then);

  /// Create a copy of CapabilityManifest
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? agentId = null,
    Object? capabilities = null,
    Object? context = freezed,
  }) {
    return _then(_$CapabilityManifestImpl(
      agentId: null == agentId
          ? _value.agentId
          : agentId // ignore: cast_nullable_to_non_nullable
              as String,
      capabilities: null == capabilities
          ? _value._capabilities
          : capabilities // ignore: cast_nullable_to_non_nullable
              as List<Map<String, dynamic>>,
      context: freezed == context
          ? _value._context
          : context // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$CapabilityManifestImpl extends _CapabilityManifest {
  const _$CapabilityManifestImpl(
      {@JsonKey(name: 'agent_id') required this.agentId,
      @JsonKey(name: 'capabilities')
      final List<Map<String, dynamic>> capabilities =
          const <Map<String, dynamic>>[],
      final Map<String, dynamic>? context})
      : _capabilities = capabilities,
        _context = context,
        super._();

  factory _$CapabilityManifestImpl.fromJson(Map<String, dynamic> json) =>
      _$$CapabilityManifestImplFromJson(json);

  @override
  @JsonKey(name: 'agent_id')
  final String agentId;
  final List<Map<String, dynamic>> _capabilities;
  @override
  @JsonKey(name: 'capabilities')
  List<Map<String, dynamic>> get capabilities {
    if (_capabilities is EqualUnmodifiableListView) return _capabilities;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_capabilities);
  }

  final Map<String, dynamic>? _context;
  @override
  Map<String, dynamic>? get context {
    final value = _context;
    if (value == null) return null;
    if (_context is EqualUnmodifiableMapView) return _context;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(value);
  }

  @override
  String toString() {
    return 'CapabilityManifest(agentId: $agentId, capabilities: $capabilities, context: $context)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$CapabilityManifestImpl &&
            (identical(other.agentId, agentId) || other.agentId == agentId) &&
            const DeepCollectionEquality()
                .equals(other._capabilities, _capabilities) &&
            const DeepCollectionEquality().equals(other._context, _context));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      agentId,
      const DeepCollectionEquality().hash(_capabilities),
      const DeepCollectionEquality().hash(_context));

  /// Create a copy of CapabilityManifest
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$CapabilityManifestImplCopyWith<_$CapabilityManifestImpl> get copyWith =>
      __$$CapabilityManifestImplCopyWithImpl<_$CapabilityManifestImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$CapabilityManifestImplToJson(
      this,
    );
  }
}

abstract class _CapabilityManifest extends CapabilityManifest {
  const factory _CapabilityManifest(
      {@JsonKey(name: 'agent_id') required final String agentId,
      @JsonKey(name: 'capabilities')
      final List<Map<String, dynamic>> capabilities,
      final Map<String, dynamic>? context}) = _$CapabilityManifestImpl;
  const _CapabilityManifest._() : super._();

  factory _CapabilityManifest.fromJson(Map<String, dynamic> json) =
      _$CapabilityManifestImpl.fromJson;

  @override
  @JsonKey(name: 'agent_id')
  String get agentId;
  @override
  @JsonKey(name: 'capabilities')
  List<Map<String, dynamic>> get capabilities;
  @override
  Map<String, dynamic>? get context;

  /// Create a copy of CapabilityManifest
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$CapabilityManifestImplCopyWith<_$CapabilityManifestImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

ToolInvokeMessage _$ToolInvokeMessageFromJson(Map<String, dynamic> json) {
  return _ToolInvokeMessage.fromJson(json);
}

/// @nodoc
mixin _$ToolInvokeMessage {
  @JsonKey(name: 'conversation_id')
  String get conversationId => throw _privateConstructorUsedError;
  @JsonKey(name: 'invocation_id')
  String get invocationId => throw _privateConstructorUsedError;
  @JsonKey(name: 'tool_id')
  String get toolId => throw _privateConstructorUsedError;
  dynamic get input => throw _privateConstructorUsedError;

  /// Words the human said alongside the tool call.
  ///
  /// Forwarded so the agent sees them as `content` next to
  /// `tool_calls` — without this the companion prose never arrives.
  String? get text => throw _privateConstructorUsedError;

  /// Serializes this ToolInvokeMessage to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of ToolInvokeMessage
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ToolInvokeMessageCopyWith<ToolInvokeMessage> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ToolInvokeMessageCopyWith<$Res> {
  factory $ToolInvokeMessageCopyWith(
          ToolInvokeMessage value, $Res Function(ToolInvokeMessage) then) =
      _$ToolInvokeMessageCopyWithImpl<$Res, ToolInvokeMessage>;
  @useResult
  $Res call(
      {@JsonKey(name: 'conversation_id') String conversationId,
      @JsonKey(name: 'invocation_id') String invocationId,
      @JsonKey(name: 'tool_id') String toolId,
      dynamic input,
      String? text});
}

/// @nodoc
class _$ToolInvokeMessageCopyWithImpl<$Res, $Val extends ToolInvokeMessage>
    implements $ToolInvokeMessageCopyWith<$Res> {
  _$ToolInvokeMessageCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ToolInvokeMessage
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? conversationId = null,
    Object? invocationId = null,
    Object? toolId = null,
    Object? input = freezed,
    Object? text = freezed,
  }) {
    return _then(_value.copyWith(
      conversationId: null == conversationId
          ? _value.conversationId
          : conversationId // ignore: cast_nullable_to_non_nullable
              as String,
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
      text: freezed == text
          ? _value.text
          : text // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ToolInvokeMessageImplCopyWith<$Res>
    implements $ToolInvokeMessageCopyWith<$Res> {
  factory _$$ToolInvokeMessageImplCopyWith(_$ToolInvokeMessageImpl value,
          $Res Function(_$ToolInvokeMessageImpl) then) =
      __$$ToolInvokeMessageImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {@JsonKey(name: 'conversation_id') String conversationId,
      @JsonKey(name: 'invocation_id') String invocationId,
      @JsonKey(name: 'tool_id') String toolId,
      dynamic input,
      String? text});
}

/// @nodoc
class __$$ToolInvokeMessageImplCopyWithImpl<$Res>
    extends _$ToolInvokeMessageCopyWithImpl<$Res, _$ToolInvokeMessageImpl>
    implements _$$ToolInvokeMessageImplCopyWith<$Res> {
  __$$ToolInvokeMessageImplCopyWithImpl(_$ToolInvokeMessageImpl _value,
      $Res Function(_$ToolInvokeMessageImpl) _then)
      : super(_value, _then);

  /// Create a copy of ToolInvokeMessage
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? conversationId = null,
    Object? invocationId = null,
    Object? toolId = null,
    Object? input = freezed,
    Object? text = freezed,
  }) {
    return _then(_$ToolInvokeMessageImpl(
      conversationId: null == conversationId
          ? _value.conversationId
          : conversationId // ignore: cast_nullable_to_non_nullable
              as String,
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
      text: freezed == text
          ? _value.text
          : text // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ToolInvokeMessageImpl extends _ToolInvokeMessage {
  const _$ToolInvokeMessageImpl(
      {@JsonKey(name: 'conversation_id') required this.conversationId,
      @JsonKey(name: 'invocation_id') required this.invocationId,
      @JsonKey(name: 'tool_id') required this.toolId,
      required this.input,
      this.text})
      : super._();

  factory _$ToolInvokeMessageImpl.fromJson(Map<String, dynamic> json) =>
      _$$ToolInvokeMessageImplFromJson(json);

  @override
  @JsonKey(name: 'conversation_id')
  final String conversationId;
  @override
  @JsonKey(name: 'invocation_id')
  final String invocationId;
  @override
  @JsonKey(name: 'tool_id')
  final String toolId;
  @override
  final dynamic input;

  /// Words the human said alongside the tool call.
  ///
  /// Forwarded so the agent sees them as `content` next to
  /// `tool_calls` — without this the companion prose never arrives.
  @override
  final String? text;

  @override
  String toString() {
    return 'ToolInvokeMessage(conversationId: $conversationId, invocationId: $invocationId, toolId: $toolId, input: $input, text: $text)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ToolInvokeMessageImpl &&
            (identical(other.conversationId, conversationId) ||
                other.conversationId == conversationId) &&
            (identical(other.invocationId, invocationId) ||
                other.invocationId == invocationId) &&
            (identical(other.toolId, toolId) || other.toolId == toolId) &&
            const DeepCollectionEquality().equals(other.input, input) &&
            (identical(other.text, text) || other.text == text));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, conversationId, invocationId,
      toolId, const DeepCollectionEquality().hash(input), text);

  /// Create a copy of ToolInvokeMessage
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ToolInvokeMessageImplCopyWith<_$ToolInvokeMessageImpl> get copyWith =>
      __$$ToolInvokeMessageImplCopyWithImpl<_$ToolInvokeMessageImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ToolInvokeMessageImplToJson(
      this,
    );
  }
}

abstract class _ToolInvokeMessage extends ToolInvokeMessage {
  const factory _ToolInvokeMessage(
      {@JsonKey(name: 'conversation_id') required final String conversationId,
      @JsonKey(name: 'invocation_id') required final String invocationId,
      @JsonKey(name: 'tool_id') required final String toolId,
      required final dynamic input,
      final String? text}) = _$ToolInvokeMessageImpl;
  const _ToolInvokeMessage._() : super._();

  factory _ToolInvokeMessage.fromJson(Map<String, dynamic> json) =
      _$ToolInvokeMessageImpl.fromJson;

  @override
  @JsonKey(name: 'conversation_id')
  String get conversationId;
  @override
  @JsonKey(name: 'invocation_id')
  String get invocationId;
  @override
  @JsonKey(name: 'tool_id')
  String get toolId;
  @override
  dynamic get input;

  /// Words the human said alongside the tool call.
  ///
  /// Forwarded so the agent sees them as `content` next to
  /// `tool_calls` — without this the companion prose never arrives.
  @override
  String? get text;

  /// Create a copy of ToolInvokeMessage
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ToolInvokeMessageImplCopyWith<_$ToolInvokeMessageImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
