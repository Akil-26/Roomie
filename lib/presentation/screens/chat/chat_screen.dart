// ignore_for_file: avoid_types_as_parameter_names

import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:just_audio/just_audio.dart';
import 'package:roomie/data/datasources/auth_service.dart';
import 'package:roomie/data/datasources/chat_service.dart';
import 'package:roomie/data/datasources/message_cache_service.dart';
import 'package:roomie/data/datasources/user_cache_service.dart';

import 'package:roomie/data/models/message_model.dart';
import 'package:roomie/presentation/widgets/chat_input_widget.dart';
import 'package:roomie/presentation/widgets/roomie_loading_widget.dart';
import 'package:roomie/presentation/widgets/poll_todo_dialogs.dart';
import 'package:roomie/presentation/widgets/payment_request_dialog.dart';
import 'package:roomie/presentation/widgets/payment_request_card.dart';
import 'package:roomie/presentation/screens/groups/current_group_detail_s.dart';
import 'package:roomie/presentation/screens/profile/other_user_profile_s.dart';
import 'package:roomie/presentation/screens/chat/chat_payments_screen.dart';
import 'package:uuid/uuid.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.chatData, required this.chatType});

  final Map<String, dynamic> chatData;
  final String chatType;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  final AuthService _authService = AuthService();
  final ChatService _chatService = ChatService();

  final Uuid _uuid = const Uuid();
  final ImagePicker _imagePicker = ImagePicker();
  final AudioRecorder _voiceRecorder = AudioRecorder();

  Stream<List<MessageModel>>? _messagesStream;
  bool _initialized = false;
  bool _isGroup = false;
  String? _containerId;
  List<String> _memberIds = [];
  Map<String, String> _memberNames = {};
  Map<String, String?> _memberImages = {};
  MessageModel? _editingMessage;
  MessageModel? _selectedMessage; // For selection mode
  bool _isUploading = false;
  DateTime? _lastDeliverySync;

  // Cached messages for offline access
  List<MessageModel> _cachedMessages = [];
  final MessageCacheService _cacheService = MessageCacheService();
  final UserCacheService _userCacheService = UserCacheService();

  // Voice recording state
  bool _isRecording = false;
  Duration _recordDuration = Duration.zero;
  Timer? _recordTimer;
  DateTime? _lastReadSync;

  // Audio playback state
  AudioPlayer? _audioPlayer;
  String? _currentPlayingAudioId;
  bool _isAudioPlaying = false;

  // Smooth fade-in animation for chat content
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  bool _isFirstLoad = true;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );
    _initializeChat();
  }

  Future<void> _initializeChat() async {
    if (_initialized) return;

    final currentUser = _authService.currentUser;
    if (currentUser == null) return;

    try {
      final data = widget.chatData;
      if (widget.chatType == 'group') {
        _isGroup = true;
        final groupId = data['id'] ?? data['groupId'];
        if (groupId == null) {
          throw Exception('Missing group identifier');
        }

        final groupName = data['name'] ?? data['groupName'] ?? 'Group chat';
        final members = List<String>.from(data['members'] ?? const <String>[]);

        // Ensure current user is in the list
        if (!members.contains(currentUser.uid)) {
          members.add(currentUser.uid);
        }

        // FAST PATH: Load from cache first for instant display
        final memberNames = <String, String>{};
        final memberImages = <String, String?>{};
        final usersToFetch = <String>[];
        int cachedCount = 0;

        for (final memberId in members) {
          final cachedUser = _userCacheService.getCachedUser(memberId);
          if (cachedUser != null) {
            memberNames[memberId] = cachedUser.displayName;
            memberImages[memberId] = cachedUser.profileImageUrl;
            cachedCount++;
            // Check if cache is stale (older than 24 hours)
            if (_userCacheService.isUserStale(memberId)) {
              usersToFetch.add(memberId);
            }
          } else {
            memberNames[memberId] = 'User';
            usersToFetch.add(memberId);
          }
        }
        
        debugPrint('👥 User cache: $cachedCount/${members.length} members loaded from cache');

        _memberIds = members;
        _memberNames = memberNames;
        _memberImages = memberImages;

        // Set up chat container and stream
        _containerId = await _chatService.createOrGetGroupChat(
          groupId: groupId,
          groupName: groupName,
          memberIds: members,
          memberNames: memberNames,
        );
        _messagesStream = _chatService.getGroupMessagesStream(_containerId!);

        // Load cached messages for instant display
        await _loadCachedMessages();

        // Mark as initialized EARLY so UI shows immediately
        if (mounted) {
          setState(() {
            _initialized = true;
          });
        }

        // BACKGROUND: Fetch fresh user data from Firestore (non-blocking)
        if (usersToFetch.isNotEmpty) {
          debugPrint('🔄 Fetching ${usersToFetch.length} users from Firestore in background');
          _fetchAndCacheUsers(usersToFetch);
        } else {
          debugPrint('✅ All group members loaded from cache - no Firestore fetch needed');
        }
      } else {
        _isGroup = false;
        final otherUserId = data['otherUserId'] ?? data['userId'];
        if (otherUserId == null) {
          throw Exception('Missing user identifier');
        }
        
        // FAST PATH: Load from cache first
        String otherUserName = data['otherUserName'] ?? data['name'] ?? 'User';
        String? otherUserImage =
            data['otherUserImageUrl'] ??
            data['profileImageUrl'] ??
            data['imageUrl'];
        
        String currentUserDisplayName = 'You';
        final usersToFetch = <String>[];

        // Check cache for other user
        final cachedOtherUser = _userCacheService.getCachedUser(otherUserId);
        if (cachedOtherUser != null) {
          otherUserName = cachedOtherUser.displayName;
          otherUserImage = cachedOtherUser.profileImageUrl ?? otherUserImage;
          if (_userCacheService.isUserStale(otherUserId)) {
            usersToFetch.add(otherUserId);
          }
        } else {
          usersToFetch.add(otherUserId);
        }

        // Check cache for current user
        final cachedCurrentUser = _userCacheService.getCachedUser(currentUser.uid);
        if (cachedCurrentUser != null) {
          currentUserDisplayName = cachedCurrentUser.displayName;
          if (_userCacheService.isUserStale(currentUser.uid)) {
            usersToFetch.add(currentUser.uid);
          }
        } else {
          currentUserDisplayName = currentUser.email?.split('@')[0] ?? 'You';
          usersToFetch.add(currentUser.uid);
        }

        _memberIds = [currentUser.uid, otherUserId];
        _memberNames = {
          currentUser.uid: currentUserDisplayName,
          otherUserId: otherUserName,
        };
        _memberImages = {otherUserId: otherUserImage?.toString()};

        _containerId = await _chatService.createOrGetChat(
          otherUserId: otherUserId,
          otherUserName: otherUserName,
          otherUserImageUrl: otherUserImage?.toString(),
        );
        _messagesStream = _chatService.getMessagesStream(_containerId!);

        // Load cached messages for instant display
        await _loadCachedMessages();

        // Mark as initialized EARLY so UI shows immediately
        if (mounted) {
          setState(() {
            _initialized = true;
          });
        }

        // BACKGROUND: Fetch fresh user data from Firestore (non-blocking)
        if (usersToFetch.isNotEmpty) {
          debugPrint('🔄 Fetching ${usersToFetch.length} users from Firestore in background');
          _fetchAndCacheUsers(usersToFetch);
        } else {
          debugPrint('✅ All users loaded from cache - no Firestore fetch needed');
        }
      }

      await Future<void>.delayed(const Duration(milliseconds: 100));
      _scrollToBottom();
    } catch (e, stackTrace) {
      debugPrint('Chat init failed: $e');
      debugPrint('$stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to open chat: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  /// Fetch users from Firestore and update cache (runs in background)
  Future<void> _fetchAndCacheUsers(List<String> userIds) async {
    final usersToCache = <CachedUser>[];

    for (final userId in userIds) {
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .get();

        if (userDoc.exists && userDoc.data() != null) {
          final userData = userDoc.data()!;
          final displayName =
              userData['username'] as String? ??
              userData['name'] as String? ??
              (userData['email'] as String?)?.split('@')[0] ??
              'User';
          final profileImageUrl = userData['profileImageUrl'] as String?;
          final email = userData['email'] as String?;

          usersToCache.add(CachedUser(
            id: userId,
            displayName: displayName,
            profileImageUrl: profileImageUrl,
            email: email,
          ));

          // Update local state if mounted
          if (mounted) {
            setState(() {
              _memberNames[userId] = displayName;
              _memberImages[userId] = profileImageUrl;
            });
          }
        }
      } catch (e) {
        debugPrint('Error fetching user $userId: $e');
      }
    }

    // Cache all fetched users
    if (usersToCache.isNotEmpty) {
      await _userCacheService.cacheUsers(usersToCache);
      debugPrint('💾 Cached ${usersToCache.length} users');
    }
  }

  /// Load cached messages from local storage for instant display
  Future<void> _loadCachedMessages() async {
    if (_containerId == null) return;

    try {
      final cached = await _cacheService.getCachedMessages(_containerId!);
      if (cached.isNotEmpty && mounted) {
        setState(() {
          _cachedMessages = cached;
        });
        debugPrint('📦 Loaded ${cached.length} cached messages for offline access');
      }
    } catch (e) {
      debugPrint('❌ Failed to load cached messages: $e');
    }
  }

  /// Cache incoming messages to local storage
  Future<void> _cacheNewMessages(List<MessageModel> messages) async {
    if (_containerId == null || messages.isEmpty) return;

    try {
      await _cacheService.cacheMessages(_containerId!, messages);
    } catch (e) {
      debugPrint('❌ Failed to cache messages: $e');
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _recordTimer?.cancel();
    _audioPlayer?.dispose();
    _messageController.dispose();
    _messageFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final String title;
    final String subtitle;
    final Widget leadingAvatar;

    if (widget.chatType == 'group') {
      title =
          widget.chatData['name'] ??
          widget.chatData['groupName'] ??
          'Group chat';
      final memberCount =
          _memberIds.isNotEmpty
              ? _memberIds.length
              : (widget.chatData['memberCount'] as int?) ?? 0;
      subtitle = '$memberCount members';
      final imageUrl =
          widget.chatData['imageUrl'] ?? widget.chatData['groupImageUrl'];
      leadingAvatar = CircleAvatar(
        radius: 20,
        backgroundColor: colorScheme.primaryContainer,
        backgroundImage: imageUrl != null ? NetworkImage(imageUrl) : null,
        child:
            imageUrl == null
                ? Text(
                  title.isNotEmpty ? title.substring(0, 1).toUpperCase() : 'G',
                  style: textTheme.titleMedium?.copyWith(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                )
                : null,
      );
    } else {
      final otherId = _memberIds.firstWhere(
        (id) => id != _authService.currentUser?.uid,
        orElse:
            () =>
                widget.chatData['otherUserId'] ??
                widget.chatData['userId'] ??
                '',
      );
      title =
          _memberNames[otherId] ??
          widget.chatData['name'] ??
          widget.chatData['otherUserName'] ??
          'Chat';
      subtitle = widget.chatData['status'] ?? 'Tap for info';
      final imageUrl =
          _memberImages[otherId] ??
          widget.chatData['imageUrl'] ??
          widget.chatData['profileImageUrl'];
      leadingAvatar = CircleAvatar(
        radius: 20,
        backgroundColor: colorScheme.primaryContainer,
        backgroundImage: imageUrl != null ? NetworkImage(imageUrl) : null,
        child:
            imageUrl == null
                ? Text(
                  title.isNotEmpty ? title.substring(0, 1).toUpperCase() : 'U',
                  style: textTheme.titleMedium?.copyWith(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                )
                : null,
      );
    }

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 0.5,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: Icon(Icons.arrow_back, color: colorScheme.onSurface),
        ),
        titleSpacing: 0,
        title: GestureDetector(
          onTap: () {
            // Navigate to group details or user profile
            if (_isGroup) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (context) =>
                          CurrentGroupDetailScreen(group: widget.chatData),
                ),
              );
            } else {
              // Navigate to user profile
              final otherId = _memberIds.firstWhere(
                (id) => id != _authService.currentUser?.uid,
                orElse: () => widget.chatData['otherUserId'] ?? '',
              );
              if (otherId.isNotEmpty) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (context) => OtherUserProfileScreen(userId: otherId),
                  ),
                );
              }
            }
          },
          child: Row(
            children: [
              leadingAvatar,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: textTheme.titleMedium?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (_selectedMessage != null)
            // Selection mode actions
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_selectedMessage!.senderId ==
                        _authService.currentUser?.uid &&
                    _selectedMessage!.type == MessageType.text)
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _editingMessage = _selectedMessage;
                        _messageController.text = _selectedMessage!.message;
                        _messageController.selection = TextSelection.collapsed(
                          offset: _selectedMessage!.message.length,
                        );
                        _selectedMessage = null;
                      });
                    },
                    icon: Icon(Icons.edit, color: colorScheme.primary),
                    tooltip: 'Edit',
                  ),
                // Don't show copy for audio/voice messages
                if (_selectedMessage!.message.isNotEmpty &&
                    _selectedMessage!.type != MessageType.audio)
                  IconButton(
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: _selectedMessage!.message),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Text copied'),
                          duration: const Duration(seconds: 1),
                          backgroundColor: colorScheme.primary,
                        ),
                      );
                      setState(() => _selectedMessage = null);
                    },
                    icon: Icon(Icons.copy, color: colorScheme.primary),
                    tooltip: 'Copy',
                  ),
                if (_selectedMessage!.senderId == _authService.currentUser?.uid)
                  IconButton(
                    onPressed: () {
                      _showMessageInfo(_selectedMessage!);
                      setState(() => _selectedMessage = null);
                    },
                    icon: Icon(Icons.info_outline, color: colorScheme.primary),
                    tooltip: 'Info',
                  ),
                IconButton(
                  onPressed: () {
                    setState(() => _selectedMessage = null);
                  },
                  icon: Icon(Icons.close, color: colorScheme.onSurface),
                  tooltip: 'Cancel',
                ),
              ],
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: _openPaymentsScreen,
                  icon: Icon(Icons.receipt_long_outlined, color: colorScheme.onSurface),
                  tooltip: 'Payment Requests',
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: IconButton(
                    onPressed: _showChatInfo,
                    icon: Icon(Icons.info_outline, color: colorScheme.onSurface),
                    tooltip: _isGroup ? 'Group Details' : 'User Details',
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildMessagesArea()),
          if (_isUploading)
            LinearProgressIndicator(
              minHeight: 2,
              color: colorScheme.primary,
              backgroundColor: colorScheme.surfaceContainerHighest,
            ),
          _buildComposer(),
        ],
      ),
    );
  }

  Widget _buildMessagesArea() {
    if (!_initialized || _messagesStream == null) {
      // If we have cached messages, show them while initializing
      if (_cachedMessages.isNotEmpty) {
        // Start fade animation for cached content
        if (_isFirstLoad && !_fadeController.isAnimating && _fadeController.value == 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
            }
            _fadeController.forward();
            _isFirstLoad = false;
          });
        }
        return _buildMessagesList(_cachedMessages, fromCache: true);
      }
      return const Center(
        child: RoomieLoadingWidget(
          size: 60,
          showText: true,
          text: 'Loading messages...',
        ),
      );
    }

    return StreamBuilder<List<MessageModel>>(
      stream: _messagesStream,
      builder: (context, snapshot) {
        final colorScheme = Theme.of(context).colorScheme;
        final textTheme = Theme.of(context).textTheme;

        // Show cached messages while waiting for Firebase
        if (snapshot.connectionState == ConnectionState.waiting &&
            snapshot.data == null) {
          if (_cachedMessages.isNotEmpty) {
            return _buildMessagesList(_cachedMessages, fromCache: true);
          }
          return const Center(
            child: RoomieLoadingWidget(
              size: 60,
              showText: true,
              text: 'Loading messages...',
            ),
          );
        }

        // On error, show cached messages if available
        if (snapshot.hasError) {
          if (_cachedMessages.isNotEmpty) {
            return Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: colorScheme.errorContainer.withOpacity(0.3),
                  child: Row(
                    children: [
                      Icon(Icons.cloud_off, size: 16, color: colorScheme.onErrorContainer),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Offline mode - showing cached messages',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(child: _buildMessagesList(_cachedMessages, fromCache: true)),
              ],
            );
          }
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 48, color: colorScheme.error),
                const SizedBox(height: 12),
                Text(
                  'Something went wrong',
                  style: textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  snapshot.error.toString(),
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        final messages = snapshot.data ?? const <MessageModel>[];
        
        // Cache new messages for offline access
        if (messages.isNotEmpty) {
          _cacheNewMessages(messages);
          // Update cached messages reference
          _cachedMessages = messages;
        }
        
        if (messages.isEmpty) {
          // Check cached messages first
          if (_cachedMessages.isNotEmpty) {
            return _buildMessagesList(_cachedMessages, fromCache: true);
          }
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  widget.chatType == 'group'
                      ? Icons.group_outlined
                      : Icons.chat_bubble_outline,
                  size: 52,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 12),
                Text(
                  widget.chatType == 'group'
                      ? 'No messages in this group yet'
                      : 'Say hello 👋',
                  style: textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Start the conversation with a message or attachment.',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToBottom();
        });

        _syncMessageStates(messages);

        return _buildMessagesList(messages, fromCache: false);
      },
    );
  }

  /// Build the messages list view with smooth fade-in animation
  Widget _buildMessagesList(List<MessageModel> messages, {bool fromCache = false}) {
    final listView = ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        return _buildMessageBubble(message);
      },
    );
    
    // Wrap in fade animation for smooth appearance
    return FadeTransition(
      opacity: _fadeAnimation,
      child: listView,
    );
  }

  Widget _buildComposer() {
    return Column(
      children: [
        // Edit message banner
        if (_editingMessage != null) _buildEditingBanner(),

        // Modern chat input widget
        ChatInputWidget(
          messageController: _messageController,
          messageFocusNode: _messageFocusNode,
          onSendPressed: _handleSendPressed,
          onImageSelected: (file, fileName) => _handleImageUpload(file),
          onFileSelected: (file, fileName) => _handleFileUpload(file),
          onVoiceRecorded: (file, duration) => _handleVoiceUpload(file),
          onPollPressed: () => _showPollDialog(),
          onTodoPressed: () => _showTodoDialog(),
          onPaymentPressed: () => _showPaymentRequestDialog(),
          isUploading: _isUploading,
          isGroup: _isGroup,
        ),
      ],
    );
  }

  Widget _buildEditingBanner() {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final editing = _editingMessage!;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.edit, size: 18, color: colorScheme.onPrimaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Editing: ${editing.message}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          IconButton(
            onPressed: () {
              setState(() {
                _editingMessage = null;
                _messageController.clear();
              });
            },
            icon: Icon(
              Icons.close,
              size: 18,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }

  // Emoji picker removed

  Future<void> _startRecording() async {
    if (_isRecording) return;
    final hasPerm = await _voiceRecorder.hasPermission();
    if (!hasPerm) {
      _showError('Microphone permission denied.');
      return;
    }
    final dir = await getTemporaryDirectory();
    final path = p.join(
      dir.path,
      'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
    );
    await _voiceRecorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 44100,
        bitRate: 128000,
      ),
      path: path,
    );
    setState(() {
      _isRecording = true;
      _recordDuration = Duration.zero;
    });
    _recordTimer?.cancel();
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _recordDuration += const Duration(seconds: 1));
    });
  }

  Future<void> _stopRecording({required bool send}) async {
    if (!_isRecording) return;
    _recordTimer?.cancel();
    String? recordedPath;
    try {
      recordedPath = await _voiceRecorder.stop();
    } catch (e) {
      debugPrint('record stop error: $e');
    }

    final duration = _recordDuration;
    setState(() {
      _isRecording = false;
      _recordDuration = Duration.zero;
    });

    if (!send || recordedPath == null) {
      if (recordedPath != null) {
        try {
          await File(recordedPath).delete();
        } catch (_) {}
      }
      return;
    }

    File? file;
    try {
      file = File(recordedPath);
      final bytes = await file.readAsBytes();
      setState(() => _isUploading = true);
      final url = await _chatService.uploadChatFile(
        bytes: bytes,
        fileName: p.basename(recordedPath),
        contentType: 'audio/m4a',
        folder:
            _isGroup
                ? 'groups/$_containerId/audio'
                : 'chats/$_containerId/audio',
      );
      final attachment = MessageAttachment(
        url: url,
        name: 'Voice message',
        type: AttachmentType.voice,
        mimeType: 'audio/m4a',
        size: bytes.lengthInBytes,
        durationInMs: duration.inMilliseconds,
      );
      await _sendRichMessage(
        type: MessageType.voice,
        attachments: [attachment],
      );
    } catch (e) {
      _showError('Failed to send voice message: $e');
    } finally {
      if (file != null) {
        try {
          await file.delete();
        } catch (_) {}
      }
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _handleSendPressed() async {
    if (_editingMessage != null) {
      await _applyEdit();
      return;
    }

    final text = _messageController.text.trim();
    if (text.isEmpty || _containerId == null) {
      return;
    }

    await _sendRichMessage(text: text, type: MessageType.text);
    _messageController.clear();
    setState(() {});
  }

  Future<void> _applyEdit() async {
    final editing = _editingMessage;
    if (editing == null || _containerId == null) return;

    final newText = _messageController.text.trim();
    if (newText.isEmpty || newText == editing.message) {
      setState(() {
        _editingMessage = null;
        _messageController.clear();
      });
      return;
    }

    try {
      if (_isGroup) {
        await _chatService.editGroupMessage(
          groupId: _containerId!,
          messageId: editing.id,
          newText: newText,
        );
      } else {
        await _chatService.editMessage(
          chatId: _containerId!,
          messageId: editing.id,
          newText: newText,
        );
      }
      setState(() {
        _editingMessage = null;
        _messageController.clear();
      });
    } catch (e) {
      _showError('Failed to edit message: $e');
    }
  }

  Future<void> _sendRichMessage({
    required MessageType type,
    String? text,
    List<MessageAttachment> attachments = const [],
    PollData? poll,
    TodoData? todo,
    PaymentRequestData? paymentRequest,
    Map<String, dynamic>? extraData,
  }) async {
    if (_containerId == null) return;

    try {
      if (_isGroup) {
        await _chatService.sendGroupMessage(
          groupId: _containerId!,
          message: text,
          type: type,
          attachments: attachments,
          poll: poll,
          todo: todo,
          paymentRequest: paymentRequest,
          extraData: extraData,
        );
      } else {
        await _chatService.sendMessage(
          chatId: _containerId!,
          message: text,
          type: type,
          attachments: attachments,
          poll: poll,
          todo: todo,
          paymentRequest: paymentRequest,
          extraData: extraData,
        );
      }
      _scrollToBottom();
    } catch (e) {
      _showError('Failed to send message: $e');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    final colorScheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: colorScheme.onError)),
        backgroundColor: colorScheme.error,
      ),
    );
  }

  void _scrollToBottom({bool instant = false}) {
    if (!_scrollController.hasClients) return;
    
    if (instant || _isFirstLoad) {
      // Instant scroll on first load - no animation to avoid jarring effect
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      if (_isFirstLoad) {
        _isFirstLoad = false;
        // Start fade-in animation after positioning
        _fadeController.forward();
      }
    } else {
      // Animated scroll for new messages
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _syncMessageStates(List<MessageModel> messages) {
    if (_containerId == null || messages.isEmpty) return;

    final now = DateTime.now();
    const debounce = Duration(seconds: 3);

    if (_isGroup) {
      if (_lastReadSync == null || now.difference(_lastReadSync!) > debounce) {
        _chatService.markGroupMessagesAsRead(_containerId!);
        _lastReadSync = now;
      }
      return;
    }

    if (_lastDeliverySync == null ||
        now.difference(_lastDeliverySync!) > debounce) {
      _chatService.markMessagesAsDelivered(_containerId!);
      _lastDeliverySync = now;
    }

    if (_lastReadSync == null || now.difference(_lastReadSync!) > debounce) {
      _chatService.markMessagesAsRead(_containerId!);
      _lastReadSync = now;
    }
  }

  void _showAttachmentSheet() {
    FocusScope.of(context).unfocus();
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        final textTheme = Theme.of(context).textTheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 60,
                  height: 4,
                  decoration: BoxDecoration(
                    // ignore: deprecated_member_use
                    color: colorScheme.onSurfaceVariant.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                ListTile(
                  leading: Icon(
                    Icons.insert_drive_file,
                    color: colorScheme.primary,
                  ),
                  title: Text('Document', style: textTheme.bodyLarge),
                  onTap: () {
                    Navigator.pop(context);
                    _pickAndSendDocument();
                  },
                ),
                ListTile(
                  leading: Icon(
                    Icons.photo_library,
                    color: colorScheme.primary,
                  ),
                  title: Text('Gallery', style: textTheme.bodyLarge),
                  onTap: () {
                    Navigator.pop(context);
                    _pickAndSendImage(ImageSource.gallery);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.camera_alt, color: colorScheme.primary),
                  title: Text('Camera', style: textTheme.bodyLarge),
                  onTap: () {
                    Navigator.pop(context);
                    _pickAndSendImage(ImageSource.camera);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.poll, color: colorScheme.primary),
                  title: Text('Create poll', style: textTheme.bodyLarge),
                  onTap: () {
                    Navigator.pop(context);
                    _showCreatePollSheet();
                  },
                ),
                ListTile(
                  leading: Icon(Icons.checklist, color: colorScheme.primary),
                  title: Text('Create to-do list', style: textTheme.bodyLarge),
                  onTap: () {
                    Navigator.pop(context);
                    _showCreateTodoSheet();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    if (_containerId == null) return;

    try {
      final XFile? file =
          source == ImageSource.camera
              ? await _imagePicker.pickImage(
                source: ImageSource.camera,
                imageQuality: 80,
              )
              : await _imagePicker.pickImage(
                source: ImageSource.gallery,
                imageQuality: 85,
              );

      if (file == null) return;

      setState(() => _isUploading = true);

      final bytes = await file.readAsBytes();
      final fileName =
          file.name.isNotEmpty ? file.name : 'image_${_uuid.v4()}.jpg';
      final extension = p.extension(fileName).toLowerCase();
      final contentType = _inferImageContentType(extension);

      final url = await _chatService.uploadChatFile(
        bytes: bytes,
        fileName: fileName,
        contentType: contentType,
        folder:
            _isGroup
                ? 'groups/$_containerId/images'
                : 'chats/$_containerId/images',
      );

      final attachment = MessageAttachment(
        url: url,
        name: fileName,
        type: AttachmentType.image,
        mimeType: contentType,
        size: bytes.lengthInBytes,
      );

      await _sendRichMessage(
        type: MessageType.image,
        attachments: [attachment],
      );
    } catch (e) {
      _showError('Failed to send image: $e');
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _pickAndSendDocument() async {
    if (_containerId == null) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final picked = result.files.single;
      Uint8List? bytes = picked.bytes;
      if (bytes == null && picked.path != null) {
        bytes = await File(picked.path!).readAsBytes();
      }
      if (bytes == null) {
        _showError('Unable to read selected file.');
        return;
      }

      setState(() => _isUploading = true);

      final fileName =
          picked.name.isNotEmpty ? picked.name : 'file_${_uuid.v4()}';
      final extension = p.extension(fileName).toLowerCase();
      final contentType = _inferFileContentType(extension);

      final url = await _chatService.uploadChatFile(
        bytes: bytes,
        fileName: fileName,
        contentType: contentType,
        folder:
            _isGroup
                ? 'groups/$_containerId/files'
                : 'chats/$_containerId/files',
      );

      final attachment = MessageAttachment(
        url: url,
        name: fileName,
        type: AttachmentType.document,
        mimeType: contentType,
        size: picked.size,
      );

      await _sendRichMessage(type: MessageType.file, attachments: [attachment]);
    } catch (e) {
      _showError('Failed to share file: $e');
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _showCreatePollSheet() async {
    // Use the hardened dialog widget to avoid controller lifecycle issues
    final result = await showDialog<PollData>(
      context: context,
      builder: (ctx) => const CreatePollDialog(),
    );
    if (!mounted || result == null) return;
    await _sendRichMessage(type: MessageType.poll, poll: result);
  }

  void _showCreateTodoSheet() async {
    // Use the hardened dialog widget to avoid controller lifecycle issues
    final result = await showDialog<TodoData>(
      context: context,
      builder: (ctx) => const CreateTodoDialog(),
    );
    if (!mounted || result == null) return;
    await _sendRichMessage(type: MessageType.todo, todo: result);
  }

  void _showPaymentRequestDialog() async {
    final currentUserId = _authService.currentUser?.uid;
    if (currentUserId == null || _containerId == null) return;

    final result = await showDialog<PaymentRequestData>(
      context: context,
      builder:
          (ctx) => CreatePaymentRequestDialog(
            isGroup: _isGroup,
            memberIds: _memberIds,
            memberNames: _memberNames,
            currentUserId: currentUserId,
          ),
    );

    if (!mounted || result == null) return;
    await _sendRichMessage(
      type: MessageType.paymentRequest,
      paymentRequest: result,
      text: '💰 Payment Request: ₹${result.totalAmount.toStringAsFixed(0)}',
    );
  }

  Widget _buildMessageBubble(MessageModel message) {
    final currentUserId = _authService.currentUser?.uid;
    final isMine = message.senderId == currentUserId;
    final isSystem =
        message.isSystemMessage || message.type == MessageType.system;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              message.message,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final bubbleColor =
        isMine
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerHighest;
    final textColor =
        isMine ? colorScheme.onPrimaryContainer : colorScheme.onSurface;

    final isSelected = _selectedMessage?.id == message.id;

    return GestureDetector(
      onLongPress: () {
        // Enter selection mode
        setState(() {
          _selectedMessage = message;
        });
      },
      onTap: () {
        // If in selection mode and clicking same message, deselect
        if (_selectedMessage?.id == message.id) {
          setState(() {
            _selectedMessage = null;
          });
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment:
              isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // Sender name and time above message (WhatsApp style)
            if (_isGroup)
              Padding(
                padding: EdgeInsets.only(
                  left: isMine ? 0 : 8,
                  right: isMine ? 8 : 0,
                  bottom: 4,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _resolveUserName(
                        message.senderId,
                        fallback: message.senderName,
                      ),
                      style: textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatTimestamp(message.timestamp),
                      style: textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 10,
                      ),
                    ),
                    // Show seen count only for current user's messages
                    if (isMine) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.remove_red_eye,
                        size: 13,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '${message.seenBy.keys.where((id) => id != message.senderId).length}',
                        style: textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            Align(
              alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.78,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color:
                        isSelected
                            ? colorScheme.primary.withOpacity(0.2)
                            : bubbleColor,
                    border:
                        isSelected
                            ? Border.all(color: colorScheme.primary, width: 2)
                            : null,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(isMine ? 18 : 6),
                      bottomRight: Radius.circular(isMine ? 6 : 18),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Column(
                      crossAxisAlignment:
                          isMine
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
                      children: [
                        if (message.attachments.isNotEmpty)
                          ...message.attachments.map(
                            (attachment) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _buildAttachmentPreview(
                                attachment,
                                message.id,
                              ),
                            ),
                          ),
                        // Don't show message text for audio/voice messages or payment requests
                        if (message.message.isNotEmpty &&
                            (message.type != MessageType.audio ||
                                message.attachments.isEmpty) &&
                            message.type != MessageType.paymentRequest)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              message.message,
                              style: textTheme.bodyMedium?.copyWith(
                                color: textColor,
                                height: 1.4,
                              ),
                            ),
                          ),
                        if (message.poll != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: _buildPollWidget(message),
                          ),
                        if (message.todo != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: _buildTodoWidget(message),
                          ),
                        if (message.paymentRequest != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: _buildPaymentRequestWidget(message),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentPreview(
    MessageAttachment attachment,
    String messageId,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    switch (attachment.type) {
      case AttachmentType.image:
        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: () => _openImagePreview(attachment.url),
            child: Image.network(
              attachment.url,
              fit: BoxFit.cover,
              width: 220,
              height: 220,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return const SizedBox(
                  width: 220,
                  height: 220,
                  child: Center(
                    child: RoomieLoadingWidget(size: 36, showText: false),
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.broken_image,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Failed to load image',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      // Voice/audio playback - WhatsApp style
      case AttachmentType.voice:
      case AttachmentType.audio:
        final isThisAudioPlaying =
            _currentPlayingAudioId == messageId && _isAudioPlaying;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Play/pause button
              InkWell(
                onTap: () => _playPauseAudio(attachment.url, messageId),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isThisAudioPlaying ? Icons.pause : Icons.play_arrow,
                    color: colorScheme.onPrimary,
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Waveform placeholder
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Waveform bars
                    Row(
                      children: List.generate(30, (index) {
                        final heights = [3.0, 6.0, 9.0, 12.0, 8.0, 5.0];
                        return Container(
                          width: 3,
                          height: heights[index % heights.length],
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          decoration: BoxDecoration(
                            color: colorScheme.onSurface.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Duration
              Text(
                attachment.durationInMs != null
                    ? _formatAudioDuration(attachment.durationInMs!)
                    : '0:02',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
            ],
          ),
        );
      default:
        return InkWell(
          onTap: () => _openExternalLink(attachment.url),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.insert_drive_file, color: colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    attachment.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
              ],
            ),
          ),
        );
    }
  }

  Widget _buildPollWidget(MessageModel message) {
    final poll = message.poll!;
    final currentUserId = _authService.currentUser?.uid;
    final totalVotes = poll.options.fold<int>(
      0,
      (sum, option) => sum + option.votes.length,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          poll.question,
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        ...poll.options.map((option) {
          final hasVoted =
              currentUserId != null && option.votes.contains(currentUserId);
          final voteCount = option.votes.length;
          final ratio = totalVotes == 0 ? 0.0 : voteCount / totalVotes;

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: () {
                _chatService.togglePollVote(
                  containerId: _containerId!,
                  messageId: message.id,
                  optionId: option.id,
                  isGroup: _isGroup,
                );
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color:
                      hasVoted
                          // ignore: deprecated_member_use
                          ? Theme.of(
                            context,
                          ).colorScheme.primary.withOpacity(0.12)
                          : Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(option.title),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 6,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$voteCount vote${voteCount == 1 ? '' : 's'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // View votes button
            TextButton(
              onPressed: totalVotes > 0 ? () => _showPollVotes(message) : null,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: const Size(0, 0),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'View votes',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color:
                      totalVotes > 0
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant.withOpacity(0.5),
                ),
              ),
            ),
            Text(
              totalVotes == 0 ? 'No votes yet' : '$totalVotes total votes',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTodoWidget(MessageModel message) {
    final todo = message.todo!;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          todo.title,
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        ...todo.items.map(
          (item) => CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: item.isDone,
            dense: true,
            onChanged: (_) {
              _chatService.updateTodoItem(
                containerId: _containerId!,
                messageId: message.id,
                itemId: item.id,
                isGroup: _isGroup,
              );
            },
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              item.title,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                decoration: item.isDone ? TextDecoration.lineThrough : null,
                color:
                    item.isDone
                        ? colorScheme.onSurfaceVariant
                        : colorScheme.onSurface,
              ),
            ),
            secondary:
                item.isDone && item.completedBy != null
                    ? CircleAvatar(
                      radius: 14,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                      backgroundImage:
                          _memberImages[item.completedBy] != null
                              ? NetworkImage(_memberImages[item.completedBy]!)
                              : null,
                      child:
                          _memberImages[item.completedBy] == null
                              ? Text(
                                _resolveUserName(
                                  item.completedBy!,
                                ).substring(0, 1).toUpperCase(),
                                style: Theme.of(
                                  context,
                                ).textTheme.labelSmall?.copyWith(fontSize: 10),
                              )
                              : null,
                    )
                    : null,
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentRequestWidget(MessageModel message) {
    final paymentRequest = message.paymentRequest!;
    final currentUserId = _authService.currentUser?.uid ?? '';
    final isMine = message.senderId == currentUserId;

    return PaymentRequestCard(
      paymentRequest: paymentRequest,
      currentUserId: currentUserId,
      senderId: message.senderId,
      memberNames: _memberNames,
      isSentByMe: isMine,
      onPaymentStatusChanged: (odId, newStatus) {
        _handlePaymentStatusChange(message.id, odId, newStatus);
      },
    );
  }

  void _handlePaymentStatusChange(
    String messageId,
    String odId,
    PaymentStatus newStatus,
  ) async {
    if (_containerId == null) return;

    try {
      await _chatService.updatePaymentRequestStatus(
        containerId: _containerId!,
        messageId: messageId,
        odId: odId,
        newStatus: newStatus,
        isGroupChat: _isGroup,
      );
    } catch (e) {
      _showError('Failed to update payment status: $e');
    }
  }

  Widget _buildStatusRow(MessageModel message, bool isMine) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final timeString = _formatTimestamp(message.timestamp);
    final isEdited = message.editedAt != null;
    final seenCount =
        _isGroup
            ? message.seenBy.keys.where((id) => id != message.senderId).length
            : 0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isEdited)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Text(
              'Edited',
              style: textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        Text(
          timeString,
          style: textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        if (isMine) ...[
          const SizedBox(width: 4),
          Icon(
            _statusIcon(message.status),
            size: 16,
            color: _statusColor(message.status, colorScheme),
          ),
        ],
        if (_isGroup && seenCount > 0) ...[
          const SizedBox(width: 6),
          Icon(
            Icons.remove_red_eye,
            size: 14,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 2),
          Text(
            '$seenCount',
            style: textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  IconData _statusIcon(MessageStatus status) {
    switch (status) {
      case MessageStatus.sending:
        return Icons.access_time;
      case MessageStatus.sent:
        return Icons.check;
      case MessageStatus.delivered:
        return Icons.done_all;
      case MessageStatus.read:
        return Icons.done_all;
    }
  }

  Color _statusColor(MessageStatus status, ColorScheme colorScheme) {
    switch (status) {
      case MessageStatus.read:
        return colorScheme.primary;
      case MessageStatus.delivered:
        return colorScheme.onSurfaceVariant;
      case MessageStatus.sent:
        return colorScheme.onSurfaceVariant.withOpacity(0.7);
      case MessageStatus.sending:
        return colorScheme.onSurfaceVariant.withOpacity(0.6);
    }
  }

  String _formatTimestamp(DateTime timestamp) {
    final local = timestamp.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final suffix = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  String _formatFullDate(DateTime timestamp) {
    final local = timestamp.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year;
    final time = _formatTimestamp(timestamp);
    return '$day/$month/$year $time';
  }

  String _formatAudioDuration(int milliseconds) {
    final duration = Duration(milliseconds: milliseconds);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  void _onMessageLongPress(MessageModel message, bool isMine) {
    final actions = <_MessageAction>[
      // Don't show copy for audio/voice messages
      if (message.message.isNotEmpty && message.type != MessageType.audio)
        _MessageAction(
          icon: Icons.copy,
          label: 'Copy text',
          onSelected: () {
            Clipboard.setData(ClipboardData(text: message.message));
            Navigator.pop(context);
          },
        ),
      if (isMine && message.type == MessageType.text)
        _MessageAction(
          icon: Icons.edit,
          label: 'Edit message',
          onSelected: () {
            Navigator.pop(context);
            setState(() {
              _editingMessage = message;
              _messageController.text = message.message;
              _messageController.selection = TextSelection.collapsed(
                offset: message.message.length,
              );
            });
          },
        ),
      if (message.editHistory.isNotEmpty)
        _MessageAction(
          icon: Icons.history,
          label: 'View edit history',
          onSelected: () {
            Navigator.pop(context);
            _showEditHistory(message);
          },
        ),
      _MessageAction(
        icon: Icons.info_outline,
        label: 'Message info',
        onSelected: () {
          Navigator.pop(context);
          _showMessageInfo(message);
        },
      ),
    ];

    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        final textTheme = Theme.of(context).textTheme;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ...actions.map(
                (action) => ListTile(
                  leading: Icon(action.icon, color: colorScheme.primary),
                  title: Text(action.label, style: textTheme.bodyLarge),
                  onTap: action.onSelected,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showEditHistory(MessageModel message) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final entries = List<MessageEditEntry>.from(message.editHistory);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Edit history',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                if (entries.isEmpty)
                  const Text('No edits yet')
                else
                  ...entries.map(
                    (entry) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(entry.text),
                      subtitle: Text(_formatFullDate(entry.editedAt)),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showPollVotes(MessageModel message) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final poll = message.poll!;

    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Poll Votes',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  poll.question,
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                ...poll.options.map((option) {
                  if (option.votes.isEmpty) return const SizedBox.shrink();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        option.title,
                        style: textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...option.votes.map((userId) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 16,
                                backgroundColor:
                                    colorScheme.surfaceContainerHighest,
                                backgroundImage:
                                    _memberImages[userId] != null
                                        ? NetworkImage(_memberImages[userId]!)
                                        : null,
                                child:
                                    _memberImages[userId] == null
                                        ? Text(
                                          _resolveUserName(
                                            userId,
                                          ).substring(0, 1).toUpperCase(),
                                          style: textTheme.bodySmall,
                                        )
                                        : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _resolveUserName(userId),
                                  style: textTheme.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 12),
                    ],
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showMessageInfo(MessageModel message) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final seenEntries =
        message.seenBy.entries
            .where((entry) => entry.key != message.senderId)
            .toList()
          ..sort((a, b) => a.value.compareTo(b.value));

    DateTime? readAt;
    if (!_isGroup) {
      final otherId = _memberIds.firstWhere(
        (id) => id != message.senderId,
        orElse: () => '',
      );
      if (otherId.isNotEmpty) {
        readAt = message.seenBy[otherId];
      }
    }

    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Message info',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 16),
                if (!_isGroup)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      _statusIcon(message.status),
                      color: _statusColor(message.status, colorScheme),
                    ),
                    title: Text(
                      message.status.name.toUpperCase(),
                      style: textTheme.bodyLarge,
                    ),
                    subtitle: Text(switch (message.status) {
                      MessageStatus.read when readAt != null =>
                        'Read at ${_formatFullDate(readAt)}',
                      MessageStatus.read => 'Read',
                      MessageStatus.delivered => 'Delivered',
                      MessageStatus.sent => 'Sent',
                      MessageStatus.sending => 'Sending…',
                    }),
                  ),
                if (_isGroup) ...[
                  Text(
                    'Seen by',
                    style: textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (seenEntries.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'No one has seen this yet',
                        style: textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    ...seenEntries.map(
                      (entry) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          radius: 18,
                          backgroundColor: colorScheme.surfaceContainerHighest,
                          child: Text(
                            _resolveUserName(
                              entry.key,
                            ).substring(0, 1).toUpperCase(),
                          ),
                        ),
                        title: Text(_resolveUserName(entry.key)),
                        subtitle: Text(_formatFullDate(entry.value)),
                      ),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _openImagePreview(String url) {
    showDialog<void>(
      context: context,
      builder:
          (context) => Dialog(
            insetPadding: const EdgeInsets.all(12),
            child: InteractiveViewer(
              child: Image.network(url, fit: BoxFit.contain),
            ),
          ),
    );
  }

  Future<void> _openExternalLink(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _showError('Unable to open file.');
    }
  }

  void _openPaymentsScreen() {
    if (_containerId == null) return;

    final chatName = _isGroup
        ? (widget.chatData['name'] ?? widget.chatData['groupName'] ?? 'Group')
        : (_memberNames.entries
                .firstWhere(
                  (e) => e.key != _authService.currentUser?.uid,
                  orElse: () => const MapEntry('', 'Chat'),
                )
                .value);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatPaymentsScreen(
          containerId: _containerId!,
          chatName: chatName,
          isGroup: _isGroup,
          memberNames: _memberNames,
        ),
      ),
    );
  }

  void _showChatInfo() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        if (_isGroup) {
          return _buildGroupInfoSheet();
        }
        return _buildPersonInfoSheet();
      },
    );
  }

  String _formatRecordingDuration(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  String _inferImageContentType(String extension) {
    switch (extension) {
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      case '.gif':
        return 'image/gif';
      case '.heic':
      case '.heif':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
  }

  String _inferFileContentType(String extension) {
    switch (extension) {
      case '.pdf':
        return 'application/pdf';
      case '.doc':
        return 'application/msword';
      case '.docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case '.ppt':
        return 'application/vnd.ms-powerpoint';
      case '.pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case '.xls':
        return 'application/vnd.ms-excel';
      case '.xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case '.txt':
        return 'text/plain';
      case '.png':
        return 'image/png';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.webp':
        return 'image/webp';
      case '.gif':
        return 'image/gif';
      case '.mp3':
        return 'audio/mpeg';
      case '.wav':
        return 'audio/wav';
      case '.aac':
        return 'audio/aac';
      case '.m4a':
        return 'audio/m4a';
      case '.mp4':
        return 'video/mp4';
      case '.mov':
        return 'video/quicktime';
      case '.webm':
        return 'video/webm';
      default:
        return 'application/octet-stream';
    }
  }

  Widget _buildGroupInfoSheet() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    final groupName =
        widget.chatData['name'] ?? widget.chatData['groupName'] ?? 'Group';
    final imageUrl =
        widget.chatData['imageUrl'] ?? widget.chatData['groupImageUrl'];
    final members = _memberIds;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 48,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: colorScheme.primaryContainer,
                  backgroundImage:
                      imageUrl != null ? NetworkImage(imageUrl) : null,
                  child:
                      imageUrl == null
                          ? Text(
                            groupName.substring(0, 1).toUpperCase(),
                            style: textTheme.headlineSmall?.copyWith(
                              color: colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                          : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        groupName,
                        style: textTheme.headlineSmall?.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${members.length} members',
                        style: textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Members',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            ...members.map((memberId) {
              final isCurrentUser = _authService.currentUser?.uid == memberId;
              final displayName = _resolveUserName(memberId);

              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  backgroundImage:
                      _memberImages[memberId] != null
                          ? NetworkImage(_memberImages[memberId]!)
                          : null,
                  child:
                      _memberImages[memberId] == null
                          ? Text(
                            displayName.substring(0, 1).toUpperCase(),
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                          : null,
                ),
                title: Text(
                  isCurrentUser ? '$displayName (You)' : displayName,
                  style: textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildPersonInfoSheet() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    final otherId = _memberIds.firstWhere(
      (id) => id != _authService.currentUser?.uid,
      orElse: () => widget.chatData['otherUserId'] ?? '',
    );
    final name = _resolveUserName(otherId, fallback: widget.chatData['name']);
    final imageUrl =
        _memberImages[otherId] ??
        widget.chatData['imageUrl'] ??
        widget.chatData['profileImageUrl'];

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 48,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: colorScheme.primaryContainer,
                  backgroundImage:
                      imageUrl != null ? NetworkImage(imageUrl) : null,
                  child:
                      imageUrl == null
                          ? Text(
                            name.substring(0, 1).toUpperCase(),
                            style: textTheme.headlineSmall?.copyWith(
                              color: colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                          : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: textTheme.headlineSmall?.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (widget.chatData['email'] != null)
                        Text(
                          widget.chatData['email'],
                          style: textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Contact info',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            if (widget.chatData['phone'] != null)
              _buildInfoRow(Icons.phone, 'Phone', widget.chatData['phone']),
            if (widget.chatData['email'] != null)
              _buildInfoRow(Icons.email, 'Email', widget.chatData['email']),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Text(
            label,
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  // Modern chat widget handlers

  Future<void> _sendPollMessage(PollData pollData) async {
    if (!_initialized || _containerId == null) return;

    final currentUser = _authService.currentUser;
    if (currentUser == null) return;

    try {
      if (_isGroup) {
        await _chatService.sendGroupMessage(
          groupId: _containerId!,
          message: 'Poll: ${pollData.question}',
          type: MessageType.poll,
          poll: pollData,
        );
      } else {
        await _chatService.sendMessage(
          chatId: _containerId!,
          message: 'Poll: ${pollData.question}',
          type: MessageType.poll,
          poll: pollData,
        );
      }

      _scrollToBottom();
    } catch (e) {
      debugPrint('Failed to send poll: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send poll: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _sendTodoMessage(TodoData todoData) async {
    if (!_initialized || _containerId == null) return;

    final currentUser = _authService.currentUser;
    if (currentUser == null) return;

    try {
      if (_isGroup) {
        await _chatService.sendGroupMessage(
          groupId: _containerId!,
          message: 'To-do: ${todoData.title}',
          type: MessageType.todo,
          todo: todoData,
        );
      } else {
        await _chatService.sendMessage(
          chatId: _containerId!,
          message: 'To-do: ${todoData.title}',
          type: MessageType.todo,
          todo: todoData,
        );
      }

      _scrollToBottom();
    } catch (e) {
      debugPrint('Failed to send to-do: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send to-do: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _resolveUserName(String userId, {String? fallback}) {
    if (_authService.currentUser?.uid == userId) {
      return 'You';
    }
    return _memberNames[userId] ?? fallback ?? 'Member';
  }

  Future<void> _handleImageUpload(File imageFile) async {
    if (_containerId == null) return;

    try {
      setState(() => _isUploading = true);

      final bytes = await imageFile.readAsBytes();
      final fileName = 'image_${_uuid.v4()}.jpg';

      final url = await _chatService.uploadChatFile(
        bytes: bytes,
        fileName: fileName,
        contentType: 'image/jpeg',
        folder:
            _isGroup
                ? 'groups/$_containerId/images'
                : 'chats/$_containerId/images',
      );

      final attachment = MessageAttachment(
        url: url,
        name: fileName,
        type: AttachmentType.image,
        mimeType: 'image/jpeg',
        size: bytes.lengthInBytes,
      );

      await _sendRichMessage(
        type: MessageType.image,
        attachments: [attachment],
      );
    } catch (e) {
      _showError('Failed to send image: $e');
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _handleFileUpload(File file) async {
    if (_containerId == null) return;

    try {
      setState(() => _isUploading = true);

      final bytes = await file.readAsBytes();
      final fileName = p.basename(file.path);
      final extension = p.extension(fileName).toLowerCase();
      final contentType = _inferFileContentType(extension);

      final url = await _chatService.uploadChatFile(
        bytes: bytes,
        fileName: fileName,
        contentType: contentType,
        folder:
            _isGroup
                ? 'groups/$_containerId/files'
                : 'chats/$_containerId/files',
      );

      final attachment = MessageAttachment(
        url: url,
        name: fileName,
        type: AttachmentType.document,
        mimeType: contentType,
        size: bytes.lengthInBytes,
      );

      await _sendRichMessage(type: MessageType.file, attachments: [attachment]);
    } catch (e) {
      _showError('Failed to send file: $e');
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _handleVoiceUpload(File audioFile) async {
    if (_containerId == null) return;

    try {
      setState(() => _isUploading = true);

      final bytes = await audioFile.readAsBytes();
      final fileName = 'voice_${_uuid.v4()}.m4a';

      final url = await _chatService.uploadChatFile(
        bytes: bytes,
        fileName: fileName,
        contentType: 'audio/mp4',
        folder:
            _isGroup
                ? 'groups/$_containerId/audio'
                : 'chats/$_containerId/audio',
      );

      final attachment = MessageAttachment(
        url: url,
        name: fileName,
        type: AttachmentType.audio,
        mimeType: 'audio/mp4',
        size: bytes.lengthInBytes,
      );

      await _sendRichMessage(
        type: MessageType.audio,
        attachments: [attachment],
      );
    } catch (e) {
      _showError('Failed to send voice message: $e');
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _playPauseAudio(String audioUrl, String messageId) async {
    try {
      // If this audio is already playing, pause it
      if (_currentPlayingAudioId == messageId && _isAudioPlaying) {
        await _audioPlayer?.pause();
        if (mounted) {
          setState(() {
            _isAudioPlaying = false;
          });
        }
        return;
      }

      // If clicking on a paused audio, resume it
      if (_currentPlayingAudioId == messageId &&
          !_isAudioPlaying &&
          _audioPlayer != null) {
        await _audioPlayer!.play();
        if (mounted) {
          setState(() {
            _isAudioPlaying = true;
          });
        }
        return;
      }

      // If another audio is playing, stop it
      if (_currentPlayingAudioId != null &&
          _currentPlayingAudioId != messageId) {
        await _audioPlayer?.stop();
        await _audioPlayer?.dispose();
        _audioPlayer = null;
      }

      // Create new player for new audio
      _audioPlayer = AudioPlayer();
      await _audioPlayer!.setUrl(audioUrl);

      // Listen for completion
      _audioPlayer!.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          if (mounted) {
            setState(() {
              _isAudioPlaying = false;
              _currentPlayingAudioId = null;
            });
          }
        }
      });

      // Play the audio
      await _audioPlayer!.play();
      if (mounted) {
        setState(() {
          _isAudioPlaying = true;
          _currentPlayingAudioId = messageId;
        });
      }
    } catch (e) {
      if (mounted) {
        _showError('Failed to play audio: $e');
      }
    }
  }

  void _showPollDialog() {
    _showCreatePollSheet();
  }

  void _showTodoDialog() {
    _showCreateTodoSheet();
  }
}

class _MessageAction {
  _MessageAction({
    required this.icon,
    required this.label,
    required this.onSelected,
  });

  final IconData icon;
  final String label;
  final VoidCallback onSelected;
}
