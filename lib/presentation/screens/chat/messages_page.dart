import 'package:flutter/material.dart';
import 'package:roomie/presentation/screens/chat/chat_screen.dart';
import 'package:roomie/data/datasources/messages_service.dart';
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
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 1,
        automaticallyImplyLeading: false,
        title: Text(
          'Messages',
          style: textTheme.headlineSmall?.copyWith(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Column(
        children: [
          // Top Row: Search bar + Filter tabs (matching search page structure)
          Container(
            color: Colors.transparent,
            padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.028, vertical: 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Search bar
                Expanded(
                  flex: 1,
                  child: Container(
                    height: screenHeight * 0.055,
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(screenHeight * 0.0275),
                      border: Border.all(
                        color: colorScheme.outlineVariant,
                        width: 1,
                      ),
                    ),
                    child: Center(
                      child: TextField(
                        controller: _searchController,
                        onChanged: _onSearchChanged,
                        textAlignVertical: TextAlignVertical.center,
                        style: textTheme.bodyMedium,
                        decoration: InputDecoration(
                          hintText: 'Search',
                          hintStyle: textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                          prefixIcon: Padding(
                            padding: EdgeInsets.only(left: screenWidth * 0.03, right: screenWidth * 0.02),
                            child: Icon(
                              Icons.search,
                              color: colorScheme.onSurfaceVariant,
                              size: screenHeight * 0.025,
                            ),
                          ),
                          prefixIconConstraints: BoxConstraints(
                            minWidth: 0,
                            minHeight: 0,
                          ),
                          filled: true,
                          fillColor: Colors.transparent,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          isCollapsed: true,
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: screenWidth * 0.04),
                // Filter tabs with gap on right
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
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
                // Show loading only if no data and still waiting
                // With caching, we usually have data immediately
                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return _buildShimmerLoading(screenHeight, screenWidth, colorScheme);
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

                return RefreshIndicator(
                  onRefresh: () => _messagesService.forceRefresh(),
                  child: ListView.builder(
                    padding: EdgeInsets.only(top: screenHeight * 0.012),  // Space below search bar
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: filteredConversations.length,
                    itemBuilder: (context, index) {
                      final conversation = filteredConversations[index];
                      return _buildConversationTile(conversation, screenHeight, screenWidth);
                    },
                  ),
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
          horizontal: screenWidth * 0.04,
          vertical: screenHeight * 0.014,
        ),
        decoration: BoxDecoration(
          color:
              isSelected
                  ? colorScheme.primary
                  : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(screenHeight * 0.0275),
        ),
        child: Center(
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
      margin: EdgeInsets.symmetric(
        horizontal: screenWidth * 0.015,  // 1.5% left/right
        vertical: screenHeight * 0.004,   // Small gap between items
      ),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(
          horizontal: screenWidth * 0.03,  // Reduced horizontal padding since margin is added
          vertical: screenHeight * 0.003,  // Reduced vertical padding
        ),
        dense: true,  // Makes ListTile more compact
        visualDensity: VisualDensity.compact,
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

  // Shimmer loading effect for smooth UX (like WhatsApp)
  Widget _buildShimmerLoading(double screenHeight, double screenWidth, ColorScheme colorScheme) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.only(top: screenHeight * 0.012),  // Space below search bar
      itemCount: 8,
      itemBuilder: (context, index) {
        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: screenWidth * 0.04,
            vertical: screenHeight * 0.005,  // Reduced vertical padding
          ),
          child: Row(
            children: [
              // Avatar shimmer
              Container(
                width: screenHeight * 0.06,
                height: screenHeight * 0.06,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: screenWidth * 0.03),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name shimmer
                    Container(
                      width: screenWidth * 0.4,
                      height: screenHeight * 0.018,
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    SizedBox(height: screenHeight * 0.008),
                    // Message shimmer
                    Container(
                      width: screenWidth * 0.6,
                      height: screenHeight * 0.014,
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
              // Time shimmer
              Container(
                width: screenWidth * 0.1,
                height: screenHeight * 0.014,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}