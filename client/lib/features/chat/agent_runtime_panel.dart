/// Agent Runtime Panel — displays agent runtime metadata + tool invoker.
///
/// Tools are **interactive**: click to expand a form, fill in parameters,
/// click "Execute" → sends `tool.invoke` via WS → result displayed inline.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'tool_labels.dart';
import 'package:openhuman_client/app/theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openhuman_sdk_dart/openhuman.dart' as oh;

import '../../core/sdk_provider.dart';

// ═══════════════════════════════════════════════════════════════
//  Pending tool invocations — state shared between panel & result
// ═══════════════════════════════════════════════════════════════

/// A pending tool invocation result, tracked by invocation_id.
class ToolInvocationState {
  ToolInvocationState({required this.toolId, required this.toolName, this.status = 'pending'});

  final String toolId;
  final String toolName;
  String status; // 'pending', 'success', 'error', 'timeout'
  dynamic output;
  String? error;
}

/// Provider tracking pending tool invocations.
final toolInvocationsProvider =
    StateNotifierProvider<ToolInvocationNotifier, Map<String, ToolInvocationState>>((ref) {
  return ToolInvocationNotifier(ref);
});

class ToolInvocationNotifier extends StateNotifier<Map<String, ToolInvocationState>> {
  ToolInvocationNotifier(this._ref) : super(const {}) {
    _sub = _ref.read(openHumanClientProvider).toolResults.listen(_onResult);
  }

  final Ref _ref;
  late final StreamSubscription<oh.ToolResultData> _sub;

  void _onResult(oh.ToolResultData result) {
    final invocations = Map<String, ToolInvocationState>.from(state);
    final existing = invocations[result.invocationId];
    if (existing != null) {
      existing.status = result.status;
      existing.output = result.output;
      existing.error = result.error;
      state = invocations;
    }
  }

  void addPending(String invocationId, String toolId, String toolName) {
    state = {
      ...state,
      invocationId: ToolInvocationState(toolId: toolId, toolName: toolName),
    };
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

// ═══════════════════════════════════════════════════════════════
//  Agent Runtime Panel
// ═══════════════════════════════════════════════════════════════

class AgentRuntimePanel extends ConsumerWidget {
  const AgentRuntimePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Use the always-on cache, not a lazy StreamProvider.
    final data = ref.watch(capabilityCacheProvider);
    final theme = Theme.of(context);

    // Same treatment as the conversation sidebar: a card inset from the
    // window rather than a panel divided off by a full-height rule.
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 12, 12, 12),
      child: SizedBox(
        width: 348,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Header ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
                  child: Row(
                    children: [
                      Icon(Icons.smart_toy_outlined,
                          size: 16, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Text('工具', style: theme.textTheme.titleSmall),
                    ],
                  ),
                ),
                Expanded(child: _buildContent(context, ref, data, theme)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    oh.CapabilityUpdatedData? data,
    ThemeData theme,
  ) {
    if (data == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('还没有工具信息', textAlign: TextAlign.center),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _InfoRow(
          label: 'Agent',
          value: data.agentId,
          icon: Icons.fingerprint,
        ),
        const SizedBox(height: 16),

        // ── Tools ──
        _SectionHeader(
          title: '可用工具 · ${data.capabilities.length} 个',
          icon: Icons.build_outlined,
          theme: theme,
        ),
        const SizedBox(height: 8),
        if (data.capabilities.isEmpty)
          Text('这个 agent 没有声明工具',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant))
        else
          ...data.capabilities.map((cap) => _ToolCard(
                capability: cap,
                theme: theme,
                conversationId: ref.read(activeConversationIdProvider),
              )),

        const SizedBox(height: 16),

        // ── System Prompt ──
        if (data.context != null) ...[
          _SectionHeader(
            title: '系统提示词',
            icon: Icons.description_outlined,
            theme: theme,
          ),
          const SizedBox(height: 8),
          if (data.context!['system_prompt'] != null)
            _SystemPromptButton(
              prompt: data.context!['system_prompt'].toString(),
              theme: theme,
            ),
          const SizedBox(height: 8),
          if (data.context!['model'] != null)
            _InfoRow(
              label: '模型',
              value: _extractModelName(data.context!['model']),
              icon: Icons.memory,
            ),
        ],
      ],
    );
  }

