import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:dutch_remit/components/settings_screen/all_licenses.dart';
import 'package:dutch_remit/components/shared/dutch_remit_wordmark.dart';
import 'package:dutch_remit/components/shared/invite_to_dutch_remit_sheet.dart';
import 'package:dutch_remit/components/shared/transaction_receipt_dialog.dart'
    show kSupportWhatsAppUrl;
import 'package:dutch_remit/database/cards_storage.dart';
import 'package:dutch_remit/database/login_info_storage.dart';
import 'package:dutch_remit/database/product_tour_storage.dart';
import 'package:dutch_remit/database/successful_transactions_storage.dart';
import 'package:dutch_remit/database/user_data_storage.dart';
import 'package:dutch_remit/providers/live_transactions_provider.dart';
import 'package:dutch_remit/providers/user_login_state_provider.dart';
import 'package:dutch_remit/utilities/hadwin_markdown_viewer.dart';
import 'package:dutch_remit/utilities/legal_documents.dart';
import 'package:dutch_remit/utilities/url_external_launcher.dart';
import 'package:dutch_remit/screens/login_screen.dart';
import 'package:dutch_remit/utilities/slide_right_route.dart';
import 'package:provider/provider.dart';
import 'package:dutch_remit/utilities/app_theme.dart';

class AppSettingsComponent extends StatelessWidget {
  final Map<String, dynamic>? user;
  const AppSettingsComponent({Key? key, this.user}) : super(key: key);

  Future<bool> _deleteLoggedInUserData() async {
    List<bool> deletionStatus = await Future.wait(
        [LoginInfoStorage().deleteFile(), UserDataStorage().deleteFile()]);
    return deletionStatus.first && deletionStatus.last;
  }

  Future<bool> _resetTransactionsAndCards(BuildContext context) async {
    List<bool> deletionStatus = await Future.wait([
      CardsStorage().resetLocallySavedCards(),
      SuccessfulTransactionsStorage().resetLocallySavedTransactions(),
      Provider.of<UserLoginStateProvider>(context, listen: false)
          .resetBankBalance(),
      Provider.of<LiveTransactionsProvider>(context, listen: false)
          .resetTransactionsInState()
    ]);
    Set<bool> deletionStatusSet = deletionStatus.toSet();
    return deletionStatusSet.length == 1 && deletionStatusSet.first == true;
  }

