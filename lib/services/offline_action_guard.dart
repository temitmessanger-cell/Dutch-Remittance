import 'package:flutter/material.dart';
import 'package:dutch_remit/services/connectivity_service.dart';
import 'package:dutch_remit/utilities/app_theme.dart';

/// Protects any action that requires a network connection.
///
/// For Dutch Remit, financial writes (send money, deposit, swap,
/// card fund/withdraw) must NEVER be attempted offline — they would
/// silently fail and could confuse the user about whether money moved.
///
/// Usage — check before showing a screen:
/// ```dart
/// if (!await OfflineActionGuard.check(context, action: 'Send Money')) return;
/// Navigator.push(...);
/// ```
///
/// Usage — wrap a button's onPressed:
/// ```dart
/// onPressed: () => OfflineActionGuard.run(
///   context,
///   action: 'Deposit',
///   fn: () => _initDeposit(),
/// ),
/// ```
class OfflineActionGuard {
  OfflineActionGuard._();

  /// Returns `true` if online and the action should proceed.
  /// Shows a bottom sheet explaining why if offline.
  static Future<bool> check(
    BuildContext context, {
    required String action,
    String? reason,
  }) async {
    if (ConnectivityService.instance.isOnline) return true;
    await _showOfflineSheet(context, action: action, reason: reason);
    return false;
  }

  /// Runs [fn] only when online; shows the sheet if offline.
  static Future<void> run(
    BuildContext context, {
    required String action,
    required Future<void> Function() fn,
    String? reason,
  }) async {
    if (await check(context, action: action, reason: reason)) {
      await fn();
    }
  }

  static Future<void> _showOfflineSheet(
    BuildContext context, {
    required String action,
    String? reason,
  }) async {
    return showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _OfflineSheet(action: action, reason: reason),
    );
  }
}

class _OfflineSheet extends StatefulWidget {
  final String  action;
  final String? reason;
  const _OfflineSheet({required this.action, this.reason});

  @override
  State<_OfflineSheet> createState() => _OfflineSheetState();
}

class _OfflineSheetState extends State<_OfflineSheet> {
  bool _waiting = false;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),

            // Icon
            Container(
              width: 60, height: 60,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                shape: BoxShape.circle,
              ),
              child: const Center(child: Text('📡', style: TextStyle(fontSize: 28))),
            ),
            const SizedBox(height: 16),

            // Title
            Text(
              'You\'re offline',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 8),

            // Body
            Text(
              widget.reason ??
                  '${widget.action} requires an internet connection.\n'
                  'Connect to Wi-Fi or mobile data and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.ink.withOpacity(0.6),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),

            // Wait for connection button
            if (_waiting)
              Column(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(
                    'Waiting for connection…',
                    style: TextStyle(fontSize: 13, color: AppColors.ink.withOpacity(0.5)),
                  ),
                ],
              )
            else
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () async {
                        setState(() => _waiting = true);
                        await ConnectivityService.instance.waitForOnline();
                        if (mounted) Navigator.of(context).pop();
                      },
                      child: const Text(
                        'Wait for connection',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                          color: AppColors.ink.withOpacity(0.5), fontSize: 14),
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

/// Widget that disables its [child] with a greyed-out overlay when offline,
/// and shows the [OfflineActionGuard] sheet when tapped.
///
/// Wrap any button or card that requires connectivity:
/// ```dart
/// OfflineAwareButton(
///   action: 'Send Money',
///   child: ElevatedButton(...),
/// )
/// ```
class OfflineAwareButton extends StatelessWidget {
  final Widget  child;
  final String  action;
  final String? reason;
  const OfflineAwareButton({
    super.key,
    required this.child,
    required this.action,
    this.reason,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: ConnectivityService.instance.stream,
      initialData: ConnectivityService.instance.isOnline,
      builder: (context, snap) {
        final online = snap.data ?? true;
        if (online) return child;

        return Stack(
          children: [
            IgnorePointer(
              child: Opacity(opacity: 0.45, child: child),
            ),
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => OfflineActionGuard.check(
                    context, action: action, reason: reason),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Inline connectivity banner — shown at the top of any screen
/// that has live-data dependencies (balance, transactions, etc.).
///
/// ```dart
/// Column(children: [
///   const OfflineBanner(),
///   // rest of screen
/// ])
/// ```
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: ConnectivityService.instance.stream,
      initialData: ConnectivityService.instance.isOnline,
      builder: (context, snap) {
        final online = snap.data ?? true;
        if (online) return const SizedBox.shrink();

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          color: const Color(0xFF7A5C00),
          child: Row(
            children: [
              const Text('📡', style: TextStyle(fontSize: 13)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'You\'re offline — showing cached data',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