  String _extractModelName(dynamic model) {
    if (model is String) return model;
    if (model is Map) return model['name'] as String? ?? model.toString();
    return model.toString();
  }
}

// ═══════════════════════════════════════════════════════════════
//  Tool Card — collapsed by default, expand → form with inputs
// ═══════════════════════════════════════════════════════════════

class _ToolCard extends ConsumerStatefulWidget {
  const _ToolCard({
    required this.capability,
    required this.theme,
    required this.conversationId,
  });

  final Map<String, dynamic> capability;
  final ThemeData theme;
  final String? conversationId;

  @override
  ConsumerState<_ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends ConsumerState<_ToolCard> {
  bool _expanded = false;
  bool _showOptional = false;
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, bool> _boolValues = {};
  String? _invocationId;

  String get _toolName =>
      widget.capability['name'] as String? ??
      widget.capability['id'] as String? ??
      'unknown';
  String get _toolId =>
      widget.capability['id'] as String? ?? _toolName;

  /// What the tool is for, in words, plus how much it wants from you.
  String get _toolGloss {
    final category = toolCategory(_toolName);
    final total = _properties.length;
    if (total == 0) return '$category · 无需填写';
    final needed = _required.length;
    return needed == 0 ? '$category · $total 项可选' : '$category · 需填 $needed 项';
  }

  Map<String, dynamic>? get _inputSchema =>
      widget.capability['input_schema'] as Map<String, dynamic>?;

  Map<String, dynamic> get _properties =>
      (_inputSchema?['properties'] as Map<String, dynamic>?) ?? {};

  List<String> get _required =>
      (_inputSchema?['required'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList() ??
      [];

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(String name) {
    return _controllers.putIfAbsent(name, () => TextEditingController());
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final category = widget.capability['category'] as String?;
    final invocations = ref.watch(toolInvocationsProvider);
    final connected = ref.watch(connectionStateProvider).valueOrNull ==
        oh.ConnectionState.connected;
    final invState = _invocationId != null ? invocations[_invocationId] : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          // Status has to stay readable at a glance, but the default
          // Material green and red are far louder than anything else in
          // the console. Muted to sit inside the zinc palette.
          color: invState?.status == 'success'
              ? const Color(0xFF639922).withValues(alpha: 0.45)
              : invState?.status == 'error'
                  ? theme.colorScheme.error.withValues(alpha: 0.45)
                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header (always visible) ──
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(_categoryIcon(category), size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  // The tool's own identifier stays — it is how the
                  // agent names it — with a plain-language gloss beneath.
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_toolName,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w500)),
                        const SizedBox(height: 1),
                        Text(
                          _toolGloss,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 10,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (invState != null) ...[
                    _StatusDot(status: invState.status),
                    const SizedBox(width: 6),
                  ],
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          // ── Expanded form ──
          if (_expanded) ...[
            Divider(height: 1, color: theme.colorScheme.outlineVariant),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ..._buildFormFields(theme),
                  const SizedBox(height: 12),
                  // Execute button. Disabled while the socket is down,
                  // with the reason on the button rather than discovered
                  // by pressing it.
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: connected && _canExecute() ? _execute : null,
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: Text(connected ? '执行' : '未连接'),
                    ),
                  ),
                  // Result
                  if (invState != null) ...[
                    const SizedBox(height: 12),
                    _ResultView(state: invState, theme: theme),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Build form fields from JSON Schema properties ──

  List<Widget> _buildFormFields(ThemeData theme) {
    final properties = _properties;
    if (properties.isEmpty) {
      return [
        Text('这个工具不需要填写参数',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ];
    }

    Widget field(String name, Map<String, dynamic> def) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _FormField(
          name: name,
          type: def['type'] as String? ?? 'string',
          description: def['description'] as String?,
          enumValues: (def['enum'] as List?)?.map((e) => e.toString()).toList(),
          isRequired: _required.contains(name),
          controller: _controllerFor(name),
          boolValue: _boolValues[name],
          onBoolChanged: (v) => setState(() => _boolValues[name] = v),
          onChanged: () => setState(() {}),
          theme: theme,
        ),
      );
    }

    // Required first and always visible; everything else is tucked away.
    // A tool with a dozen optional knobs reads as a wall of boxes otherwise,
    // and most of them are never touched.
    final required = properties.entries
        .where((e) => _required.contains(e.key))
        .map((e) => field(e.key, e.value as Map<String, dynamic>))
        .toList();

    final optional = properties.entries
        .where((e) => !_required.contains(e.key))
        .toList();

    if (optional.isEmpty) return required;

    return [
      ...required,
      const SizedBox(height: 2),
      _OptionalSection(
        count: optional.length,
        expanded: _showOptional,
        onToggle: () => setState(() => _showOptional = !_showOptional),
        theme: theme,
        child: Column(
          children: optional
              .map((e) => field(e.key, e.value as Map<String, dynamic>))
              .toList(),
        ),
      ),
    ];
  }

  bool _canExecute() {
    // Try to get conversationId from the provider, or from SDK's active list.
    final convId = widget.conversationId ?? _sdkConversationId();
    if (convId == null) return false;
    for (final name in _required) {
      final def = _properties[name];
      if (def == null) continue;
      final type = def['type'] as String? ?? 'string';
      if (type == 'boolean') continue;
      final val = _controllerFor(name).text.trim();
      if (val.isEmpty) return false;
    }
    return true;
  }

  String? _sdkConversationId() {
    final client = ref.read(openHumanClientProvider);
    final convs = client.activeConversations;
    return convs.isNotEmpty ? convs.first : null;
  }

  Future<void> _execute() async {
    final conversationId = widget.conversationId ?? _sdkConversationId();
    if (conversationId == null) return;

    // The idle connection gets reaped upstream, and sending over a dead
    // socket throws. Uncaught, that killed the whole app rather than
    // failing this one call.
    final connection = ref.read(connectionStateProvider).valueOrNull;
    if (connection != oh.ConnectionState.connected) {
      _showError('连接已断开，请先点顶栏的重连按钮');
      return;
    }

    // Build input map
    final input = <String, dynamic>{};
    for (final entry in _properties.entries) {
      final name = entry.key;
      final def = entry.value as Map<String, dynamic>;
      final type = def['type'] as String? ?? 'string';

      if (type == 'boolean') {
        input[name] = _boolValues[name] ?? false;
      } else if (type == 'integer' || type == 'number') {
        final text = _controllerFor(name).text.trim();
        if (text.isNotEmpty) {
          input[name] = type == 'integer' ? int.tryParse(text) : double.tryParse(text);
        }
      } else if (type == 'array') {
        // Arrays are entered as comma-separated values
        final text = _controllerFor(name).text.trim();
        if (text.isNotEmpty) {
          input[name] = text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
        }
      } else {
        final text = _controllerFor(name).text.trim();
        if (text.isNotEmpty) {
          input[name] = text;
        }
      }
    }

    final invId = 'inv_${DateTime.now().microsecondsSinceEpoch}';
    setState(() => _invocationId = invId);

    ref.read(toolInvocationsProvider.notifier).addPending(invId, _toolId, _toolName);

    // `invokeTool` is async, so a failure arrives as a rejected Future —
    // without the await this try/catch never sees it, and an unhandled
    // Future error takes the application down.
    try {
      await ref
          .read(openHumanClientProvider)
          .invokeTool(conversationId, _toolId, input);
    } catch (e) {
      if (!mounted) return;
      setState(() => _invocationId = null);
      _showError('执行失败：${_messageFor(e)}');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// Sending is the only step that can realistically fail here, and its
  /// exception names the connection rather than anything actionable.
  String _messageFor(Object error) {
    final text = error.toString();
    if (text.contains('not connected')) return '连接已断开';
    return text.replaceFirst(RegExp(r'^[^:]*:\s*'), '');
  }

  IconData _categoryIcon(String? category) {
    switch (category) {
      case 'terminal': return Icons.terminal;
      case 'filesystem': return Icons.folder_outlined;
      case 'web': return Icons.language;
      case 'subagent': return Icons.account_tree_outlined;
      case 'task_management': return Icons.task_alt;
      case 'ui': return Icons.web_outlined;
      case 'communication': return Icons.chat_outlined;
      case 'skill': return Icons.school_outlined;
      case 'scheduling': return Icons.schedule_outlined;
      default: return Icons.build_outlined;
    }
  }
}

// ═══════════════════════════════════════════════════════════════
//  Form Field — renders the right input widget per schema type
// ═══════════════════════════════════════════════════════════════

/// Holds a tool's optional parameters out of the way.
///
/// A disclosure rather than a second expansion level of the card — the
/// required fields stay put above it.
class _OptionalSection extends StatelessWidget {
  const _OptionalSection({
    required this.count,
    required this.expanded,
    required this.onToggle,
    required this.child,
    required this.theme,
  });

  final int count;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  '更多选项（可选 · $count 项）',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (expanded) ...[
          const SizedBox(height: 4),
          child,
        ],
      ],
    );
  }
}

class _FormField extends StatelessWidget {
  const _FormField({
    required this.name,
    required this.type,
    required this.description,
    required this.enumValues,
    required this.isRequired,
    required this.controller,
    required this.boolValue,
    required this.onBoolChanged,
    required this.onChanged,
    required this.theme,
  });

  final String name;
  final String type;
  final String? description;
  final List<String>? enumValues;
  final bool isRequired;
  final TextEditingController controller;
  final bool? boolValue;
  final ValueChanged<bool> onBoolChanged;

  /// Notified on every keystroke — lets the parent re-evaluate the
  /// Execute button's enabled state (`_canExecute` depends on the
  /// controller's text, which does not trigger rebuilds by itself).
  final VoidCallback onChanged;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final translated = parameterLabel(name);
    final showsOriginal = translated != name;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label row. The translated name leads; the schema name stays
        // alongside it, since that is what the agent's own docs call it.
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                translated,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            if (showsOriginal) ...[
              const SizedBox(width: 6),
              Text(
                name,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontFamily: 'GeistMono',
                  fontSize: 10,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(width: 6),
            if (isRequired)
              Text(
                '必填',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 10,
                  color: theme.colorScheme.error,
                ),
              ),
          ],
        ),
        // The description is the agent's own wording, in English more
        // often than not. Shown quietly — it is a hint, not the label.
        if (description != null) ...[
          const SizedBox(height: 2),
          Text(description!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 11,
                height: 1.4,
              )),
        ],
        const SizedBox(height: 5),
        _buildInput(),
      ],
    );
  }

  Widget _buildInput() {
    // A fixed set of choices is a menu, not a box to type into.
    if (enumValues != null && enumValues!.isNotEmpty) {
      return DropdownButtonFormField<String>(
        initialValue: enumValues!.contains(controller.text) &&
                controller.text.isNotEmpty
            ? controller.text
            : null,
        isDense: true,
        isExpanded: true,
        decoration: InputDecoration(
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm)),
          hintText: '请选择…',
        ),
        style: theme.textTheme.bodySmall,
        items: enumValues!
            .map((v) => DropdownMenuItem(value: v, child: Text(v)))
            .toList(),
        onChanged: (v) {
          controller.text = v ?? '';
          onChanged();
        },
      );
    }

    switch (type) {
      case 'boolean':
        // A bare switch loses its question once you flip it, so the row
        // keeps the choice visible on both sides.
        return Row(
          children: [
            Switch(
              value: boolValue ?? false,
              onChanged: onBoolChanged,
            ),
            const SizedBox(width: 8),
            Text(
              boolValue == true ? '是' : '否',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );
      case 'integer':
      case 'number':
        return TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
            hintText: '0',
          ),
          style: theme.textTheme.bodySmall,
          onChanged: (_) => onChanged(),
        );
      case 'array':
        return TextField(
          controller: controller,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
            hintText: '多个用逗号分隔，如 a, b',
          ),
          style: theme.textTheme.bodySmall,
          onChanged: (_) => onChanged(),
        );
      default: // string
        return TextField(
          controller: controller,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
            hintText: '请输入…',
          ),
          style: theme.textTheme.bodySmall,
          onChanged: (_) => onChanged(),
        );
    }
  }
}

