import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:dutch_remit/utilities/app_theme.dart';

/// Shown briefly while main.dart resolves login/onboarding state from
/// local storage — typically well under a second, occasionally a bit
/// longer on a cold start with a slow disk. Because this can be the
/// very first frame the app ever shows, it needs to look intentional
/// on frame one, not fade in after the fact.
///
/// Structure: an immediate navy-to-navy gradient (renders instantly,
/// no network wait) with the wordmark scaling/fading in, a subtle
/// animated gold underline "draw-on", and a photo that crossfades in
/// underneath once it loads — so slow networks still see a polished
/// branded screen immediately, and fast networks get the extra
/// texture as a bonus rather than a dependency.
class LocalSplashScreenComponent extends StatefulWidget {
  const LocalSplashScreenComponent({Key? key}) : super(key: key);

  @override
  State<LocalSplashScreenComponent> createState() =>
      _LocalSplashScreenComponentState();
}

class _LocalSplashScreenComponentState
    extends State<LocalSplashScreenComponent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _photoLoaded = false;

  static const Color heroTop = Color(0xFF0A1B47);
  static const Color heroBottom = Color(0xFF163172);
  static const Color gold = Color(0xFFF5B841);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wordmarkScale = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOutBack),
    );
    final wordmarkFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
    );
    final underline = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.35, 0.75, curve: Curves.easeOutCubic),
    );
    final tagFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.5, 0.9, curve: Curves.easeOut),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        // Instant-render gradient — never depends on the network, so
        // frame one is always fully branded even offline.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [heroTop, heroBottom],
            ),
          ),
        ),
        // Photo crossfades in once loaded — pure enhancement, never
        // a blocker. Low opacity so text stays crisp above it.
        AnimatedOpacity(
          opacity: _photoLoaded ? 0.22 : 0.0,
          duration: const Duration(milliseconds: 700),
          child: Image.network(
            'https://images.unsplash.com/photo-1523482580672-f109ba8cb9be?auto=format&fit=crop&w=1200&q=60',
            fit: BoxFit.cover,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (frame != null && !_photoLoaded) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _photoLoaded = true);
                });
              }
              return child;
            },
            errorBuilder: (context, error, stackTrace) =>
                const SizedBox.shrink(),
          ),
        ),
        // Extra scrim so the photo never fights the wordmark.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x330A1B47), Color(0x990A1B47)],
            ),
          ),
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FadeTransition(
                opacity: wordmarkFade,
                child: ScaleTransition(
                  scale: wordmarkScale,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: gold,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: gold.withOpacity(0.35),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'D',
                          style: GoogleFonts.manrope(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            color: heroTop,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Dutch Remit',
                        style: GoogleFonts.manrope(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Gold underline that "draws on" left to right.
              AnimatedBuilder(
                animation: underline,
                builder: (context, _) => Container(
                  width: 64 * underline.value,
                  height: 3,
                  decoration: BoxDecoration(
                    color: gold,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              FadeTransition(
                opacity: tagFade,
                child: Text(
                  "Cameroon's #1 · Africa's leading platform",
                  style: GoogleFonts.manrope(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                    color: Colors.white.withOpacity(0.72),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Small bottom-anchored progress hint — subtle, doesn't
        // compete with the wordmark as the visual anchor.
        Positioned(
          left: 0,
          right: 0,
          bottom: 56,
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  Colors.white.withOpacity(0.55),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
