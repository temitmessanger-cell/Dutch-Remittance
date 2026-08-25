import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dutch_remit/components/settings_screen/app_settings.dart';
import 'package:dutch_remit/utilities/app_theme.dart';

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
            Divider(height: 1, color: AppColors.divider),
            Expanded(child: AppSettingsComponent()),
          ],
        ),
      ),
    );
  }
}
