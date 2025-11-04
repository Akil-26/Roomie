import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class RoomieLoadingWidget extends StatelessWidget {
  final double? size;
  final Color? backgroundColor;
  final String? text;
  final bool showText;

  const RoomieLoadingWidget({
    super.key,
    this.size,
    this.backgroundColor,
    this.text,
    this.showText = false,
  });

  @override
  Widget build(BuildContext context) {
    final loadingSize = size ?? 100.0;

    return Container(
      color: backgroundColor,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Lottie Animation
            SizedBox(
              width: loadingSize,
              height: loadingSize,
              child: Lottie.asset(
                Theme.of(context).brightness == Brightness.dark
                    ? 'assets/Roomie-loading-dark.json'
                    : 'assets/Roomie-loading-light.json',
                width: loadingSize,
                height: loadingSize,
                fit: BoxFit.contain,
                repeat: true,
                animate: true,
              ),
            ),

            // Optional text
            if (showText || text != null) ...[
              const SizedBox(height: 16),
              Text(
                text ?? 'Loading...',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color:
                      Theme.of(context).textTheme.bodyMedium?.color ??
                      Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Small inline loading widget for buttons, etc.
class RoomieLoadingSmall extends StatelessWidget {
  final double size;
  final Color? color;

  const RoomieLoadingSmall({super.key, this.size = 24.0, this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Lottie.asset(
        Theme.of(context).brightness == Brightness.dark
            ? 'assets/Roomie-loading-dark.json'
            : 'assets/Roomie-loading-light.json',
        width: size,
        height: size,
        fit: BoxFit.contain,
        repeat: true,
        animate: true,
      ),
    );
  }
}

// Full screen loading overlay
class RoomieFullScreenLoading extends StatelessWidget {
  final String? text;
  final bool canDismiss;

  const RoomieFullScreenLoading({
    super.key,
    this.text,
    this.canDismiss = false,
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: canDismiss,
      child: Container(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
        child: RoomieLoadingWidget(size: 120, text: text, showText: true),
      ),
    );
  }
}
