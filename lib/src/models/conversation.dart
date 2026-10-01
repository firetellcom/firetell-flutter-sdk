import 'dart:convert';

/// Represents the last message summary inside a conversation thread.
class ConversationLastMessage {
  const ConversationLastMessage({
    required this.id,
    required this.body,
    required this.direction,
    required this.senderType,
    this.senderId,
    this.createdAt,
  });

  factory ConversationLastMessage.fromJson(Map<String, dynamic> json) {
    return ConversationLastMessage(
      id: json['id'] as String? ?? '',
      body: json['body'] as String? ?? '',
      direction: json['direction'] as String? ?? 'inbound',
      senderType: json['sender_type'] as String? ?? 'client',
      senderId: json['sender_id'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'body': body,
        'direction': direction,
        'sender_type': senderType,
        if (senderId != null) 'sender_id': senderId,
        if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      };

  final String id;
  String get messageId => id;
  final String body;
  final String direction;
  final String senderType;
  final String? senderId;
  final DateTime? createdAt;

  @override
  String toString() =>
      'ConversationLastMessage(id: $id, body: $body, direction: $direction)';
}

/// Represents a persistent SMS conversation thread in Call Center Portal.
class Conversation {
  const Conversation({
    required this.id,
    this.workspaceId = '',
    this.phoneNumberId = '',
    required this.systemNumber,
    required this.clientNumber,
    this.clientName,
    this.contactId,
    this.assignedAgentId,
    this.assignedTeamId,
    this.status = 'open',
    this.unreadCount = 0,
    this.lastMessage,
    this.lastMessageAt,
    this.lastReadAt,
    this.createdAt,
    this.updatedAt,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id'] as String? ?? '',
      workspaceId: json['workspace_id'] as String? ?? '',
      phoneNumberId: json['phone_number_id'] as String? ?? '',
      systemNumber: json['system_number'] as String? ?? '',
      clientNumber: json['client_number'] as String? ?? '',
      clientName: json['client_name'] as String?,
      contactId: json['contact_id'] as String?,
      assignedAgentId: json['assigned_agent_id'] as String?,
      assignedTeamId: json['assigned_team_id'] as String?,
      status: json['status'] as String? ?? 'open',
      unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
      lastMessage: json['last_message'] is Map
          ? ConversationLastMessage.fromJson(
              json['last_message'] as Map<String, dynamic>,
            )
          : null,
      lastMessageAt: json['last_message_at'] != null
          ? DateTime.tryParse(json['last_message_at'].toString())
          : null,
      lastReadAt: json['last_read_at'] != null
          ? DateTime.tryParse(json['last_read_at'].toString())
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'workspace_id': workspaceId,
        'phone_number_id': phoneNumberId,
        'system_number': systemNumber,
        'client_number': clientNumber,
        if (clientName != null) 'client_name': clientName,
        if (contactId != null) 'contact_id': contactId,
        if (assignedAgentId != null) 'assigned_agent_id': assignedAgentId,
        if (assignedTeamId != null) 'assigned_team_id': assignedTeamId,
        'status': status,
        'unread_count': unreadCount,
        if (lastMessage != null) 'last_message': lastMessage!.toJson(),
        if (lastMessageAt != null)
          'last_message_at': lastMessageAt!.toIso8601String(),
        if (lastReadAt != null) 'last_read_at': lastReadAt!.toIso8601String(),
        if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
        if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
      };

  final String id;
  String get messageId => id;
  final String workspaceId;
  final String phoneNumberId;
  final String systemNumber;
  final String clientNumber;
  final String? clientName;
  final String? contactId;
  final String? assignedAgentId;
  final String? assignedTeamId;
  final String status;
  final int unreadCount;
  final ConversationLastMessage? lastMessage;
  final DateTime? lastMessageAt;
  final DateTime? lastReadAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Returns true if this conversation has unread messages.
  bool get isUnread => unreadCount > 0;

  /// Returns true if this conversation is open.
  bool get isOpen => status == 'open';

  /// Formatted contact display name.
  String get displayTitle =>
      (clientName != null && clientName!.isNotEmpty) ? clientName! : clientNumber;

  @override
  String toString() =>
      'Conversation(id: $id, clientNumber: $clientNumber, status: $status, unread: $unreadCount)';
}

/// Represents an individual SMS/MMS message inside a conversation thread.
class ConversationMessage {
  const ConversationMessage({
    required this.id,
    required this.conversationId,
    this.workspaceId = '',
    this.phoneNumberId = '',
    required this.from,
    this.fromNumber,
    required this.to,
    this.toNumber,
    required this.clientNumber,
    required this.body,
    required this.direction,
    required this.status,
    required this.senderType,
    this.senderId,
    this.mediaUrls = const [],
    this.cost,
    this.errorCode,
    this.errorMessage,
    this.createdAt,
    this.updatedAt,
  });

  factory ConversationMessage.fromJson(Map<String, dynamic> json) {
    return ConversationMessage(
      id: json['id'] as String? ?? '',
      conversationId: json['conversation_id'] as String? ?? '',
      workspaceId: json['workspace_id'] as String? ?? '',
      phoneNumberId: json['phone_number_id'] as String? ?? '',
      from: json['from'] as String? ?? '',
      fromNumber: json['from_number'] as String?,
      to: json['to'] as String? ?? '',
      toNumber: json['to_number'] as String?,
      clientNumber: json['client_number'] as String? ?? '',
      body: json['body'] as String? ?? '',
      direction: json['direction'] as String? ?? 'outbound',
      status: json['status'] as String? ?? 'queued',
      senderType: json['sender_type'] as String? ?? 'agent',
      senderId: json['sender_id'] as String?,
      mediaUrls: (json['media_urls'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      cost: (json['cost'] as num?)?.toDouble(),
      errorCode: json['error_code'] as String?,
      errorMessage: json['error_message'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'conversation_id': conversationId,
        'workspace_id': workspaceId,
        'phone_number_id': phoneNumberId,
        'from': from,
        if (fromNumber != null) 'from_number': fromNumber,
        'to': to,
        if (toNumber != null) 'to_number': toNumber,
        'client_number': clientNumber,
        'body': body,
        'direction': direction,
        'status': status,
        'sender_type': senderType,
        if (senderId != null) 'sender_id': senderId,
        'media_urls': mediaUrls,
        if (cost != null) 'cost': cost,
        if (errorCode != null) 'error_code': errorCode,
        if (errorMessage != null) 'error_message': errorMessage,
        if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
        if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
      };

  final String id;
  String get messageId => id;
  final String conversationId;
  final String workspaceId;
  final String phoneNumberId;
  final String from;
  final String? fromNumber;
  final String to;
  final String? toNumber;
  final String clientNumber;
  final String body;
  final String direction;
  final String status;
  final String senderType;
  final String? senderId;
  final List<String> mediaUrls;
  final double? cost;
  final String? errorCode;
  final String? errorMessage;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isInbound => direction == 'inbound';
  bool get isOutbound => direction == 'outbound';
  bool get hasMedia => mediaUrls.isNotEmpty;

  @override
  String toString() =>
      'ConversationMessage(id: $id, direction: $direction, status: $status, body: $body)';
}

/// Query parameters for listing conversations.
class ListConversationsQuery {
  const ListConversationsQuery({
    this.status,
    this.assignedTo,
    this.assignedTeamId,
    this.unreadOnly,
    this.search,
    this.page,
    this.limit,
  });

  final String? status;
  final String? assignedTo;
  final String? assignedTeamId;
  final bool? unreadOnly;
  final String? search;
  final int? page;
  final int? limit;

  Map<String, String> toQueryParams() {
    final params = <String, String>{};
    if (status != null && status!.isNotEmpty) params['status'] = status!;
    if (assignedTo != null && assignedTo!.isNotEmpty) {
      params['assigned_to'] = assignedTo!;
    }
    if (assignedTeamId != null && assignedTeamId!.isNotEmpty) {
      params['assigned_team_id'] = assignedTeamId!;
    }
    if (unreadOnly != null) params['unread_only'] = unreadOnly.toString();
    if (search != null && search!.isNotEmpty) params['search'] = search!;
    if (page != null) params['page'] = page.toString();
    if (limit != null) params['limit'] = limit.toString();
    return params;
  }
}

/// Paginated response for conversations inbox.
class ConversationsResponse {
  const ConversationsResponse({
    required this.data,
    required this.total,
    required this.page,
    required this.limit,
    required this.totalPages,
  });

  factory ConversationsResponse.fromJson(Map<String, dynamic> json) {
    final rawList = json['data'] as List<dynamic>? ?? [];
    final meta = json['meta'] as Map<String, dynamic>? ?? {};

    return ConversationsResponse(
      data: rawList
          .whereType<Map<String, dynamic>>()
          .map(Conversation.fromJson)
          .toList(),
      total: (meta['total'] as num?)?.toInt() ?? rawList.length,
      page: (meta['page'] as num?)?.toInt() ?? 1,
      limit: (meta['limit'] as num?)?.toInt() ?? 20,
      totalPages: (meta['total_pages'] as num?)?.toInt() ?? 1,
    );
  }

  final List<Conversation> data;
  final int total;
  final int page;
  final int limit;
  final int totalPages;
}

/// Query parameters for listing messages inside a conversation.
class ListMessagesQuery {
  const ListMessagesQuery({
    this.page,
    this.limit,
    this.before,
    this.after,
  });

  final int? page;
  final int? limit;
  final String? before;
  final String? after;

  Map<String, String> toQueryParams() {
    final params = <String, String>{};
    if (page != null) params['page'] = page.toString();
    if (limit != null) params['limit'] = limit.toString();
    if (before != null && before!.isNotEmpty) params['before'] = before!;
    if (after != null && after!.isNotEmpty) params['after'] = after!;
    return params;
  }
}

/// Paginated response for conversation messages.
class ConversationMessagesResponse {
  const ConversationMessagesResponse({
    required this.data,
    required this.total,
    required this.page,
    required this.limit,
    required this.totalPages,
  });

  factory ConversationMessagesResponse.fromJson(Map<String, dynamic> json) {
    final rawList = json['data'] as List<dynamic>? ?? [];
    final meta = json['meta'] as Map<String, dynamic>? ?? {};

    return ConversationMessagesResponse(
      data: rawList
          .whereType<Map<String, dynamic>>()
          .map(ConversationMessage.fromJson)
          .toList(),
      total: (meta['total'] as num?)?.toInt() ?? rawList.length,
      page: (meta['page'] as num?)?.toInt() ?? 1,
      limit: (meta['limit'] as num?)?.toInt() ?? 20,
      totalPages: (meta['total_pages'] as num?)?.toInt() ?? 1,
    );
  }

  final List<ConversationMessage> data;
  final int total;
  final int page;
  final int limit;
  final int totalPages;
}

/// Payload for starting a new conversation thread.
class StartConversationPayload {
  const StartConversationPayload({
    required this.from,
    required this.clientNumber,
    this.to,
    required this.body,
    this.mediaUrls,
    this.contactId,
    this.assignedAgentId,
    this.assignedTeamId,
  });

  final String from;
  final String clientNumber;
  final String? to;
  final String body;
  final List<String>? mediaUrls;
  final String? contactId;
  final String? assignedAgentId;
  final String? assignedTeamId;

  Map<String, dynamic> toJson() {
    final target = clientNumber.isNotEmpty ? clientNumber : (to ?? '');
    return {
      'from': from,
      'client_number': target,
      'body': body,
      if (mediaUrls != null && mediaUrls!.isNotEmpty) 'media_urls': mediaUrls,
      if (contactId != null) 'contact_id': contactId,
      if (assignedAgentId != null) 'assigned_agent_id': assignedAgentId,
      if (assignedTeamId != null) 'assigned_team_id': assignedTeamId,
    };
  }
}

/// Response returned when starting a conversation.
class StartConversationResponse {
  const StartConversationResponse({
    required this.conversation,
    required this.message,
  });

  factory StartConversationResponse.fromJson(Map<String, dynamic> json) {
    return StartConversationResponse(
      conversation: Conversation.fromJson(
        json['conversation'] as Map<String, dynamic>? ?? {},
      ),
      message: ConversationMessage.fromJson(
        json['message'] as Map<String, dynamic>? ?? {},
      ),
    );
  }

  final Conversation conversation;
  final ConversationMessage message;
}

/// Payload for sending an SMS/MMS message into an active conversation.
class SendConversationMessagePayload {
  const SendConversationMessagePayload({
    required this.body,
    this.mediaUrls,
  });

  final String body;
  final List<String>? mediaUrls;

  Map<String, dynamic> toJson() => {
        'body': body,
        if (mediaUrls != null && mediaUrls!.isNotEmpty) 'media_urls': mediaUrls,
      };
}

/// Payload for updating conversation metadata.
class UpdateConversationPayload {
  const UpdateConversationPayload({
    this.assignedAgentId,
    this.assignedTeamId,
    this.status,
  });

  final String? assignedAgentId;
  final String? assignedTeamId;
  final String? status;

  Map<String, dynamic> toJson() => {
        if (assignedAgentId != null) 'assigned_agent_id': assignedAgentId,
        if (assignedTeamId != null) 'assigned_team_id': assignedTeamId,
        if (status != null) 'status': status,
      };
}

/// Response returned after marking a conversation as read.
class MarkAsReadResponse {
  const MarkAsReadResponse({
    required this.ok,
    required this.conversationId,
  });

  factory MarkAsReadResponse.fromJson(Map<String, dynamic> json) {
    return MarkAsReadResponse(
      ok: json['ok'] as bool? ?? false,
      conversationId: json['conversation_id'] as String? ?? '',
    );
  }

  final bool ok;
  final String conversationId;
}

/// Real-time event emitted when an inbound SMS is received.
class MessageReceivedEvent {
  const MessageReceivedEvent({
    required this.id,
    required this.conversationId,
    required this.from,
    this.fromNumber,
    required this.to,
    this.toNumber,
    required this.clientNumber,
    this.clientName,
    required this.body,
    this.direction = 'inbound',
    this.status = 'received',
    this.senderType = 'client',
    this.mediaUrls = const [],
    this.phoneNumberId,
    this.unreadCount,
    this.createdAt,
    this.raw = const {},
  });

  factory MessageReceivedEvent.fromJson(Map<String, dynamic> json) {
    // Supports direct SSE stream, APNs payload, and FCM data payload (message_data or root data)
    final data = json['message_data'] is Map
        ? json['message_data'] as Map<String, dynamic>
        : (json['data'] is Map ? json['data'] as Map<String, dynamic> : json);

    final rawUnread = data['unread_count'];
    final unread = rawUnread is num
        ? rawUnread.toInt()
        : int.tryParse(rawUnread?.toString() ?? '');

    return MessageReceivedEvent(
      id: data['id'] as String? ?? data['message_id'] as String? ?? '',
      conversationId: data['conversation_id'] as String? ?? '',
      from: data['from'] as String? ?? data['from_number'] as String? ?? '',
      fromNumber: data['from_number'] as String? ?? data['from'] as String?,
      to: data['to'] as String? ?? data['to_number'] as String? ?? '',
      toNumber: data['to_number'] as String? ?? data['to'] as String?,
      clientNumber: data['client_number'] as String? ??
          data['from_number'] as String? ??
          data['from'] as String? ??
          '',
      clientName: data['client_name'] as String?,
      body: data['body'] as String? ?? '',
      direction: data['direction'] as String? ?? 'inbound',
      status: data['status'] as String? ?? 'received',
      senderType: data['sender_type'] as String? ?? 'client',
      mediaUrls: (data['media_urls'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      phoneNumberId: data['phone_number_id'] as String?,
      unreadCount: unread,
      createdAt: data['created_at'] != null
          ? DateTime.tryParse(data['created_at'].toString())
          : null,
      raw: json,
    );
  }

  final String id;
  String get messageId => id;
  final String conversationId;
  final String from;
  final String? fromNumber;
  final String to;
  final String? toNumber;
  final String clientNumber;
  final String? clientName;
  final String body;
  final String direction;
  final String status;
  final String senderType;
  final List<String> mediaUrls;
  final String? phoneNumberId;
  final int? unreadCount;
  final DateTime? createdAt;
  final Map<String, dynamic> raw;

  @override
  String toString() =>
      'MessageReceivedEvent(id: $id, conversationId: $conversationId, from: $from, body: $body)';
}

/// Real-time event emitted when an outbound SMS is dispatched.
class MessageSentEvent {
  const MessageSentEvent({
    required this.id,
    required this.conversationId,
    required this.from,
    this.fromNumber,
    required this.to,
    this.toNumber,
    required this.clientNumber,
    this.clientName,
    required this.body,
    this.direction = 'outbound',
    this.status = 'sent',
    this.senderType = 'agent',
    this.senderId,
    this.mediaUrls = const [],
    this.phoneNumberId,
    this.unreadCount,
    this.createdAt,
    this.raw = const {},
  });

  factory MessageSentEvent.fromJson(Map<String, dynamic> json) {
    final data = json['data'] is Map ? json['data'] as Map<String, dynamic> : json;

    return MessageSentEvent(
      id: data['id'] as String? ?? '',
      conversationId: data['conversation_id'] as String? ?? '',
      from: data['from'] as String? ?? '',
      fromNumber: data['from_number'] as String? ?? data['from'] as String?,
      to: data['to'] as String? ?? '',
      toNumber: data['to_number'] as String? ?? data['to'] as String?,
      clientNumber: data['client_number'] as String? ?? data['to'] as String? ?? '',
      clientName: data['client_name'] as String?,
      body: data['body'] as String? ?? '',
      direction: data['direction'] as String? ?? 'outbound',
      status: data['status'] as String? ?? 'sent',
      senderType: data['sender_type'] as String? ?? 'agent',
      senderId: data['sender_id'] as String?,
      mediaUrls: (data['media_urls'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      phoneNumberId: data['phone_number_id'] as String?,
      unreadCount: (data['unread_count'] as num?)?.toInt(),
      createdAt: data['created_at'] != null
          ? DateTime.tryParse(data['created_at'].toString())
          : null,
      raw: json,
    );
  }

  final String id;
  String get messageId => id;
  final String conversationId;
  final String from;
  final String? fromNumber;
  final String to;
  final String? toNumber;
  final String clientNumber;
  final String? clientName;
  final String body;
  final String direction;
  final String status;
  final String senderType;
  final String? senderId;
  final List<String> mediaUrls;
  final String? phoneNumberId;
  final int? unreadCount;
  final DateTime? createdAt;
  final Map<String, dynamic> raw;

  @override
  String toString() =>
      'MessageSentEvent(id: $id, conversationId: $conversationId, to: $to, body: $body)';
}

/// Real-time event emitted when message delivery receipt (DLR) transitions.
class MessageUpdatedEvent {
  const MessageUpdatedEvent({
    required this.id,
    this.conversationId,
    required this.status,
    this.cost,
    this.errorCode,
    this.errorMessage,
    this.updatedAt,
    this.raw = const {},
  });

  factory MessageUpdatedEvent.fromJson(Map<String, dynamic> json) {
    final data = json['data'] is Map ? json['data'] as Map<String, dynamic> : json;

    return MessageUpdatedEvent(
      id: data['id'] as String? ?? '',
      conversationId: data['conversation_id'] as String?,
      status: data['status'] as String? ?? '',
      cost: (data['cost'] as num?)?.toDouble(),
      errorCode: data['error_code'] as String?,
      errorMessage: data['error_message'] as String?,
      updatedAt: data['updated_at'] != null
          ? DateTime.tryParse(data['updated_at'].toString())
          : null,
      raw: json,
    );
  }

  final String id;
  String get messageId => id;
  final String? conversationId;
  final String status;
  final double? cost;
  final String? errorCode;
  final String? errorMessage;
  final DateTime? updatedAt;
  final Map<String, dynamic> raw;

  @override
  String toString() =>
      'MessageUpdatedEvent(id: $id, status: $status, errorCode: $errorCode)';
}

/// Real-time event emitted when a conversation thread status, assignment, or unread count updates.
class ConversationUpdatedEvent {
  const ConversationUpdatedEvent({
    required this.id,
    required this.workspaceId,
    this.phoneNumberId,
    this.systemNumber,
    this.clientNumber,
    this.clientName,
    this.assignedAgentId,
    this.assignedTeamId,
    this.status,
    this.unreadCount,
    this.lastMessage,
    this.lastMessageAt,
    this.lastReadAt,
    this.updatedAt,
    this.raw = const {},
  });

  factory ConversationUpdatedEvent.fromJson(Map<String, dynamic> json) {
    // Supports direct SSE stream, APNs payload, and FCM data payload
    final data = json['conversation_data'] is Map
        ? json['conversation_data'] as Map<String, dynamic>
        : (json['data'] is Map ? json['data'] as Map<String, dynamic> : json);

    final rawUnread = data['unread_count'];
    final unread = rawUnread is num
        ? rawUnread.toInt()
        : int.tryParse(rawUnread?.toString() ?? '');

    ConversationLastMessage? parseLastMessage(dynamic raw) {
      if (raw is Map<String, dynamic>) {
        return ConversationLastMessage.fromJson(raw);
      } else if (raw is Map) {
        return ConversationLastMessage.fromJson(raw.cast<String, dynamic>());
      } else if (raw is String && raw.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map<String, dynamic>) {
            return ConversationLastMessage.fromJson(decoded);
          } else if (decoded is Map) {
            return ConversationLastMessage.fromJson(decoded.cast<String, dynamic>());
          }
        } catch (_) {}
      }
      return null;
    }

    return ConversationUpdatedEvent(
      id: data['id'] as String? ?? data['conversation_id'] as String? ?? '',
      workspaceId: data['workspace_id'] as String? ?? '',
      phoneNumberId: data['phone_number_id'] as String?,
      systemNumber: data['system_number'] as String?,
      clientNumber: data['client_number'] as String?,
      clientName: data['client_name'] as String?,
      assignedAgentId: data['assigned_agent_id'] as String?,
      assignedTeamId: data['assigned_team_id'] as String?,
      status: data['status'] as String?,
      unreadCount: unread,
      lastMessage: parseLastMessage(data['last_message']),
      lastMessageAt: data['last_message_at'] != null
          ? DateTime.tryParse(data['last_message_at'].toString())
          : null,
      lastReadAt: data['last_read_at'] != null
          ? DateTime.tryParse(data['last_read_at'].toString())
          : null,
      updatedAt: data['updated_at'] != null
          ? DateTime.tryParse(data['updated_at'].toString())
          : null,
      raw: json,
    );
  }

  final String id;
  String get messageId => id;
  final String workspaceId;
  final String? phoneNumberId;
  final String? systemNumber;
  final String? clientNumber;
  final String? clientName;
  final String? assignedAgentId;
  final String? assignedTeamId;
  final String? status;
  final int? unreadCount;
  final ConversationLastMessage? lastMessage;
  final DateTime? lastMessageAt;
  final DateTime? lastReadAt;
  final DateTime? updatedAt;
  final Map<String, dynamic> raw;

  @override
  String toString() =>
      'ConversationUpdatedEvent(id: $id, status: $status, unreadCount: $unreadCount)';
}
