import 'package:flutter_test/flutter_test.dart';
import 'package:firetell_flutter_sdk/firetell_flutter_sdk.dart';

void main() {
  group('Call Center SMS Conversation Models', () {
    test('ConversationLastMessage serialization and deserialization', () {
      final json = {
        'id': 'msg_123',
        'body': 'Hello customer',
        'direction': 'outbound',
        'sender_type': 'agent',
        'sender_id': 'agent_1',
        'created_at': '2026-10-01T10:00:00.000Z',
      };

      final lastMsg = ConversationLastMessage.fromJson(json);
      expect(lastMsg.id, 'msg_123');
      expect(lastMsg.body, 'Hello customer');
      expect(lastMsg.direction, 'outbound');
      expect(lastMsg.senderType, 'agent');
      expect(lastMsg.senderId, 'agent_1');
      expect(lastMsg.createdAt, isNotNull);

      final outJson = lastMsg.toJson();
      expect(outJson['id'], 'msg_123');
      expect(outJson['body'], 'Hello customer');
      expect(outJson['direction'], 'outbound');
      expect(outJson['sender_type'], 'agent');
      expect(outJson['sender_id'], 'agent_1');
    });

    test('Conversation model serialization and properties', () {
      final json = {
        'id': 'conv_123',
        'workspace_id': 'ws_abc',
        'phone_number_id': 'pn_456',
        'system_number': '+13074295456',
        'client_number': '+18647123123',
        'client_name': 'John Doe',
        'contact_id': 'ct_789',
        'assigned_agent_id': 'ag_1',
        'assigned_team_id': 'te_2',
        'status': 'open',
        'unread_count': 3,
        'last_message': {
          'id': 'msg_001',
          'body': 'Inquiry about service',
          'direction': 'inbound',
          'sender_type': 'client',
          'created_at': '2026-10-01T10:05:00.000Z',
        },
        'last_message_at': '2026-10-01T10:05:00.000Z',
        'last_read_at': '2026-10-01T10:00:00.000Z',
        'created_at': '2026-10-01T09:00:00.000Z',
        'updated_at': '2026-10-01T10:05:00.000Z',
      };

      final conv = Conversation.fromJson(json);
      expect(conv.id, 'conv_123');
      expect(conv.workspaceId, 'ws_abc');
      expect(conv.phoneNumberId, 'pn_456');
      expect(conv.systemNumber, '+13074295456');
      expect(conv.clientNumber, '+18647123123');
      expect(conv.clientName, 'John Doe');
      expect(conv.displayTitle, 'John Doe');
      expect(conv.isUnread, isTrue);
      expect(conv.isOpen, isTrue);
      expect(conv.unreadCount, 3);
      expect(conv.lastMessage, isNotNull);
      expect(conv.lastMessage!.body, 'Inquiry about service');

      final outJson = conv.toJson();
      expect(outJson['client_number'], '+18647123123');
      expect(outJson['unread_count'], 3);
      expect(outJson['status'], 'open');
    });

    test('ConversationMessage serialization and properties', () {
      final json = {
        'id': 'msg_999',
        'conversation_id': 'conv_123',
        'workspace_id': 'ws_abc',
        'phone_number_id': 'pn_456',
        'from': '+13074295456',
        'from_number': '+13074295456',
        'to': '+18647123123',
        'to_number': '+18647123123',
        'client_number': '+18647123123',
        'body': 'Here is your receipt',
        'direction': 'outbound',
        'status': 'delivered',
        'sender_type': 'agent',
        'sender_id': 'ag_1',
        'media_urls': ['https://example.com/receipt.jpg'],
        'cost': 0.0052,
        'created_at': '2026-10-01T10:10:00.000Z',
        'updated_at': '2026-10-01T10:10:05.000Z',
      };

      final msg = ConversationMessage.fromJson(json);
      expect(msg.id, 'msg_999');
      expect(msg.conversationId, 'conv_123');
      expect(msg.from, '+13074295456');
      expect(msg.to, '+18647123123');
      expect(msg.clientNumber, '+18647123123');
      expect(msg.isOutbound, isTrue);
      expect(msg.isInbound, isFalse);
      expect(msg.hasMedia, isTrue);
      expect(msg.mediaUrls, contains('https://example.com/receipt.jpg'));
      expect(msg.cost, 0.0052);

      final outJson = msg.toJson();
      expect(outJson['status'], 'delivered');
      expect(outJson['media_urls'], hasLength(1));
    });

    test('ListConversationsQuery parameters generation', () {
      const query = ListConversationsQuery(
        status: 'open',
        assignedTo: 'ag_1',
        assignedTeamId: 'te_1',
        unreadOnly: true,
        search: 'smith',
        page: 2,
        limit: 25,
      );

      final params = query.toQueryParams();
      expect(params['status'], 'open');
      expect(params['assigned_to'], 'ag_1');
      expect(params['assigned_team_id'], 'te_1');
      expect(params['unread_only'], 'true');
      expect(params['search'], 'smith');
      expect(params['page'], '2');
      expect(params['limit'], '25');
    });

    test('StartConversationPayload uses client_number with fallback to to', () {
      const payload1 = StartConversationPayload(
        from: '+13074295456',
        clientNumber: '+18647123123',
        body: 'Initial greeting',
      );
      expect(payload1.toJson()['client_number'], '+18647123123');

      const payload2 = StartConversationPayload(
        from: '+13074295456',
        clientNumber: '',
        to: '+18647123999',
        body: 'Legacy to field',
      );
      expect(payload2.toJson()['client_number'], '+18647123999');
    });

    test('MessageReceivedEvent parses direct SSE and push message_data', () {
      // Direct SSE event format
      final sseJson = {
        'id': 'msg_001',
        'conversation_id': 'conv_001',
        'from': '+18647123123',
        'to': '+13074295456',
        'client_number': '+18647123123',
        'client_name': 'Jane Client',
        'body': 'Need help with order #123',
        'unread_count': 1,
        'created_at': '2026-10-01T10:15:00.000Z',
      };
      final event1 = MessageReceivedEvent.fromJson(sseJson);
      expect(event1.id, 'msg_001');
      expect(event1.conversationId, 'conv_001');
      expect(event1.clientName, 'Jane Client');
      expect(event1.body, 'Need help with order #123');

      // Push notification payload format from voip-push.service.ts
      final pushJson = {
        'event': 'message.received',
        'message_data': {
          'id': 'msg_002',
          'conversation_id': 'conv_002',
          'from': '+18647123123',
          'to': '+13074295456',
          'client_number': '+18647123123',
          'body': 'Push received message',
          'unread_count': 2,
        },
      };
      final event2 = MessageReceivedEvent.fromJson(pushJson);
      expect(event2.id, 'msg_002');
      expect(event2.conversationId, 'conv_002');
      expect(event2.body, 'Push received message');
      expect(event2.unreadCount, 2);
    });

    test('ConversationUpdatedEvent parses direct SSE and push conversation_data', () {
      final pushJson = {
        'event': 'conversation.updated',
        'conversation_data': {
          'id': 'conv_003',
          'workspace_id': 'ws_abc',
          'client_number': '+18647123123',
          'status': 'closed',
          'unread_count': 0,
        },
      };

      final event = ConversationUpdatedEvent.fromJson(pushJson);
      expect(event.id, 'conv_003');
      expect(event.workspaceId, 'ws_abc');
      expect(event.status, 'closed');
      expect(event.unreadCount, 0);
    });

    test('ApiEndpoints conversation URLs format correctly', () {
      expect(
        ApiEndpoints.conversations,
        '/api/v1/call-center/conversations',
      );
      expect(
        ApiEndpoints.conversationDetails('conv_123'),
        '/api/v1/call-center/conversations/conv_123',
      );
      expect(
        ApiEndpoints.conversationMessages('conv_123'),
        '/api/v1/call-center/conversations/conv_123/messages',
      );
      expect(
        ApiEndpoints.conversationRead('conv_123'),
        '/api/v1/call-center/conversations/conv_123/read',
      );
    });
    test('MessageReceivedEvent parses backend FCM data payload', () {
      final fcmData = {
        'event': 'message.received',
        'workspace_id': 'solar',
        'message_id': 'msg_abc123',
        'conversation_id': 'conv_def456',
        'from_number': '+18647123123',
        'to_number': '+13074295456',
        'client_number': '+18647123123',
        'client_name': 'Alice Smith',
        'body': 'FCM message body test',
        'unread_count': '3',
        'created_at': '2026-10-01T11:00:00.000Z',
      };

      final event = MessageReceivedEvent.fromJson(fcmData);
      expect(event.id, 'msg_abc123');
      expect(event.conversationId, 'conv_def456');
      expect(event.from, '+18647123123');
      expect(event.to, '+13074295456');
      expect(event.clientNumber, '+18647123123');
      expect(event.clientName, 'Alice Smith');
      expect(event.body, 'FCM message body test');
      expect(event.unreadCount, 3);
    });

    test('ConversationUpdatedEvent parses backend FCM data payload with JSON last_message', () {
      final fcmData = {
        'event': 'conversation.updated',
        'workspace_id': 'solar',
        'id': 'conv_def456',
        'conversation_id': 'conv_def456',
        'system_number': '+13074295456',
        'client_number': '+18647123123',
        'client_name': 'Alice Smith',
        'status': 'open',
        'unread_count': '5',
        'last_message': '{"id":"msg_last","body":"Hello again","direction":"inbound","sender_type":"client"}',
      };

      final event = ConversationUpdatedEvent.fromJson(fcmData);
      expect(event.id, 'conv_def456');
      expect(event.workspaceId, 'solar');
      expect(event.unreadCount, 5);
      expect(event.lastMessage, isNotNull);
      expect(event.lastMessage!.id, 'msg_last');
      expect(event.lastMessage!.body, 'Hello again');
    });

    test('FiretellClient.handlePushEvent ingests FCM data message correctly', () async {
      final client = FiretellClient(
        jwt: 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJhZ2VudF8xMjMiLCJkb21haW4iOiJzb2xhci5maXJldGVsbC5hcHAifQ.mock_signature',
        domain: 'solar.firetell.app',
      );

      MessageReceivedEvent? received;
      client.onMessageReceived.listen((e) => received = e);

      final fcmPayload = {
        'data': {
          'event': 'message.received',
          'message_id': 'msg_push_1',
          'conversation_id': 'conv_push_1',
          'from_number': '+18647123123',
          'to_number': '+13074295456',
          'client_number': '+18647123123',
          'body': 'Push received via FCM',
          'unread_count': '1',
        },
      };

      final handled = client.handlePushEvent(fcmPayload);
      expect(handled, isTrue);
      await pumpEventQueue();
      expect(received, isNotNull);
      expect(received!.id, 'msg_push_1');
      expect(received!.body, 'Push received via FCM');
      expect(received!.unreadCount, 1);
    });
  });
}

