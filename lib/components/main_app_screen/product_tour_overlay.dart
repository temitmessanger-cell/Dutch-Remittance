import 'package:flutter/material.dart';
import 'package:dutch_remit/utilities/app_theme.dart';

/// A single step in the guided product tour.
class TourStep {
  final String title;
  final String description;
  final IconData icon;

  /// Index of the bottom-nav tab this step refers to (0-4), so the
  /// overlay can switch the underlying screen to match and spotlight
  /// the right nav icon.
  final int tabIndex;

  const TourStep({
    required this.title,
    required this.description,
    required this.icon,
    required this.tabIndex,
  });
}

/// A clean, investor-demo-ready guided tour: a soft scrim with a circular
/// spotlight over the active bottom-nav icon, paired with a small card
/// explaining what that tab does. Advances with Next, can be skipped at
/// any time, and reports back which tab should be visible underneath so
/// the real screen is shown as each step plays.
class ProductTourOverlay extends StatefulWidget {
  final List<TourStep> steps;
  final void Function(int tabIndex) onStepChanged;
  final VoidCallback onFinished;

  /// The GlobalKey on the bottom nav bar's container. Since GNav lays
  /// its tabs out evenly, each tab's position is computed as a fraction
  /// of this rect's width rather than reaching into GNav's internals.
  final GlobalKey navBarKey;

  /// Total number of bottom-nav tabs, used for the even-division math.
  final int tabCount;

  const ProductTourOverlay({
    Key? key,
    required this.steps,
    required this.onStepChanged,
    required this.onFinished,
    required this.navBarKey,
    required this.tabCount,
  }) : super(key: key);

  @override
  State<ProductTourOverlay> createState() => _ProductTourOverlayState();
}

class _ProductTourOverlayState extends State<ProductTourOverlay>
    with SingleTickerProviderStateMixin {
  int _stepIndex = 0;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);

    WidgetsBinding.instance!
        .addPostFrameCallback((_) => widget.onStepChanged(widget.steps[0].tabIndex));
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Rect? _spotlightRect() {
    final renderObject = widget.navBarKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox) return null;
    final navBarSize = renderObject.size;
    final navBarOffset = renderObject.localToGlobal(Offset.zero);

    final int tabIndex = widget.steps[_stepIndex].tabIndex;
    final double segmentWidth = navBarSize.width / widget.tabCount;
    final double centerX = navBarOffset.dx + (segmentWidth * (tabIndex + 0.5));
    // GNav centers its icon roughly in the upper-middle of each tab's
    // tappable area, above the label — this offset approximates that.
    final double iconCenterY = navBarOffset.dy + (navBarSize.height * 0.38);

    const double iconRadius = 26;
    return Rect.fromCenter(
      center: Offset(centerX, iconCenterY),
      width: iconRadius * 2,
      height: iconRadius * 2,
    );
  }

  void _next() {
    if (_stepIndex == widget.steps.length - 1) {
      widget.onFinished();
      return;
    }
    setState(() => _stepIndex++);
    widget.onStepChanged(widget.steps[_stepIndex].tabIndex);
  }

  void _skip() => widget.onFinished();

  @override
  Widget build(BuildContext context) {
    final step = widget.steps[_stepIndex];
    final screenSize = MediaQuery.of(context).size;
    final spotlight = _spotlightRect();
    final bool isLastStep = _stepIndex == widget.steps.length - 1;

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Scrim with a spotlight cutout over the relevant nav icon.
          GestureDetector(
            onTap: () {}, // swallow taps so nothing behind the scrim fires
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (context, _) {
                return CustomPaint(
                  size: screenSize,
                  painter: _SpotlightPainter(
                    spotlight: spotlight,
                    pulse: _pulseController.value,
                  ),
                );
              },
            ),
          ),

          // The explanation card, anchored above the nav bar.
          Positioned(
            left: 20,
            right: 20,
            bottom: spotlight != null
                ? (screenSize.height - spotlight.top) + 18
                : 100,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                          begin: const Offset(0, 0.08), end: Offset.zero)
                      .animate(animation),
                  child: child,
                ),
              ),
              child: Container(
                key: ValueKey(_stepIndex),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                  boxShadow: AppShadows.raised,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(step.icon,
                              color: AppColors.primary, size: 19),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            step.title,
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink),
                          ),
                        ),
                        InkWell(
                          onTap: _skip,
                          borderRadius: BorderRadius.circular(20),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(Icons.close_rounded,
                                size: 18, color: AppColors.textMuted),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      step.description,
                      style: TextStyle(
                          fontSize: 13.5,
                          color: AppColors.inkMuted,
                          height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Row(
                          children: List.generate(widget.steps.length, (i) {
                            final bool isActive = i == _stepIndex;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.only(right: 5),
                              width: isActive ? 16 : 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: isActive
                                    ? AppColors.primary
                                    : AppColors.border,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            );
                          }),
                        ),
                        const Spacer(),
                        Text(
                          "${_stepIndex + 1}/${widget.steps.length}",
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textMuted),
                        ),
                        const SizedBox(width: 14),
                        ElevatedButton(
                          onPressed: _next,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 10),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(AppRadii.sm)),
                          ),
                          child: Text(
                            isLastStep ? "Done" : "Next",
                            style: TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  final Rect? spotlight;
  final double pulse;

  _SpotlightPainter({required this.spotlight, required this.pulse});

  @override
  void paint(Canvas canvas, Size size) {
    final scrimPaint = Paint()..color = AppColors.ink.withOpacity(0.55);

    if (spotlight == null) {
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), scrimPaint);
      return;
    }

    final center = spotlight!.center;
    final baseRadius = (spotlight!.width / 2) + 14;
    final radius = baseRadius + (pulse * 4);

    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(Rect.fromCircle(center: center, radius: radius))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, scrimPaint);

    // Soft ring around the spotlight so it reads as an intentional highlight.
    final ringPaint = Paint()
      ..color = Colors.white.withOpacity(0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    canvas.drawCircle(center, radius, ringPaint);
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) =>
      oldDelegate.spotlight != spotlight || oldDelegate.pulse != pulse;
}