// ═══════════════════════════════════════════════════════════════
//  Type Badge & Status Dot
// ═══════════════════════════════════════════════════════════════

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'success' => const Color(0xFF639922),
      'error' => Theme.of(context).colorScheme.error,
      'timeout' => const Color(0xFF8A7355),
      'pending' => const Color(0xFF5B7C99),
      _ => const Color(0xFF71717B),
    };
    final icon = switch (status) {
      'success' => Icons.check_circle,
      'error' => Icons.error,
      'timeout' => Icons.timer_off,
      'pending' => Icons.hourglass_top,
      _ => Icons.circle_outlined,
    };
    return Icon(icon, size: 14, color: color);
  }
}

// ═══════════════════════════════════════════════════════════════
//  Result View
// ═══════════════════════════════════════════════════════════════

class _ResultView extends StatelessWidget {
  const _ResultView({required this.state, required this.theme});
  final ToolInvocationState state;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _StatusDot(status: state.status),
              const SizedBox(width: 6),
              Text('执行结果 · ${statusLabel(state.status)}',
                  style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
          if (state.error != null) ...[
            const SizedBox(height: 4),
            Text(state.error!,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
          ],
          if (state.output != null) ...[
            const SizedBox(height: 4),
            SelectableText(
              _formatOutput(state.output),
              style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace', fontSize: 11),
              maxLines: 8,
            ),
          ],
        ],
      ),
    );
  }

  String _formatOutput(dynamic output) {
    if (output is String) return output;
    try {
      return const JsonEncoder.withIndent('  ').convert(output);
    } catch (_) {
      return output.toString();
    }
  }
}

// ═══════════════════════════════════════════════════════════════
//  System Prompt Button → opens full screen
// ═══════════════════════════════════════════════════════════════

class _SystemPromptButton extends StatelessWidget {
  const _SystemPromptButton({required this.prompt, required this.theme});
  final String prompt;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final lineCount = '\n'.allMatches(prompt).length + 1;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => _openFullScreen(context),
        icon: Icon(Icons.description_outlined, size: 18, color: theme.colorScheme.primary),
        label: Text('查看完整提示词（$lineCount 行）'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
    );
  }

  void _openFullScreen(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, anim, __) => _SystemPromptFullScreen(prompt: prompt),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }
}

class _SystemPromptFullScreen extends StatelessWidget {
  const _SystemPromptFullScreen({required this.prompt});
  final String prompt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('系统提示词'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_outlined),
            tooltip: 'Copy',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: prompt));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('已复制到剪贴板'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: SelectableText(
            prompt,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: 'monospace',
              fontSize: 13,
              height: 1.7,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  Small reusable widgets
// ═══════════════════════════════════════════════════════════════

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.icon, required this.theme});
  final String title;
  final IconData icon;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(title,
            style: theme.textTheme.labelMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, required this.icon});
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              Text(value, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}
