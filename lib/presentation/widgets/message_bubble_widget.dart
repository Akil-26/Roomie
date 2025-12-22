// ignore_for_file: unnecessary_import

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:roomie/data/models/message_model.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:roomie/presentation/widgets/payment_request_card.dart';

class MessageBubbleWidget extends StatefulWidget {
  final MessageModel message;
  final bool isCurrentUser;
  final bool isGroup;
  final Map<String, String> memberNames;
  final Map<String, String?> memberImages;
  final String? currentUserId;
  final Function(MessageModel)? onEdit;
  final Function(MessageModel)? onReply;
  final Function(MessageModel)? onInfo;
  final Function(String, String)? onPollVote;
  final Function(String, String, bool)? onTodoToggle;

  const MessageBubbleWidget({
    super.key,
    required this.message,
    required this.isCurrentUser,
    required this.isGroup,
    required this.memberNames,
    required this.memberImages,
    this.currentUserId,
    this.onEdit,
    this.onReply,
    this.onInfo,
    this.onPollVote,
    this.onTodoToggle,
  });

  @override
  State<MessageBubbleWidget> createState() => _MessageBubbleWidgetState();
}

class _MessageBubbleWidgetState extends State<MessageBubbleWidget>
    with SingleTickerProviderStateMixin {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _showOptions = false;

  late AnimationController _optionsAnimationController;
  late Animation<double> _optionsAnimation;

  @override
  void initState() {
    super.initState();
    _optionsAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _optionsAnimation = CurvedAnimation(
      parent: _optionsAnimationController,
      curve: Curves.easeInOut,
    );

    _audioPlayer.durationStream.listen((duration) {
      if (mounted && duration != null) {
        setState(() {
          _duration = duration;
        });
      }
    });

    _audioPlayer.positionStream.listen((position) {
      if (mounted) {
        setState(() {
          _position = position;
        });
      }
    });

    _audioPlayer.playerStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state.playing;
        });
      }
    });
  }

  @override
  void dispose() {
    _optionsAnimationController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _toggleOptions() {
    setState(() {
      _showOptions = !_showOptions;
    });
    if (_showOptions) {
      _optionsAnimationController.forward();
    } else {
      _optionsAnimationController.reverse();
    }
  }

  Future<void> _playAudio(String url) async {
    try {
      if (_isPlaying) {
        await _audioPlayer.pause();
      } else {
        await _audioPlayer.setUrl(url);
        await _audioPlayer.play();
      }
    } catch (e) {
      debugPrint('Error playing audio: $e');
      _showErrorSnackBar('Failed to play audio');
    }
  }

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

  Future<void> _launchUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (!await launchUrl(uri)) {
        _showErrorSnackBar('Could not open link');
      }
    } catch (e) {
      _showErrorSnackBar('Invalid URL');
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes);
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  Color _getStatusColor(MessageStatus status, ColorScheme colorScheme) {
    switch (status) {
      case MessageStatus.sending:
        return colorScheme.outline;
      case MessageStatus.sent:
        return colorScheme.outline;
      case MessageStatus.delivered:
        return colorScheme.outline;
      case MessageStatus.read:
        return Colors.blue;
    }
  }

  IconData _getStatusIcon(MessageStatus status) {
    switch (status) {
      case MessageStatus.sending:
        return Icons.access_time;
      case MessageStatus.sent:
        return Icons.done;
      case MessageStatus.delivered:
        return Icons.done_all;
      case MessageStatus.read:
        return Icons.done_all;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    final bubbleColor =
        widget.isCurrentUser
            ? colorScheme.primary
            : colorScheme.surfaceContainer;

    final textColor =
        widget.isCurrentUser ? colorScheme.onPrimary : colorScheme.onSurface;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Column(
        crossAxisAlignment:
            widget.isCurrentUser
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
        children: [
          // Sender info for group messages
          if (widget.isGroup && !widget.isCurrentUser)
            Padding(
              padding: const EdgeInsets.only(left: 48, bottom: 2),
              child: Row(
                children: [
                  if (widget.memberImages[widget.message.senderId] != null)
                    CircleAvatar(
                      radius: 8,
                      backgroundImage: NetworkImage(
                        widget.memberImages[widget.message.senderId]!,
                      ),
                    )
                  else
                    CircleAvatar(
                      radius: 8,
                      backgroundColor: colorScheme.primary.withOpacity(0.7),
                      child: Text(
                        widget.message.senderName.isNotEmpty
                            ? widget.message.senderName[0].toUpperCase()
                            : 'U',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Text(
                    widget.memberNames[widget.message.senderId]
                                ?.trim()
                                .isNotEmpty ==
                            true
                        ? widget.memberNames[widget.message.senderId]!
                        : (widget.message.senderName.trim().isNotEmpty
                            ? widget.message.senderName
                            : 'Unknown'),
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

          // Message bubble (payment requests render without bubble)
          if (widget.message.type == MessageType.paymentRequest)
            // Payment request card renders standalone without bubble wrapper
            Padding(
              padding: const EdgeInsets.only(left: 48, right: 48),
              child: _buildMessageContent(textColor),
            )
          else
            // Regular message with bubble styling
            Row(
              mainAxisAlignment:
                  widget.isCurrentUser
                      ? MainAxisAlignment.end
                      : MainAxisAlignment.start,
              children: [
                if (!widget.isCurrentUser) ...[const SizedBox(width: 48)],
                Flexible(
                  child: GestureDetector(
                    onLongPress: widget.isCurrentUser ? _toggleOptions : null,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: bubbleColor,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(18),
                          topRight: const Radius.circular(18),
                          bottomLeft: Radius.circular(
                            widget.isCurrentUser ? 18 : 4,
                          ),
                          bottomRight: Radius.circular(
                            widget.isCurrentUser ? 4 : 18,
                          ),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Message content
                          _buildMessageContent(textColor),

                          const SizedBox(height: 4),

                          // Message info
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (widget.message.editedAt != null) ...[
                                Icon(
                                  Icons.edit,
                                  size: 12,
                                  color: textColor.withOpacity(0.7),
                                ),
                                const SizedBox(width: 4),
                              ],
                              Text(
                                timeago.format(widget.message.timestamp),
                                style: textTheme.bodySmall?.copyWith(
                                  color: textColor.withOpacity(0.7),
                                  fontSize: 11,
                                ),
                              ),
                              if (widget.isCurrentUser) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  _getStatusIcon(widget.message.status),
                                  size: 12,
                                  color: _getStatusColor(
                                    widget.message.status,
                                    colorScheme,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (widget.isCurrentUser) ...[const SizedBox(width: 48)],
              ],
            ),

          // Message options
          if (_showOptions)
            AnimatedBuilder(
              animation: _optionsAnimation,
              builder: (context, child) {
                return SizeTransition(
                  sizeFactor: _optionsAnimation,
                  child: Container(
                    margin: const EdgeInsets.only(top: 8, right: 48),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _OptionButton(
                          icon: Icons.edit,
                          label: 'Edit',
                          onTap: () {
                            widget.onEdit?.call(widget.message);
                            _toggleOptions();
                          },
                        ),
                        const SizedBox(width: 8),
                        _OptionButton(
                          icon: Icons.reply,
                          label: 'Reply',
                          onTap: () {
                            widget.onReply?.call(widget.message);
                            _toggleOptions();
                          },
                        ),
                        const SizedBox(width: 8),
                        _OptionButton(
                          icon: Icons.info_outline,
                          label: 'Info',
                          onTap: () {
                            widget.onInfo?.call(widget.message);
                            _toggleOptions();
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildMessageContent(Color textColor) {
    switch (widget.message.type) {
      case MessageType.text:
        return _buildTextMessage(textColor);
      case MessageType.image:
        return _buildImageMessage(textColor);
      case MessageType.file:
        return _buildFileMessage(textColor);
      case MessageType.audio:
      case MessageType.voice:
        return _buildAudioMessage(textColor);
      case MessageType.poll:
        return _buildPollMessage(textColor);
      case MessageType.todo:
        return _buildTodoMessage(textColor);
      case MessageType.system:
        return _buildSystemMessage(textColor);
      case MessageType.paymentRequest:
        return _buildPaymentRequestMessage();
    }
  }

  Widget _buildTextMessage(Color textColor) {
    // Payment requests are now handled by _buildPaymentRequestMessage()
    // Message type routing (in _buildMessageContent) handles the dispatching
    
    // Normal text message
    return SelectableText(
      widget.message.message,
      style: TextStyle(color: textColor, fontSize: 16),
    );
  }

  Widget _buildImageMessage(Color textColor) {
    if (widget.message.attachments.isEmpty) {
      return Text(
        'Image not available',
        style: TextStyle(color: textColor.withOpacity(0.7)),
      );
    }

    final attachment = widget.message.attachments.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            attachment.url,
            width: 200,
            height: 200,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                width: 200,
                height: 200,
                color: Colors.grey.withOpacity(0.3),
                child: const Icon(Icons.broken_image, size: 50),
              );
            },
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Container(
                width: 200,
                height: 200,
                color: Colors.grey.withOpacity(0.3),
                child: const Center(child: CircularProgressIndicator()),
              );
            },
          ),
        ),
        if (widget.message.message.isNotEmpty) ...[
          const SizedBox(height: 8),
          SelectableText(
            widget.message.message,
            style: TextStyle(color: textColor),
          ),
        ],
      ],
    );
  }

  Widget _buildFileMessage(Color textColor) {
    if (widget.message.attachments.isEmpty) {
      return Text(
        'File not available',
        style: TextStyle(color: textColor.withOpacity(0.7)),
      );
    }

    final attachment = widget.message.attachments.first;
    return GestureDetector(
      onTap: () => _launchUrl(attachment.url),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: textColor.withOpacity(0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_getFileIcon(attachment.mimeType), color: textColor, size: 24),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    attachment.name,
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (attachment.size != null)
                    Text(
                      _formatFileSize(attachment.size!),
                      style: TextStyle(
                        color: textColor.withOpacity(0.7),
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.download, color: textColor.withOpacity(0.7), size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioMessage(Color textColor) {
    if (widget.message.attachments.isEmpty) {
      return Text(
        'Audio not available',
        style: TextStyle(color: textColor.withOpacity(0.7)),
      );
    }

    final attachment = widget.message.attachments.first;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => _playAudio(attachment.url),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: textColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                _isPlaying ? Icons.pause : Icons.play_arrow,
                color: textColor,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 2,
                  decoration: BoxDecoration(
                    color: textColor.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(1),
                  ),
                  child: LinearProgressIndicator(
                    value:
                        _duration.inMilliseconds > 0
                            ? _position.inMilliseconds /
                                _duration.inMilliseconds
                            : 0,
                    backgroundColor: Colors.transparent,
                    valueColor: AlwaysStoppedAnimation<Color>(textColor),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                  style: TextStyle(
                    color: textColor.withOpacity(0.7),
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPollMessage(Color textColor) {
    final colorScheme = Theme.of(context).colorScheme;
    final poll = widget.message.poll;
    if (poll == null) {
      return Text(
        'Poll not available',
        style: TextStyle(color: textColor.withOpacity(0.7)),
      );
    }

    final totalVotes = poll.options.fold<int>(
      0,
      (sum, option) => sum + option.votes.length,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          poll.question,
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 12),
        ...poll.options.map((option) {
          final percentage =
              totalVotes > 0
                  ? (option.votes.length / totalVotes * 100).round()
                  : 0;
          final hasVoted = option.votes.contains(widget.currentUserId);

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTap:
                  () => widget.onPollVote?.call(widget.message.id, option.id),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color:
                      hasVoted
                          ? colorScheme.primary.withOpacity(0.15)
                          : colorScheme.surfaceContainer.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color:
                        hasVoted
                            ? colorScheme.primary
                            : colorScheme.outline.withOpacity(0.3),
                    width: hasVoted ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        option.title,
                        style: TextStyle(
                          color: textColor,
                          fontWeight:
                              hasVoted ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                    Text(
                      '$percentage% (${option.votes.length})',
                      style: TextStyle(
                        color: textColor.withOpacity(0.7),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildTodoMessage(Color textColor) {
    final colorScheme = Theme.of(context).colorScheme;
    final todo = widget.message.todo;
    if (todo == null) {
      return Text(
        'To-do not available',
        style: TextStyle(color: textColor.withOpacity(0.7)),
      );
    }

    final completedCount = todo.items.where((item) => item.isDone).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.task_alt, color: textColor, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                todo.title,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            Text(
              '$completedCount/${todo.items.length}',
              style: TextStyle(
                color: textColor.withOpacity(0.7),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...todo.items.map((item) {
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            child: GestureDetector(
              onTap:
                  () => widget.onTodoToggle?.call(
                    widget.message.id,
                    item.id,
                    !item.isDone,
                  ),
              child: Row(
                children: [
                  Icon(
                    item.isDone
                        ? Icons.check_box
                        : Icons.check_box_outline_blank,
                    color:
                        item.isDone
                            ? colorScheme.primary
                            : colorScheme.onSurface.withOpacity(0.7),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.title,
                      style: TextStyle(
                        color: textColor,
                        decoration:
                            item.isDone
                                ? TextDecoration.lineThrough
                                : TextDecoration.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildSystemMessage(Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.info_outline, color: Colors.orange, size: 16),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              widget.message.message,
              style: TextStyle(
                color: Colors.orange.shade700,
                fontSize: 14,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getFileIcon(String? mimeType) {
    if (mimeType == null) return Icons.insert_drive_file;

    if (mimeType.startsWith('image/')) return Icons.image;
    if (mimeType.startsWith('video/')) return Icons.video_file;
    if (mimeType.startsWith('audio/')) return Icons.audio_file;
    if (mimeType.contains('pdf')) return Icons.picture_as_pdf;
    if (mimeType.contains('word') || mimeType.contains('document')) {
      return Icons.description;
    }
    if (mimeType.contains('sheet') || mimeType.contains('excel')) {
      return Icons.table_chart;
    }
    if (mimeType.contains('presentation') || mimeType.contains('powerpoint')) {
      return Icons.slideshow;
    }
    if (mimeType.contains('zip') || mimeType.contains('rar')) {
      return Icons.archive;
    }

    return Icons.insert_drive_file;
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Widget _buildPaymentRequestMessage() {
    if (widget.currentUserId == null) {
      return Text('Payment Request', style: TextStyle(color: Colors.grey));
    }

    final amount = widget.message.paymentAmount ?? 0.0;
    final note = widget.message.paymentNote;
    final toUsers = widget.message.payToUserIds ?? [];
    final paymentStatus = widget.message.paymentStatus ?? {};
    final senderPhone = widget.message.payToPhoneNumber;
    final senderUpiId = widget.message.paymentUpiId;
    final requestId = widget.message.paymentRequestId ?? widget.message.id;
    
    // Determine chat ID (works for both group and individual chats)
    final chatId = widget.message.extraData['chatId']?.toString() ?? 
        (widget.isGroup ? widget.message.receiverId : 
        'chat_${widget.message.senderId}_${widget.currentUserId}');

    return PaymentRequestCard(
      messageId: widget.message.id,
      chatId: chatId,
      requestId: requestId,
      amount: amount,
      note: note,
      senderName: widget.message.senderName,
      senderId: widget.message.senderId,
      senderUpiId: senderUpiId,
      senderPhone: senderPhone,
      paymentStatus: paymentStatus,
      toUsers: toUsers,
      memberNames: widget.memberNames,
      currentUserId: widget.currentUserId!,
      isGroupChat: widget.isGroup,
      isCompleted: widget.message.isPaymentCompleted,
    );
  }
}

class _OptionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _OptionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colorScheme.outline.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: colorScheme.primary),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: colorScheme.primary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
