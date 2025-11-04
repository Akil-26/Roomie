import 'package:flutter/material.dart';

class ImageHelper {
  // Display a network image (Cloudinary) with graceful fallback.
  static Widget networkImage(
    String? url, {
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
    Widget? placeholder,
    Widget? errorWidget,
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
      errorBuilder: (context, error, stack) {
        print('Network image error: $error');
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
      // Optional: you could add frameBuilder for fade-in effect
    );
  }
}
