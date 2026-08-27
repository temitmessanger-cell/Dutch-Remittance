import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dutch_remit/components/settings_screen/app_settings.dart';
import 'package:dutch_remit/screens/rewards_hub_screen.dart';
import 'package:dutch_remit/utilities/app_theme.dart';
import 'package:dutch_remit/utilities/slide_right_route.dart';

/// The Profile/Settings bottom-nav tab. Replaces the old gear icon that
/// used to live inside the Cards screen's app bar — settings deserve
/// their own home rather than being tucked away on an unrelated screen.
class ProfileSettingsTabScreen extends StatelessWidget {
  final Map<String, dynamic> user;
  const ProfileSettingsTabScreen({Key? key, required this.user}) : super(key: key);

  String _displayName() {
    final first = user['first_name']?.toString().trim() ?? '';
    final last = user['last_name']?.toString().trim() ?? '';
    final full = '$first $last'.trim();
    if (full.isNotEmpty) return full;
    if (user.isEmpty) return 'Guest';
    return user['username']?.toString() ?? 'Guest';
  }

  String _initial() {
    final name = _displayName();
    return name.isNotEmpty ? name[0].toUpperCase() : 'G';
  }

  bool get _isGuest => user.isEmpty;

  void _copyDutchRemitId(BuildContext context, String id) {
    Clipboard.setData(ClipboardData(text: id));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Dutch Remit ID copied"), backgroundColor: AppColors.success),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        title: Text("Profile",
            style: TextStyle(
                color: AppColors.ink, fontSize: 19, fontWeight: FontWeight.w700)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: AppColors.primary.withOpacity(0.1),
                    child: Text(
                      _initial(),
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _displayName(),
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _isGuest
                              ? "Browsing as a guest"
                              : (user['email']?.toString() ?? ''),
                          style: TextStyle(
                              fontSize: 13, color: AppColors.textMuted),
                        ),
                        if (!_isGuest && user['dutchRemitId'] != null) ...[
                          const SizedBox(height: 4),
                          InkWell(
                            onTap: () => _copyDutchRemitId(context, user['dutchRemitId'].toString()),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(user['dutchRemitId'].toString(),
                                    style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.primary)),
                                const SizedBox(width: 4),
                                Icon(Icons.copy_rounded, size: 13, color: AppColors.primary),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (_isGuest)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(AppRadii.md),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 18, color: AppColors.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          "Create an account to save your data and send real transfers.",
                          style: TextStyle(
                              fontSize: 13, color: AppColors.inkMuted, height: 1.3),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: _RewardsHubCard(
                onTap: () => Navigator.push(
                    context, SlideRightRoute(page: const RewardsHubScreen())),
              ),
            ),
            Divider(height: 1, color: AppColors.divider),
            Expanded(child: AppSettingsComponent()),
          ],
        ),
      ),
    );
  }
}

/// Entry point into the Tasks & Rewards hub — a gold-accented card
/// styled to stand apart from the plain settings list below it, since
/// it leads somewhere with visual identity of its own rather than a
/// static settings page.
class _RewardsHubCard extends StatelessWidget {
  final VoidCallback onTap;
  const _RewardsHubCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primary, AppColors.primaryDark],
          ),
          borderRadius: BorderRadius.circular(AppRadii.lg),
          boxShadow: AppShadows.card,
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.card_giftcard_rounded,
                  color: Color(0xFFF5B841), size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tasks & Rewards',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  const SizedBox(height: 2),
                  Text('Complete tasks, earn coupons and fee discounts',
                      style: TextStyle(
                          fontSize: 12.5, color: Colors.white.withOpacity(0.75))),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Colors.white.withOpacity(0.7)),
          ],
        ),
      ),
    );
  }
}
