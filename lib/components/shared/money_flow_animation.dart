import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:dutch_remit/utilities/app_theme.dart';

/// A real, watchable "your money is moving" animation — shown while a
/// deposit, withdrawal, or transfer is actually in flight, not just a
/// button spinner. Coins arc from a source point toward a destination
/// point, with a status line underneath that can change as the real
/// request progresses (e.g. "Confirming with your bank..." then
/// "Almost there..."). Used identically across top-up, withdraw, and
/// every Send Abroad corridor screen so the visual language for
/// "money is moving" is the same everywhere in the app, not four
/// different bespoke animations.
class MoneyFlowAnimation extends StatefulWidget {
  /// Emoji/short label for the source side (e.g. "🇺🇸" or "USD").
  final String fromLabel;

  /// Emoji/short label for the destination side (e.g. "🇨🇲" or "XAF").
  final String toLabel;

  /// Status text shown under the animation — callers can update this
  /// via setState as a multi-step request progresses.
  final String statusText;

  const MoneyFlowAnimation({
    Key? key,
    required this.fromLabel,
    required this.toLabel,
    this.statusText = "Sending your money…",
  }) : super(key: key);

  @override
  State<MoneyFlowAnimation> createState() => _MoneyFlowAnimationState();
}

class _MoneyFlowAnimationState extends State<MoneyFlowAnimation>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  static const List<double> _coinDelays = [0.0, 0.22, 0.44];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 96,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _endpoint(widget.fromLabel),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Container(
                            height: 2,
                            decoration: BoxDecoration(
                              color: AppColors.border,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                      _endpoint(widget.toLabel),
                    ],
                  ),
                  for (int i = 0; i < _coinDelays.length; i++) _buildCoin(i),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 18),
        Text(
          widget.statusText,
          textAlign: TextAlign.center,
          style: GoogleFonts.manrope(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textMuted),
        ),
      ],
    );
  }

  Widget _endpoint(String label) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.border),
      ),
      alignment: Alignment.center,
      child: Text(label, style: TextStyle(fontSize: 20)),
    );
  }

  Widget _buildCoin(int index) {
    // Each coin loops on its own delayed phase of the shared
    // repeating controller, so three coins are always mid-flight at
    // staggered positions rather than one coin doing one lonely trip.
    final delay = _coinDelays[index];
    double t = _controller.value + delay;
    t = t - t.floorToDouble(); // wrap into [0, 1)
    final eased = Curves.easeInOut.transform(t);

    // Travels left-to-right along the connector, with a slight arc
    // (a small negative-y bump at the midpoint) so it doesn't just
    // slide flatly along the line.
    final arcHeight = 18 * (1 - (2 * t - 1).abs());
    // Fades in/out at the very start/end of its trip so it doesn't
    // pop abruptly at either endpoint.
    final opacity = t < 0.08 ? t / 0.08 : (t > 0.92 ? (1 - t) / 0.08 : 1.0);

    return Align(
      alignment: Alignment(-1 + (2 * eased), -arcHeight / 48),
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.4), blurRadius: 8)],
          ),
          alignment: Alignment.center,
          child: Text('\$', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
        ),
      ),
    );
  }
}
