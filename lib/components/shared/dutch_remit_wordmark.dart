import 'package:flutter/material.dart';
import 'package:dutch_remit/utilities/app_theme.dart';

/// A clean, theme-consistent text wordmark for "Dutch Remit", used
/// everywhere the app previously showed a Hadwin-branded logo image
/// asset (login, sign up, splash, wallet). Using a text widget rather
/// than another image asset means there's no leftover brand artwork
/// anywhere in the app, and it always matches the current theme.
class DutchRemitWordmark extends StatelessWidget {
  final double fontSize;
  final Color? color;
  final bool showTagline;

  const DutchRemitWordmark({
    Key? key,
    this.fontSize = 28,
    this.color,
    this.showTagline = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final Color resolvedColor = color ?? AppColors.primary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: resolvedColor,
            ),
            children: [
              TextSpan(text: "Dutch ", style: TextStyle(fontWeight: FontWeight.w600)),
              TextSpan(text: "Remit", style: TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
        ),
        if (showTagline) ...[
          const SizedBox(height: 4),
          Text(
            "Send money, simply.",
            style: TextStyle(
              fontSize: fontSize * 0.32,
              color: AppColors.textMuted,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ],
    );
  }
}
