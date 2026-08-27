import 'dart:async';
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

/// The professional landing screen for Dutch Remit — Cameroon's
/// biggest international remittance and cards platform, and a
/// leading platform across Africa.
///
/// Design language: a full-bleed photography hero — real cities,
/// real people across the corridors Dutch Remit serves — behind a
/// navy scrim, with a slow Ken Burns drift and a crossfading carousel
/// so the very first frame feels alive rather than a static gradient.
/// A glass "send preview" card floats on the seam between hero and
/// body: the juxtaposition of documentary photography with a crisp
/// financial data card is the signature move — it says "this product
/// connects real lives across real places," not just "fintech app."
///
/// Below the fold: a one-line manifesto set in a serif display face
/// (the one deliberate typographic risk on this screen — everywhere
/// else in the app is Manrope-only), then features, corridors, trust
/// bar and CTAs. Always shown first for both brand-new and returning
/// users — see main.dart, which routes here before login.
class OnboardingScreen extends StatefulWidget {
  /// If a user is already logged in (returning user), their data is
  /// carried through so tapping "Get started" opens the app directly
  /// instead of asking them to log in again.
  final Map<String, dynamic>? userData;

  const OnboardingScreen({Key? key, this.userData}) : super(key: key);

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final UserDeviceInfoStorage userDeviceInfoStorage = UserDeviceInfoStorage();
  bool _isContinuing = false;

  late final AnimationController _entrance;
  late final AnimationController _kenBurns;
  late final PageController _heroPageController;
  Timer? _heroTimer;
  int _heroIndex = 0;

