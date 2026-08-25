import 'package:flutter/material.dart';
import 'package:dutch_remit/utilities/app_theme.dart';
import 'package:dutch_remit/screens/send_money_quote_screen.dart';
import 'package:dutch_remit/screens/send_and_recipients_screen.dart';
import 'package:dutch_remit/screens/invite_friends_screen.dart';

/// The bottom-nav "Send" tab's home: three separate, clean upper
/// sub-navs — Send, Recipient, Invite — replacing the old single
/// "Send & Recipients" screen and its merged header. Send is the
/// initial sub-tab.
class SendTabHubScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  final String userAuthKey;
  final Function setTab;
  const SendTabHubScreen(
      {Key? key, required this.user, required this.userAuthKey, required this.setTab})
      : super(key: key);

  @override
  State<SendTabHubScreen> createState() => _SendTabHubScreenState();
}

class _SendTabHubScreenState extends State<SendTabHubScreen> {
  int _activeSubTab = 0;

  static const List<String> _subTabLabels = ["Send", "Recipient", "Invite"];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        title: Text(_subTabLabels[_activeSubTab],
            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 19)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.ink,
      ),
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _subTabLabels.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final bool isActive = _activeSubTab == index;
                  return GestureDetector(
                    onTap: () => setState(() => _activeSubTab = index),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isActive ? AppColors.primary : AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                      ),
                      child: Text(
                        _subTabLabels[index],
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: isActive ? Colors.white : AppColors.inkMuted),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
                child: KeyedSubtree(
                  key: ValueKey(_activeSubTab),
                  child: _buildActiveSubTab(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveSubTab() {
    switch (_activeSubTab) {
      case 0:
        return SendMoneyQuoteScreen(user: widget.user, userAuthKey: widget.userAuthKey);
      case 1:
        return SendAndRecipientsScreen(
          user: widget.user,
          userAuthKey: widget.userAuthKey,
          setTab: widget.setTab,
        );
      case 2:
        return InviteFriendsScreen(user: widget.user);
      default:
        return SendMoneyQuoteScreen(user: widget.user, userAuthKey: widget.userAuthKey);
    }
  }
}
