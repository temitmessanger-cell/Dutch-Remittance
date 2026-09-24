import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dutch_remit/utilities/app_theme.dart';
import 'package:dutch_remit/utilities/make_api_request.dart';

// ─────────────────────────────────────────────────────────────
// Task & Rewards Hub
// 20 pts = free virtual card + $3 top-up
// ─────────────────────────────────────────────────────────────

class RewardsHubScreen extends StatefulWidget {
  final String? userAuthKey;
  const RewardsHubScreen({Key? key, this.userAuthKey}) : super(key: key);

  @override
  State<RewardsHubScreen> createState() => _RewardsHubScreenState();
}

class _RewardsHubScreenState extends State<RewardsHubScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  bool _loading = true;
  String? _error;
  List<dynamic> _tasks = [];
  int _available = 0;
  int _totalEarned = 0;
  int _totalRedeemed = 0;
  List<dynamic> _redemptions = [];

  static const int _required = 20;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        getData(urlPath: '/api/v1/rewards/tasks', authKey: widget.userAuthKey),
        getData(urlPath: '/api/v1/rewards/redemptions', authKey: widget.userAuthKey),
      ]);
      final tasksRes = results[0];
      final redRes   = results[1];
      if (!mounted) return;
      setState(() {
        _tasks         = List.from(tasksRes['tasks'] ?? []);
        _available     = (tasksRes['points']?['available'] ?? 0) as int;
        _totalEarned   = (tasksRes['points']?['totalEarned'] ?? 0) as int;
        _totalRedeemed = (tasksRes['points']?['totalRedeemed'] ?? 0) as int;
        _redemptions   = List.from(redRes['redemptions'] ?? []);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = 'Could not load rewards. Please try again.'; _loading = false; });
    }
  }

  Future<void> _completeTask(Map task) async {
    // Open the URL first
    final url = task['url'] as String?;
    if (url != null) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      // Give them a moment to interact, then show confirm dialog
      await Future.delayed(const Duration(seconds: 1));
    }
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.lg)),
        title: Text(
          'Confirm ${task['action']}',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        content: Text(
          'Did you ${task['action'].toString().toLowerCase()} ${task['platform']} @Dutch.Inc.Platforms?',
          style: TextStyle(color: AppColors.ink.withOpacity(0.7), fontSize: 14),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not yet')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, I did! +1pt', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final res = await sendData(
      urlPath: '/api/v1/rewards/complete',
      data: {'taskId': task['id']},
      authKey: widget.userAuthKey,
    );

    if (!mounted) return;

    if (res.containsKey('apiRequestError') || res['error'] != null) {
      _showSnack(res['error']?.toString() ?? 'Could not record task.', isError: true);
    } else {
      _showSnack(res['message']?.toString() ?? '+1 point earned! 🎉');
      _load();
    }
  }

  Future<void> _redeem() async {
    if (_available < _required) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.lg)),
        title: const Text('Claim your reward', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        content: const Text(
          'Use 20 points to get a FREE virtual card topped up with \$3?\n\nYour card will be ready within 24 hours.',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Claim', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final res = await sendData(
      urlPath: '/api/v1/rewards/redeem',
      data: {},
      authKey: widget.userAuthKey,
    );
    if (!mounted) return;

    if (res.containsKey('apiRequestError') || res['error'] != null) {
      _showSnack(res['error']?.toString() ?? 'Redemption failed.', isError: true);
    } else {
      _showSnack('🎉 Redeemed! Your card will be ready within 24 hours.');
      _load();
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red.shade700 : AppColors.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text('Rewards', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
        iconTheme: IconThemeData(color: AppColors.ink),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.ink.withOpacity(0.5),
          indicatorColor: AppColors.primary,
          indicatorWeight: 2.5,
          tabs: const [
            Tab(text: 'Earn Points'),
            Tab(text: 'My Rewards'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildTasksTab(),
                    _buildRewardsTab(),
                  ],
                ),
    );
  }

  Widget _buildError() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: AppColors.ink.withOpacity(0.6))),
        const SizedBox(height: 16),
        ElevatedButton(onPressed: _load, child: const Text('Retry')),
      ],
    ),
  );

  Widget _buildTasksTab() {
    final progress = (_available / _required).clamp(0.0, 1.0);
    final platforms = ['YouTube', 'Instagram', 'TikTok'];

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Points banner ──
          _PointsBanner(
            available: _available,
            required: _required,
            progress: progress,
            onRedeem: _available >= _required ? _redeem : null,
          ),
          const SizedBox(height: 20),

          // ── Tasks grouped by platform ──
          for (final platform in platforms) ...[
            _PlatformHeader(platform: platform),
            const SizedBox(height: 8),
            ..._tasks
                .where((t) => t['platform'] == platform)
                .map((t) => _TaskCard(task: t, onTap: () => _completeTask(t)))
                .toList(),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  Widget _buildRewardsTab() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Summary ──
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadii.md),
              boxShadow: AppShadows.card,
            ),
            child: Row(
              children: [
                Expanded(child: _StatTile(label: 'Available', value: '$_available pts')),
                Container(width: 1, height: 40, color: AppColors.divider),
                Expanded(child: _StatTile(label: 'Total Earned', value: '$_totalEarned pts')),
                Container(width: 1, height: 40, color: AppColors.divider),
                Expanded(child: _StatTile(label: 'Redeemed', value: '$_totalRedeemed pts')),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Redeem card ──
          _RedeemCard(
            available: _available,
            required: _required,
            onRedeem: _available >= _required ? _redeem : null,
          ),
          const SizedBox(height: 20),

          // ── Redemption history ──
          if (_redemptions.isNotEmpty) ...[
            Text('History', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.ink)),
            const SizedBox(height: 10),
            ..._redemptions.map((r) => _RedemptionTile(redemption: r)).toList(),
          ] else
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 32),
                child: Text(
                  'No redemptions yet.\nEarn 20 points to claim your first free card!',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.ink.withOpacity(0.5), fontSize: 14),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Subwidgets
