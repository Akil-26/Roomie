import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

class ChatInputWidget extends StatefulWidget {
  final TextEditingController messageController;
  final FocusNode messageFocusNode;
  final VoidCallback? onSendPressed;
  final Function(String)? onTextChanged;
  final Function(File, String)? onImageSelected;
  final Function(File, String)? onFileSelected;
  final Function(File, int)? onVoiceRecorded;
  final Function()? onPollPressed;
  final Function()? onTodoPressed;
  final Function()? onPaymentPressed;
  final bool isUploading;
  final bool isGroup;

  const ChatInputWidget({
    super.key,
    required this.messageController,
    required this.messageFocusNode,
    this.onSendPressed,
    this.onTextChanged,
    this.onImageSelected,
    this.onFileSelected,
    this.onVoiceRecorded,
    this.onPollPressed,
    this.onTodoPressed,
    this.onPaymentPressed,
    this.isUploading = false,
    this.isGroup = false,
  });

  @override
  State<ChatInputWidget> createState() => _ChatInputWidgetState();
}

class _ChatInputWidgetState extends State<ChatInputWidget>
    with TickerProviderStateMixin {
  bool _isRecording = false;
  bool _hasText = false;
  bool _showAttachmentMenu = false;
  Duration _recordDuration = Duration.zero;
  Timer? _recordTimer;
  final AudioRecorder _voiceRecorder = AudioRecorder();
  final ImagePicker _imagePicker = ImagePicker();

  late AnimationController _attachmentAnimationController;
  late AnimationController _recordAnimationController;
  late Animation<double> _attachmentAnimation;
  late Animation<double> _recordAnimation;

  @override
  void initState() {
    super.initState();
    _attachmentAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _recordAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    _attachmentAnimation = CurvedAnimation(
      parent: _attachmentAnimationController,
      curve: Curves.easeInOut,
    );
    _recordAnimation = CurvedAnimation(
      parent: _recordAnimationController,
      curve: Curves.easeInOut,
    );

    widget.messageController.addListener(() {
      final hasText = widget.messageController.text.trim().isNotEmpty;
      if (hasText != _hasText) {
        setState(() {
          _hasText = hasText;
        });
      }
      widget.onTextChanged?.call(widget.messageController.text);
    });
  }

  @override
  void dispose() {
    _attachmentAnimationController.dispose();
    _recordAnimationController.dispose();
    _recordTimer?.cancel();
    _voiceRecorder.dispose();
    super.dispose();
  }

  void _toggleAttachmentMenu() {
    setState(() {
      _showAttachmentMenu = !_showAttachmentMenu;
    });
    if (_showAttachmentMenu) {
      _attachmentAnimationController.forward();
    } else {
      _attachmentAnimationController.reverse();
    }
  }

  Future<void> _startRecording() async {
    if (_isRecording) return;

    try {
      final hasPermission = await _voiceRecorder.hasPermission();
      if (!hasPermission) {
        _showPermissionDialog();
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final path =
          '${tempDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _voiceRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: path,
      );

      setState(() {
        _isRecording = true;
        _recordDuration = Duration.zero;
      });

      _recordAnimationController.forward();
      HapticFeedback.lightImpact();

      _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() {
          _recordDuration = Duration(seconds: timer.tick);
        });
      });
    } catch (e) {
      debugPrint('Failed to start recording: $e');
      _showErrorSnackBar('Failed to start recording');
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;

    // Check if recording is at least 1 second
    if (_recordDuration.inSeconds < 1) {
      _showErrorSnackBar('Recording must be at least 1 second');
      _cancelRecording();
      return;
    }

    try {
      final path = await _voiceRecorder.stop();
      _recordTimer?.cancel();

      final duration = _recordDuration;

      setState(() {
        _isRecording = false;
        _recordDuration = Duration.zero;
      });

      _recordAnimationController.reverse();
      HapticFeedback.selectionClick();

      if (path != null) {
        final file = File(path);
        if (await file.exists()) {
          widget.onVoiceRecorded?.call(file, duration.inMilliseconds);
        }
      }
    } catch (e) {
      debugPrint('Failed to stop recording: $e');
      _showErrorSnackBar('Failed to save recording');
    }
  }

  void _cancelRecording() async {
    if (!_isRecording) return;

    try {
      await _voiceRecorder.cancel();
      _recordTimer?.cancel();

      setState(() {
        _isRecording = false;
        _recordDuration = Duration.zero;
      });

      _recordAnimationController.reverse();
      HapticFeedback.heavyImpact();
    } catch (e) {
      debugPrint('Failed to cancel recording: $e');
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (image != null) {
        final file = File(image.path);
        final fileName = image.name.isNotEmpty ? image.name : 'image.jpg';
        widget.onImageSelected?.call(file, fileName);
        _toggleAttachmentMenu();
      }
    } catch (e) {
      debugPrint('Failed to pick image: $e');
      _showErrorSnackBar('Failed to select image');
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final platformFile = result.files.first;
        final file = File(platformFile.path!);
        widget.onFileSelected?.call(file, platformFile.name);
        _toggleAttachmentMenu();
      }
    } catch (e) {
      debugPrint('Failed to pick file: $e');
      _showErrorSnackBar('Failed to select file');
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Permission Required'),
            content: const Text(
              'Microphone permission is required to record voice messages.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
    );
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

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes);
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      decoration: BoxDecoration(
        color: colorScheme.surface,
      ),
      child: SafeArea(
        child: Column(
        children: [
          // Attachment menu
          AnimatedBuilder(
            animation: _attachmentAnimation,
            builder: (context, child) {
              return SizeTransition(
                sizeFactor: _attachmentAnimation,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _AttachmentButton(
                        icon: Icons.insert_drive_file_outlined,
                        label: 'File',
                        onTap: _pickFile,
                      ),
                      _AttachmentButton(
                        icon: Icons.poll_outlined,
                        label: 'Poll',
                        onTap: () {
                          widget.onPollPressed?.call();
                          _toggleAttachmentMenu();
                        },
                      ),
                      _AttachmentButton(
                        icon: Icons.task_alt_outlined,
                        label: 'To-Do',
                        onTap: () {
                          widget.onTodoPressed?.call();
                          _toggleAttachmentMenu();
                        },
                      ),
                      _AttachmentButton(
                        icon: Icons.payment_outlined,
                        label: 'Payment',
                        onTap: () {
                          widget.onPaymentPressed?.call();
                          _toggleAttachmentMenu();
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          // Recording overlay
          if (_isRecording)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(25),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  AnimatedBuilder(
                    animation: _recordAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: 1.0 + (_recordAnimation.value * 0.2),
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Recording...',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _formatDuration(_recordDuration),
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: _cancelRecording,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.close,
                        color: Colors.red,
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Main input row
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Text input field with icons
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(width: 20),
                      
                      // Text field
                      Expanded(
                        child: TextField(
                          controller: widget.messageController,
                          focusNode: widget.messageFocusNode,
                          maxLines: 5,
                          minLines: 1,
                          textInputAction: TextInputAction.newline,
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontSize: 16,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Message',
                            hintStyle: TextStyle(
                              color: colorScheme.onSurfaceVariant.withOpacity(0.6),
                              fontSize: 16,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 10,
                            ),
                          ),
                          onSubmitted: (_) {
                            if (_hasText && !widget.isUploading) {
                              widget.onSendPressed?.call();
                            }
                          },
                        ),
                      ),
                      
                      const SizedBox(width: 4),
                      
                      // Attachment button (pin icon)
                      IconButton(
                        onPressed: widget.isUploading ? null : _toggleAttachmentMenu,
                        icon: Icon(
                          Icons.attach_file,
                          color: colorScheme.onSurfaceVariant,
                          size: 24,
                        ),
                        padding: const EdgeInsets.all(8),
                        constraints: const BoxConstraints(),
                      ),
                      
                      // Camera button
                      IconButton(
                        onPressed: widget.isUploading ? null : () => _pickImage(ImageSource.camera),
                        icon: Icon(
                          Icons.camera_alt,
                          color: colorScheme.onSurfaceVariant,
                          size: 24,
                        ),
                        padding: const EdgeInsets.all(8),
                        constraints: const BoxConstraints(),
                      ),
                      
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // Send/Voice button
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.isUploading
                      ? null
                      : _hasText
                          ? widget.onSendPressed
                          : _isRecording
                              ? _stopRecording
                              : _startRecording,
                  borderRadius: BorderRadius.circular(28),
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color:
                          _hasText || _isRecording
                              ? colorScheme.primary
                              : colorScheme.primary.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child:
                        widget.isUploading
                            ? Padding(
                              padding: const EdgeInsets.all(16),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  colorScheme.onPrimary,
                                ),
                              ),
                            )
                            : Icon(
                              _hasText || _isRecording
                                  ? Icons.send
                                  : Icons.mic,
                              color: colorScheme.onPrimary,
                              size: 24,
                            ),
                  ),
                ),
              ),
            ],
          ),
        ],
        ),
      ),
    );
  }
}

class _AttachmentButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _AttachmentButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final primary = colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: colorScheme.outline.withOpacity(0.2),
                width: 1,
              ),
            ),
            child: Icon(icon, color: primary, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurface.withOpacity(0.9),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
