import 'dart:async';

import 'package:firetell_flutter_sdk/firetell_flutter_sdk.dart';
import 'package:flutter/material.dart';

import 'call_screen.dart';
import 'video_call_screen.dart';

/// Screen for active 2-way SMS/MMS conversation thread.
///
/// Features:
/// - Real-time chronological message history
/// - Inbound/Outbound chat bubbles with carrier delivery status
/// - Sending SMS & MMS replies
/// - Direct Voice & Video Call actions via Firetell WebRTC
/// - Mark as read & status management (Open / Close)
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.client,
    required this.conversation,
  });

  final FiretellClient client;
  final Conversation conversation;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late Conversation _conversation;
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<ConversationMessage> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  String? _errorMessage;

  StreamSubscription<MessageReceivedEvent>? _messageReceivedSub;
  StreamSubscription<MessageSentEvent>? _messageSentSub;
  StreamSubscription<MessageUpdatedEvent>? _messageUpdatedSub;
  StreamSubscription<ConversationUpdatedEvent>? _conversationUpdatedSub;

  @override
  void initState() {
    super.initState();
    _conversation = widget.conversation;
    _loadMessages();
    _markReadIfNeeded();
    _subscribeToEvents();
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _messageReceivedSub?.cancel();
    _messageSentSub?.cancel();
    _messageUpdatedSub?.cancel();
    _conversationUpdatedSub?.cancel();
    super.dispose();
  }

  void _subscribeToEvents() {
    _messageReceivedSub = widget.client.onMessageReceived.listen((event) {
      if (event.conversationId != _conversation.id) return;
      if (!mounted) return;

      setState(() {
        _messages.add(
          ConversationMessage(
            id: event.id,
            conversationId: event.conversationId,
            workspaceId: _conversation.workspaceId,
            phoneNumberId: _conversation.phoneNumberId,
            from: event.from,
            to: event.to,
            clientNumber: event.clientNumber,
            body: event.body,
            direction: 'inbound',
            status: 'received',
            senderType: 'client',
            createdAt: event.createdAt,
            updatedAt: DateTime.now(),
          ),
        );
      });
      _scrollToBottom();
      _markReadIfNeeded();
    });

    _messageSentSub = widget.client.onMessageSent.listen((event) {
      if (event.conversationId != _conversation.id) return;
      if (!mounted) return;

      // Avoid adding duplicate if sent by this client session
      final alreadyExists = _messages.any((m) => m.id == event.id);
      if (!alreadyExists) {
        setState(() {
          _messages.add(
            ConversationMessage(
              id: event.id,
              conversationId: event.conversationId,
              workspaceId: _conversation.workspaceId,
              phoneNumberId: _conversation.phoneNumberId,
              from: event.from,
              to: event.to,
              clientNumber: event.clientNumber,
              body: event.body,
              direction: event.direction,
              status: event.status,
              senderType: event.senderType,
              senderId: event.senderId,
              mediaUrls: event.mediaUrls,
              createdAt: event.createdAt,
              updatedAt: DateTime.now(),
            ),
          );
        });
        _scrollToBottom();
      }
    });

    _messageUpdatedSub = widget.client.onMessageUpdated.listen((event) {
      if (!mounted) return;
      setState(() {
        final index = _messages.indexWhere((m) => m.id == event.messageId);
        if (index != -1) {
          final existing = _messages[index];
          _messages[index] = ConversationMessage(
            id: existing.id,
            conversationId: existing.conversationId,
            workspaceId: existing.workspaceId,
            phoneNumberId: existing.phoneNumberId,
            from: existing.from,
            fromNumber: existing.fromNumber,
            to: existing.to,
            toNumber: existing.toNumber,
            clientNumber: existing.clientNumber,
            body: existing.body,
            direction: existing.direction,
            status: event.status,
            senderType: existing.senderType,
            senderId: existing.senderId,
            errorCode: event.errorCode ?? existing.errorCode,
            errorMessage: event.errorMessage ?? existing.errorMessage,
            cost: event.cost ?? existing.cost,
            mediaUrls: existing.mediaUrls,
            createdAt: existing.createdAt,
            updatedAt: DateTime.now(),
          );
        }
      });
    });

    _conversationUpdatedSub = widget.client.onConversationUpdated.listen((event) {
      if (event.id != _conversation.id) return;
      if (!mounted) return;

      setState(() {
        _conversation = Conversation(
          id: _conversation.id,
          workspaceId: event.workspaceId.isNotEmpty ? event.workspaceId : _conversation.workspaceId,
          phoneNumberId: _conversation.phoneNumberId,
          systemNumber: _conversation.systemNumber,
          clientNumber: event.clientNumber ?? _conversation.clientNumber,
          clientName: event.clientName ?? _conversation.clientName,
          contactId: _conversation.contactId,
          assignedAgentId: event.assignedAgentId ?? _conversation.assignedAgentId,
          assignedTeamId: event.assignedTeamId ?? _conversation.assignedTeamId,
          status: event.status ?? _conversation.status,
          unreadCount: event.unreadCount ?? _conversation.unreadCount,
          lastMessage: _conversation.lastMessage,
          lastMessageAt: _conversation.lastMessageAt,
          lastReadAt: _conversation.lastReadAt,
          createdAt: _conversation.createdAt,
          updatedAt: DateTime.now(),
        );
      });
    });
  }

  Future<void> _loadMessages() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await widget.client.getConversationMessages(
        _conversation.id,
        const ListMessagesQuery(limit: 50),
      );

      if (!mounted) return;
      setState(() {
        _messages = response.data;
        _isLoading = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _markReadIfNeeded() async {
    try {
      await widget.client.markConversationAsRead(_conversation.id);
    } catch (_) {
      // Ignored for background silent read marking
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _isSending) return;

    _textController.clear();
    setState(() => _isSending = true);

    try {
      final payload = SendConversationMessagePayload(body: text);
      final message = await widget.client.sendConversationMessage(
        _conversation.id,
        payload,
      );

      if (!mounted) return;
      setState(() {
        final alreadyInList = _messages.any((m) => m.id == message.id);
        if (!alreadyInList) {
          _messages.add(message);
        }
        _isSending = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send SMS: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _toggleConversationStatus() async {
    final nextStatus = _conversation.isOpen ? 'closed' : 'open';
    try {
      final updated = await widget.client.updateConversation(
        _conversation.id,
        UpdateConversationPayload(status: nextStatus),
      );
      if (!mounted) return;
      setState(() => _conversation = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Conversation marked as $nextStatus')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update status: $e')),
      );
    }
  }

  Future<void> _callClient({bool isVideo = false}) async {
    try {
      final call = await widget.client.makeOutboundCall(
        to: _conversation.clientNumber,
        from: _conversation.systemNumber,
        isVideo: isVideo,
      );

      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => isVideo
              ? VideoCallScreen(call: call)
              : CallScreen(call: call),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to initiate call: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  _conversation.displayTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: _conversation.isOpen
                        ? Colors.teal.withValues(alpha: 0.2)
                        : Colors.grey.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _conversation.status.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: _conversation.isOpen ? Colors.tealAccent : Colors.grey,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              'DID: ${_conversation.systemNumber} • Client: ${_conversation.clientNumber}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontFamily: 'monospace',
                fontSize: 11,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.phone),
            tooltip: 'Call Client',
            onPressed: () => _callClient(isVideo: false),
          ),
          IconButton(
            icon: const Icon(Icons.videocam),
            tooltip: 'Video Call Client',
            onPressed: () => _callClient(isVideo: true),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'toggle_status') {
                _toggleConversationStatus();
              } else if (value == 'mark_read') {
                _markReadIfNeeded();
              } else if (value == 'refresh') {
                _loadMessages();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'toggle_status',
                child: Text(
                  _conversation.isOpen
                      ? 'Close Conversation'
                      : 'Reopen Conversation',
                ),
              ),
              const PopupMenuItem(
                value: 'mark_read',
                child: Text('Mark as Read'),
              ),
              const PopupMenuItem(
                value: 'refresh',
                child: Text('Refresh Messages'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Messages list
          Expanded(
            child: _isLoading && _messages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null && _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
                            const SizedBox(height: 12),
                            Text(_errorMessage!),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: _loadMessages,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : _messages.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.forum_outlined,
                                  size: 48,
                                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                                ),
                                const SizedBox(height: 12),
                                const Text('No messages yet in this conversation.'),
                                const SizedBox(height: 4),
                                const Text('Send a message below to start.'),
                              ],
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            itemCount: _messages.length,
                            itemBuilder: (context, index) {
                              final msg = _messages[index];
                              return _buildMessageBubble(msg, theme);
                            },
                          ),
          ),

          // Message input bar
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 4,
                    offset: const Offset(0, -1),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: 'Type an SMS reply...',
                        hintStyle: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        isDense: true,
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerHighest,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _isSending ? null : _sendMessage,
                    icon: _isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send, size: 20),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ConversationMessage msg, ThemeData theme) {
    final isOutbound = msg.isOutbound;
    final timeStr = msg.createdAt != null
        ? '${msg.createdAt!.toLocal().hour.toString().padLeft(2, '0')}:${msg.createdAt!.toLocal().minute.toString().padLeft(2, '0')}'
        : '';

    return Align(
      alignment: isOutbound ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isOutbound
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isOutbound ? 16 : 4),
            bottomRight: Radius.circular(isOutbound ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              isOutbound ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // Sender badge for clarity
            Text(
              isOutbound ? 'Agent' : 'Client',
              style: theme.textTheme.labelSmall?.copyWith(
                color: isOutbound
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.bold,
                fontSize: 10,
              ),
            ),
            const SizedBox(height: 2),

            // Message text body
            Text(
              msg.body,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isOutbound
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurface,
              ),
            ),

            // Media attachment pills if any
            if (msg.hasMedia) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 4,
                children: msg.mediaUrls.map((url) {
                  return Chip(
                    label: Text(
                      'Attachment',
                      style: theme.textTheme.labelSmall,
                    ),
                    avatar: const Icon(Icons.attach_file, size: 14),
                    visualDensity: VisualDensity.compact,
                  );
                }).toList(),
              ),
            ],

            const SizedBox(height: 4),
            // Footer: time, delivery status & cost
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (msg.cost != null && msg.cost! > 0) ...[
                  Text(
                    '\$${msg.cost!.toStringAsFixed(4)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isOutbound
                          ? theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.6)
                          : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                      fontSize: 10,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  timeStr,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: isOutbound
                        ? theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.7)
                        : theme.colorScheme.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
                if (isOutbound) ...[
                  const SizedBox(width: 4),
                  _buildDeliveryStatusIcon(msg.status, theme),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeliveryStatusIcon(String status, ThemeData theme) {
    switch (status.toLowerCase()) {
      case 'delivered':
        return const Icon(Icons.done_all, size: 14, color: Colors.tealAccent);
      case 'sent':
        return Icon(
          Icons.check,
          size: 14,
          color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
        );
      case 'queued':
        return Icon(
          Icons.schedule,
          size: 14,
          color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.6),
        );
      case 'failed':
        return const Icon(Icons.error_outline, size: 14, color: Colors.redAccent);
      default:
        return const SizedBox.shrink();
    }
  }
}
