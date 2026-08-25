import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:dutch_remit/database/hadwin_user_device_info_storage.dart';
import 'package:dutch_remit/database/login_info_storage.dart';
import 'package:dutch_remit/database/user_data_storage.dart';
import 'package:dutch_remit/components/main_app_screen/tabbed_layout_component.dart';
import 'package:dutch_remit/screens/login_screen.dart';
import 'package:dutch_remit/utilities/app_theme.dart';
import 'package:dutch_remit/utilities/hadwin_markdown_viewer.dart';
import 'package:dutch_remit/utilities/legal_documents.dart';
import 'package:dutch_remit/utilities/slide_right_route.dart';

/// The app's onboarding / landing screen — a single, clean marketing
/// screen (not a multi-page swiper) matching the reference design: a
/// light background with a faint backdrop image, a live-rates badge,
/// the "Send Money Across Africa, Simply." headline, a short pitch,
/// a "Start sending" CTA, and a trio of trust icons.
///
/// This is always shown first, for both brand-new and returning
/// users — see main.dart, which now routes here before deciding
/// whether to continue on to login or straight into the app.
class OnboardingScreen extends StatefulWidget {
  /// If a user is already logged in (returning user), their data is
  /// carried through so tapping "Start sending" opens the main app
  /// directly instead of asking them to log in again. Null means
  /// there's no signed-in session yet.
  final Map<String, dynamic>? userData;

  const OnboardingScreen({Key? key, this.userData}) : super(key: key);

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final UserDeviceInfoStorage userDeviceInfoStorage = UserDeviceInfoStorage();
  bool _isContinuing = false;

  void _getDocs() {
    Navigator.push(
        context,
        SlideRightRoute(
            page: DutchRemitMarkdownViewer(
                screenName: 'Getting Started',
                content: kGettingStartedGuide)));
  }

  Future<void> _startSending() async {
    setState(() => _isContinuing = true);
    bool isSaved = await userDeviceInfoStorage.initializeInstallationStatus();
    if (!isSaved) {
      if (mounted) setState(() => _isContinuing = false);
      return;
    }

    Map<String, dynamic> userData = widget.userData ?? {};

    // No session was handed in — check local storage for a saved
    // session before falling back to the login screen.
    if (widget.userData == null) {
      try {
        final loaded = await UserDataStorage().getUserData();
        if (loaded is Map<String, dynamic> && !loaded.containsKey('localDBError')) {
          userData = loaded;
        }
      } catch (_) {}
    }

    if (!mounted) return;

    final bool hasSession = userData.isNotEmpty && userData['email'] != null;
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
            builder: (context) => hasSession
                ? TabbedLayoutComponent(userData: userData)
                : LoginScreen()),
        (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // A light, faint backdrop image — present but never
          // overpowering the text on top of it.
          Opacity(
            opacity: 0.18,
            child: ColorFiltered(
              colorFilter: ColorFilter.mode(AppColors.primary, BlendMode.color),
              child: Image.network(
                'https://images.unsplash.com/photo-1523482580672-f109ba8cb9be?auto=format&fit=crop&w=1200&q=60',
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : const SizedBox.shrink(),
                errorBuilder: (context, error, stackTrace) =>
                    const SizedBox.shrink(),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                    decoration: BoxDecoration(
                      color: AppColors.successBg,
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                            width: 8, height: 8,
                            decoration: BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
                        const SizedBox(width: 10),
                        Text("Live exchange rates · 40+ African currencies",
                            style: GoogleFonts.manrope(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.success)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                            text: "Send Money\nAcross\nAfrica, ",
                            style: GoogleFonts.manrope(
                                fontSize: 42,
                                fontWeight: FontWeight.w800,
                                height: 1.08,
                                color: AppColors.ink)),
                        TextSpan(
                            text: "Simply.",
                            style: GoogleFonts.manrope(
                                fontSize: 42,
                                fontWeight: FontWeight.w800,
                                height: 1.08,
                                color: AppColors.success)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    "Convert and transfer African currencies using trusted local payment methods — mobile money and bank transfer, all in one place.",
                    style: GoogleFonts.manrope(
                        fontSize: 16, height: 1.5, color: AppColors.inkMuted),
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isContinuing ? null : _startSending,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadii.lg)),
                      ),
                      child: _isContinuing
                          ? SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text("Start sending",
                                    style: GoogleFonts.manrope(
                                        fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
                                const SizedBox(width: 8),
                                Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  InkWell(
                    onTap: _getDocs,
                    child: Text(
                      "How it works",
                      style: GoogleFonts.manrope(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                          decoration: TextDecoration.underline),
                    ),
                  ),
                  const SizedBox(height: 30),
                  Row(
                    children: [
                      Expanded(
                          child: _trustIcon(Icons.shield_outlined, "Bank-grade\nsecurity")),
                      Expanded(
                          child: _trustIcon(Icons.bolt_rounded, "Fast\ntransfers")),
                      Expanded(
                          child: _trustIcon(Icons.lock_outline_rounded, "Transparent\nfees")),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _trustIcon(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.success),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label,
              style: GoogleFonts.manrope(fontSize: 12.5, color: AppColors.inkMuted, height: 1.25)),
        ),
      ],
    );
  }
}
