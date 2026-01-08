import 'package:flutter/material.dart';

/// STEP-6: Safety, Guards & Edge-Case Protection
/// 
/// This file provides reusable utilities for:
/// - Double-action protection
/// - UI locking during critical actions
/// - Network failure recovery
/// 
/// NO backend logic changes. UI behavior only.

/// A mixin that provides double-action protection for StatefulWidgets.
/// 
/// Usage:
/// 1. Add `with ActionGuardMixin` to your State class
/// 2. Wrap critical actions with `guardedAction('actionKey', () async { ... })`
/// 3. Check `isActionInProgress('actionKey')` to disable buttons
mixin ActionGuardMixin<T extends StatefulWidget> on State<T> {
  final Set<String> _inProgressActions = {};

  /// Check if a specific action is currently in progress
  bool isActionInProgress(String actionKey) => _inProgressActions.contains(actionKey);

  /// Check if ANY action is currently in progress
  bool get hasAnyActionInProgress => _inProgressActions.isNotEmpty;

  /// Execute an action with double-tap protection.
  /// Returns the result of the action, or null if already in progress.
  Future<R?> guardedAction<R>(
    String actionKey,
    Future<R> Function() action, {
    VoidCallback? onStart,
    void Function(R result)? onSuccess,
    void Function(Object error)? onError,
    VoidCallback? onFinally,
  }) async {
    // STEP-6: Double-action protection - prevent if already in progress
    if (_inProgressActions.contains(actionKey)) {
      debugPrint('[ActionGuard] Blocked duplicate action: $actionKey');
      return null;
    }

    // Mark action as in progress
    if (mounted) {
      setState(() => _inProgressActions.add(actionKey));
    }
    onStart?.call();

    try {
      final result = await action();
      onSuccess?.call(result);
      return result;
    } catch (e) {
      debugPrint('[ActionGuard] Action $actionKey failed: $e');
      onError?.call(e);
      rethrow;
    } finally {
      // STEP-6: Always reset state - prevents stuck loaders
      if (mounted) {
        setState(() => _inProgressActions.remove(actionKey));
      }
      onFinally?.call();
    }
  }

  /// Reset all action states (useful on dispose or error recovery)
  void resetAllActions() {
    if (mounted) {
      setState(() => _inProgressActions.clear());
    }
  }
}

/// A widget that blocks user interaction during critical actions.
/// 
/// STEP-6: UI Lock During Critical Actions
/// This is a SOFT lock - visual blocker only, not preventing system back.
class CriticalActionOverlay extends StatelessWidget {
  final bool isActive;
  final Widget child;
  final String? message;

  const CriticalActionOverlay({
    super.key,
    required this.isActive,
    required this.child,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isActive)
          Positioned.fill(
            child: AbsorbPointer(
              absorbing: true,
              child: Container(
                color: Colors.black.withAlpha(100),
                child: Center(
                  child: Card(
                    margin: const EdgeInsets.all(32),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          if (message != null) ...[
                            const SizedBox(height: 16),
                            Text(
                              message!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 14),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Text(
                            'Please wait...',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A widget wrapper that prevents back navigation during critical actions.
/// 
/// STEP-6: UI Lock During Critical Actions (back navigation)
class BackNavigationGuard extends StatelessWidget {
  final bool canPop;
  final Widget child;
  final String? warningMessage;

  const BackNavigationGuard({
    super.key,
    required this.canPop,
    required this.child,
    this.warningMessage,
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && warningMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(warningMessage!),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
      child: child,
    );
  }
}

/// STEP-6: Network Failure Guard - Standard error handler
/// Shows error snackbar and ensures UI recovers
void showNetworkErrorSnackbar(
  BuildContext context, {
  String? message,
  VoidCallback? onRetry,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message ?? 'Something went wrong. Please try again.'),
      backgroundColor: colorScheme.error,
      action: onRetry != null
          ? SnackBarAction(
              label: 'Retry',
              textColor: colorScheme.onError,
              onPressed: onRetry,
            )
          : null,
      duration: const Duration(seconds: 4),
    ),
  );
}

/// STEP-6: Defensive assertion helper
/// Returns true if assertion passes, false if it fails (with optional error message)
bool assertCondition(
  bool condition,
  BuildContext context, {
  String? failureMessage,
}) {
  if (!condition) {
    if (failureMessage != null) {
      showNetworkErrorSnackbar(context, message: failureMessage);
    }
    debugPrint('[AssertionFailed] $failureMessage');
    return false;
  }
  return true;
}
