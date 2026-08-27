import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dutch_remit/utilities/app_theme.dart';
import 'package:dutch_remit/utilities/url_external_launcher.dart';

/// Every invite link points at the app's real production domain
/// (dutchremit.dubiabank.com — confirmed against web_final/web/index.html's
/// canonical/og:url tags and netlify.toml). The previous version
/// pointed at "dutchremit.app", a domain never registered or
/// deployed anywhere in this project — every invite sent through it
/// went nowhere.
const String _kInviteDomain = 'https://dutchremit.dubiabank.com';

/// Builds the referral URL and share message for a given inviter.
/// [referralCode] is the inviter's own Dutch Remit ID
/// (`user['dutchRemitId']`, shaped server-side in
/// Backend/src/routes/auth.js's shapeUser() as `DR-XXXXXXXX`, unique
/// per user, already generated for every account — see
/// generate_dutch_remit_id() in supabase/schema.sql). Passed as a
/// `?ref=` query param, which Netlify's redirect rules
/// (web_final/web/netlify.toml) pass through untouched to index.html,
/// so a future signup flow can read `ref` from the URL and credit the
/// right inviter — the query param is real and correctly formed even
/// though no backend endpoint consumes it yet (there's no referral
/// -tracking route in this backend as of this pass); nothing here
/// invents fake tracking that silently does nothing.
String _inviteUrlFor(String? referralCode) {
  if (referralCode == null || referralCode.trim().isEmpty) return _kInviteDomain;
  return '$_kInviteDomain?ref=${Uri.encodeComponent(referralCode.trim())}';
}

String _inviteMessageFor(String? referralCode) {
  final url = _inviteUrlFor(referralCode);
  return "I'm on Dutch Remit — Cameroon's biggest cross-border remittance platform. "
      "Join me and let's send money simply: $url";
}

/// Shows the "Invite to Dutch Remit" picker: lets the person choose
/// which app to share their invite through. [user] should be the
/// signed-in user's map (carrying `dutchRemitId`) so the invite link
/// includes their real referral code — pass null/omit if inviting as
/// a guest, in which case the link still works, just without a
/// tracked referral.
void showInviteToDutchRemitSheet(BuildContext context, {Map<String, dynamic>? user}) {
  final referralCode = user?['dutchRemitId']?.toString() ?? user?['dutch_remit_id']?.toString();
  final inviteUrl = _inviteUrlFor(referralCode);
  final inviteMessage = _inviteMessageFor(referralCode);

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
            Text(
              referralCode != null
                  ? "Your invite code: $referralCode — choose how you'd like to share it."
                  : "Choose how you'd like to share your invite.",
              style: TextStyle(fontSize: 13, color: AppColors.inkMuted),
            ),
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
                    launchExternalURL("sms:?body=${Uri.encodeComponent(inviteMessage)}");
                  },
                ),
                _InviteOption(
                  icon: Icons.chat_rounded,
                  label: "WhatsApp",
                  color: Color(0xFF25D366),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    launchExternalURL(
                        "https://wa.me/?text=${Uri.encodeComponent(inviteMessage)}");
                  },
                ),
                _InviteOption(
                  icon: Icons.facebook_rounded,
                  label: "Facebook",
                  color: Color(0xFF1877F2),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    launchExternalURL(
                        "https://www.facebook.com/sharer/sharer.php?u=${Uri.encodeComponent(inviteUrl)}");
                  },
                ),
                _InviteOption(
                  icon: Icons.send_rounded,
                  label: "Telegram",
                  color: Color(0xFF229ED9),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    launchExternalURL(
                        "https://t.me/share/url?url=${Uri.encodeComponent(inviteUrl)}&text=${Uri.encodeComponent(inviteMessage)}");
                  },
                ),
                _InviteOption(
                  // X (formerly Twitter)'s share intent — confirmed
                  // real, working endpoint: x.com/intent/post (the
                  // renamed successor to twitter.com/intent/tweet,
                  // both still live). Opens X's own compose screen
                  // pre-filled with the message.
                  icon: Icons.alternate_email_rounded,
                  label: "X",
                  color: Colors.black,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    launchExternalURL(
                        "https://x.com/intent/post?text=${Uri.encodeComponent(inviteMessage)}");
                  },
                ),
                _InviteOption(
                  // Instagram has no web share-intent URL that accepts
                  // pre-filled text the way X/Facebook/Telegram do —
                  // their app deliberately doesn't support it. The
                  // honest, actually-working option is to copy the
                  // message and open Instagram directly so the person
                  // can paste it into a DM, Story, or bio link
                  // themselves, rather than link to something that
                  // silently drops the message.
                  icon: Icons.camera_alt_rounded,
                  label: "Instagram",
                  color: Color(0xFFE1306C),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: inviteMessage));
                    Navigator.of(sheetContext).pop();
                    launchExternalURL("https://www.instagram.com/");
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text("Invite copied — paste it in Instagram"),
                          backgroundColor: AppColors.success),
                    );
                  },
                ),
                _InviteOption(
                  // Messenger's real share endpoint requires a
                  // registered Facebook App ID to open with pre-filled
                  // text (m.me/share doesn't accept a text param the
                  // way WhatsApp/Telegram do) — without one, the
                  // honest working option is the same
                  // copy-then-open-the-app pattern as Instagram, never
                  // a link that looks like it should pre-fill but
                  // silently won't.
                  icon: Icons.messenger_outline_rounded,
                  label: "Messenger",
                  color: Color(0xFF00B2FF),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: inviteMessage));
                    Navigator.of(sheetContext).pop();
                    launchExternalURL("https://www.messenger.com/");
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text("Invite copied — paste it in Messenger"),
                          backgroundColor: AppColors.success),
                    );
                  },
                ),
                _InviteOption(
                  // TikTok has no public share-intent URL for
                  // pre-filled outbound text at all (their share sheet
                  // is app-native and platform-gated) — same honest
                  // copy-then-open pattern as Instagram/Messenger.
                  icon: Icons.music_note_rounded,
                  label: "TikTok",
                  color: Colors.black,
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: inviteMessage));
                    Navigator.of(sheetContext).pop();
                    launchExternalURL("https://www.tiktok.com/");
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text("Invite copied — paste it in TikTok"),
                          backgroundColor: AppColors.success),
                    );
                  },
                ),
                _InviteOption(
                  icon: Icons.mail_rounded,
                  label: "Email",
                  color: AppColors.primary,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    launchExternalURL(
                        "mailto:?subject=${Uri.encodeComponent('Join me on Dutch Remit')}&body=${Uri.encodeComponent(inviteMessage)}");
                  },
                ),
                _InviteOption(
                  icon: Icons.link_rounded,
                  label: "Copy link",
                  color: AppColors.inkMuted,
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: inviteMessage));
                    Navigator.of(sheetContext).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text("Invite copied"),
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
