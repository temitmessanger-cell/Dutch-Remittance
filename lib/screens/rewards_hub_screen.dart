import 'package:flutter/material.dart';
import 'package:dutch_remit/database/rewards_storage.dart';
import 'package:dutch_remit/utilities/app_theme.dart';

/// The Task & Rewards hub, reached from the Profile screen. Three
/// upper tabs — Tasks, Pending, Rewards — each with its own honest
/// empty state ("No tasks available yet") since nothing is wired to
/// a live rewards backend yet. On first entry ever, a popup explains
/// what the hub is for and what kinds of rewards to expect (coupons,
/// discounts, free cards, fee reductions or waivers, and occasionally
/// cash) so an empty screen still reads as intentional, not broken.
class RewardsHubScreen extends StatefulWidget {
  const RewardsHubScreen({Key? key}) : super(key: key);

  @override
  State<RewardsHubScreen> createState() => _RewardsHubScreenState();
}

class _RewardsHubScreenState extends State<RewardsHubScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final RewardsStorage _rewardsStorage = RewardsStorage();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowExplainer());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _maybeShowExplainer() async {
    final seen = await _rewardsStorage.hasSeenExplainer;
    if (!seen && mounted) {
      _showExplainer();
    }
  }

  void _showExplainer() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.lg)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.warningBg,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(Icons.card_giftcard_rounded,
                    color: AppColors.warning, size: 28),
              ),
              const SizedBox(height: 16),
              Text(
                'Tasks & Rewards',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                'Complete simple tasks — like your first transfer, verifying your account, or inviting friends — and earn rewards.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, height: 1.5, color: AppColors.inkMuted),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Rewards can include:',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink)),
              ),
              const SizedBox(height: 8),
              _explainerBullet('Coupons and discount codes'),
              _explainerBullet('Free virtual cards'),
              _explainerBullet('Reduced or waived transfer fees'),
              _explainerBullet('Occasional cash rewards'),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    _rewardsStorage.markExplainerSeen();
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadii.md)),
                  ),
                  child: Text('Got it', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _explainerBullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                  color: AppColors.warning, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 13, color: AppColors.inkMuted, height: 1.4)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Tasks & Rewards',
            style: TextStyle(
                color: AppColors.ink, fontSize: 19, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: Icon(Icons.info_outline_rounded, color: AppColors.textMuted),
            onPressed: _showExplainer,
            tooltip: 'What is this?',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textMuted,
              indicatorColor: AppColors.primary,
              indicatorWeight: 2.5,
              labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              unselectedLabelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              tabs: const [
                Tab(text: 'Tasks'),
                Tab(text: 'Pending'),
                Tab(text: 'Rewards'),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _EmptyTabState(
            icon: Icons.checklist_rounded,
            iconBg: AppColors.primary.withOpacity(0.08),
            iconColor: AppColors.primary,
            title: 'No tasks available yet',
            subtitle:
                'New tasks — like completing your first transfer or verifying your account — will show up here as they become available.',
          ),
          _EmptyTabState(
            icon: Icons.hourglass_empty_rounded,
            iconBg: AppColors.warningBg,
            iconColor: AppColors.warning,
            title: 'Nothing pending',
            subtitle:
                'Tasks you\'ve started but not yet completed will appear here while they\'re being reviewed.',
          ),
          _EmptyTabState(
            icon: Icons.card_giftcard_rounded,
            iconBg: AppColors.successBg,
            iconColor: AppColors.success,
            title: 'No rewards available yet',
            subtitle:
                'Coupons, fee discounts, free cards and other rewards you\'ve earned will be collected here.',
          ),
        ],
      ),
    );
  }
}

class _EmptyTabState extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;

  const _EmptyTabState({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Icon(icon, color: iconColor, size: 32),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, height: 1.5, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
