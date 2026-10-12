/// Message adapter — bridges OpenHuman SDK events to Flyer Chat types.
///
/// ## Architectural Principle
///
/// In OpenHuman, the **Human** is the real participant. The **Agent**
/// is an external AI tool (Trae, Codex, WorkBuddy) that communicates
/// via the OpenAI API. The agent is **not** a chat user — it is a
/// connection endpoint whose runtime metadata (system prompt, model,
/// tools) is displayed in a separate panel, not in the message timeline.
///
/// ## Conversion Map
///
/// ```
/// OpenHuman SDK               →    Flyer Chat
/// ─────────────────────────────────────────────
/// MessageReceivedData          →    types.TextMessage
///   .messageId                 →    .id
///   .senderId                  →    author.id
///   .senderName                →    author.firstName (fallback to senderId)
///   .senderType                →    (ignored — not used for role assignment)
///   .text                      →    .text
///   (event timestamp)          →    .createdAt (ms)
///
/// HumanSession                 →    types.User
///   .id                        →    .id
///   .displayName               →    .firstName
/// ```
library;

import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:openhuman_sdk_dart/openhuman.dart' as oh;

/// Converts an OpenHuman [MessageReceivedData] into Flyer Chat messages.
///
/// Usually one [types.TextMessage]. When the agent sent images, the text
/// (if any) comes first followed by one [types.ImageMessage] per image, so
/// the human can actually see what the question is about.
///
/// The `senderName` (if present) is used as the author's display name.
/// If absent, the `senderId` is used as a fallback.
List<types.Message> messageReceivedToMessages(
  oh.MessageReceivedData data, {
  required DateTime eventTimestamp,
  required types.User humanUser,
}) {
  // Use senderName if available, otherwise fall back to senderId.
  final displayName = data.senderName ?? data.senderId;

  // Messages the human sent come back over the socket too. They must carry
  // the *same* author object as the local user, because Flyer Chat decides
  // which side a bubble goes on by comparing author id with the chat's user
  // id — a sender id that merely happens to be the human's would land on
  // the wrong side whenever the session object had not resolved yet.
  final isHuman = data.senderType.toLowerCase() == 'human';
  final author = isHuman
      ? humanUser
      : types.User(
          id: data.senderId,
          firstName: displayName,
          // The agent is not a "user" in the chat sense — it is a
          // communication endpoint. We use Role.user so Flyer Chat
          // renders it on the left side (incoming), while the human's
          // own messages appear on the right (outgoing).
          role: types.Role.user,
        );
  final createdAt = eventTimestamp.millisecondsSinceEpoch;

  final out = <types.Message>[];

  // The text precedes any images so it reads as one turn. The server
  // appends a `[图片]` marker for image-only messages; that marker is
  // redundant once the image itself is rendered.
  final text = data.text.replaceAll('[图片]', '').trim();
  if (text.isNotEmpty || data.images.isEmpty) {
    out.add(
      types.TextMessage(
        author: author,
        createdAt: createdAt,
        id: data.messageId,
        text: data.text,
        status: types.Status.delivered,
      ),
    );
  }

  for (var i = 0; i < data.images.length; i++) {
    out.add(
      types.ImageMessage(
        author: author,
        createdAt: createdAt,
        // Distinct id per image: Flyer Chat keys the list on message id.
        id: '${data.messageId}-img$i',
        uri: data.images[i],
        name: '图片 ${i + 1}',
        // Images are never editable, but a size keeps the bubble from
        // collapsing before the bytes decode.
        size: 0,
        status: types.Status.delivered,
      ),
    );
  }

  return out;
}

/// Converts a history message into Flyer Chat messages.
///
/// Same shape as [messageReceivedToMessages]: text first, then one entry
/// per image. History carries its own timestamp and sender type, so the
/// resulting bubbles land on the correct side and in the right order.
List<types.Message> historyMessageToMessages(
  oh.HistoryMessage data, {
  required types.User humanUser,
}) {
  final isHuman = data.senderType.toLowerCase() == 'human';
  final createdAt =
      (data.createdAt ?? DateTime.now()).millisecondsSinceEpoch;

  final author = isHuman
      ? humanUser
      : types.User(
          id: data.senderId,
          firstName: data.senderName ?? data.senderId,
          role: types.Role.user,
        );

  final out = <types.Message>[];

  final text = data.text.replaceAll('[图片]', '').trim();
  if (text.isNotEmpty || data.images.isEmpty) {
    out.add(
      types.TextMessage(
        author: author,
        createdAt: createdAt,
        id: data.id,
        text: data.text,
        status: types.Status.delivered,
      ),
    );
  }

  for (var i = 0; i < data.images.length; i++) {
    out.add(
      types.ImageMessage(
        author: author,
        createdAt: createdAt,
        id: '${data.id}-img$i',
        uri: data.images[i],
        name: '图片 ${i + 1}',
        size: 0,
        status: types.Status.delivered,
      ),
    );
  }

  return out;
}

/// Builds a local [types.TextMessage] for the human's own outgoing reply.
types.TextMessage buildOutgoingTextMessage({
  required String text,
  required types.User humanUser,
  required String messageId,
}) {
  return types.TextMessage(
    author: humanUser,
    createdAt: DateTime.now().millisecondsSinceEpoch,
    id: messageId,
    text: text,
    status: types.Status.sent,
  );
}

/// Builds a Flyer Chat [types.User] from the OpenHuman [HumanSession].
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
