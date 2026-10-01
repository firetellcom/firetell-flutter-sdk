import 'dart:async';

import 'package:firetell_flutter_sdk/firetell_flutter_sdk.dart';
import 'package:flutter/material.dart';

import 'chat_screen.dart';
import 'new_conversation_screen.dart';

/// Screen displaying the SMS Conversations Inbox.
///
/// Features:
/// - List conversations with client number/name, last message, and unread counter
/// - Filter by All, Unread, Open, and Closed threads
/// - Search by client phone or name
/// - Real-time SSE updates for new incoming/outgoing SMS
/// - Quick navigation to ChatScreen and NewConversationScreen
class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({
    super.key,
    required this.client,
    this.embedded = false,
  });

  final FiretellClient client;
  final bool embedded;

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Conversation> _conversations = [];
  bool _isLoading = false;
  String? _errorMessage;
  String _selectedFilter = 'all'; // 'all', 'unread', 'open', 'closed'

  StreamSubscription<MessageReceivedEvent>? _messageReceivedSub;
  StreamSubscription<MessageSentEvent>? _messageSentSub;
  StreamSubscription<MessageUpdatedEvent>? _messageUpdatedSub;
  StreamSubscription<ConversationUpdatedEvent>? _conversationUpdatedSub;

  @override
  void initState() {
    super.initState();
    _loadConversations();
    _subscribeToEvents();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _messageReceivedSub?.cancel();
    _messageSentSub?.cancel();
    _messageUpdatedSub?.cancel();
    _conversationUpdatedSub?.cancel();
    super.dispose();
  }

  void _subscribeToEvents() {
    _messageReceivedSub = widget.client.onMessageReceived.listen((event) {
      if (!mounted) return;
      setState(() {
        final index = _conversations.indexWhere((c) => c.id == event.conversationId);
        if (index != -1) {
          final existing = _conversations[index];
          final updated = Conversation(
            id: existing.id,
            workspaceId: existing.workspaceId,
            phoneNumberId: existing.phoneNumberId,
            systemNumber: existing.systemNumber,
            clientNumber: existing.clientNumber,
            clientName: event.clientName ?? existing.clientName,
            contactId: existing.contactId,
            assignedAgentId: existing.assignedAgentId,
            assignedTeamId: existing.assignedTeamId,
            status: existing.status,
            unreadCount: (event.unreadCount != null && event.unreadCount! > 0) ? event.unreadCount! : (existing.unreadCount + 1),
            lastMessage: ConversationLastMessage(
              id: event.id,
              body: event.body,
              direction: 'inbound',
              senderType: 'client',
              senderId: null,
              createdAt: event.createdAt,
            ),
            lastMessageAt: event.createdAt,
            lastReadAt: existing.lastReadAt,
            createdAt: existing.createdAt,
            updatedAt: DateTime.now(),
          );
          _conversations.removeAt(index);
          _conversations.insert(0, updated);
        } else {
          // New conversation from outside, reload full list
          _loadConversations();
        }
      });
    });

    _messageSentSub = widget.client.onMessageSent.listen((event) {
      if (!mounted) return;
      setState(() {
        final index = _conversations.indexWhere((c) => c.id == event.conversationId);
        if (index != -1) {
          final existing = _conversations[index];
          final updated = Conversation(
            id: existing.id,
            workspaceId: existing.workspaceId,
            phoneNumberId: existing.phoneNumberId,
            systemNumber: existing.systemNumber,
            clientNumber: existing.clientNumber,
            clientName: existing.clientName,
            contactId: existing.contactId,
            assignedAgentId: existing.assignedAgentId,
            assignedTeamId: existing.assignedTeamId,
            status: existing.status,
            unreadCount: existing.unreadCount,
            lastMessage: ConversationLastMessage(
              id: event.id,
              body: event.body,
              direction: event.direction,
              senderType: event.senderType,
              senderId: event.senderId,
              createdAt: event.createdAt,
            ),
            lastMessageAt: event.createdAt,
            lastReadAt: existing.lastReadAt,
            createdAt: existing.createdAt,
            updatedAt: DateTime.now(),
          );
          _conversations.removeAt(index);
          _conversations.insert(0, updated);
        }
      });
    });

    _conversationUpdatedSub = widget.client.onConversationUpdated.listen((event) {
      if (!mounted) return;
      setState(() {
        final index = _conversations.indexWhere((c) => c.id == event.id);
        if (index != -1) {
          final existing = _conversations[index];
          _conversations[index] = Conversation(
            id: existing.id,
            workspaceId: event.workspaceId.isNotEmpty ? event.workspaceId : existing.workspaceId,
            phoneNumberId: existing.phoneNumberId,
            systemNumber: existing.systemNumber,
            clientNumber: event.clientNumber ?? existing.clientNumber,
            clientName: event.clientName ?? existing.clientName,
            contactId: existing.contactId,
            assignedAgentId: event.assignedAgentId ?? existing.assignedAgentId,
            assignedTeamId: event.assignedTeamId ?? existing.assignedTeamId,
            status: event.status ?? existing.status,
            unreadCount: event.unreadCount ?? existing.unreadCount,
            lastMessage: existing.lastMessage,
            lastMessageAt: existing.lastMessageAt,
            lastReadAt: existing.lastReadAt,
            createdAt: existing.createdAt,
            updatedAt: DateTime.now(),
          );
        }
      });
    });
  }

  Future<void> _loadConversations() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final query = ListConversationsQuery(
        status: (_selectedFilter == 'open' || _selectedFilter == 'closed')
            ? _selectedFilter
            : null,
        unreadOnly: _selectedFilter == 'unread' ? true : null,
        search: _searchController.text.trim().isNotEmpty
            ? _searchController.text.trim()
            : null,
        limit: 30,
      );

      final response = await widget.client.getConversations(query);

      if (!mounted) return;
      setState(() {
        _conversations = response.data;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  String _formatTime(DateTime? dt) {
    if (dt == null) return '';
    final local = dt.toLocal();
    final now = DateTime.now();
    if (local.year == now.year && local.month == now.month && local.day == now.day) {
      return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    }
    return '${local.month}/${local.day}';
  }

  void _openChat(Conversation conversation) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          client: widget.client,
          conversation: conversation,
        ),
      ),
    );
    _loadConversations();
  }

  void _openNewConversation() async {
    final result = await Navigator.of(context).push<Conversation>(
      MaterialPageRoute(
        builder: (_) => NewConversationScreen(client: widget.client),
      ),
    );
    if (result != null) {
      _loadConversations();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final Widget content = Column(
      children: [
        // Search & Filter header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search number or contact...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        _loadConversations();
                      },
                    )
                  : null,
              isDense: true,
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onSubmitted: (_) => _loadConversations(),
          ),
        ),

        // Filter chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              _buildFilterChip('all', 'All'),
              const SizedBox(width: 8),
              _buildFilterChip('unread', 'Unread'),
              const SizedBox(width: 8),
              _buildFilterChip('open', 'Open'),
              const SizedBox(width: 8),
              _buildFilterChip('closed', 'Closed'),
            ],
          ),
        ),
        const Divider(height: 16),

        // Conversation list
        Expanded(
          child: _isLoading && _conversations.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null && _conversations.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
                          const SizedBox(height: 12),
                          Text(_errorMessage!, textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _loadConversations,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  : _conversations.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.chat_bubble_outline,
                                size: 56,
                                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No conversations found',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text('Start a new SMS thread using the + button'),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadConversations,
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: _conversations.length,
                            separatorBuilder: (_, __) => const Divider(
                              indent: 72,
                              endIndent: 16,
                              height: 1,
                            ),
                            itemBuilder: (context, index) {
                              final conv = _conversations[index];
                              return _buildConversationTile(conv, theme);
                            },
                          ),
                        ),
        ),
      ],
    );

    if (widget.embedded) {
      return content;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('SMS Conversations'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadConversations,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: content,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openNewConversation,
        icon: const Icon(Icons.add_comment),
        label: const Text('New SMS'),
      ),
    );
  }

  Widget _buildFilterChip(String value, String label) {
    final isSelected = _selectedFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() => _selectedFilter = value);
          _loadConversations();
        }
      },
    );
  }

  Widget _buildConversationTile(Conversation conv, ThemeData theme) {
    final hasUnread = conv.isUnread;
    final lastMsg = conv.lastMessage;
    final timeStr = _formatTime(conv.lastMessageAt ?? conv.updatedAt);

    return ListTile(
      onTap: () => _openChat(conv),
      leading: CircleAvatar(
        backgroundColor: hasUnread
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        child: Icon(
          hasUnread ? Icons.mark_chat_unread : Icons.person,
          color: hasUnread
              ? theme.colorScheme.onPrimaryContainer
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              conv.displayTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (timeStr.isNotEmpty)
            Text(
              timeStr,
              style: theme.textTheme.bodySmall?.copyWith(
                color: hasUnread
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
              ),
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Row(
            children: [
              if (lastMsg?.direction == 'outbound') ...[
                Icon(
                  Icons.arrow_outward,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  lastMsg?.body ?? 'No messages yet',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: hasUnread
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurfaceVariant,
                    fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'DID: ${conv.systemNumber}',
                  style: theme.textTheme.labelSmall?.copyWith(fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: conv.isOpen
                      ? Colors.teal.withValues(alpha: 0.15)
                      : Colors.grey.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  conv.status.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: conv.isOpen ? Colors.tealAccent : Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Spacer(),
              if (hasUnread)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${conv.unreadCount}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
