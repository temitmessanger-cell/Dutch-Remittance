import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dutch_remit/services/offline_setup_bridge.dart';
import 'package:dutch_remit/methods/download_helper.dart';
import 'package:dutch_remit/utilities/pwa_detection.dart';
import 'package:dutch_remit/utilities/app_theme.dart';

/// One-time offline setup screen.
///
/// Shown on the very first PWA launch while the service worker
/// pre-caches all app assets. Once complete it sets
/// [SharedPreferences] flag `offline_setup_complete = true` and
/// calls [onComplete]. It is never shown again.
///
/// Progress phases:
///   Phase 1 (0 – 85%): Main assets — JS bundle, WASM, fonts, images.
///                       User-visible message: "Downloading files…"
///   Phase 2 (85–100%): Secondary assets cached silently in background.
///                       User-visible message: "Finalizing offline setup…"
class OfflineSetupScreen extends StatefulWidget {
  final VoidCallback onComplete;
  const OfflineSetupScreen({super.key, required this.onComplete});

  @override
  State<OfflineSetupScreen> createState() => _OfflineSetupScreenState();
}

class _OfflineSetupScreenState extends State<OfflineSetupScreen>
    with TickerProviderStateMixin {
  // ── State ──────────────────────────────────────────────────────────────
  double _progress     = 0.0;  // 0.0 – 1.0
  int    _cachedFiles  = 0;
  int    _totalFiles   = 0;
  _Phase _phase        = _Phase.waiting;
  String _statusLine   = 'Preparing your offline setup…';
  bool   _hasError     = false;
  bool   _isOffline    = false;

  // ── Animation ──────────────────────────────────────────────────────────
  late AnimationController _barController;
  late Animation<double>   _barAnimation;
  late AnimationController _pulseController;
  late Animation<double>   _pulseAnimation;

  // ── Connectivity polling ───────────────────────────────────────────────
  Timer? _connectivityTimer;
  Timer? _timeoutTimer;

  static const Duration _totalTimeout = Duration(minutes: 5);

  @override
  void initState() {
    super.initState();

    // Smooth progress bar animation
    _barController = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _barAnimation  = Tween<double>(begin: 0, end: 0).animate(
        CurvedAnimation(parent: _barController, curve: Curves.easeOut));

    // Icon pulse while waiting/downloading
    _pulseController = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 1600))..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
        CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));

    _startListening();

    // Safety timeout — if SW never sends INSTALL_COMPLETE after 5 min,
    // let the user in anyway (they may have slow connection or old browser).
    _timeoutTimer = Timer(_totalTimeout, _finishSetup);
  }

  @override
  void dispose() {
    _barController.dispose();
    _pulseController.dispose();
    _connectivityTimer?.cancel();
    _timeoutTimer?.cancel();
    super.dispose();
  }

  // ── SW message listener ─────────────────────────────────────────────────
  void _startListening() {
    OfflineSetupBridge.instance.startListening();
    _timeoutTimer = Timer(_totalTimeout, _finishSetup);

    OfflineSetupBridge.instance.messages.listen(_handleSwMsg);

    Future.delayed(const Duration(milliseconds: 400), () {
      if (!mounted || _phase != _Phase.waiting) return;
      setState(() {
        _phase = _Phase.downloading;
        _statusLine = 'Downloading files to enable offline use…';
      });
    });
  }

  void _handleSwMsg(SwMessage msg) {
    switch (msg.type) {
      case SwMessageType.progress:
        _updateProgress(msg.cached, msg.total);
        break;
      case SwMessageType.complete:
        _onMainDownloadComplete();
        break;
      case SwMessageType.error:
        if (mounted) setState(() => _hasError = true);
        break;
    }
  }

  void _updateProgress(int cached, int total) {
    if (!mounted || total == 0) return;

    // Phase 1 occupies 0–85% of the bar
    final rawRatio   = cached / total;
    final barTarget  = (rawRatio * 0.85).clamp(0.0, 0.85);
    final percentage = (barTarget * 100).round();

    final remaining   = _totalFiles > 0 ? _totalFiles - _cachedFiles : 0;
    setState(() {
      _cachedFiles = cached;
      _totalFiles  = total;
      _phase       = _Phase.downloading;
      _isOffline   = false;
      _hasError    = false;
      _statusLine  = percentage < 30
          ? 'Downloading files to enable offline use…  $percentage%'
          : percentage < 75
              ? 'Saving files offline — ${DownloadHelper.etaLabel(remaining)}'
              : 'Almost done — $percentage% complete';
    });
    _animateBar(barTarget);
  }

  void _onMainDownloadComplete() {
    if (!mounted) return;
    setState(() {
      _phase      = _Phase.secondary;
      _statusLine = 'Finalizing offline setup — almost ready…';
    });
    _animateBar(0.9);

    // Phase 2: brief pause, then complete (secondary assets cached by SW silently)
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      _animateBar(1.0);
      Future.delayed(const Duration(milliseconds: 500), _finishSetup);
    });
  }

  void _animateBar(double target) {
    final current = _barAnimation.value;
    _barAnimation = Tween<double>(begin: current, end: target).animate(
        CurvedAnimation(parent: _barController, curve: Curves.easeOut));
    _barController.forward(from: 0);
  }

  Future<void> _finishSetup() async {
    if (!mounted) return;

    setState(() {
      _phase      = _Phase.done;
      _statusLine = '✓  Dutch Remit is ready — fully offline';
      _progress   = 1.0;
    });
    _animateBar(1.0);
    _pulseController.stop();

    // Mark as complete so this screen is never shown again
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('offline_setup_complete', true);

    // Brief pause to let user read the success message
    await Future.delayed(const Duration(milliseconds: 1800));
    if (mounted) widget.onComplete();
  }

  // ── Build ───────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(flex: 3),
              _buildLogo(),
              const SizedBox(height: 32),
              _buildTitle(),
              const SizedBox(height: 8),
              _buildSubtitle(),
              const Spacer(flex: 2),
              _buildProgressSection(),
              const Spacer(flex: 3),
              _buildFooter(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (_, child) => Transform.scale(
        scale: _phase == _Phase.done ? 1.0 : _pulseAnimation.value,
        child: child,
      ),
      child: Container(
        width: 88, height: 88,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.25), width: 1.5),
        ),
        alignment: Alignment.center,
        child: Text('DR',
          style: TextStyle(
            color: Colors.white,
            fontSize: 32, fontWeight: FontWeight.w800,
            letterSpacing: -1,
          )),
      ),
    );
  }

  Widget _buildTitle() => Text(
    'Dutch Remit',
    style: TextStyle(
      color: Colors.white,
      fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5,
    ),
  );

  Widget _buildSubtitle() => Text(
    'Send money to 32 countries',
    style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 15),
  );

  Widget _buildProgressSection() {
    if (_isOffline) return _buildOfflineBanner();
    if (_hasError)  return _buildErrorBanner();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Status label
        Text(
          _phase == _Phase.done
              ? '✓  All set! Dutch Remit now works fully offline.'
              : _statusLine,
          style: TextStyle(
            color: _phase == _Phase.done
                ? Colors.greenAccent.shade200
                : Colors.white.withOpacity(0.9),
            fontSize: 14, fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 14),

        // Progress bar
        AnimatedBuilder(
          animation: _barAnimation,
          builder: (_, __) {
            final pct = _barAnimation.value;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    // Track
                    Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    // Fill
                    FractionallySizedBox(
                      widthFactor: pct,
                      child: Container(
                        height: 8,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _phase == _Phase.secondary
                          ? 'Finalizing…'
                          : _totalFiles > 0
                              ? '$_cachedFiles of $_totalFiles files'
                              : 'Starting download…',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.55), fontSize: 12),
                    ),
                    Text(
                      '${(pct * 100).round()}%',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.75),
                          fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ],
            );
          },
        ),

        // Secondary phase note
        if (_phase == _Phase.secondary || _phase == _Phase.downloading) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Text('📦', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _phase == _Phase.secondary
                        ? 'Additional files are downloading in the background to ensure 100% offline coverage.'
                        : 'This is a one-time download. Dutch Remit will work fully offline forever after.',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.7), fontSize: 12, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildOfflineBanner() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.12),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white.withOpacity(0.2)),
    ),
    child: Column(
      children: [
        const Text('📡', style: TextStyle(fontSize: 36)),
        const SizedBox(height: 12),
        Text('Download paused',
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text('Reconnect to continue. Your progress is saved.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13)),
      ],
    ),
  );

  Widget _buildErrorBanner() => Column(
    children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'Some files could not be downloaded. '
          'The app may not work fully offline yet.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13),
        ),
      ),
      const SizedBox(height: 12),
      TextButton(
        onPressed: _finishSetup,
        child: Text('Continue anyway →',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
    ],
  );

  Widget _buildFooter() => Text(
    'This is a one-time setup. Please stay connected.',
    style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12),
    textAlign: TextAlign.center,
  );
}

enum _Phase { waiting, downloading, secondary, done }
