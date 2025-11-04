import 'package:flutter/material.dart';
import 'package:roomie/presentation/widgets/roomie_loading_widget.dart';

/// Helper class to show loading dialogs and overlays throughout the app
class RoomieLoadingHelper {
  static OverlayEntry? _overlayEntry;

  /// Show a full screen loading overlay
  static void showFullScreenLoading(BuildContext context, {String? message}) {
    if (_overlayEntry != null) return; // Prevent multiple overlays

    _overlayEntry = OverlayEntry(
      builder:
          (context) => RoomieFullScreenLoading(text: message ?? 'Loading...'),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  /// Hide the full screen loading overlay
  static void hideFullScreenLoading() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  /// Show loading dialog
  static Future<void> showLoadingDialog(
    BuildContext context, {
    String? message,
    bool barrierDismissible = false,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.7),
      builder:
          (context) => PopScope(
            canPop: barrierDismissible,
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(24),
                margin: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(
                        context,
                      ).colorScheme.shadow.withValues(alpha: 0.1),
                      blurRadius: 10,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: RoomieLoadingWidget(
                  size: 80,
                  showText: true,
                  text: message ?? 'Loading...',
                ),
              ),
            ),
          ),
    );
  }

  /// Show loading snackbar
  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason>
  showLoadingSnackBar(BuildContext context, {String? message}) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const RoomieLoadingSmall(size: 20),
            const SizedBox(width: 12),
            Text(
              message ?? 'Loading...',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onPrimary,
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 30), // Long duration for loading
        backgroundColor: colorScheme.primary,
      ),
    );
  }

  /// Get a loading widget for list items
  static Widget getListLoadingWidget({String? message}) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: RoomieLoadingWidget(
        size: 50,
        showText: true,
        text: message ?? 'Loading...',
      ),
    );
  }

  /// Get a small loading widget for buttons
  static Widget getButtonLoadingWidget({double size = 20}) {
    return RoomieLoadingSmall(size: size);
  }

  /// Get a page loading widget (for entire page loading states)
  static Widget getPageLoadingWidget({String? message}) {
    return Scaffold(
      body: Center(
        child: RoomieLoadingWidget(
          size: 100,
          showText: true,
          text: message ?? 'Loading...',
        ),
      ),
    );
  }

  /// Show loading for async operations with automatic cleanup
  static Future<T> showLoadingFor<T>(
    BuildContext context,
    Future<T> operation, {
    String? message,
    bool showDialog = true,
  }) async {
    if (showDialog) {
      showFullScreenLoading(context, message: message);
    }

    try {
      final result = await operation;
      return result;
    } finally {
      if (showDialog) {
        hideFullScreenLoading();
      }
    }
  }
}
