/// Plain models for the human-side REST surface beyond chat history:
/// answering API tasks with files (`/v1/seat/reply`), the files library
/// (`/v1/files`), and the model name callers see (`/v1/seat/model-name`).
library;

import 'dart:convert';
import 'dart:typed_data';

/// A file sent with an answer: the picture an image request asked for,
/// the audio of a speech request, the clip of a video request.
class ReplyAttachment {
  const ReplyAttachment({required this.name, required this.bytes, this.mime});

  final String name;
  final Uint8List bytes;

  /// Sniffed by the server when absent.
  final String? mime;

  Map<String, dynamic> toJson() => {
        'name': name,
        if (mime != null) 'mime': mime,
        'data': base64Encode(bytes),
      };
}

/// What `POST /v1/seat/reply` said about an answer.
class AnswerResult {
  const AnswerResult({
    required this.ok,
    this.live = false,
    this.turnEnded = false,
    this.abandoned = false,
    this.errorCode,
    this.errorMessage,
  });

  factory AnswerResult.fromJson(Map<String, dynamic> j) => AnswerResult(
        ok: j['ok'] == true,
        live: j['live'] == true,
        turnEnded: j['turn_ended'] == true,
        abandoned: j['abandoned'] == true,
      );

  factory AnswerResult.refused(Map<String, dynamic> j) {
    final e = j['error'];
    return AnswerResult(
      ok: false,
      errorCode: e is Map ? e['code'] as String? : null,
      errorMessage: e is Map ? e['message'] as String? : j.toString(),
    );
  }

  /// The server took the answer.
  final bool ok;

  /// Someone was still waiting for it.
  final bool live;
  final bool turnEnded;

  /// The asker stopped waiting before the answer arrived (an API task
  /// past its deadline): there is nobody left to deliver it to.
  final bool abandoned;

  /// `bad_answer` when the server's task check refused the answer.
  final String? errorCode;
  final String? errorMessage;
}

/// One entry of the files library (`GET /v1/files`).
class StoredFileInfo {
  const StoredFileInfo({
    required this.id,
    required this.filename,
    required this.bytes,
    this.mime,
    this.purpose,
    this.createdAt,
  });

  factory StoredFileInfo.fromJson(Map<String, dynamic> j) {
    final ts = j['created_at'];
    return StoredFileInfo(
      id: j['id'] as String? ?? '',
      filename: j['filename'] as String? ?? '',
      bytes: (j['bytes'] as num?)?.toInt() ?? 0,
      mime: (j['mime_type'] ?? j['mime']) as String?,
      purpose: j['purpose'] as String?,
      createdAt: ts is num
          ? DateTime.fromMillisecondsSinceEpoch(ts.toInt() * 1000, isUtc: true)
          : null,
    );
  }

  final String id;
  final String filename;
  final int bytes;
  final String? mime;
  final String? purpose;
  final DateTime? createdAt;
}

/// The model name callers put in their tool (`openhuman-human` unless
/// someone renamed it), and whether the server's owner pinned it.
class ModelName {
  const ModelName({required this.name, this.locked = false});
  final String name;
  final bool locked;
}

/// Someone who holds a caller key from this seat (`/v1/seat/caller-keys`).
/// The key itself is never listed: it is shown once, when made.
class CallerKey {
  const CallerKey({
    required this.id,
    required this.name,
    this.agentId,
    this.revoked = false,
    this.apiKey,
  });

  factory CallerKey.fromJson(Map<String, dynamic> j) => CallerKey(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        agentId: j['agent_id'] as String?,
        revoked: j['revoked'] == true,
        apiKey: j['api_key'] as String?,
      );

  final String id;
  final String name;

  /// The identity their messages arrive under.
  final String? agentId;
  final bool revoked;

  /// Only on the key just made.
  final String? apiKey;
}
