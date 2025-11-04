import 'package:flutter/material.dart';
import 'package:roomie/presentation/screens/chat/chat_screen.dart';
import 'package:roomie/data/datasources/messages_service.dart';
import 'package:roomie/presentation/widgets/roomie_loading_widget.dart';
import 'package:timeago/timeago.dart' as timeago;

class MessagesPage extends StatefulWidget {
  const MessagesPage({super.key});

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  final MessagesService _messagesService = MessagesService();
  final TextEditingController _searchController = TextEditingController();
  String _selectedFilter = 'all'; // all, groups, individual

  String _searchQuery = '';
  
  // Cache screen dimensions on first build
  double? _cachedScreenHeight;
  double? _cachedScreenWidth;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() {
      _searchQuery = value;
    });
  }

  List<Map<String, dynamic>> _applyFilters(
    List<Map<String, dynamic>> conversations,
  ) {
    List<Map<String, dynamic>> filtered = [];

    // First, filter by type
    switch (_selectedFilter) {
      case 'groups':
        filtered =
            conversations.where((conv) => conv['type'] == 'group').toList();
        break;
      case 'individual':
        filtered =
            conversations
                .where((conv) => conv['type'] == 'individual')
                .toList();
        break;
      case 'all':
      default:
        filtered = List.from(conversations);
    }

    // Then, filter by search query
    if (_searchQuery.isNotEmpty) {
      filtered =
          filtered.where((conv) {
            final name = (conv['name'] ?? '').toLowerCase();
            final lastMessage = (conv['lastMessage'] ?? '').toLowerCase();
            final query = _searchQuery.toLowerCase();
            return name.contains(query) || lastMessage.contains(query);
          }).toList();
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    
    // Cache screen dimensions on first build (before keyboard appears)
    _cachedScreenHeight ??= MediaQuery.of(context).size.height;
    _cachedScreenWidth ??= MediaQuery.of(context).size.width;
    
    // Use cached values which won't change
    final screenHeight = _cachedScreenHeight!;
    final screenWidth = _cachedScreenWidth!;
    
    return Scaffold(
      backgroundColor: colorScheme.surface,
      resizeToAvoidBottomInset: false,
      body: Column(
        children: [
          // Header with title
          Container(
            color: colorScheme.surface,
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: screenWidth * 0.04,  // 4% of screen width
                  right: 0.0,
                  top: screenHeight * 0.012,  // 1.2% of screen height
                  bottom: 0,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Messages',
                        style: textTheme.headlineSmall?.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Search bar and Filter tabs on same row
          Container(
            color: Colors.transparent,
            padding: EdgeInsets.only(
              left: screenWidth * 0.03,
              right: screenWidth * 0.03,
              bottom: screenHeight * 0.0005,  // 0.5% very small bottom padding
            ),
            child: Row(
              children: [
                // Search bar (left side)
                Expanded(
                  flex: 1,
                  child: Container(
                    height: screenHeight * 0.055,  // 5.5% of screen height
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(screenHeight * 0.0275),
                      border: Border.all(
                        color: colorScheme.outlineVariant,
                        width: 1,
                      ),
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: _onSearchChanged,
                      decoration: InputDecoration(
                        hintText: 'Search here',
                        prefixIcon: Icon(
                          Icons.search,
                          color: colorScheme.onSurfaceVariant,
                          size: screenHeight * 0.025,  // 2.5% of screen height
                        ),
                        filled: true,
                        fillColor: Colors.transparent,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: screenWidth * 0.04,
                          vertical: screenHeight * 0.015,
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: screenWidth * 0.03),
                // Filter tabs with gap on right
                Row(
                  children: [
                    _buildFilterTab('all', 'All', screenHeight, screenWidth),
                    SizedBox(width: screenWidth * 0.025),
                    _buildFilterTab('groups', 'Groups', screenHeight, screenWidth),
                    SizedBox(width: screenWidth * 0.025),
                    _buildFilterTab('individual', 'Direct', screenHeight, screenWidth),
                  ],
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _messagesService.getAllConversations(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Padding(
                    padding: EdgeInsets.all(screenHeight * 0.04),
                    child: const Center(
                      child: RoomieLoadingWidget(
                        size: 80,
                        text: 'Loading conversations...',
                        showText: true,
                      ),
                    ),
                  );
                }

                if (snapshot.hasError) {
                  print('❌ Snapshot error: ${snapshot.error}');
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: screenHeight * 0.08,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        SizedBox(height: screenHeight * 0.02),
                        Text(
                          'Error loading conversations',
                          style: textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w500,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        SizedBox(height: screenHeight * 0.01),
                        Text(
                          '${snapshot.error}',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.error,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }

                final conversations = snapshot.data ?? [];
                print(
                  '📱 Messages page received ${conversations.length} conversations',
                );
                print(
                  '📊 Conversation types: ${conversations.map((c) => c['type']).toList()}',
                );

                final filteredConversations = _applyFilters(conversations);
                print(
                  '🔍 Filtered to ${filteredConversations.length} conversations (filter: $_selectedFilter)',
                );

                if (filteredConversations.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: screenHeight * 0.08,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        SizedBox(height: screenHeight * 0.02),
                        Text(
                          'No conversations yet',
                          style: textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w500,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        SizedBox(height: screenHeight * 0.01),
                        Text(
                          'Start a conversation by joining a group!',
                          style: textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: filteredConversations.length,
                  itemBuilder: (context, index) {
                    final conversation = filteredConversations[index];
                    return _buildConversationTile(conversation, screenHeight, screenWidth);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTab(String value, String label, double screenHeight, double screenWidth) {
    final isSelected = _selectedFilter == value;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedFilter = value;
        });
      },
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: screenWidth * 0.03,  // 3% of screen width
          vertical: screenHeight * 0.0125,  // 1.25% of screen height
        ),
        decoration: BoxDecoration(
          color:
              isSelected
                  ? colorScheme.primary
                  : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(screenHeight * 0.025),
        ),
        child: Text(
          label,
          style: textTheme.labelLarge?.copyWith(
            color:
                isSelected
                    ? colorScheme.onPrimary
                    : colorScheme.onSurfaceVariant,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildConversationTile(Map<String, dynamic> conversation, double screenHeight, double screenWidth) {
    final isGroup = conversation['type'] == 'group';
    final lastMessageTime = conversation['lastMessageTime'] as DateTime?;
    final timeText =
        lastMessageTime != null
            ? timeago.format(lastMessageTime, locale: 'en_short')
            : '';

    return Container(
      color: Theme.of(context).colorScheme.surface,
      // Very small gap - only horizontal
      margin: EdgeInsets.symmetric(
        horizontal: screenWidth * 0.015,  // 1.5% left/right
        vertical: screenHeight * 0.00,   // 0.1% top/bottom (very small)
      ),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(
          horizontal: screenWidth * 0.03,  // Reduced horizontal padding since margin is added
          vertical: screenHeight * 0.006,
        ),
        leading: CircleAvatar(
          radius: screenHeight * 0.028,  // Slightly smaller - 2.8% instead of 3%
          backgroundColor:
              isGroup
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.secondaryContainer,
          backgroundImage:
              conversation['imageUrl'] != null &&
                      conversation['imageUrl'].isNotEmpty
                  ? NetworkImage(conversation['imageUrl'])
                  : null,
          child:
              conversation['imageUrl'] == null ||
                      conversation['imageUrl'].isEmpty
                  ? Icon(
                    isGroup ? Icons.group : Icons.person,
                    color:
                        isGroup
                            ? Theme.of(context).colorScheme.onPrimary
                            : Theme.of(
                              context,
                            ).colorScheme.onSecondaryContainer,
                    size: screenHeight * 0.022,  // Smaller icon - 2.2% instead of 2.5%
                  )
                  : null,
        ),
        title: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  // Name
                  Flexible(
                    child: Text(
                      conversation['name'] ?? 'Unknown',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 15.5,  // Slightly smaller
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Member count for groups (next to name)
                  if (isGroup && conversation['memberCount'] != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      '(${conversation['memberCount']})',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Time on the right
            if (timeText.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(
                timeText,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 11.5,  // Slightly smaller
                ),
              ),
            ],
          ],
        ),
        subtitle: Padding(
          padding: EdgeInsets.only(top: screenHeight * 0.003),  // Reduced spacing
          child: Text(
            conversation['lastMessage'] ?? 'No messages yet',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13.5,  // Slightly smaller
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
        onTap: () => _openConversation(conversation),
      ),
    );
  }

  void _openConversation(Map<String, dynamic> conversation) {
    final isGroup = conversation['type'] == 'group';

    final chatData = conversation['groupData'] ?? conversation;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => ChatScreen(
              chatData: {
                ...chatData,
                if (!isGroup) 'otherUserId': conversation['otherUserId'],
                if (!isGroup) 'otherUserName': conversation['name'],
                if (!isGroup) 'otherUserImageUrl': conversation['imageUrl'],
              },
              chatType: isGroup ? 'group' : 'individual',
            ),
      ),
    );
  }
}