// ─────────────────────────────────────────────

class _PointsBanner extends StatelessWidget {
  final int available;
  final int required;
  final double progress;
  final VoidCallback? onRedeem;
  const _PointsBanner({required this.available, required this.required, required this.progress, this.onRedeem});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primaryLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('⭐', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Text(
                '$available / $required pts',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 22),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            onRedeem != null
                ? '🎉 You\'ve earned enough for a free card!'
                : '${required - available} more points for a free virtual card + \$3',
            style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 13),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white.withOpacity(0.25),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              minHeight: 7,
            ),
          ),
          if (onRedeem != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onRedeem,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.primary,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Claim Free Card + \$3', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlatformHeader extends StatelessWidget {
  final String platform;
  const _PlatformHeader({required this.platform});

  String get _emoji {
    if (platform == 'YouTube') return '▶️';
    if (platform == 'Instagram') return '📸';
    if (platform == 'TikTok') return '🎵';
    return '📱';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(_emoji, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 7),
        Text(
          platform,
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.ink),
        ),
      ],
    );
  }
}

class _TaskCard extends StatelessWidget {
  final Map task;
  final VoidCallback onTap;
  const _TaskCard({required this.task, required this.onTap});

  bool get _isOneTime => task['repeatable'] == false;
  bool get _completed => task['completed'] == true;
  bool get _earnedToday => task['earnedToday'] == true;
  bool get _blocked => _completed || (_isOneTime == false && _earnedToday);

  String get _statusLabel {
    if (_completed) return 'Done ✓';
    if (_earnedToday) return 'Done today ✓';
    return '+1 pt';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _blocked ? null : onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _blocked ? AppColors.scaffold : Colors.white,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: _blocked ? AppColors.divider : Colors.transparent),
          boxShadow: _blocked ? [] : AppShadows.card,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${task['action']} on ${task['platform']}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: _blocked ? AppColors.ink.withOpacity(0.4) : AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _isOneTime ? 'One-time · 1 point' : 'Daily · 1 point per day',
                    style: TextStyle(fontSize: 12, color: AppColors.ink.withOpacity(0.45)),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(
                color: _blocked
                    ? AppColors.divider
                    : AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _statusLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _blocked ? AppColors.ink.withOpacity(0.35) : AppColors.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  const _StatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.ink)),
        const SizedBox(height: 3),
        Text(label, style: TextStyle(fontSize: 11, color: AppColors.ink.withOpacity(0.5))),
      ],
    );
  }
}

class _RedeemCard extends StatelessWidget {
  final int available;
  final int required;
  final VoidCallback? onRedeem;
  const _RedeemCard({required this.available, required this.required, this.onRedeem});

  @override
  Widget build(BuildContext context) {
    final canRedeem = onRedeem != null;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: canRedeem ? AppColors.successBg : Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: canRedeem ? AppColors.success : AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('💳', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Free Virtual Card + \$3',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.ink),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: canRedeem ? AppColors.success : AppColors.divider,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$required pts',
                  style: TextStyle(
                    color: canRedeem ? Colors.white : AppColors.ink.withOpacity(0.4),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Earn $required points through social tasks and get a free virtual card loaded with \$3 — ready within 24 hours.',
            style: TextStyle(fontSize: 13, color: AppColors.ink.withOpacity(0.65)),
          ),
          if (canRedeem) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onRedeem,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Claim Now', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
          ] else ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: (available / required).clamp(0.0, 1.0),
              backgroundColor: AppColors.divider,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              minHeight: 5,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 5),
            Text(
              '$available / $required points',
              style: TextStyle(fontSize: 12, color: AppColors.ink.withOpacity(0.5)),
            ),
          ],
        ],
      ),
    );
  }
}

class _RedemptionTile extends StatelessWidget {
  final Map redemption;
  const _RedemptionTile({required this.redemption});

  @override
  Widget build(BuildContext context) {
    final status = redemption['status'] as String? ?? 'pending';
    final date = redemption['redeemed_at']?.toString().substring(0, 10) ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.md),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          const Text('💳', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Free Virtual Card + \$3', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                Text(date, style: TextStyle(fontSize: 11, color: AppColors.ink.withOpacity(0.45))),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: status == 'completed'
                  ? AppColors.successBg
                  : status == 'failed'
                      ? const Color(0xFFFFEEEE)
                      : const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              status == 'completed' ? 'Issued ✓' : status == 'failed' ? 'Failed' : 'Pending',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: status == 'completed'
                    ? AppColors.success
                    : status == 'failed'
                        ? Colors.red.shade700
                        : const Color(0xFF7A5C00),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
