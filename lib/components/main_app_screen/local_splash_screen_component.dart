import 'package:flutter/material.dart';
import 'package:dutch_remit/utilities/app_theme.dart';

/// Shown briefly while main.dart resolves login/onboarding state from
/// local storage — a light backdrop photo (not the solid brand-color
/// fill this used to be) so the very first frame the app ever shows
/// already looks like a real product, not a placeholder.
class LocalSplashScreenComponent extends StatelessWidget {
  const LocalSplashScreenComponent({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: AppColors.scaffold),
        Opacity(
          opacity: 0.35,
          child: Image.network(
            'https://images.unsplash.com/photo-1523482580672-f109ba8cb9be?auto=format&fit=crop&w=1200&q=60',
            fit: BoxFit.cover,
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : const SizedBox.shrink(),
            errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
          ),
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Dutch Remit",
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.primary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
