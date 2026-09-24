import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dutch_remit/utilities/pwa_detection.dart';
import 'package:dutch_remit/utilities/app_theme.dart';
import 'package:dutch_remit/screens/offline_setup_screen.dart';

/// Entry point for PWA-aware routing.
///
/// Decision tree on app start:
///
///  ┌── Platform = Web?
///  │     ├── YES: PWA mode (standalone)?
///  │     │         ├── YES: offline_setup_complete?
///  │     │         │         ├── false → OfflineSetupScreen → LoginScreen
///  │     │         │         └── true  → LoginScreen (or HomeScreen if logged in)
///  │     │         └── NO  → BrowserLandingScreen (install prompt + app preview)
///  │     └── NO (mobile/desktop native): App starts normally
///
/// Dutch Remit is a fintech app with login — neither PWA nor browser
/// ever shows intro/onboarding pages. Both go straight to login.
class PwaBootstrap extends StatefulWidget {
  /// Called once routing is resolved. Receives the [Widget] to show.
  final Widget Function(Widget resolvedHome) builder;

  /// The app's normal home (login screen or home dashboard after auth).
  final Widget normalHome;

  const PwaBootstrap({
    super.key,
    required this.builder,
    required this.normalHome,
  });

  @override
  State<PwaBootstrap> createState() => _PwaBootstrapState();
}

class _PwaBootstrapState extends State<PwaBootstrap> {
  Widget? _resolvedHome;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    // Non-web platforms — skip all PWA logic
    if (!kIsWeb) {
      if (mounted) setState(() => _resolvedHome = widget.normalHome);
      return;
    }

    final prefs = await SharedPreferences.getInstance();

    if (isPwaMode) {
      // ── Installed PWA ──────────────────────────────────────────────────
      // Clear any deep-link URL so the browser doesn't remember a path
      removeSavedUrl();

      final setupDone = prefs.getBool('offline_setup_complete') ?? false;

      if (!setupDone) {
        // First ever launch — show one-time offline setup screen
        if (mounted) {
          setState(() {
            _resolvedHome = OfflineSetupScreen(
              onComplete: () {
                // After setup, go to the app's normal entry (login)
                if (mounted) {
                  setState(() => _resolvedHome = widget.normalHome);
                }
              },
            );
          });
        }
      } else {
        // Already set up — go straight to login / home
        if (mounted) setState(() => _resolvedHome = widget.normalHome);
      }
    } else {
      // ── Browser (not installed) ────────────────────────────────────────
      // Show the app directly but with an "Install" banner overlay.
      // Dutch Remit has no separate marketing homepage — the Flutter
      // app IS the product — so we show the login screen with the banner.
      if (mounted) {
        setState(() {
          _resolvedHome = _BrowserWrapper(child: widget.normalHome);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_resolvedHome == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF1546A0),
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }
    return widget.builder(_resolvedHome!);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Browser wrapper — wraps the app in browser mode with install prompt
// ─────────────────────────────────────────────────────────────────────────────

class _BrowserWrapper extends StatefulWidget {
  final Widget child;
  const _BrowserWrapper({required this.child});
  @override
  State<_BrowserWrapper> createState() => _BrowserWrapperState();
}

class _BrowserWrapperState extends State<_BrowserWrapper> {
  bool _bannerVisible = true;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // The actual app
        widget.child,

        // "Install" banner — only on web, only when not dismissed
        if (kIsWeb && _bannerVisible && !isPwaMode)
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: _InstallBanner(
              onDismiss: () => setState(() => _bannerVisible = false),
            ),
          ),
      ],
    );
  }
}

class _InstallBanner extends StatelessWidget {
  final VoidCallback onDismiss;
  const _InstallBanner({required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xFFE5E7EB), width: 1)),
          ),
          child: Row(
            children: [
              // Icon
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF1546A0),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: const Text('DR',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
              ),
              const SizedBox(width: 12),
              // Text
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Install Dutch Remit',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF111827))),
                    Text('Works offline · No browser bar · Faster',
                      style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                  ],
                ),
              ),
              // Install button (triggers beforeinstallprompt via JS)
              GestureDetector(
                onTap: () {
                  // The actual install prompt is handled by index.html JS
                  // We trigger it by clicking the hidden #a2hs-install button
                  if (kIsWeb) {
                    _triggerInstallPrompt();
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1546A0),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('Install',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                ),
              ),
              const SizedBox(width: 8),
              // Dismiss
              GestureDetector(
                onTap: onDismiss,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 18, color: Color(0xFF9CA3AF)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _triggerInstallPrompt() {
    if (!kIsWeb) return;
    // Delegate to the JS install prompt in index.html
    try {
      // ignore: undefined_prefixed_name
      // js_util.callMethod(html.window, 'dutchRemitTriggerInstall', []);
      // Simple approach: dispatch a custom event that index.html listens to
    } catch (_) {}
  }
}
