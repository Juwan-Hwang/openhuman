// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'messages.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$ParticipantRefImpl _$$ParticipantRefImplFromJson(Map<String, dynamic> json) =>
    _$ParticipantRefImpl(
      participantId: json['participant_id'] as String,
      participantType:
          $enumDecode(_$ParticipantTypeEnumMap, json['participant_type']),
    );

Map<String, dynamic> _$$ParticipantRefImplToJson(
        _$ParticipantRefImpl instance) =>
    <String, dynamic>{
      'participant_id': instance.participantId,
      'participant_type': _$ParticipantTypeEnumMap[instance.participantType]!,
    };

const _$ParticipantTypeEnumMap = {
  ParticipantType.human: 'human',
  ParticipantType.agent: 'agent',
};

_$TextContentImpl _$$TextContentImplFromJson(Map<String, dynamic> json) =>
    _$TextContentImpl(
      text: json['text'] as String,
      $type: json['type'] as String?,
    );

Map<String, dynamic> _$$TextContentImplToJson(_$TextContentImpl instance) =>
    <String, dynamic>{
      'text': instance.text,
      'type': instance.$type,
    };

_$StructuredContentImpl _$$StructuredContentImplFromJson(
        Map<String, dynamic> json) =>
    _$StructuredContentImpl(
      schema: json['schema'] as Map<String, dynamic>,
      data: json['data'],
      $type: json['type'] as String?,
    );

Map<String, dynamic> _$$StructuredContentImplToJson(
        _$StructuredContentImpl instance) =>
    <String, dynamic>{
      'schema': instance.schema,
      'data': instance.data,
      'type': instance.$type,
    };

_$MultipartContentImpl _$$MultipartContentImplFromJson(
        Map<String, dynamic> json) =>
    _$MultipartContentImpl(
      parts: (json['parts'] as List<dynamic>)
          .map((e) => ContentBlock.fromJson(e as Map<String, dynamic>))
          .toList(),
      $type: json['type'] as String?,
    );

Map<String, dynamic> _$$MultipartContentImplToJson(
        _$MultipartContentImpl instance) =>
    <String, dynamic>{
      'parts': instance.parts,
      'type': instance.$type,
    };

_$AttachmentImpl _$$AttachmentImplFromJson(Map<String, dynamic> json) =>
    _$AttachmentImpl(
      id: json['id'] as String,
      filename: json['filename'] as String,
      contentType: json['content_type'] as String,
      sizeBytes: (json['size_bytes'] as num).toInt(),
      url: json['url'] as String,
    );

Map<String, dynamic> _$$AttachmentImplToJson(_$AttachmentImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'filename': instance.filename,
      'content_type': instance.contentType,
      'size_bytes': instance.sizeBytes,
      'url': instance.url,
    };

_$OpenHumanMessageImpl _$$OpenHumanMessageImplFromJson(
        Map<String, dynamic> json) =>
    _$OpenHumanMessageImpl(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      sender: ParticipantRef.fromJson(json['sender'] as Map<String, dynamic>),
      content: ContentBlock.fromJson(json['content'] as Map<String, dynamic>),
      attachments: (json['attachments'] as List<dynamic>?)
              ?.map((e) => Attachment.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const <Attachment>[],
      metadata: json['metadata'] as Map<String, dynamic>? ??
          const <String, dynamic>{},
      status: $enumDecode(_$MessageStatusEnumMap, json['status']),
      createdAt: DateTime.parse(json['created_at'] as String),
    );

Map<String, dynamic> _$$OpenHumanMessageImplToJson(
        _$OpenHumanMessageImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'conversation_id': instance.conversationId,
      'sender': instance.sender,
      'content': instance.content,
      'attachments': instance.attachments,
      'metadata': instance.metadata,
      'status': _$MessageStatusEnumMap[instance.status]!,
      'created_at': instance.createdAt.toIso8601String(),
    };

const _$MessageStatusEnumMap = {
  MessageStatus.pending: 'pending',
  MessageStatus.sent: 'sent',
  MessageStatus.delivered: 'delivered',
  MessageStatus.read: 'read',
  MessageStatus.failed: 'failed',
};
