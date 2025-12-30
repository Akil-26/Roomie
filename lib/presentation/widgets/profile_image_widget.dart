import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:roomie/data/datasources/image_helper.dart';
import 'package:roomie/data/datasources/profile_image_notifier.dart';

/// Displays a profile image from a Cloudinary URL (or placeholder).
/// Listens to global ProfileImageNotifier for updates.
/// Uses cacheWidth/cacheHeight for memory optimization.
class ProfileImageWidget extends StatefulWidget {
  final String? imageUrl;
  final double radius;
  final Widget? placeholder;
  final File? localPreviewFile; // If user just picked an image

  const ProfileImageWidget({
    super.key,
    this.imageUrl,
    this.radius = 60,
    this.placeholder,
    this.localPreviewFile,
  });

  @override
  State<ProfileImageWidget> createState() => _ProfileImageWidgetState();
}

class _ProfileImageWidgetState extends State<ProfileImageWidget> {
  final ProfileImageNotifier _notifier = ProfileImageNotifier();
  String? _currentUrl;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.imageUrl;
    _notifier.addListener(_onGlobalChange);
  }

  @override
  void didUpdateWidget(ProfileImageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _currentUrl = widget.imageUrl;
    }
  }

  void _onGlobalChange() {
    final global = _notifier.currentImageId; // now expected to be URL
    if (global != null && global != _currentUrl) {
      setState(() => _currentUrl = global);
    }
  }

  @override
  void dispose() {
    _notifier.removeListener(_onGlobalChange);
    super.dispose();
  }

  bool get _isUrl => _currentUrl != null && _currentUrl!.startsWith('http');

  @override
  Widget build(BuildContext context) {
    // Calculate cache size based on device pixel ratio for memory efficiency
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    final cacheSize = (widget.radius * 2 * devicePixelRatio).toInt();

    // Show immediate local preview if provided (editing state)
    if (widget.localPreviewFile != null && !kIsWeb) {
      return CircleAvatar(
        radius: widget.radius,
        backgroundColor: Theme.of(context).colorScheme.surface,
        backgroundImage: ResizeImage(
          FileImage(widget.localPreviewFile!),
          width: cacheSize,
          height: cacheSize,
        ),
      );
    }

    if (_isUrl) {
      // Debug log for diagnosing image not showing issues
      if (kDebugMode) {
        debugPrint('[ProfileImageWidget] Loading network image: $_currentUrl');
      }
      return ClipOval(
        child: ImageHelper.networkImage(
          _currentUrl,
          width: widget.radius * 2,
          height: widget.radius * 2,
          fit: BoxFit.cover,
          cacheWidth: cacheSize,
          cacheHeight: cacheSize,
          placeholder: CircleAvatar(
            radius: widget.radius,
            backgroundColor: Theme.of(context).colorScheme.surface,
            child:
                widget.placeholder ??
                Icon(
                  Icons.person,
                  size: widget.radius,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      );
    }

    // Legacy / no image fallback
    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: Theme.of(context).colorScheme.surface,
      child:
          widget.placeholder ??
          Icon(
            Icons.person,
            size: widget.radius,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }
}