  // Verified, hotlinkable Unsplash photography spanning the corridors
  // Dutch Remit serves — Lagos, Accra and Nairobi city life, plus the
  // original diaspora-sender shot — with graceful fallback if any URL
  // ever fails to load (see _HeroPhoto). Every URL below was fetched
  // and confirmed individually (photo page -> real images.unsplash.com
  // asset URL, all "Free to use under the Unsplash License") — the
  // three added this pass replace an earlier version that used
  // Unsplash's newer short-ID slugs directly after "photo-", which is
  // not a real CDN asset path; only the first slide's classic
  // timestamp-format ID actually resolved, which is why the carousel
  // only ever showed one photo.
  static const List<_HeroSlide> _heroSlides = [
    _HeroSlide(
      url:
          'https://images.unsplash.com/photo-1523482580672-f109ba8cb9be?auto=format&fit=crop&w=1400&q=80',
      caption: 'Wherever home is, it stays reachable.',
    ),
    _HeroSlide(
      url:
          'https://images.unsplash.com/photo-1559833064-6f4573ec1ac9?auto=format&fit=crop&w=1400&q=80',
      caption: 'Built for the cities the diaspora calls home.',
    ),
    _HeroSlide(
      url:
          'https://images.unsplash.com/photo-1741779628586-0fd1269de8cd?auto=format&fit=crop&w=1400&q=80',
      caption: 'From Accra to Lagos, money that moves like people do.',
    ),
    _HeroSlide(
      url:
          'https://images.unsplash.com/photo-1664181220731-06219378d8c7?auto=format&fit=crop&w=1400&q=80',
      caption: 'Every transfer is somebody\'s Monday made easier.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..forward();

    // Slow continuous drift/zoom on the active photo — the "Ken
    // Burns" effect that keeps the hero feeling alive without being
    // distracting. Loops forever; direction reverses each cycle.
    _kenBurns = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    )..repeat(reverse: true);

    _heroPageController = PageController();
    _heroTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      _heroIndex = (_heroIndex + 1) % _heroSlides.length;
      _heroPageController.animateToPage(
        _heroIndex,
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _entrance.dispose();
    _kenBurns.dispose();
    _heroTimer?.cancel();
    _heroPageController.dispose();
    super.dispose();
  }

  /// A staggered fade-and-rise for hero elements. `start`/`end` are
  /// fractions of the entrance timeline so elements cascade in.
  Widget _fadeSlide(Widget child, double start, double end) {
    final curved = CurvedAnimation(
      parent: _entrance,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: curved,
      builder: (context, c) => Opacity(
        opacity: curved.value,
        child: Transform.translate(
          offset: Offset(0, 18 * (1 - curved.value)),
          child: c,
        ),
      ),
      child: child,
    );
  }

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

    if (widget.userData == null) {
      try {
        final loaded = await UserDataStorage().getUserData();
        if (loaded is Map<String, dynamic> && !loaded.containsKey('localDBError')) {
          userData = loaded;
        }
      } catch (_) {}
    }

    if (!mounted) return;

    final loginData = await LoginInfoStorage().getPersistentLoginData;
    final authToken = loginData['authToken']?.toString().trim();
    final bool hasSession =
      userData.isNotEmpty && userData['email'] != null && authToken != null && authToken.isNotEmpty;
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
            builder: (context) => hasSession
                ? TabbedLayoutComponent(userData: userData)
                : LoginScreen()),
        (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    // Brand palette — deep navy hero, warm gold accent, off-white
    // surface. Kept local so this screen has its own strong visual
    // identity without disturbing the rest of the app's theme.
    const Color heroTop = Color(0xFF0A1B47);
    const Color heroBottom = Color(0xFF163172);
    const Color gold = Color(0xFFF5B841);
    const Color surface = Color(0xFFFDFBF6);
    const Color ink = Color(0xFF0F172A);
    const Color inkMuted = Color(0xFF475569);

    final screenHeight = MediaQuery.of(context).size.height;
    final heroHeight = (screenHeight * 0.62).clamp(460.0, 640.0);

    return Scaffold(
      backgroundColor: surface,
      body: SingleChildScrollView(
        child: Column(
          children: [
            // ==================== PHOTOGRAPHY HERO ====================
            SizedBox(
              height: heroHeight,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Rotating, slowly-zooming photo carousel.
                  PageView.builder(
                    controller: _heroPageController,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _heroSlides.length,
                    onPageChanged: (i) => _heroIndex = i,
                    itemBuilder: (context, i) {
                      return AnimatedBuilder(
                        animation: _kenBurns,
                        builder: (context, child) {
                          final scale = 1.05 + (_kenBurns.value * 0.07);
                          return Transform.scale(scale: scale, child: child);
                        },
                        child: _HeroPhoto(url: _heroSlides[i].url),
                      );
                    },
                  ),
                  // Navy scrim — deepens toward the bottom so the
                  // floating card and text always stay legible
                  // regardless of the photo underneath.
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xCC0A1B47),
                          Color(0x990A1B47),
                          Color(0xE60A1B47),
                          Color(0xFF0A1B47),
                        ],
                        stops: [0.0, 0.35, 0.8, 1.0],
                      ),
                    ),
                  ),
                  SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // -- Top bar: wordmark + tiny country pill --
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: gold,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text('D',
                                        style: GoogleFonts.manrope(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w800,
                                            color: heroTop)),
                                  ),
                                  const SizedBox(width: 10),
                                  Text('Dutch Remit',
                                      style: GoogleFonts.manrope(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white)),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.10),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color: Colors.white.withOpacity(0.15)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text('🇨🇲', style: TextStyle(fontSize: 14)),
                                    const SizedBox(width: 6),
                                    Text('Cameroon',
                                        style: GoogleFonts.manrope(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 30),

                          // -- Eyebrow --
                          _fadeSlide(
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: gold.withOpacity(0.16),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'CAMEROON\'S #1 · AFRICA\'S LEADING PLATFORM',
                                style: GoogleFonts.manrope(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.8,
                                    color: gold),
                              ),
                            ),
                            0.0,
                            0.4,
                          ),
                          const SizedBox(height: 18),

                          // -- Headline --
                          _fadeSlide(
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: 'Send money home.\n',
                                    style: GoogleFonts.manrope(
                                        fontSize: 32,
                                        fontWeight: FontWeight.w800,
                                        height: 1.12,
                                        color: Colors.white),
                                  ),
                                  TextSpan(
                                    text: 'Spend anywhere.',
                                    style: GoogleFonts.manrope(
                                        fontSize: 32,
                                        fontWeight: FontWeight.w800,
                                        height: 1.12,
                                        color: gold),
                                  ),
                                ],
                              ),
                            ),
                            0.12,
                            0.55,
                          ),
                          const SizedBox(height: 12),

                          // -- Rotating caption tied to active photo --
                          _fadeSlide(
                            SizedBox(
                              height: 20,
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 500),
                                child: Text(
                                  _heroSlides[_heroIndex].caption,
                                  key: ValueKey(_heroIndex),
                                  style: GoogleFonts.manrope(
                                      fontSize: 13.5,
                                      fontStyle: FontStyle.italic,
                                      color: Colors.white.withOpacity(0.78)),
                                ),
                              ),
                            ),
                            0.24,
                            0.65,
                          ),
                          const SizedBox(height: 22),

                          // -- Primary CTA --
                          _fadeSlide(
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _isContinuing ? null : _startSending,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: gold,
                                  foregroundColor: heroTop,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(vertical: 18),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14)),
                                ),
                                child: _isContinuing
                                    ? SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2.6, color: heroTop),
                                      )
                                    : Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text('Get started',
                                              style: GoogleFonts.manrope(
                                                  fontSize: 16.5,
                                                  fontWeight: FontWeight.w800,
                                                  color: heroTop)),
                                          const SizedBox(width: 8),
                                          Icon(Icons.arrow_forward_rounded,
                                              color: heroTop, size: 20),
                                        ],
                                      ),
                              ),
                            ),
                            0.36,
                            0.8,
                          ),
                          const SizedBox(height: 10),
                          Center(
                            child: TextButton(
                              onPressed: _getDocs,
                              style: TextButton.styleFrom(
                                  foregroundColor: Colors.white.withOpacity(0.85)),
                              child: Text('How it works',
                                  style: GoogleFonts.manrope(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      decoration: TextDecoration.underline)),
                            ),
                          ),
                          const SizedBox(height: 6),

                          // -- Carousel dots --
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              _heroSlides.length,
                              (i) => AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                margin: const EdgeInsets.symmetric(horizontal: 3),
                                width: i == _heroIndex ? 18 : 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: i == _heroIndex
                                      ? gold
                                      : Colors.white.withOpacity(0.35),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ==================== SEND PREVIEW CARD ====================
            // Sits on the seam between hero and body — the visual
            // centerpiece, showing what the product actually does.
            _fadeSlide(
              Transform.translate(
                offset: const Offset(0, -28),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _SendPreviewCard(
                      heroTop: heroTop, gold: gold, ink: ink, inkMuted: inkMuted),
                ),
              ),
              0.5,
              1.0,
            ),

            // ==================== MANIFESTO ====================
            // The one deliberate typographic risk on this screen — a
            // serif display line, set apart from the Manrope-only
            // voice everywhere else, giving the product a moment of
            // conviction rather than another feature callout.
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 8, 28, 4),
              child: Text(
                '"Distance was never the problem. The banks were."',
                textAlign: TextAlign.center,
                style: GoogleFonts.playfairDisplay(
                  fontSize: 21,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                  color: heroTop,
                ),
              ),
            ),
            const SizedBox(height: 28),

            // ==================== CARD SHOWCASE ====================
            // A dedicated hero moment for the physical/virtual card
            // product — distinct from the small credit-card icon in
            // the feature list below, and from the functional card
            // rendered on the Wallet screen (wallet_screen.dart's
            // _buildCardVisual, which shows a real linked card's
            // masked number and fetched brand logo). This is a
            // marketing showpiece: same brand language (navy,
            // "DR" monogram, gold accents) as the real card, with a
            // subtle 3D tilt and layered shadow so it reads as a
            // tangible object, not a flat icon.
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Your card, wherever you spend',
                      style: GoogleFonts.manrope(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: ink)),
                  const SizedBox(height: 4),
                  Text(
                      'A virtual USD Dutch Remit card, funded straight from your wallet — created in seconds, spendable anywhere.',
                      style: GoogleFonts.manrope(
                          fontSize: 14, height: 1.5, color: inkMuted)),
                  const SizedBox(height: 22),
                  Center(
                    child: _fadeSlide(
                      _DutchRemitCardMockup(
                          heroTop: heroTop, heroBottom: heroBottom, gold: gold),
                      0.55,
                      1.0,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 36),

            // ==================== FEATURES ====================
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Everything you need',
                      style: GoogleFonts.manrope(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: ink)),
                  const SizedBox(height: 4),
                  Text(
                      'Two products, one wallet — remittances that land in minutes, cards that work anywhere.',
                      style: GoogleFonts.manrope(
                          fontSize: 14, height: 1.5, color: inkMuted)),
                  const SizedBox(height: 20),
                  _FeatureRow(
                    icon: Icons.send_rounded,
                    accent: heroBottom,
                    title: 'Instant remittances',
                    subtitle:
                        'Mobile money and bank transfers across Africa — Cameroon, Nigeria, Kenya and more, in minutes not days.',
                  ),
                  const SizedBox(height: 14),
                  _FeatureRow(
                    icon: Icons.credit_card_rounded,
                    accent: gold,
                    title: 'Virtual USD cards',
                    subtitle:
                        'Spend online anywhere Visa or Mastercard is accepted — Netflix, Amazon, ads, hosting — all funded from your wallet.',
                  ),
                  const SizedBox(height: 14),
                  _FeatureRow(
                    icon: Icons.currency_exchange_rounded,
                    accent: Color(0xFF1FB17A),
                    title: 'Fair exchange rates',
                    subtitle:
                        'Live mid-market rates with a transparent margin — no hidden markup buried in the FX like banks do.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),

            // ==================== CORRIDORS ====================
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                            color: Color(0xFF1FB17A), shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Text('LIVE CORRIDORS',
                          style: GoogleFonts.manrope(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                              color: const Color(0xFF1FB17A))),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text('Send across Africa and beyond',
                      style: GoogleFonts.manrope(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: ink)),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: const [
                      _CountryChip(flag: '🇨🇲', code: 'CM', name: 'Cameroon', highlighted: true),
                      _CountryChip(flag: '🇳🇬', code: 'NG', name: 'Nigeria'),
                      _CountryChip(flag: '🇰🇪', code: 'KE', name: 'Kenya'),
                      _CountryChip(flag: '🇬🇭', code: 'GH', name: 'Ghana'),
                      _CountryChip(flag: '🇷🇼', code: 'RW', name: 'Rwanda'),
                      _CountryChip(flag: '🇺🇬', code: 'UG', name: 'Uganda'),
                      _CountryChip(flag: '🇹🇿', code: 'TZ', name: 'Tanzania'),
                      _CountryChip(flag: '🇿🇲', code: 'ZM', name: 'Zambia'),
                      _CountryChip(flag: '🇸🇳', code: 'SN', name: 'Senegal'),
                      _CountryChip(flag: '🇨🇮', code: 'CI', name: "Côte d'Ivoire"),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // ==================== TRUST BAR ====================
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              color: const Color(0xFFF1F5F9),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _StatTile(value: '20+', label: 'Currencies', color: heroBottom),
                      Container(width: 1, height: 40, color: const Color(0xFFCBD5E1)),
                      _StatTile(value: '120+', label: 'Countries', color: heroBottom),
                      Container(width: 1, height: 40, color: const Color(0xFFCBD5E1)),
                      _StatTile(value: '<5m', label: 'Avg. delivery', color: heroBottom),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock_rounded, size: 14, color: inkMuted),
                      const SizedBox(width: 6),
                      Text('Bank-grade security · Licensed partners',
                          style: GoogleFonts.manrope(
                              fontSize: 12, color: inkMuted, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ==================== SECONDARY CTA ====================
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _isContinuing ? null : _startSending,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: heroTop,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: BorderSide(color: heroTop, width: 1.5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text('Create your free account',
                      style: GoogleFonts.manrope(
                          fontSize: 15.5, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single hero photo slide: url + the caption shown while it's active.
class _HeroSlide {
  final String url;
  final String caption;
  const _HeroSlide({required this.url, required this.caption});
}

/// Renders one hero photo with a loading shimmer and a graceful
/// gradient fallback if the network image ever fails — the hero must
/// never show a broken-image icon or blank white frame.
class _HeroPhoto extends StatelessWidget {
  final String url;
  const _HeroPhoto({required this.url});

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return const DecoratedBox(
          decoration: BoxDecoration(color: Color(0xFF0A1B47)),
        );
      },
      errorBuilder: (context, error, stackTrace) => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0A1B47), Color(0xFF163172)],
          ),
        ),
      ),
    );
  }
}

