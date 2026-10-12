// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'events.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$OpenHumanEventImpl _$$OpenHumanEventImplFromJson(Map<String, dynamic> json) =>
    _$OpenHumanEventImpl(
      eventId: json['event_id'] as String,
      eventType: json['event_type'] as String,
      conversationId: json['conversation_id'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      data: json['data'] as Map<String, dynamic>,
    );

Map<String, dynamic> _$$OpenHumanEventImplToJson(
        _$OpenHumanEventImpl instance) =>
    <String, dynamic>{
      'event_id': instance.eventId,
      'event_type': instance.eventType,
      'conversation_id': instance.conversationId,
      'timestamp': instance.timestamp.toIso8601String(),
      'data': instance.data,
    };

_$SessionConnectedDataImpl _$$SessionConnectedDataImplFromJson(
        Map<String, dynamic> json) =>
    _$SessionConnectedDataImpl(
      humanId: json['human_id'] as String,
      displayName: json['display_name'] as String,
    );

Map<String, dynamic> _$$SessionConnectedDataImplToJson(
        _$SessionConnectedDataImpl instance) =>
    <String, dynamic>{
      'human_id': instance.humanId,
      'display_name': instance.displayName,
    };

_$MessageReceivedDataImpl _$$MessageReceivedDataImplFromJson(
        Map<String, dynamic> json) =>
    _$MessageReceivedDataImpl(
      conversationId: json['conversation_id'] as String,
      messageId: json['message_id'] as String,
      senderId: json['sender_id'] as String,
      senderType: json['sender_type'] as String,
      senderName: json['sender_name'] as String?,
      text: json['text'] as String,
      images: (json['images'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const <String>[],
    );

Map<String, dynamic> _$$MessageReceivedDataImplToJson(
        _$MessageReceivedDataImpl instance) =>
    <String, dynamic>{
      'conversation_id': instance.conversationId,
      'message_id': instance.messageId,
      'sender_id': instance.senderId,
      'sender_type': instance.senderType,
      'sender_name': instance.senderName,
      'text': instance.text,
      'images': instance.images,
    };

_$ReplyDeliveredDataImpl _$$ReplyDeliveredDataImplFromJson(
        Map<String, dynamic> json) =>
    _$ReplyDeliveredDataImpl(
      delivered: json['delivered'] as bool,
    );

Map<String, dynamic> _$$ReplyDeliveredDataImplToJson(
        _$ReplyDeliveredDataImpl instance) =>
    <String, dynamic>{
      'delivered': instance.delivered,
    };

_$CapabilityUpdatedDataImpl _$$CapabilityUpdatedDataImplFromJson(
        Map<String, dynamic> json) =>
    _$CapabilityUpdatedDataImpl(
      agentId: json['agent_id'] as String,
      capabilities: (json['capabilities'] as List<dynamic>?)
              ?.map((e) => e as Map<String, dynamic>)
              .toList() ??
          const <Map<String, dynamic>>[],
      context: json['context'] as Map<String, dynamic>?,
    );

Map<String, dynamic> _$$CapabilityUpdatedDataImplToJson(
        _$CapabilityUpdatedDataImpl instance) =>
    <String, dynamic>{
      'agent_id': instance.agentId,
      'capabilities': instance.capabilities,
      'context': instance.context,
    };

_$ToolResultDataImpl _$$ToolResultDataImplFromJson(Map<String, dynamic> json) =>
    _$ToolResultDataImpl(
      invocationId: json['invocation_id'] as String,
      toolId: json['tool_id'] as String,
      status: json['status'] as String,
      output: json['output'],
      error: json['error'] as String?,
    );

Map<String, dynamic> _$$ToolResultDataImplToJson(
        _$ToolResultDataImpl instance) =>
    <String, dynamic>{
      'invocation_id': instance.invocationId,
      'tool_id': instance.toolId,
      'status': instance.status,
      'output': instance.output,
      'error': instance.error,
    };

_$ErrorDataImpl _$$ErrorDataImplFromJson(Map<String, dynamic> json) =>
    _$ErrorDataImpl(
      code: json['code'] as String,
      message: json['message'] as String,
    );

Map<String, dynamic> _$$ErrorDataImplToJson(_$ErrorDataImpl instance) =>
    <String, dynamic>{
      'code': instance.code,
      'message': instance.message,
    };

_$AsyncInvocationCreatedDataImpl _$$AsyncInvocationCreatedDataImplFromJson(
        Map<String, dynamic> json) =>
    _$AsyncInvocationCreatedDataImpl(
      conversationId: json['conversation_id'] as String,
      invocationId: json['invocation_id'] as String,
    );

Map<String, dynamic> _$$AsyncInvocationCreatedDataImplToJson(
        _$AsyncInvocationCreatedDataImpl instance) =>
    <String, dynamic>{
      'conversation_id': instance.conversationId,
      'invocation_id': instance.invocationId,
    };

_$ReplySendImpl _$$ReplySendImplFromJson(Map<String, dynamic> json) =>
    _$ReplySendImpl(
      conversationId: json['conversation_id'] as String,
      text: json['text'] as String,
      invocationId: json['invocation_id'] as String?,
    );

Map<String, dynamic> _$$ReplySendImplToJson(_$ReplySendImpl instance) =>
    <String, dynamic>{
      'conversation_id': instance.conversationId,
      'text': instance.text,
      'invocation_id': instance.invocationId,
    };

_$PresenceUpdateImpl _$$PresenceUpdateImplFromJson(Map<String, dynamic> json) =>
    _$PresenceUpdateImpl(
      status: json['status'] as String,
    );

Map<String, dynamic> _$$PresenceUpdateImplToJson(
        _$PresenceUpdateImpl instance) =>
    <String, dynamic>{
      'status': instance.status,
    };

_$CapabilityManifestImpl _$$CapabilityManifestImplFromJson(
        Map<String, dynamic> json) =>
    _$CapabilityManifestImpl(
      agentId: json['agent_id'] as String,
      capabilities: (json['capabilities'] as List<dynamic>?)
              ?.map((e) => e as Map<String, dynamic>)
              .toList() ??
          const <Map<String, dynamic>>[],
      context: json['context'] as Map<String, dynamic>?,
    );

Map<String, dynamic> _$$CapabilityManifestImplToJson(
        _$CapabilityManifestImpl instance) =>
    <String, dynamic>{
      'agent_id': instance.agentId,
      'capabilities': instance.capabilities,
      'context': instance.context,
    };

_$ToolInvokeMessageImpl _$$ToolInvokeMessageImplFromJson(
        Map<String, dynamic> json) =>
    _$ToolInvokeMessageImpl(
      conversationId: json['conversation_id'] as String,
      invocationId: json['invocation_id'] as String,
      toolId: json['tool_id'] as String,
      input: json['input'],
      text: json['text'] as String?,
    );

Map<String, dynamic> _$$ToolInvokeMessageImplToJson(
        _$ToolInvokeMessageImpl instance) =>
    <String, dynamic>{
      'conversation_id': instance.conversationId,
      'invocation_id': instance.invocationId,
      'tool_id': instance.toolId,
      'input': instance.input,
      'text': instance.text,
    };
