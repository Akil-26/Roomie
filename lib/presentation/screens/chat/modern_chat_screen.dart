import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:roomie/data/datasources/auth_service.dart';
import 'package:roomie/data/datasources/chat_service.dart';
import 'package:roomie/data/datasources/cloudinary_service.dart';
import 'package:roomie/data/models/message_model.dart';
import 'package:roomie/presentation/widgets/chat_input_widget.dart';
import 'package:roomie/presentation/widgets/message_bubble_widget.dart';
import 'package:roomie/presentation/widgets/poll_todo_dialogs.dart';
import 'package:roomie/presentation/widgets/message_dialogs.dart';
import 'package:roomie/presentation/widgets/roomie_loading_widget.dart';

class ModernChatScreen extends StatefulWidget {
  const ModernChatScreen({
    super.key,
    required this.chatData,
    required this.chatType,
  });

  final Map<String, dynamic> chatData;
  final String chatType;

  @override
  State<ModernChatScreen> createState() => _ModernChatScreenState();
}

class _ModernChatScreenState extends State<ModernChatScreen>
    with TickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  final AuthService _authService = AuthService();
  final ChatService _chatService = ChatService();
  final CloudinaryService _cloudinaryService = CloudinaryService();
  // Removed unused Uuid field

  Stream<List<MessageModel>>? _messagesStream;
  bool _initialized = false;
  bool _isGroup = false;
  String? _containerId;
  List<String> _memberIds = [];
  Map<String, String> _memberNames = {};
  Map<String, String?> _memberImages = {};
  MessageModel? _editingMessage;
  bool _isUploading = false;

  // Removed unused FAB animation fields

  @override
  void initState() {
    super.initState();
    _initializeChat();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _messageFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
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
        final memberNames = Map<String, String>.from(
          data['memberNames'] ?? const <String, String>{},
        );
        final memberImages = Map<String, String?>.from(
          (data['memberImages'] ?? const <String, dynamic>{}).map(
            (key, value) => MapEntry(key, value?.toString()),
          ),
        );

        if (!members.contains(currentUser.uid)) {
          members.add(currentUser.uid);
        }
        
        // Fetch current user's username from Firestore instead of using Auth displayName
        try {
          final currentUserDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(currentUser.uid)
              .get();
          
          if (currentUserDoc.exists && currentUserDoc.data() != null) {
            final currentUserData = currentUserDoc.data()!;
            memberNames[currentUser.uid] = currentUserData['username'] as String? ??
                                           currentUserData['name'] as String? ??
                                           currentUser.email?.split('@')[0] ?? 
                                           'You';
          } else {
            memberNames[currentUser.uid] = currentUser.email?.split('@')[0] ?? 'You';
          }
        } catch (e) {
          debugPrint('Error loading current user data: $e');
          memberNames[currentUser.uid] = currentUser.email?.split('@')[0] ?? 'You';
        }

        _memberIds = members;
        _memberNames = memberNames;
        _memberImages = memberImages;

        _containerId = await _chatService.createOrGetGroupChat(
          groupId: groupId,
          groupName: groupName,
          memberIds: members,
          memberNames: memberNames,
        );
        _messagesStream = _chatService.getGroupMessagesStream(_containerId!);
      } else {
        _isGroup = false;
        final otherUserId = data['otherUserId'] ?? data['userId'];
        if (otherUserId == null) {
          throw Exception('Missing user identifier');
        }
        final otherUserName = data['otherUserName'] ?? data['name'] ?? 'User';
        final otherUserImage =
            data['otherUserImageUrl'] ??
            data['profileImageUrl'] ??
            data['imageUrl'];

        _containerId = await _chatService.createOrGetChat(
          otherUserId: otherUserId,
          otherUserName: otherUserName,
          otherUserImageUrl: otherUserImage?.toString(),
        );

        // Fetch current user's username from Firestore for 1-on-1 chat
        String currentUserDisplayName = 'You';
        try {
          final currentUserDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(currentUser.uid)
              .get();
          
          if (currentUserDoc.exists && currentUserDoc.data() != null) {
            final currentUserData = currentUserDoc.data()!;
            currentUserDisplayName = currentUserData['username'] as String? ??
                                    currentUserData['name'] as String? ??
                                    currentUser.email?.split('@')[0] ?? 
                                    'You';
          }
        } catch (e) {
          debugPrint('Error loading current user data: $e');
        }

        _memberIds = [currentUser.uid, otherUserId];
        _memberNames = {
          currentUser.uid: currentUserDisplayName,
          otherUserId: otherUserName,
        };
        _memberImages = {otherUserId: otherUserImage?.toString()};

        _messagesStream = _chatService.getMessagesStream(_containerId!);
      }

      setState(() {
        _initialized = true;
      });

      await Future<void>.delayed(const Duration(milliseconds: 150));
      _scrollToBottom();
    } catch (e, stackTrace) {
      debugPrint('Chat init failed: $e');
      debugPrint('$stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load chat: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  // Message sending functions
  Future<void> _sendTextMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || !_initialized || _containerId == null) return;

    final currentUser = _authService.currentUser;
    if (currentUser == null) return;

    try {
      if (_editingMessage != null) {
        // Edit existing message
        await _editMessage(text);
        return;
      }

      _messageController.clear();
      _messageFocusNode.unfocus();

      if (_isGroup) {
        await _chatService.sendGroupMessage(
          groupId: _containerId!,
          message: text,
          type: MessageType.text,
        );
      } else {
        await _chatService.sendMessage(
          chatId: _containerId!,
          message: text,
          type: MessageType.text,
        );
      }

      _scrollToBottom();
    } catch (e) {
      debugPrint('Failed to send message: $e');
      _showErrorSnackBar('Failed to send message');
    }
  }

  Future<void> _sendImageMessage(File imageFile, String fileName) async {
    if (!_initialized || _containerId == null) return;

    final currentUser = _authService.currentUser;
    if (currentUser == null) return;

    setState(() {
      // Keep interactions limited during upload, but we'll avoid showing spinners in UI
      _isUploading = true;
    });

    try {
      // Upload to Cloudinary
      final uploadResult = await _cloudinaryService.uploadFile(
        file: imageFile,
        folder: CloudinaryFolder.chat,
        resourceType: CloudinaryResourceType.image,
      );

      if (uploadResult == null) {
        throw Exception('Failed to upload image');
      }

      final attachment = MessageAttachment(
        url: uploadResult,
        name: fileName,
        type: AttachmentType.image,
        mimeType: 'image/jpeg',
        size: await imageFile.length(),
      );

      // Send empty text so only the image is shown in the bubble
      if (_isGroup) {
        await _chatService.sendGroupMessage(
          groupId: _containerId!,
          message: '',
          type: MessageType.image,
          attachments: [attachment],
        );
      } else {
        await _chatService.sendMessage(
          chatId: _containerId!,
          message: '',
          type: MessageType.image,
          attachments: [attachment],
        );
      }

      _scrollToBottom();
    } catch (e) {
      debugPrint('Failed to send image: $e');
      _showErrorSnackBar('Failed to send image');
    } finally {
      setState(() {
        _isUploading = false;
      });
    }
  }

  Future<void> _sendFileMessage(File file, String fileName) async {
    if (!_initialized || _containerId == null) return;

    final currentUser = _authService.currentUser;
    if (currentUser == null) return;

    setState(() {
      _isUploading = true;
    });

    try {
      // Upload to Cloudinary (for files, use raw resource type)
      final uploadResult = await _cloudinaryService.uploadFile(
        file: file,
        folder: CloudinaryFolder.chat,
        resourceType: CloudinaryResourceType.raw,
      );

      if (uploadResult == null) {
        throw Exception('Failed to upload file');
      }

      final attachment = MessageAttachment(
        url: uploadResult,
        name: fileName,
        type: AttachmentType.document,
        size: await file.length(),
      );

      if (_isGroup) {
        await _chatService.sendGroupMessage(
          groupId: _containerId!,
          message: 'File: $fileName',
          type: MessageType.file,
          attachments: [attachment],
        );
      } else {
        await _chatService.sendMessage(
          chatId: _containerId!,
          message: 'File: $fileName',
          type: MessageType.file,
          attachments: [attachment],
        );
      }

      _scrollToBottom();
    } catch (e) {
      debugPrint('Failed to send file: $e');
      _showErrorSnackBar('Failed to send file');
    } finally {
      setState(() {
        _isUploading = false;
      });
    }
  }

  Future<void> _sendVoiceMessage(File audioFile, int durationMs) async {
    if (!_initialized || _containerId == null) return;

    final currentUser = _authService.currentUser;
    if (currentUser == null) return;

    setState(() {
      _isUploading = true;
    });

    try {
      // Upload to Cloudinary as raw (audio)
      final uploadResult = await _cloudinaryService.uploadFile(
        file: audioFile,
        folder: CloudinaryFolder.chat,
        resourceType: CloudinaryResourceType.raw,
      );

      if (uploadResult == null) {
        throw Exception('Failed to upload voice message');
      }

      final attachment = MessageAttachment(
        url: uploadResult,
        name: 'voice_message.m4a',
        type: AttachmentType.voice,
        mimeType: 'audio/m4a',
        size: await audioFile.length(),
        durationInMs: durationMs,
      );

      if (_isGroup) {
        await _chatService.sendGroupMessage(
          groupId: _containerId!,
          message: 'Voice message',
          type: MessageType.voice,
          attachments: [attachment],
        );
      } else {
        await _chatService.sendMessage(
          chatId: _containerId!,
          message: 'Voice message',
          type: MessageType.voice,
          attachments: [attachment],
        );
      }

      _scrollToBottom();
    } catch (e) {
      debugPrint('Failed to send voice message: $e');
      _showErrorSnackBar('Failed to send voice message');
    } finally {
      setState(() {
        _isUploading = false;
      });
    }
  }

  Future<void> _sendPollMessage(PollData pollData) async {
    if (!_initialized || _containerId == null || !mounted) return;

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

      if (mounted) _scrollToBottom();
    } catch (e) {
      debugPrint('Failed to send poll: $e');
      if (mounted) _showErrorSnackBar('Failed to send poll');
    }
  }

  Future<void> _sendTodoMessage(TodoData todoData) async {
    if (!_initialized || _containerId == null || !mounted) return;

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

      if (mounted) _scrollToBottom();
    } catch (e) {
      debugPrint('Failed to send to-do: $e');
      if (mounted) _showErrorSnackBar('Failed to send to-do');
    }
  }

  // Message interaction functions
  Future<void> _editMessage(String newText) async {
    if (_editingMessage == null || !_initialized || _containerId == null) {
      return;
    }

    try {
      await _chatService.editMessage(
        chatId: _containerId!,
        messageId: _editingMessage!.id,
        newText: newText,
      );

      setState(() {
        _editingMessage = null;
      });

      _messageController.clear();
      _messageFocusNode.unfocus();

      _showSuccessSnackBar('Message edited');
    } catch (e) {
      debugPrint('Failed to edit message: $e');
      _showErrorSnackBar('Failed to edit message');
    }
  }

  void _startEditingMessage(MessageModel message) {
    setState(() {
      _editingMessage = message;
      _messageController.text = message.message;
    });
    _messageFocusNode.requestFocus();
  }

  void _cancelEdit() {
    setState(() {
      _editingMessage = null;
    });
    _messageController.clear();
    _messageFocusNode.unfocus();
  }

  Future<void> _handlePollVote(String messageId, String optionId) async {
    if (!_initialized || _containerId == null) return;

    try {
      await _chatService.togglePollVote(
        containerId: _containerId!,
        messageId: messageId,
        optionId: optionId,
        isGroup: _isGroup,
      );
    } catch (e) {
      debugPrint('Failed to vote on poll: $e');
      _showErrorSnackBar('Failed to vote on poll');
    }
  }

  Future<void> _handleTodoToggle(
    String messageId,
    String todoId,
    bool isDone,
  ) async {
    if (!_initialized || _containerId == null) return;

    try {
      await _chatService.updateTodoItem(
        containerId: _containerId!,
        messageId: messageId,
        itemId: todoId,
        isGroup: _isGroup,
        isDone: isDone,
      );
    } catch (e) {
      debugPrint('Failed to update to-do item: $e');
      _showErrorSnackBar('Failed to update to-do item');
    }
  }

  // Dialog functions
  Future<void> _showCreatePollDialog() async {
    if (!mounted) return;

    final result = await showDialog<PollData>(
      context: context,
      builder: (context) => const CreatePollDialog(),
    );

    if (result != null && mounted) {
      await _sendPollMessage(result);
    }
  }

  Future<void> _showCreateTodoDialog() async {
    if (!mounted) return;

    final result = await showDialog<TodoData>(
      context: context,
      builder: (context) => const CreateTodoDialog(),
    );

    if (result != null && mounted) {
      await _sendTodoMessage(result);
    }
  }

  Future<void> _showEditMessageDialog(MessageModel message) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => EditMessageDialog(message: message),
    );

    if (result != null) {
      setState(() {
        _editingMessage = message;
        _messageController.text = result;
      });
      await _editMessage(result);
    }
  }

  void _showMessageInfoDialog(MessageModel message) {
    showDialog(
      context: context,
      builder:
          (context) => MessageInfoDialog(
            message: message,
            memberNames: _memberNames,
            memberImages: _memberImages,
            isGroup: _isGroup,
          ),
    );
  }

  // Utility functions
  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _getChatTitle() {
    if (_isGroup) {
      return widget.chatData['name'] ??
          widget.chatData['groupName'] ??
          'Group Chat';
    } else {
      return widget.chatData['otherUserName'] ??
          widget.chatData['name'] ??
          'Chat';
    }
  }

  String? _getChatImage() {
    if (_isGroup) {
      return widget.chatData['imageUrl']?.toString();
    } else {
      return widget.chatData['otherUserImageUrl']?.toString() ??
          widget.chatData['profileImageUrl']?.toString() ??
          widget.chatData['imageUrl']?.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        elevation: 1,
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            // Chat avatar
            CircleAvatar(
              radius: 20,
              backgroundImage:
                  _getChatImage() != null
                      ? NetworkImage(_getChatImage()!)
                      : null,
              backgroundColor: colorScheme.primary.withOpacity(0.7),
              child:
                  _getChatImage() == null
                      ? Text(
                        _getChatTitle().isNotEmpty
                            ? _getChatTitle()[0].toUpperCase()
                            : 'C',
                        style: TextStyle(
                          color: colorScheme.onPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                      : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _getChatTitle(),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_isGroup)
                    Text(
                      '${_memberIds.length} members',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: const [],
      ),
      body: Column(
        children: [
          // Edit message banner
          if (_editingMessage != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withOpacity(0.3),
                border: Border(
                  bottom: BorderSide(
                    color: colorScheme.outline.withOpacity(0.2),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.edit, size: 20, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Edit message',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          _editingMessage!.message,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurface.withOpacity(0.7),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _cancelEdit,
                    iconSize: 20,
                  ),
                ],
              ),
            ),

          // Messages list
          Expanded(
            child:
                !_initialized
                    ? const Center(child: RoomieLoadingWidget())
                    : StreamBuilder<List<MessageModel>>(
                      stream: _messagesStream,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(child: RoomieLoadingWidget());
                        }

                        if (snapshot.hasError) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  size: 64,
                                  color: colorScheme.error,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Failed to load messages',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: colorScheme.error,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${snapshot.error}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurface.withOpacity(
                                      0.7,
                                    ),
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          );
                        }

                        final messages = snapshot.data ?? [];

                        if (messages.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.chat_outlined,
                                  size: 64,
                                  color: colorScheme.onSurface.withOpacity(0.3),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No messages yet',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: colorScheme.onSurface.withOpacity(
                                      0.7,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Start the conversation by sending a message',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurface.withOpacity(
                                      0.5,
                                    ),
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          );
                        }

                        return ListView.builder(
                          controller: _scrollController,
                          reverse: true,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final message = messages[index];
                            final currentUserId = _authService.currentUser?.uid;
                            final isCurrentUser =
                                message.senderId == currentUserId;

                            return MessageBubbleWidget(
                              message: message,
                              isCurrentUser: isCurrentUser,
                              isGroup: _isGroup,
                              memberNames: _memberNames,
                              memberImages: _memberImages,
                              currentUserId: currentUserId,
                              onEdit:
                                  isCurrentUser &&
                                          message.type == MessageType.text
                                      ? _showEditMessageDialog
                                      : null,
                              onReply: null,
                              onInfo: _showMessageInfoDialog,
                              onPollVote: _handlePollVote,
                              onTodoToggle: _handleTodoToggle,
                            );
                          },
                        );
                      },
                    ),
          ),

          // Chat input
          ChatInputWidget(
            messageController: _messageController,
            messageFocusNode: _messageFocusNode,
            onSendPressed: _sendTextMessage,
            onImageSelected: _sendImageMessage,
            onFileSelected: _sendFileMessage,
            onVoiceRecorded: _sendVoiceMessage,
            onPollPressed: _showCreatePollDialog,
            onTodoPressed: _showCreateTodoDialog,
            isUploading: _isUploading,
            isGroup: _isGroup,
          ),
        ],
      ),
    );
  }
}