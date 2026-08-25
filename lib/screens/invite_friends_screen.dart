import 'package:flutter/material.dart';
import 'package:dutch_remit/database/contacts_storage.dart';
import 'package:dutch_remit/utilities/app_theme.dart';
import 'package:dutch_remit/utilities/url_external_launcher.dart';

/// The "Invite" sub-tab of the Send hub, matching the reference
/// "Friends on Eversend" panel 1:1 (rebranded to Dutch Remit): a
/// purple card with the pitch, an "Invite friends" button that opens
/// a real share sheet, a row of contact avatars, and a sample
/// zero-fee balance-to-balance transfer line.
class InviteFriendsScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  const InviteFriendsScreen({Key? key, required this.user}) : super(key: key);

  @override
  State<InviteFriendsScreen> createState() => _InviteFriendsScreenState();
}

class _InviteFriendsScreenState extends State<InviteFriendsScreen> {
  final ContactsStorage _contactsStorage = ContactsStorage();
  List<Map<String, dynamic>> _contacts = [];

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    final contacts = await _contactsStorage.readContacts();
    if (mounted) setState(() => _contacts = contacts.take(3).toList());
  }

  void _inviteFriends() {
    final name = widget.user['firstName']?.toString() ??
        widget.user['name']?.toString() ??
        'a friend';
    // Genuinely opens the device's share/SMS composer instead of doing
    // nothing when tapped.
    launchExternalURL(
        "sms:?body=Hey! ${Uri.encodeComponent(name)} invited you to Dutch Remit — pay each other instantly and free. Download it here: https://dutchremit.app");
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.06),
            borderRadius: BorderRadius.circular(AppRadii.xl),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("FRIENDS ON DUTCH REMIT",
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                      color: AppColors.primary)),
              const SizedBox(height: 10),
              Text("Pay friends on Dutch Remit,\ninstantly and free.",
                  style: TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.ink, height: 1.2)),
              const SizedBox(height: 10),
              Text(
                "Money moves between Dutch Remit balances in real time, with zero fees. "
                "Invite the friends you split bills and send money with, and pay them in a single tap.",
                style: TextStyle(fontSize: 13.5, color: AppColors.inkMuted, height: 1.5),
              ),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: _inviteFriends,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text("Invite friends", style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(width: 8),
                    Icon(Icons.arrow_forward_rounded, size: 16),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        ..._avatarStack(),
                        GestureDetector(
                          onTap: _inviteFriends,
                          child: Container(
                            width: 40,
                            height: 40,
                            margin: const EdgeInsets.only(left: 4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.border, width: 1.4),
                            ),
                            child: Icon(Icons.add_rounded, color: AppColors.primary, size: 18),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(AppRadii.md),
                      ),
                      child: Row(
                        children: [
                          Container(
                              width: 8, height: 8,
                              decoration: BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                      text: "You → ${_contacts.isNotEmpty ? _contacts.first['name'] : 'Maya'} · ",
                                      style: TextStyle(fontSize: 13, color: AppColors.ink, fontWeight: FontWeight.w600)),
                                  TextSpan(text: "Dutch Remit", style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                                ],
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                                color: AppColors.successBg, borderRadius: BorderRadius.circular(AppRadii.pill)),
                            child: Text("Free",
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.success)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _avatarStack() {
    final colors = [AppColors.primary, AppColors.success, AppColors.warning];
    final labels = _contacts.isNotEmpty
        ? _contacts.map((c) => (c['name']?.toString() ?? '?')[0].toUpperCase()).toList()
        : ['M', 'K', 'A'];
    return List.generate(labels.length, (i) {
      return Container(
        width: 40,
        height: 40,
        margin: EdgeInsets.only(left: i == 0 ? 0 : -10),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors[i % colors.length],
          border: Border.all(color: Colors.white, width: 2),
        ),
        alignment: Alignment.center,
        child: Text(labels[i], style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      );
    });
  }
}
