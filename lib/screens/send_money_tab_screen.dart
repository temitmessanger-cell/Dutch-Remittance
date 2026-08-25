import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dutch_remit/dutchremit_components.dart';
import 'package:dutch_remit/utilities/app_theme.dart';

/// "Send" tab — lets the user pick a contact or business to pay or
/// request money from. Defaults to the Pay (debit) flow, matching the
/// reference app's primary "Send" action, while keeping the existing
/// Request (credit) capability available via a segmented toggle.
class SendMoneyTabScreen extends StatefulWidget {
  final Function setTab;
  const SendMoneyTabScreen({Key? key, required this.setTab})
      : super(key: key);

  @override
  State<SendMoneyTabScreen> createState() => _SendMoneyTabScreenState();
}

class _SendMoneyTabScreenState extends State<SendMoneyTabScreen> {
  late TextEditingController contactSearchController;
  String _transactionType = 'debit';

  List<String> searchHintsList = [
    'Search...',
    'Search for a contact by their name',
    'Search for a business',
    'Search by their phone number',
    'Search by their email id',
  ];
  int currentSearchHintIndex = 0;
  Timer? _updateSearchingHintTimer;

  @override
  void initState() {
    super.initState();
    contactSearchController = TextEditingController();
    _updateSearchingHintTimer = Timer.periodic(Duration(seconds: 10), (timer) {
      if (mounted && contactSearchController.text.isEmpty) {
        setState(() {
          currentSearchHintIndex =
              (currentSearchHintIndex + 1) % searchHintsList.length;
        });
      }
    });
  }

