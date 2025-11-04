import 'package:flutter/material.dart';
import 'package:roomie/data/models/base_chat.dart';
import 'package:roomie/data/datasources/chat_manager.dart';
import 'package:roomie/presentation/screens/chat/chat_screen.dart';

/// Reusable chat list widget that uses OOP principles
/// This widget can display both individual and group chats
class ChatListWidget extends StatefulWidget {
  final String currentUserId;
  final VoidCallback? onChatTap;

  const ChatListWidget({
    super.key,
    required this.currentUserId,
    this.onChatTap,
  });

  @override
  State<ChatListWidget> createState() => _ChatListWidgetState();
}

class _ChatListWidgetState extends State<ChatListWidget> {
  final ChatManager _chatManager = ChatManager();
  List<BaseChat> _chats = [];
  List<BaseChat> _filteredChats = [];
  bool _isLoading = true;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadChats();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadChats() async {
    try {
      setState(() => _isLoading = true);
      final chats = await _chatManager.getAllChats();
      if (mounted) {
        setState(() {
          _chats = chats;
          _filteredChats = chats;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load chats: ${e.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _filterChats(String query) {
    setState(() {
      _searchQuery = query;
      _filteredChats = _chatManager.searchChats(_chats, query);
    });
  }

  void _openChat(BaseChat chat) {
    Map<String, dynamic> chatData;
    String chatType;

    if (chat is IndividualChat) {
      chatData = {
        'id': chat.id,
        'otherUserId': chat.otherUserId,
        'otherUserName': chat.otherUserName,
        'otherUserImageUrl': chat.otherUserImageUrl,
      };
      chatType = 'individual';
    } else if (chat is GroupChat) {
      chatData = {
        'id': chat.id,
        'name': chat.groupName,
        'imageUrl': chat.groupImageUrl,
        'members': chat.participants,
        'memberNames': chat.participantNames,
      };
      chatType = 'group';
    } else {
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => ChatScreen(chatData: chatData, chatType: chatType),
      ),
    ).then((_) {
      // Refresh chats when returning from chat screen
      _loadChats();
    });

    if (widget.onChatTap != null) {
      widget.onChatTap!();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search chats...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
            onChanged: _filterChats,
          ),
        ),

        // Chat list
        Expanded(
          child:
              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredChats.isEmpty
                  ? _buildEmptyState()
                  : RefreshIndicator(
                    onRefresh: _loadChats,
                    child: ListView.builder(
                      itemCount: _filteredChats.length,
                      itemBuilder: (context, index) {
                        final chat = _filteredChats[index];
                        return _ChatListItem(
                          chat: chat,
                          currentUserId: widget.currentUserId,
                          onTap: () => _openChat(chat),
                        );
                      },
                    ),
                  ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isEmpty ? 'No chats yet' : 'No chats found',
            style: TextStyle(
              fontSize: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isEmpty
                ? 'Start a conversation with someone!'
                : 'Try a different search term',
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Individual chat list item widget
class _ChatListItem extends StatelessWidget {
  final BaseChat chat;
  final String currentUserId;
  final VoidCallback onTap;

  const _ChatListItem({
    required this.chat,
    required this.currentUserId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasUnread = chat.hasUnreadMessages(currentUserId);
    final unreadCount = chat.getUnreadCount(currentUserId);

    return ListTile(
      onTap: onTap,
      leading: _buildAvatar(),
      title: Text(
        chat.getChatTitle(),
        style: TextStyle(
          fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        ChatUtils.getChatPreview(
          chat.lastMessage,
          chat.lastSenderId,
          currentUserId,
        ),
        style: TextStyle(
          color:
              hasUnread
                  ? Theme.of(context).colorScheme.onSurface
                  : Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: hasUnread ? FontWeight.w500 : FontWeight.normal,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            chat.getTimeAgo(),
            style: TextStyle(
              fontSize: 12,
              color:
                  hasUnread
                      ? Theme.of(context).colorScheme.onSurface
                      : Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: hasUnread ? FontWeight.w500 : FontWeight.normal,
            ),
          ),
          if (hasUnread) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
              child: Text(
                unreadCount > 99 ? '99+' : unreadCount.toString(),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    if (chat is GroupChat) {
      // Group chat avatar
      return CircleAvatar(
        backgroundImage:
            chat.getChatImageUrl() != null
                ? NetworkImage(chat.getChatImageUrl()!)
                : null,
        child: chat.getChatImageUrl() == null ? const Icon(Icons.group) : null,
      );
    } else {
      // Individual chat avatar
      return CircleAvatar(
        backgroundImage:
            chat.getChatImageUrl() != null
                ? NetworkImage(chat.getChatImageUrl()!)
                : null,
        child: chat.getChatImageUrl() == null ? const Icon(Icons.person) : null,
      );
    }
  }
}
