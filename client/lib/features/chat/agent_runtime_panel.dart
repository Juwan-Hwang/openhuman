/// The other side's tools — what their tool declared it can do — and the
/// invoker behind each one, embedded in the details pane.
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
  ToolInvocationState(
      {required this.toolId, required this.toolName, this.status = 'pending'});

  final String toolId;
  final String toolName;
  String status; // 'pending', 'success', 'error', 'timeout'
  dynamic output;
  String? error;
}

/// Provider tracking pending tool invocations.
final toolInvocationsProvider = StateNotifierProvider<ToolInvocationNotifier,
    Map<String, ToolInvocationState>>((ref) {
  return ToolInvocationNotifier(ref);
});

class ToolInvocationNotifier
    extends StateNotifier<Map<String, ToolInvocationState>> {
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

/// The tools a caller declared, their system prompt and model — the
/// technical half of the details pane, embedded there under a fold.
class RuntimeTools extends ConsumerWidget {
  const RuntimeTools({super.key, required this.data});

  final oh.CapabilityUpdatedData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ctx = data.context;
    final prompt = ctx?['system_prompt'];
    final model = ctx?['model'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (data.capabilities.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Sp.x2),
            child: Text(
              '对方的工具没有声明可调用的功能',
              style: Ty.small.copyWith(color: Dk.t3, fontSize: 12),
            ),
          )
        else
          for (final cap in data.capabilities)
            _ToolCard(
              capability: cap,
              theme: theme,
              conversationId: ref.read(activeConversationIdProvider),
            ),
        if (prompt != null) ...[
          const SizedBox(height: Sp.x2),
          _SystemPromptButton(prompt: prompt.toString(), theme: theme),
        ],
        if (model != null) ...[
          const SizedBox(height: Sp.x3),
          _InfoRow(
            label: '对方用的模型',
            value: model is Map
                ? (model['name'] as String? ?? model.toString())
                : model.toString(),
            icon: Icons.memory,
          ),
        ],
      ],
    );
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
  String get _toolId => widget.capability['id'] as String? ?? _toolName;

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
        color: _expanded ? Dk.p2 : Dk.p1,
        borderRadius: BorderRadius.circular(Rd.lg),
        border: Border.all(
          // Status stays readable at a glance without shouting.
          color: invState?.status == 'success'
              ? Dk.ok.withValues(alpha: 0.35)
              : invState?.status == 'error'
                  ? Dk.danger.withValues(alpha: 0.4)
                  : _expanded
                      ? Dk.line2
                      : Dk.line,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header (always visible) ──
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(Rd.md),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: Dk.blueFloor,
                      borderRadius: BorderRadius.circular(Rd.sm),
                      border: Border.all(color: Dk.blueLine),
                    ),
                    child: Icon(
                      _categoryIcon(category),
                      size: 15,
                      color: Dk.blue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // The tool's own identifier stays — it is how the
                  // agent names it — with a plain-language gloss beneath.
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _toolName,
                          style: Ty.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _toolGloss,
                          style: Ty.meta.copyWith(fontSize: 10.5),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (invState != null) ...[
                    _StatusDot(status: invState.status),
                    const SizedBox(width: 6),
                  ],
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: Mo.base,
                    curve: Mo.expo,
                    child: const Icon(
                      Icons.expand_more_rounded,
                      size: 18,
                      color: Dk.t3,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // ── Expanded form ──
          if (_expanded) ...[
            const Divider(height: 1, color: Dk.line),
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
        Text('这个工具不需要填写参数', style: Ty.small.copyWith(color: Dk.t2)),
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

    final optional =
        properties.entries.where((e) => !_required.contains(e.key)).toList();

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
          input[name] =
              type == 'integer' ? int.tryParse(text) : double.tryParse(text);
        }
      } else if (type == 'array') {
        // Arrays are entered as comma-separated values
        final text = _controllerFor(name).text.trim();
        if (text.isNotEmpty) {
          input[name] = text
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();
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

    ref
        .read(toolInvocationsProvider.notifier)
        .addPending(invId, _toolId, _toolName);

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
    return switch (category) {
      'terminal' || 'shell' => Icons.terminal_rounded,
      'filesystem' || 'fs' || 'file' => Icons.folder_outlined,
      'git' || 'vcs' => Icons.commit_rounded,
      'web' || 'browser' => Icons.language_rounded,
      'subagent' => Icons.account_tree_outlined,
      'task_management' => Icons.task_alt_rounded,
      'ui' => Icons.web_outlined,
      'communication' => Icons.chat_bubble_outline_rounded,
      'skill' => Icons.school_outlined,
      'scheduling' => Icons.schedule_rounded,
      'search' => Icons.search_rounded,
      _ => Icons.extension_outlined,
    };
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
          borderRadius: BorderRadius.circular(Rd.sm),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: Dk.t2,
                ),
                const SizedBox(width: 4),
                Text(
                  '更多选项（可选 · $count 项）',
                  style: Ty.small.copyWith(
                    fontSize: 11.5,
                    color: Dk.t2,
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
                style: Ty.small.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Dk.t1,
                ),
              ),
            ),
            if (showsOriginal) ...[
              const SizedBox(width: 6),
              Text(
                name,
                style: Ty.small.copyWith(
                  fontFamily: 'GeistMono',
                  fontSize: 10,
                  color: Dk.t2,
                ),
              ),
            ],
            const SizedBox(width: 6),
            if (isRequired)
              Text(
                '必填',
                style: Ty.small.copyWith(
                  fontSize: 10,
                  color: Dk.danger,
                ),
              ),
          ],
        ),
        // The description is the agent's own wording, in English more
        // often than not. Shown quietly — it is a hint, not the label.
        if (description != null) ...[
          const SizedBox(height: 2),
          Text(description!,
              style: Ty.small.copyWith(
                color: Dk.t2,
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
        initialValue:
            enumValues!.contains(controller.text) && controller.text.isNotEmpty
                ? controller.text
                : null,
        isDense: true,
        isExpanded: true,
        decoration: InputDecoration(
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border:
              OutlineInputBorder(borderRadius: BorderRadius.circular(Rd.sm)),
          hintText: '请选择…',
        ),
        style: Ty.small,
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
              style: Ty.small.copyWith(
                color: Dk.t2,
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
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(Rd.sm)),
            hintText: '0',
          ),
          style: Ty.small,
          onChanged: (_) => onChanged(),
        );
      case 'array':
        return TextField(
          controller: controller,
          decoration: InputDecoration(
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(Rd.sm)),
            hintText: '多个用逗号分隔，如 a, b',
          ),
          style: Ty.small,
          onChanged: (_) => onChanged(),
        );
      default: // string
        return TextField(
          controller: controller,
          decoration: InputDecoration(
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(Rd.sm)),
            hintText: '请输入…',
          ),
          style: Ty.small,
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
      'success' => Dk.ok,
      'error' => Dk.danger,
      'timeout' => Dk.warn,
      'pending' => Dk.blue,
      _ => Dk.t3,
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
        color: Dk.codeFloor,
        borderRadius: BorderRadius.circular(Rd.sm),
        border: Border.all(color: Dk.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _StatusDot(status: state.status),
              const SizedBox(width: 6),
              Text('执行结果 · ${statusLabel(state.status)}',
                  style: Ty.small
                      .copyWith(fontSize: 11.5, fontWeight: FontWeight.w600)),
            ],
          ),
          if (state.error != null) ...[
            const SizedBox(height: 4),
            Text(state.error!, style: Ty.small.copyWith(color: Dk.danger)),
          ],
          if (state.output != null) ...[
            const SizedBox(height: 4),
            SelectableText(
              _formatOutput(state.output),
              style: Ty.small.copyWith(
                  fontFamily: 'GeistMono',
                  fontFamilyFallback: const ['NotoSansSC'],
                  fontSize: 11),
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
        icon: const Icon(Icons.description_outlined, size: 18, color: Dk.t2),
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
            style: Ty.body.copyWith(
              fontFamily: 'GeistMono',
              fontFamilyFallback: const ['NotoSansSC'],
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

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Dk.bg,
        borderRadius: BorderRadius.circular(Rd.md),
        border: Border.all(color: Dk.line),
      ),
      child: Row(
        children: [
          Text(label, style: Ty.label),
          const SizedBox(width: Sp.x3),
          Expanded(
            child: SelectableText(
              value,
              style: Ty.code.copyWith(color: Dk.t1, height: 1.3),
              maxLines: 1,
            ),
          ),
          Icon(icon, size: 14, color: Dk.t4),
        ],
      ),
    );
  }
}
