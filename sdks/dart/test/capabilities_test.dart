// ═════════════════════════════════════════════════════════════════
// OpenHuman Dart SDK — Protocol Tests: capabilities.dart
//
// Verifies:
//   - AgentCapability serialization (snake_case, includeIfNull)
//   - AgentContext serialization (snake_case, includeIfNull)
//   - ToolInvoke serialization
//   - ToolResult serialization (InvocationStatus enum wire values)
//   - InvocationStatus wire values (lowercase)
//
// All JSON fixtures are taken verbatim from the Rust server's
// `server/src/model/agent_capability.rs`, `agent_context.rs`,
// and `tool_invocation.rs`.
// ═════════════════════════════════════════════════════════════════

import 'package:test/test.dart';
import 'package:openhuman_sdk_dart/openhuman.dart';

void main() {
  // ── InvocationStatus wire values ──────────────────────────────────

  group('InvocationStatus wire values', () {
    test('all statuses produce correct wire strings via ToolResult.toJson', () {
      for (final status in InvocationStatus.values) {
        final result = ToolResult(
          invocationId: 'inv_test',
          toolId: 'test_tool',
          status: status,
        );
        final json = result.toJson();
        expect(json['status'], status.name,
            reason: '${status.name} should serialize to lowercase');
      }
    });
  });

  // ── AgentCapability ────────────────────────────────────────────────

  group('AgentCapability', () {
    test('deserializes from server wire format', () {
      // Exact JSON from Rust AgentCapability struct
      final cap = AgentCapability.fromJson({
        'id': 'github_create_issue',
        'name': 'Create GitHub Issue',
        'description': 'Creates an issue in a GitHub repository.',
        'category': 'github',
        'input_schema': {'type': 'object', 'properties': {}},
        'output_schema': {'type': 'object'},
        'ui_schema': {'component': 'form'},
        'permissions': ['repo:issues:write'],
        'metadata': {'icon': 'github'},
      });

      expect(cap.id, 'github_create_issue');
      expect(cap.name, 'Create GitHub Issue');
      expect(cap.description, 'Creates an issue in a GitHub repository.');
      expect(cap.category, 'github');
      expect(cap.inputSchema?['type'], 'object');
      expect(cap.outputSchema?['type'], 'object');
      expect(cap.uiSchema?['component'], 'form');
      expect(cap.permissions, ['repo:issues:write']);
      expect(cap.metadata['icon'], 'github');
    });

    test('serializes with snake_case and omits nulls (includeIfNull: false)', () {
      const cap = AgentCapability(
        id: 'terminal',
        name: 'Terminal',
        // description, category, schemas, uiSchema are null
      );

      final json = cap.toJson();

      expect(json['id'], 'terminal');
      expect(json['name'], 'Terminal');
      // null fields should be omitted
      expect(json.containsKey('description'), isFalse);
      expect(json.containsKey('category'), isFalse);
      expect(json.containsKey('input_schema'), isFalse);
      expect(json.containsKey('output_schema'), isFalse);
      expect(json.containsKey('ui_schema'), isFalse);
      // defaults should be present
      expect(json['permissions'], isEmpty);
      expect(json['metadata'], isEmpty);
    });

    test('serializes all optional fields when provided', () {
      const cap = AgentCapability(
        id: 'browser',
        name: 'Browser',
        description: 'Web browser tool',
        category: 'browser',
        inputSchema: {'type': 'object'},
        outputSchema: {'type': 'string'},
        uiSchema: {'component': 'iframe'},
        permissions: ['net:access'],
        metadata: {'version': '1.0'},
      );

      final json = cap.toJson();

      expect(json['description'], 'Web browser tool');
      expect(json['category'], 'browser');
      expect(json['input_schema']['type'], 'object');
      expect(json['output_schema']['type'], 'string');
      expect(json['ui_schema']['component'], 'iframe');
      expect(json['permissions'], ['net:access']);
      expect(json['metadata']['version'], '1.0');
    });
  });

  // ── AgentContext ───────────────────────────────────────────────────

  group('AgentContext', () {
    test('deserializes from server wire format', () {
      final ctx = AgentContext.fromJson({
        'agent_id': 'agt_demo_codex',
        'system_prompt': 'You are a coding assistant.',
        'model': {'name': 'gpt-4o', 'provider': 'openai'},
        'runtime': {'platform': 'linux', 'version': '0.1.0'},
        'environment': {'repo': 'openhuman/openhuman', 'branch': 'main'},
      });

      expect(ctx.agentId, 'agt_demo_codex');
      expect(ctx.systemPrompt, 'You are a coding assistant.');
      expect(ctx.model?['name'], 'gpt-4o');
      expect(ctx.runtime?['platform'], 'linux');
      expect(ctx.environment?['repo'], 'openhuman/openhuman');
    });

    test('serializes with snake_case and omits nulls', () {
      const ctx = AgentContext(agentId: 'agt_test');

      final json = ctx.toJson();

      expect(json['agent_id'], 'agt_test');
      expect(json.containsKey('system_prompt'), isFalse);
      expect(json.containsKey('model'), isFalse);
      expect(json.containsKey('runtime'), isFalse);
      expect(json.containsKey('environment'), isFalse);
    });
  });

  // ── ToolInvoke ────────────────────────────────────────────────────

  group('ToolInvoke', () {
    test('deserializes from server wire format', () {
      final invoke = ToolInvoke.fromJson({
        'invocation_id': 'inv_0189abc123',
        'tool_id': 'github_create_issue',
        'input': {
          'repo': 'openhuman/openhuman',
          'title': 'Bug: login fails',
          'body': 'Steps to reproduce...',
        },
      });

      expect(invoke.invocationId, 'inv_0189abc123');
      expect(invoke.toolId, 'github_create_issue');
      expect((invoke.input as Map)['repo'], 'openhuman/openhuman');
    });

    test('serializes to snake_case', () {
      const invoke = ToolInvoke(
        invocationId: 'inv_test',
        toolId: 'terminal',
        input: {'command': 'ls -la'},
      );

      final json = invoke.toJson();
      expect(json['invocation_id'], 'inv_test');
      expect(json['tool_id'], 'terminal');
      expect((json['input'] as Map)['command'], 'ls -la');
    });
  });

  // ── ToolResult ─────────────────────────────────────────────────────

  group('ToolResult', () {
    test('deserializes success result from server', () {
      final result = ToolResult.fromJson({
        'invocation_id': 'inv_0189abc',
        'tool_id': 'github_create_issue',
        'status': 'success',
        'output': {'issue_number': 42, 'html_url': 'https://github.com/...'},
        // error is omitted (skip_serializing_if = Option::is_none)
      });

      expect(result.invocationId, 'inv_0189abc');
      expect(result.toolId, 'github_create_issue');
      expect(result.status, InvocationStatus.success);
      expect((result.output as Map)['issue_number'], 42);
      expect(result.error, isNull);
    });

    test('deserializes error result', () {
      final result = ToolResult.fromJson({
        'invocation_id': 'inv_0189err',
        'tool_id': 'terminal',
        'status': 'error',
        'error': 'Permission denied',
      });

      expect(result.status, InvocationStatus.error);
      expect(result.error, 'Permission denied');
      expect(result.output, isNull);
    });

    test('deserializes timeout result', () {
      final result = ToolResult.fromJson({
        'invocation_id': 'inv_0189timeout',
        'tool_id': 'browser',
        'status': 'timeout',
      });

      expect(result.status, InvocationStatus.timeout);
    });

    test('serializes success with output, omits null error', () {
      const result = ToolResult(
        invocationId: 'inv_out',
        toolId: 'terminal',
        status: InvocationStatus.success,
        output: {'stdout': 'hello'},
      );

      final json = result.toJson();

      expect(json['invocation_id'], 'inv_out');
      expect(json['tool_id'], 'terminal');
      expect(json['status'], 'success');
      expect((json['output'] as Map)['stdout'], 'hello');
      // error should be omitted (includeIfNull: false)
      expect(json.containsKey('error'), isFalse);
    });

    test('serializes error with error message, omits null output', () {
      const result = ToolResult(
        invocationId: 'inv_err',
        toolId: 'terminal',
        status: InvocationStatus.error,
        error: 'Command not found',
      );

      final json = result.toJson();

      expect(json['status'], 'error');
      expect(json['error'], 'Command not found');
      expect(json.containsKey('output'), isFalse);
    });
  });
}
