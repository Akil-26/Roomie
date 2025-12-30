import 'package:flutter/material.dart';

/// Helper class for efficient image loading with caching support
class ImageHelper {
  // Display a network image (Cloudinary) with graceful fallback and caching.
  static Widget networkImage(
    String? url, {
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
    Widget? placeholder,
    Widget? errorWidget,
    int? cacheWidth,
    int? cacheHeight,
  }) {
    if (url == null || url.isEmpty) {
      return placeholder ??
          Builder(
            builder: (context) {
              final colorScheme = Theme.of(context).colorScheme;
              return Container(
                width: width,
                height: height,
                color: colorScheme.surfaceContainerHighest,
                child: Icon(
                  Icons.image_outlined,
                  color: colorScheme.onSurfaceVariant,
                ),
              );
            },
          );
    }
    return Image.network(
      url,
      width: width,
      height: height,
      fit: fit,
      // Memory optimization: decode image at target size
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
      // Loading indicator for better UX
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return placeholder ??
            Container(
              width: width,
              height: height,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded /
                          loadingProgress.expectedTotalBytes!
                      : null,
                ),
              ),
            );
      },
      errorBuilder: (context, error, stack) {
        debugPrint('Network image error: $error');
        return errorWidget ??
            Builder(
              builder: (context) {
                final colorScheme = Theme.of(context).colorScheme;
                return Container(
                  width: width,
                  height: height,
                  color: colorScheme.surfaceContainerHighest,
                  child: Icon(
                    Icons.broken_image,
                    color: colorScheme.onSurfaceVariant,
                  ),
                );
              },
            );
      },
    );
  }

  /// Optimized image with fade-in animation
  static Widget fadeInNetworkImage(
    String? url, {
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
    Duration duration = const Duration(milliseconds: 300),
    int? cacheWidth,
    int? cacheHeight,
  }) {
    if (url == null || url.isEmpty) {
      return Builder(
        builder: (context) {
          final colorScheme = Theme.of(context).colorScheme;
          return Container(
            width: width,
            height: height,
            color: colorScheme.surfaceContainerHighest,
            child: Icon(
              Icons.image_outlined,
              color: colorScheme.onSurfaceVariant,
            ),
          );
        },
      );
    }
    return Image.network(
      url,
      width: width,
      height: height,
      fit: fit,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: duration,
          curve: Curves.easeOut,
          child: child,
        );
      },
      errorBuilder: (context, error, stack) {
        final colorScheme = Theme.of(context).colorScheme;
        return Container(
          width: width,
          height: height,
          color: colorScheme.surfaceContainerHighest,
          child: Icon(
            Icons.broken_image,
            color: colorScheme.onSurfaceVariant,
          ),
        );
      },
    );
  }
}
