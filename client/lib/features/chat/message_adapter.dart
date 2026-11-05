/// Message adapter — turns SDK events into timeline messages.
///
/// OpenHuman is two people talking. The other side types in their own AI
/// tool, which is only the transport: the server peels its wrapper off,
/// so what arrives here is what that person wrote, and it is shown as a
/// message from them, at the same weight as mine.
///
/// ```
/// OpenHuman SDK               →    timeline (flutter_chat_types)
/// ─────────────────────────────────────────────────────────────
/// MessageReceivedData          →    TextMessage
///   .images (image/*)          →    ImageMessage, one per picture
///   .images (audio, video, …)  →    FileMessage, one per file
///   request (raw event)        →    metadata['request'] (API tasks)
/// HistoryMessage               →    the same
/// ```
///
/// "Me" is decided by sender id, never sender type: in a room other
/// people's messages must not collapse onto mine (§10.1).
library;

import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:openhuman_sdk_dart/openhuman.dart' as oh;

import '../../core/tasks.dart';

/// Metadata key holding the request shape of an incoming message.
const kRequest = 'request';

/// Metadata key for why a message of mine did not go out.
const kFailure = 'failure';

/// Metadata key marking a message of mine as the answer to a task.
const kAnswerOf = 'answerOf';

types.User _author(String id, String? name, types.User me) => id == me.id
    ? me
    : types.User(id: id, firstName: name ?? id, role: types.Role.user);

List<types.Message> _build({
  required String id,
  required types.User author,
  required int createdAt,
  required String text,
  required List<String> attachments,
  Map<String, dynamic>? request,
}) {
  final meta = request == null ? null : {kRequest: request};
  final out = <types.Message>[];
  // The server appends a `[图片]` marker for image-only messages; that
  // marker is redundant once the image itself is drawn.
  final clean = text.replaceAll('[图片]', '').trim();
  if (clean.isNotEmpty || attachments.isEmpty || meta != null) {
    out.add(
      types.TextMessage(
        author: author,
        createdAt: createdAt,
        id: id,
        text: clean.isEmpty ? text.replaceAll('[图片]', '').trim() : text,
        status: types.Status.delivered,
        metadata: meta,
      ),
    );
  }
  for (var i = 0; i < attachments.length; i++) {
    final uri = attachments[i];
    final decoded = decodeDataUrl(uri);
    final mime = decoded?.$1 ?? _mimeOfUrl(uri);
    final media = mediaOf(mime: mime, name: uri.split('?').first);
    final name = _nameFor(i, media, mime);
    if (media == AnswerMedia.image) {
      out.add(
        types.ImageMessage(
          author: author,
          createdAt: createdAt,
          // Distinct id per attachment: the list is keyed on message id.
          id: '$id-img$i',
          uri: uri,
          name: name,
          size: decoded?.$2.length ?? 0,
          status: types.Status.delivered,
        ),
      );
    } else {
      out.add(
        types.FileMessage(
          author: author,
          createdAt: createdAt,
          id: '$id-file$i',
          uri: uri,
          name: name,
          mimeType: mime,
          size: decoded?.$2.length ?? 0,
          status: types.Status.delivered,
        ),
      );
    }
  }
  return out;
}

String? _mimeOfUrl(String uri) {
  final m = mimeForName(uri.split('?').first);
  return m == 'application/octet-stream' ? null : m;
}

String _nameFor(int i, AnswerMedia? media, String? mime) {
  final n = i + 1;
  final ext = (mime ?? '').split('/').last;
  return switch (media) {
    AnswerMedia.image => '图片 $n',
    AnswerMedia.audio => '录音 $n${ext.isEmpty ? '' : '.$ext'}',
    AnswerMedia.video => '视频 $n${ext.isEmpty ? '' : '.$ext'}',
    AnswerMedia.json => '数据 $n.json',
    AnswerMedia.text => '文本 $n.txt',
    null => '文件 $n',
  };
}

/// A live `message.received`, with the request shape the raw event
/// carried (null for plain chat).
List<types.Message> messageReceivedToMessages(
  oh.MessageReceivedData data, {
  required DateTime eventTimestamp,
  required types.User humanUser,
  Map<String, dynamic>? request,
}) =>
    _build(
      id: data.messageId,
      author: _author(data.senderId, data.senderName, humanUser),
      createdAt: eventTimestamp.millisecondsSinceEpoch,
      text: data.text,
      attachments: data.images,
      request: request,
    );

/// A message from history.
List<types.Message> historyMessageToMessages(
  oh.HistoryMessage data, {
  required types.User humanUser,
}) =>
    _build(
      id: data.id,
      author: _author(data.senderId, data.senderName, humanUser),
      createdAt: (data.createdAt ?? DateTime.now()).millisecondsSinceEpoch,
      text: data.text,
      attachments: data.images,
      request: data.request,
    );

/// A reply of mine, before the server has it.
types.TextMessage buildOutgoingTextMessage({
  required String text,
  required types.User humanUser,
  required String messageId,
  String? answerOf,
}) {
  return types.TextMessage(
    author: humanUser,
    createdAt: DateTime.now().millisecondsSinceEpoch,
    id: messageId,
    text: text,
    status: types.Status.sending,
    metadata: answerOf == null ? null : {kAnswerOf: answerOf},
  );
}

/// The signed-in person as a timeline user.
types.User humanSessionToUser(oh.HumanSession? session) {
  if (session == null) {
    return const types.User(id: 'unknown');
  }
  return types.User(
    id: session.id,
    firstName: session.displayName,
    role: types.Role.admin,
  );
}

/// The API task a message carries, if any.
ApiTask? taskOf(types.Message m) {
  final r = m.metadata?[kRequest];
  return r is Map<String, dynamic>
      ? ApiTask.fromRequest(
          r,
          receivedAt: DateTime.fromMillisecondsSinceEpoch(m.createdAt ?? 0),
        )
      : null;
}