  @override
  Widget build(BuildContext context) {
    final data = _settingsMenu(context);

    return ListView.separated(
        padding: EdgeInsets.symmetric(vertical: 4),
        itemBuilder: (_, index) {
          return Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white,
            ),
            child: ListTile(
              textColor: AppColors.ink,
              iconColor: AppColors.textMuted,
              contentPadding: EdgeInsets.all(5),
              title: data[index]['title'],
              trailing: data[index]['trailing'],
              onTap: data[index]['onTap'],
            ),
          );
        },
        separatorBuilder: (_, b) => Divider(
              height: 1,
              color: AppColors.divider,
            ),
        itemCount: data.length);
  }

  List<dynamic> _settingsMenu(BuildContext context) {
    TextStyle itemStyle = TextStyle(fontSize: 15, color: AppColors.ink, fontWeight: FontWeight.w500);
    List<dynamic> settingsMenuItems = [
      {
        'title': Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Chat with support on WhatsApp', style: itemStyle),
            const SizedBox(height: 2),
            Text('+1 (289) 791-2474 — tap to open WhatsApp',
                style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
          ],
        ),
        'trailing': Icon(Icons.chat_rounded, color: AppColors.success),
        'onTap': () {
          launchExternalURL(kSupportWhatsAppUrl);
        },
        'settingsCategory': 'Help & Contact',
      },
      {
        'title': Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Not on Dutch Remit?', style: itemStyle),
            const SizedBox(height: 2),
            Text('Invite and then send money simply.',
                style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
          ],
        ),
        'trailing': Icon(Icons.person_add_alt_1_rounded, color: AppColors.primary),
        'onTap': () {
          showInviteToDutchRemitSheet(context, user: user);
        },
        'settingsCategory': 'Invite',
      },
      {
        'title': Text('Replay guided tour', style: itemStyle),
        'trailing': Icon(Icons.play_circle_outline_rounded, color: AppColors.primary),
        'onTap': () {
          Navigator.of(context).popUntil((route) => route.isFirst);
          ProductTourStorage.requestReplay();
        },
        'settingsCategory': 'About the app',
      },
      {
        'title': Text('About Dutch Remit', style: itemStyle),
        'trailing': Icon(FluentIcons.info_24_regular, color: AppColors.textMuted),
        'onTap': () =>
            openDocsViewer(kAboutDutchRemit, 'About Dutch Remit', context),
        'settingsCategory': 'About the app',
      },
      {
        'title': Text('Frequently Asked Questions', style: itemStyle),
        'trailing': Icon(FluentIcons.chat_help_24_regular, color: AppColors.textMuted),
        'onTap': () => openDocsViewer(
            kFrequentlyAskedQuestions, 'Frequently Asked Questions', context),
        'settingsCategory': 'About the app',
      },
      {
        'title': Text('Privacy Policy', style: itemStyle),
        'trailing': Icon(FluentIcons.info_24_regular, color: AppColors.textMuted),
        'onTap': () =>
            openDocsViewer(kPrivacyPolicy, 'Privacy Policy', context),
        'settingsCategory': 'About the app',
      },
      {
        'title': Text('Terms of use', style: itemStyle),
        'trailing': Icon(FluentIcons.info_24_regular, color: AppColors.textMuted),
        'onTap': () => openDocsViewer(
            kTermsOfUse, 'Terms & Conditions', context),
        'settingsCategory': 'About the app',
      },
      {
        'title': Text('End User License Agreement', style: itemStyle),
        'trailing': Icon(FluentIcons.info_24_regular, color: AppColors.textMuted),
        'onTap': () => openDocsViewer(
            kEndUserLicenseAgreement, 'End User License Agreement', context),
        'settingsCategory': 'About the app',
      },
      {
        'title': Text('Share feedback', style: itemStyle),
        'trailing': Icon(FluentIcons.person_feedback_24_regular, color: AppColors.textMuted),
        'onTap': () {
          launchExternalURL(
              'mailto:support@dutchremit.com?subject=Dutch%20Remit%20Feedback');
        },
        'settingsCategory': 'About the app',
      },
      {
        'title': Text('Licenses', style: itemStyle),
        'trailing': Icon(FluentIcons.book_24_regular, color: AppColors.textMuted),
        'onTap': () {
          Navigator.push(context, SlideRightRoute(page: AllLicenses()));
        },
        'settingsCategory': 'About the app',
      },
      {
        'title': Text('Reset', style: itemStyle.copyWith(color: AppColors.danger)),
        'trailing': Icon(FluentIcons.warning_24_regular, color: AppColors.danger),
        'onTap': () => showDialogOnResetDataRequest(context),
        'settingsCategory': 'General',
      },
      {
        'title': Text('Sign Out', style: itemStyle.copyWith(color: AppColors.danger)),
        'trailing': Icon(FluentIcons.sign_out_24_regular, color: AppColors.danger),
        'onTap': () async {
          bool logOutStatus = await _deleteLoggedInUserData();
          if (logOutStatus) {
            Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => LoginScreen()),
                (route) => false);
          }
        },
        'settingsCategory': 'General',
      },
      {
        'title': Padding(
            padding: EdgeInsets.symmetric(horizontal: 48, vertical: 16),
            child: DutchRemitWordmark(fontSize: 22)),
        'trailing': null,
        'onTap': null,
        'settingsCategory': 'About the app',
      },
    ];

    return settingsMenuItems;
  }

  void showDialogOnResetDataRequest(BuildContext context) {
    ButtonStyle resetButtonStyle = ElevatedButton.styleFrom(
      backgroundColor: AppColors.danger,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
    );
    ButtonStyle cancelButtonStyle = ElevatedButton.styleFrom(
      backgroundColor: AppColors.surfaceAlt,
      foregroundColor: AppColors.ink,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
    );

    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.lg)),
              title: Text(
                "Reset",
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink),
              ),
              content: Text(
                "This will delete all locally saved transactions and cards.\nDo you wish to continue?",
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.inkMuted),
              ),
              actionsAlignment: MainAxisAlignment.center,
              actions: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          height: 48,
                          width: 100,
                          child: ElevatedButton(
                              onPressed: () async {
                                bool deleted =
                                    await _resetTransactionsAndCards(context);
                                if (deleted) {
                                  Navigator.of(context).pop();
                                }
                              },
                              child: Text('Reset'),
                              style: resetButtonStyle),
                        ),
                        SizedBox(
                          width: 16,
                        ),
                        SizedBox(
                          height: 48,
                          width: 100,
                          child: ElevatedButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: Text('Cancel'),
                              style: cancelButtonStyle),
                        ),
                      ],
                    ),
                    SizedBox(
                      height: 18,
                    ),
                  ],
                )
              ],
            ));
  }

  void openDocsViewer(String content, String screenName, BuildContext context) {
    Navigator.push(
        context,
        SlideRightRoute(
            page: DutchRemitMarkdownViewer(
          screenName: screenName,
          content: content,
        )));
  }
}


