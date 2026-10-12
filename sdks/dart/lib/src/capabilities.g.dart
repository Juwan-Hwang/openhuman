// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'capabilities.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$AgentCapabilityImpl _$$AgentCapabilityImplFromJson(
        Map<String, dynamic> json) =>
    _$AgentCapabilityImpl(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      category: json['category'] as String?,
      inputSchema: json['input_schema'] as Map<String, dynamic>?,
      outputSchema: json['output_schema'] as Map<String, dynamic>?,
      uiSchema: json['ui_schema'] as Map<String, dynamic>?,
      permissions: (json['permissions'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const <String>[],
      metadata: json['metadata'] as Map<String, dynamic>? ??
          const <String, dynamic>{},
    );

Map<String, dynamic> _$$AgentCapabilityImplToJson(
        _$AgentCapabilityImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      if (instance.description case final value?) 'description': value,
      if (instance.category case final value?) 'category': value,
      if (instance.inputSchema case final value?) 'input_schema': value,
      if (instance.outputSchema case final value?) 'output_schema': value,
      if (instance.uiSchema case final value?) 'ui_schema': value,
      'permissions': instance.permissions,
      'metadata': instance.metadata,
    };

_$AgentContextImpl _$$AgentContextImplFromJson(Map<String, dynamic> json) =>
    _$AgentContextImpl(
      agentId: json['agent_id'] as String,
      systemPrompt: json['system_prompt'] as String?,
      model: json['model'] as Map<String, dynamic>?,
      runtime: json['runtime'] as Map<String, dynamic>?,
      environment: json['environment'] as Map<String, dynamic>?,
    );

Map<String, dynamic> _$$AgentContextImplToJson(_$AgentContextImpl instance) =>
    <String, dynamic>{
      'agent_id': instance.agentId,
      if (instance.systemPrompt case final value?) 'system_prompt': value,
      if (instance.model case final value?) 'model': value,
      if (instance.runtime case final value?) 'runtime': value,
      if (instance.environment case final value?) 'environment': value,
    };

_$ToolInvokeImpl _$$ToolInvokeImplFromJson(Map<String, dynamic> json) =>
    _$ToolInvokeImpl(
      invocationId: json['invocation_id'] as String,
      toolId: json['tool_id'] as String,
      input: json['input'],
    );

Map<String, dynamic> _$$ToolInvokeImplToJson(_$ToolInvokeImpl instance) =>
    <String, dynamic>{
      'invocation_id': instance.invocationId,
      'tool_id': instance.toolId,
      'input': instance.input,
    };

_$ToolResultImpl _$$ToolResultImplFromJson(Map<String, dynamic> json) =>
    _$ToolResultImpl(
      invocationId: json['invocation_id'] as String,
      toolId: json['tool_id'] as String,
      status: $enumDecode(_$InvocationStatusEnumMap, json['status']),
      output: json['output'],
      error: json['error'] as String?,
    );

Map<String, dynamic> _$$ToolResultImplToJson(_$ToolResultImpl instance) =>
    <String, dynamic>{
      'invocation_id': instance.invocationId,
      'tool_id': instance.toolId,
      'status': _$InvocationStatusEnumMap[instance.status]!,
      if (instance.output case final value?) 'output': value,
      if (instance.error case final value?) 'error': value,
    };

const _$InvocationStatusEnumMap = {
  InvocationStatus.pending: 'pending',
  InvocationStatus.success: 'success',
  InvocationStatus.error: 'error',
  InvocationStatus.cancelled: 'cancelled',
  InvocationStatus.timeout: 'timeout',
};