class _AmountRow extends StatelessWidget {
  final String label;
  final String amount;
  final String currency;
  final String flag;
  final Color ink;
  final Color inkMuted;

  const _AmountRow(
      {required this.label,
      required this.amount,
      required this.currency,
      required this.flag,
      required this.ink,
      required this.inkMuted});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: GoogleFonts.manrope(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: inkMuted)),
              const SizedBox(height: 4),
              Text(amount,
                  style: GoogleFonts.manrope(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: ink,
                      height: 1.1)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(flag, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Text(currency,
                  style: GoogleFonts.manrope(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: ink)),
            ],
          ),
        ),
      ],
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;

  const _FeatureRow(
      {required this.icon,
      required this.accent,
      required this.title,
      required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accent, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.manrope(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A))),
                const SizedBox(height: 4),
                Text(subtitle,
                    style: GoogleFonts.manrope(
                        fontSize: 13,
                        height: 1.45,
                        color: const Color(0xFF475569))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CountryChip extends StatelessWidget {
  final String flag;
  final String code;
  final String name;
  final bool highlighted;
  const _CountryChip(
      {required this.flag,
      required this.code,
      required this.name,
      this.highlighted = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: highlighted ? const Color(0xFF163172) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
            color: highlighted
                ? const Color(0xFF163172)
                : const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(flag, style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 8),
          Text(name,
              style: GoogleFonts.manrope(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: highlighted
                      ? Colors.white
                      : const Color(0xFF0F172A))),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const _StatTile(
      {required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: GoogleFonts.manrope(
                fontSize: 22, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 2),
        Text(label,
            style: GoogleFonts.manrope(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF475569))),
      ],
    );
  }
}

/// The product-preview card that anchors the whole screen: shows a
/// mock "You send 100 USD → They receive 62,650 XAF" transfer, so a
/// first-time visitor immediately sees what the product does.
/// A marketing-grade mockup of the Dutch Remit virtual USD card —
/// same brand language as the real card rendered on the Wallet
/// screen (navy body, "DR" monogram, gold accents), but built as a
/// hero showpiece: a slight 3D tilt via Transform, a soft chip
/// graphic, a realistic masked card number, and a two-layer shadow
/// (a tight dark shadow plus a wider gold glow) so it reads as a
/// tangible object sitting above the page rather than a flat icon.
/// Uses placeholder digits and a generic "VISA"-style wordmark since
/// this screen is shown before any account exists — never a real
/// card number.
class _DutchRemitCardMockup extends StatelessWidget {
  final Color heroTop;
  final Color heroBottom;
  final Color gold;

  const _DutchRemitCardMockup(
      {required this.heroTop, required this.heroBottom, required this.gold});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.045,
      child: Container(
        width: 320,
        height: 200,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [heroTop, heroBottom],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            // Wide, soft gold glow — the "premium object" cue.
            BoxShadow(
              color: gold.withOpacity(0.28),
              blurRadius: 46,
              offset: const Offset(0, 22),
              spreadRadius: -6,
            ),
            // Tight, dark contact shadow so the card feels grounded.
            BoxShadow(
              color: heroTop.withOpacity(0.35),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Faint diagonal sheen — a subtle highlight suggesting a
            // glossy/metallic card surface without needing an image.
            Positioned(
              top: -40,
              right: -60,
              child: Transform.rotate(
                angle: -0.5,
                child: Container(
                  width: 180,
                  height: 260,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withOpacity(0.10),
                        Colors.white.withOpacity(0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: gold,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          alignment: Alignment.center,
                          child: Text('D',
                              style: GoogleFonts.manrope(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: heroTop)),
                        ),
                        const SizedBox(width: 9),
                        Text('Dutch Remit',
                            style: GoogleFonts.manrope(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                      ],
                    ),
                    Text('USD',
                        style: GoogleFonts.manrope(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                            color: Colors.white.withOpacity(0.65))),
                  ],
                ),
                const SizedBox(height: 18),
                // Chip graphic — a small rounded-rect with etched
                // lines, evoking an EMV chip without needing an asset.
                Container(
                  width: 40,
                  height: 30,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [gold.withOpacity(0.9), gold.withOpacity(0.55)],
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(height: 1, color: heroTop.withOpacity(0.3)),
                      const SizedBox(height: 6),
                      Container(height: 1, color: heroTop.withOpacity(0.3)),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text('•••• •••• •••• 4471',
                    style: GoogleFonts.manrope(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 2.2,
                        color: Colors.white)),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('DUTCH REMIT USER',
                        style: GoogleFonts.manrope(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: Colors.white.withOpacity(0.75))),
                    // A generic scheme wordmark rather than a real
                    // Visa/Mastercard logo asset — this screen has no
                    // linked card yet, so nothing brand-specific to
                    // fetch (contrast wallet_screen.dart, which pulls
                    // the real card's brand PNG for an actual card).
                    Text('VISA',
                        style: GoogleFonts.manrope(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            fontStyle: FontStyle.italic,
                            letterSpacing: 0.5,
                            color: Colors.white.withOpacity(0.9))),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SendPreviewCard extends StatelessWidget {
  final Color heroTop;
  final Color gold;
  final Color ink;
  final Color inkMuted;

  const _SendPreviewCard(
      {required this.heroTop,
      required this.gold,
      required this.ink,
      required this.inkMuted});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: heroTop.withOpacity(0.16),
            blurRadius: 34,
            offset: const Offset(0, 14),
          ),
        ],
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                          color: Color(0xFF1FB17A), shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text('LIVE RATE',
                        style: GoogleFonts.manrope(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            color: const Color(0xFF1FB17A))),
                  ],
                ),
              ),
              const Spacer(),
              Text('Preview',
                  style: GoogleFonts.manrope(
                      fontSize: 11, fontWeight: FontWeight.w600, color: inkMuted)),
            ],
          ),
          const SizedBox(height: 18),
          _AmountRow(
            label: 'You send',
            amount: '100.00',
            currency: 'USD',
            flag: '🇺🇸',
            ink: ink,
            inkMuted: inkMuted,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Expanded(child: Container(height: 1, color: const Color(0xFFE2E8F0))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: heroTop,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.arrow_downward_rounded,
                        size: 14, color: Colors.white),
                  ),
                ),
                Expanded(child: Container(height: 1, color: const Color(0xFFE2E8F0))),
              ],
            ),
          ),
          _AmountRow(
            label: 'They receive',
            amount: '62,650',
            currency: 'XAF',
            flag: '🇨🇲',
            ink: ink,
            inkMuted: inkMuted,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.bolt_rounded, size: 16, color: gold),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Arrives in under 5 minutes · Mobile money',
                      style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: inkMuted)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