  @override
  void dispose() {
    _updateSearchingHintTimer?.cancel();
    contactSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String userAuthKey =
        Provider.of<UserLoginStateProvider>(context).userLoginAuthKey;
    String currentSearchHint = searchHintsList[currentSearchHintIndex];

    Widget modeToggle = Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        children: [
          _modeSegment(label: 'Send', value: 'debit'),
          _modeSegment(label: 'Request', value: 'credit'),
        ],
      ),
    );

    Widget searchField = Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: TextField(
        controller: contactSearchController,
        onChanged: (value) => setState(() {}),
        style: TextStyle(color: AppColors.ink, fontSize: 15),
        decoration: InputDecoration(
          prefixIcon: Icon(Icons.search, color: AppColors.textMuted, size: 20),
          filled: true,
          fillColor: AppColors.surfaceAlt,
          focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: AppColors.primary, width: 1.6),
              borderRadius: BorderRadius.all(Radius.circular(AppRadii.md))),
          enabledBorder: OutlineInputBorder(
              borderSide: BorderSide.none,
              borderRadius: BorderRadius.all(Radius.circular(AppRadii.md))),
          border: OutlineInputBorder(
              borderSide: BorderSide.none,
              borderRadius: BorderRadius.all(Radius.circular(AppRadii.md))),
          hintText: currentSearchHint,
          hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 15),
        ),
      ),
    );

    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        title: Text(_transactionType == 'debit' ? "Send Money" : "Request Money",
            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.ink,
        actions: [
          IconButton(
              onPressed: () {},
              icon: Icon(FluentIcons.qr_code_28_regular, color: AppColors.ink)),
        ],
      ),
      body: Column(
        children: [
          modeToggle,
          searchField,
          Expanded(
            child: FutureBuilder<List<dynamic>>(
              future: Future.wait([
                getData(
                    urlPath: "/Dutch Remit/v2/businesses-and-brands",
                    authKey: userAuthKey),
                getData(
                    urlPath: "/Dutch Remit/v3/all-contacts", authKey: userAuthKey)
              ]),
              builder: _buildRecipients,
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeSegment({required String label, required String value}) {
    final bool isSelected = _transactionType == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _transactionType = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadii.sm),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: isSelected ? Colors.white : AppColors.inkMuted,
                fontWeight: FontWeight.w700,
                fontSize: 14),
          ),
        ),
      ),
    );
  }

  Widget _buildRecipients(
      BuildContext context, AsyncSnapshot<List<dynamic>> snapshot) {
    if (snapshot.hasData) {
      if (snapshot.data![0].keys.join().toLowerCase().contains("error") ||
          snapshot.data![1].keys.join().toLowerCase().contains("error")) {
        Map<String, dynamic> error =
            snapshot.data![0].keys.join().toLowerCase().contains("error")
                ? snapshot.data![0]
                : snapshot.data![1];
        WidgetsBinding.instance!
            .addPostFrameCallback((_) => showErrorAlert(context, error));
        return contactsLoadingList(10);
      }

      List<dynamic> data = [
        ...snapshot.data![0]['businesses'],
        ...snapshot.data![1]['contacts']
      ];

      if (contactSearchController.text.isNotEmpty) {
        final searchTerm = contactSearchController.text.toString().toLowerCase();
        List<dynamic> nameMatch = data
            .where((contact) => RegExp(searchTerm)
                .hasMatch(contact['name']?.toString().toLowerCase() ?? ''))
            .toList();
        List<dynamic> emailMatch = data
            .where((contact) =>
                contact.containsKey('emailAddress') &&
                RegExp(searchTerm).hasMatch(
                    contact['emailAddress']?.toString().toLowerCase() ?? ''))
            .toList();
        List<dynamic> phoneNumberMatch = data
            .where((contact) =>
                contact.containsKey('phoneNumber') &&
                RegExp(searchTerm).hasMatch(
                    contact['phoneNumber']?.toString().toLowerCase() ?? ''))
            .toList();
        List<dynamic> webSiteMatch = data
            .where((contact) =>
                contact.containsKey('homepage') &&
                RegExp(searchTerm).hasMatch(
                    contact['homepage']?.toString().toLowerCase() ?? ''))
            .toList();
        data = [...nameMatch, ...emailMatch, ...phoneNumberMatch, ...webSiteMatch]
            .toSet()
            .toList();
      }

      data.sort((a, b) {
        final aName = a['name']?.toString().toLowerCase() ?? '';
        final bName = b['name']?.toString().toLowerCase() ?? '';
        return aName.compareTo(bName);
      });

      if (data.isEmpty) {
        final bool isSearching = contactSearchController.text.isNotEmpty;
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                    isSearching
                        ? Icons.search_off_rounded
                        : Icons.storefront_outlined,
                    size: 36,
                    color: AppColors.textMuted),
                const SizedBox(height: 12),
                Text(
                  isSearching
                      ? "No matches found"
                      : "No businesses or contacts found",
                  style: TextStyle(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w600,
                      fontSize: 15),
                ),
              ],
            ),
          ),
        );
      }

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: ListView.separated(
          padding: const EdgeInsets.only(bottom: 16),
          itemCount: data.length,
          separatorBuilder: (_, b) => const SizedBox(height: 10),
          itemBuilder: (_, index) {
            Widget contactImage;
            if (data[index].containsKey('homepage') &&
                data[index].containsKey('avatar')) {
              contactImage = ClipOval(
                child: AspectRatio(
                  aspectRatio: 1.0 / 1.0,
                  child: ColorFiltered(
                    colorFilter: ColorFilter.mode(AppColors.ink, BlendMode.color),
                    child: ColorFiltered(
                      colorFilter:
                          ColorFilter.mode(Colors.grey, BlendMode.saturation),
                      child: Image.network(
                        "${ApiConstants.baseUrl}/dist/images/Dutch Remit_images/brands_and_businesses/${data[index]['avatar']}",
                        height: 64,
                        width: 64,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              );
            } else if (data[index].containsKey('emailAddress') &&
                data[index].containsKey('avatar')) {
              contactImage = ClipOval(
                child: AspectRatio(
                  aspectRatio: 1.0 / 1.0,
                  child: Image.network(
                    "${ApiConstants.baseUrl}/dist/images/Dutch Remit_images/brands_and_businesses/${data[index]['avatar']}",
                    height: 64,
                    width: 64,
                    fit: BoxFit.contain,
                  ),
                ),
              );
            } else {
              contactImage = Text(
                data[index]['name'][0].toUpperCase(),
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.primary),
              );
            }

            String tileSubtitle;
            if (data[index].containsKey('emailAddress') &&
                data[index].containsKey('avatar')) {
              tileSubtitle = data[index]['emailAddress'];
            } else if (data[index].containsKey('homepage') &&
                data[index].containsKey('avatar')) {
              tileSubtitle = data[index]['homepage'];
            } else {
              tileSubtitle = data[index]['phoneNumber'];
            }

            return Material(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadii.lg),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadii.lg),
                onTap: () => _goToFundTransfer(data[index]),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                    boxShadow: AppShadows.card,
                  ),
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    leading: CircleAvatar(
                        radius: 26,
                        backgroundColor: AppColors.surfaceAlt,
                        child: contactImage),
                    title: Text(
                      data[index]['name'],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(tileSubtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                    ),
                    trailing: Icon(Icons.chevron_right_rounded,
                        color: AppColors.textMuted, size: 20),
                  ),
                ),
              ),
            );
          },
        ),
      );
    } else if (snapshot.hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: AppColors.danger, size: 60),
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text('Error: ${snapshot.error}',
                  style: TextStyle(color: AppColors.inkMuted)),
            )
          ],
        ),
      );
    } else {
      return contactsLoadingList(10);
    }
  }

  void _goToFundTransfer(Map<String, dynamic> otherParty) {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.push(
        context,
        SlideRightRoute(
            page: FundTransferScreen(
          otherParty: otherParty,
          transactionType: _transactionType,
        )));
  }
}
