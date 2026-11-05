/// History types — what a console fetches over HTTP on startup.
///
/// The WebSocket backlog carries only undelivered messages, so a newly
/// opened console would otherwise show an empty timeline. These mirror the
/// shapes returned by `GET /v1/conversations` and
/// `GET /v1/conversations/:id/messages`.
library;

/// A conversation as returned by the history endpoint.
class HistoryConversation {
  const HistoryConversation({
    required this.id,
    this.agentId,
    this.agentName,
    this.humanId,
    this.lastMessageAt,
    this.createdAt,
    this.type,
    this.title,
    this.memberCount,
  });

  factory HistoryConversation.fromJson(Map<String, dynamic> json) {
    return HistoryConversation(
      id: json['id'] as String? ?? '',
      agentId: json['agent_id'] as String?,
      agentName: json['agent_name'] as String?,
      humanId: json['human_id'] as String?,
      lastMessageAt: _parseDate(json['last_message_at']),
      createdAt: _parseDate(json['created_at']),
      type: json['type'] as String?,
      title: json['title'] as String?,
      memberCount: json['member_count'] as int?,
    );
  }

  final String id;
  final String? agentId;

  /// Display name of the agent, as the console should show it.
  final String? agentName;
  final String? humanId;
  final DateTime? lastMessageAt;
  final DateTime? createdAt;

  /// `"group"` for a room, `"agent_human"` otherwise (§10.3).
  final String? type;

  /// Room title (groups only).
  final String? title;

  /// Participant count — shown next to the group marker (§10.3).
  final int? memberCount;

  /// Whether this conversation is a group room.
  bool get isGroup => type == 'group';

  /// Most recent activity wins; conversations without a timestamp fall to
  /// the bottom rather than pretending to be epoch-old.
  DateTime get sortKey => lastMessageAt ?? createdAt ?? DateTime(0);
}

/// A message as returned by the history endpoint.
class HistoryMessage {
  const HistoryMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.senderType,
    this.senderName,
    this.text = '',
    this.images = const [],
    this.createdAt,
    this.request,
  });

  factory HistoryMessage.fromJson(Map<String, dynamic> json) {
    return HistoryMessage(
      id: json['id'] as String? ?? '',
      conversationId: json['conversation_id'] as String? ?? '',
      senderId: json['sender_id'] as String? ?? '',
      senderType: json['sender_type'] as String? ?? 'agent',
      senderName: json['sender_name'] as String?,
      text: json['text'] as String? ?? '',
      images:
          (json['images'] as List? ?? const []).whereType<String>().toList(),
      createdAt: _parseDate(json['created_at']),
      request: json['request'] is Map<String, dynamic>
          ? json['request'] as Map<String, dynamic>
          : null,
    );
  }

  /// The request's shape as the server recorded it: for an API task its
  /// kind (`"api"`), endpoint, answer contract, spec and deadline.
  final Map<String, dynamic>? request;

  final String id;
  final String conversationId;
  final String senderId;
  final String senderType;

  /// `"human"` or `"agent"`.
  final String? senderName;
  final String text;
  final List<String> images;
  final DateTime? createdAt;
}

DateTime? _parseDate(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value);
}
