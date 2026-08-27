import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dutch_remit/utilities/app_theme.dart';
import 'package:dutch_remit/utilities/url_external_launcher.dart';

/// The message shared across every invite channel — kept in one place
/// so SMS, WhatsApp, Telegram, Facebook, and the copy-link fallback
/// all say exactly the same thing.
const String _kInviteMessage =
    "I'm on Dutch Remit — Cameroon's biggest cross-border remittance platform. "
    "Join me and let's send money simply: https://dutchremit.app";
const String _kInviteUrl = 'https://dutchremit.app';

/// Shows the "Invite to Dutch Remit" picker: lets the person choose
/// which app to share their invite through, rather than jumping
/// straight into a single SMS deep-link (the old behavior). Each
/// option opens the real platform's own share/compose flow.
void showInviteToDutchRemitSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.white,
    shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg))),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Invite to Dutch Remit",
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.ink)),
            const SizedBox(height: 4),
            Text("Choose how you'd like to share your invite.",
                style: TextStyle(fontSize: 13, color: AppColors.inkMuted)),
            const SizedBox(height: 18),
            Wrap(
              spacing: 14,
              runSpacing: 16,
              children: [
                _InviteOption(
                  icon: Icons.sms_rounded,
                  label: "Messages",
                  color: Color(0xFF34C759),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    launchExternalURL("sms:?body=${Uri.encodeComponent(_kInviteMessage)}");
                  },
                ),
                _InviteOption(
                  icon: Icons.chat_rounded,
                  label: "WhatsApp",
                  color: Color(0xFF25D366),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    launchExternalURL(
                        "https://wa.me/?text=${Uri.encodeComponent(_kInviteMessage)}");
                  },
                ),
                _InviteOption(
                  icon: Icons.facebook_rounded,
                  label: "Facebook",
                  color: Color(0xFF1877F2),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    launchExternalURL(
                        "https://www.facebook.com/sharer/sharer.php?u=${Uri.encodeComponent(_kInviteUrl)}");
                  },
                ),
                _InviteOption(
                  icon: Icons.send_rounded,
                  label: "Telegram",
                  color: Color(0xFF229ED9),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    launchExternalURL(
                        "https://t.me/share/url?url=${Uri.encodeComponent(_kInviteUrl)}&text=${Uri.encodeComponent(_kInviteMessage)}");
                  },
                ),
                _InviteOption(
                  icon: Icons.mail_rounded,
                  label: "Email",
                  color: AppColors.primary,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    launchExternalURL(
                        "mailto:?subject=${Uri.encodeComponent('Join me on Dutch Remit')}&body=${Uri.encodeComponent(_kInviteMessage)}");
                  },
                ),
                _InviteOption(
                  icon: Icons.link_rounded,
                  label: "Copy link",
                  color: AppColors.inkMuted,
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: _kInviteMessage));
                    Navigator.of(sheetContext).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text("Invite link copied"),
                          backgroundColor: AppColors.success),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 13, color: AppColors.textMuted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    "Any other app on your phone can also be used to share this link — try Copy link, then paste it anywhere.",
                    style: TextStyle(fontSize: 11.5, color: AppColors.textMuted, height: 1.4),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _InviteOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _InviteOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 6),
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.ink)),
          ],
        ),
      ),
    );
  }
}
