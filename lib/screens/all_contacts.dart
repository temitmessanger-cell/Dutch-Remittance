import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dutch_remit/hadwin_components.dart';
import 'package:dutch_remit/screens/my_qr_code_screen.dart';
import 'package:dutch_remit/screens/enter_code_manually_screen.dart';
import 'package:dutch_remit/utilities/app_theme.dart';

class AllContactsScreen extends StatefulWidget {
  final String userAuthKey;
  final Function setTab;
  final Map<String, dynamic> user;
  const AllContactsScreen(
      {Key? key, required this.userAuthKey, required this.setTab, required this.user})
      : super(key: key);

  @override
  State<AllContactsScreen> createState() => _AllContactsScreenState();
}

class _AllContactsScreenState extends State<AllContactsScreen> {
  late TextEditingController contactSearchController;
  final ContactsStorage _contactsStorage = ContactsStorage();

  List<String> searchHintsList = [
    'Search...',
    'Search for a contact by their name',
    'Search by their phone number',
    'Search by their email id',
  ];
  int currentSearchHintIndex = 0;

  Timer? _updateContactsSearchingHintTimer;

  @override
  void initState() {
    super.initState();
    contactSearchController = TextEditingController();
    _updateContactsSearchingHintTimer =
        Timer.periodic(Duration(seconds: 10), (timer) {
      if (mounted && contactSearchController.text.isEmpty) {
        setState(() {
          if (currentSearchHintIndex == searchHintsList.length - 1) {
            currentSearchHintIndex = 0;
          } else {
            currentSearchHintIndex++;
          }
        });
        //* search hint updated
      } 
    });
  }

  @override
  void dispose() {
    _updateContactsSearchingHintTimer!.cancel();
    contactSearchController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String currentSearchHint = searchHintsList[currentSearchHintIndex];
    Widget searchContacts = Container(
      margin: EdgeInsets.symmetric(vertical: 12, horizontal: 20),
      child: TextField(
        controller: contactSearchController,
        onChanged: (value) {
          setState(() {});
        },
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
            hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 15)),
      ),
    );

    return Scaffold(
        backgroundColor: AppColors.scaffold,
        appBar: AppBar(
          title: Text("Recipients",
              style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w700)),
          centerTitle: true,
          actions: [
            IconButton(
                onPressed: _showAddContactDialog,
                icon: Icon(Icons.person_add_alt_1_rounded,
                    color: AppColors.ink)),
            IconButton(
                onPressed: openQRCodeScanner,
                icon: Icon(FluentIcons.qr_code_28_regular,
                    color: AppColors.ink)),
          ],
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: SafeArea(
          child: Column(
            children: [
              searchContacts,
              if (contactSearchController.text.isEmpty) _buildRecentTransfers(),
              Expanded(
                child: FutureBuilder<Map<String, dynamic>>(
                    future: getData(
                        urlPath: "/Dutch Remit/v3/all-contacts",
                        authKey: widget.userAuthKey),
                    builder: buildContacts),
              )
            ],
          ),
        ));
  }

  Widget _buildRecentTransfers() {
    return FutureBuilder<List<dynamic>>(
      future: Future.wait([
        getData(
            urlPath: "/Dutch Remit/v1/all-transactions",
            authKey: widget.userAuthKey),
        SuccessfulTransactionsStorage().getSuccessfulTransactions()
      ]),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }
        if (snapshot.data![0].keys.join().toLowerCase().contains("error") ||
            snapshot.data![1].keys.join().toLowerCase().contains("error")) {
          return const SizedBox.shrink();
        }

        List<dynamic> allTransactions = [
          ...snapshot.data![0]['transactions'],
          ...snapshot.data![1]['transactions']
        ];
        allTransactions.sort(
            (a, b) => b['transactionDate'].compareTo(a['transactionDate']));

        // Unique recent transaction partners, most recent first.
        List<Map<String, dynamic>> recentPartners = [];
        Set<String> seenNames = {};
        for (var t in allTransactions) {
          final name = t['transactionMemberName']?.toString() ?? '';
          if (name.isEmpty || seenNames.contains(name)) continue;
          seenNames.add(name);
          recentPartners.add(t);
          if (recentPartners.length >= 8) break;
        }

        if (recentPartners.isEmpty) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 0, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Recent transfer",
                style: TextStyle(
                    fontSize: 15.5, fontWeight: FontWeight.w700, color: AppColors.ink),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 84,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(right: 20),
                  itemCount: recentPartners.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 14),
                  itemBuilder: (_, index) {
                    final t = recentPartners[index];
                    final String name = t['transactionMemberName']?.toString() ?? '';
                    Widget avatarContent;
                    if (t.containsKey('transactionMemberAvatar')) {
                      avatarContent = ClipOval(
                        child: Image.network(
                          "${ApiConstants.baseUrl}/dist/images/Dutch Remit_images/brands_and_businesses/${t['transactionMemberAvatar']}",
                          height: 52,
                          width: 52,
                          fit: BoxFit.cover,
                        ),
                      );
                    } else {
                      avatarContent = Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary),
                      );
                    }
                    return GestureDetector(
                      onTap: () => _showInitiateTransactionDialogBox({
                        'name': name,
                        if (t.containsKey('transactionMemberAvatar'))
                          'avatar': t['transactionMemberAvatar'],
                        if (t.containsKey('transactionMemberEmail'))
                          'emailAddress': t['transactionMemberEmail'],
                      }),
                      child: SizedBox(
                        width: 60,
                        child: Column(
                          children: [
                            CircleAvatar(
                              radius: 26,
                              backgroundColor: AppColors.surfaceAlt,
                              child: avatarContent,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              name.split(' ').first,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11.5, color: AppColors.inkMuted),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Contact List",
                style: TextStyle(
                    fontSize: 15.5, fontWeight: FontWeight.w700, color: AppColors.ink),
              ),
              const SizedBox(height: 4),
            ],
          ),
        );
      },
    );
  }


  void _showInitiateTransactionDialogBox(Map<String, dynamic> otherParty) {
    WidgetsBinding.instance!.addPostFrameCallback((_) => showDialog(
        context: context,
        builder: (context) => AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.lg)),
              title: Text(
                "Pay/Request",
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink),
              ),
              content: Text(
                "Decide what you want to do",
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
                              onPressed: () =>
                                  _makeATransaction(otherParty, 'debit'),
                              child: Text('Pay'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(AppRadii.md)),
                              )),
                        ),
                        SizedBox(
                          width: 16,
                        ),
                        SizedBox(
                          height: 48,
                          width: 100,
                          child: ElevatedButton(
                              onPressed: () =>
                                  _makeATransaction(otherParty, 'credit'),
                              child: Text('Request'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.surfaceAlt,
                                foregroundColor: AppColors.ink,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(AppRadii.md)),
                              )),
                        ),
                      ],
                    ),
                    SizedBox(
                      height: 18,
                    ),
                    Padding(
                      padding: EdgeInsets.all(10),
                      child: Text(
                        "tap the back button or outside this dialog box to cancel",
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    SizedBox(
                      height: 18,
                    ),
                  ],
                )
              ],
            )));
  }

  void _makeATransaction(
      Map<String, dynamic> otherParty, String transactionType) {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop();
    Navigator.push(
        context,
        SlideRightRoute(
            page: FundTransferScreen(
          otherParty: otherParty,
          transactionType: transactionType,
        )));
  }

  void openQRCodeScanner() {
    FocusManager.instance.primaryFocus?.unfocus();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg))),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.qr_code_2_rounded, color: AppColors.primary),
                title: Text("My QR Code",
                    style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink)),
                subtitle: Text("Show your code to get paid",
                    style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.push(context,
                      SlideRightRoute(page: MyQrCodeScreen(user: widget.user)));
                },
              ),
              ListTile(
                leading: Icon(Icons.keyboard_alt_outlined, color: AppColors.primary),
                title: Text("Enter a code",
                    style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink)),
                subtitle: Text("Paste someone else's code to pay them",
                    style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.push(context,
                      SlideRightRoute(page: EnterCodeManuallyScreen()));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddContactDialog() {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final phoneController = TextEditingController();
    String? errorText;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.lg)),
          title: Text("Add contact",
              style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                    hintText: "Full name",
                    filled: true,
                    fillColor: AppColors.surfaceAlt,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadii.sm),
                        borderSide: BorderSide.none)),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                    hintText: "Email (optional)",
                    filled: true,
                    fillColor: AppColors.surfaceAlt,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadii.sm),
                        borderSide: BorderSide.none)),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                    hintText: "Phone (optional)",
                    filled: true,
                    fillColor: AppColors.surfaceAlt,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadii.sm),
                        borderSide: BorderSide.none)),
              ),
              if (errorText != null) ...[
                const SizedBox(height: 8),
                Text(errorText!, style: TextStyle(color: AppColors.danger, fontSize: 12.5)),
              ],
            ],
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text("Cancel", style: TextStyle(color: AppColors.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.sm)),
              ),
              onPressed: () async {
                if (nameController.text.trim().isEmpty) {
                  setDialogState(() => errorText = "Name is required");
                  return;
                }
                final added = await _contactsStorage.addContact(
                  name: nameController.text.trim(),
                  emailAddress: emailController.text.trim(),
                  phoneNumber: phoneController.text.trim(),
                );
                if (!added) {
                  setDialogState(() => errorText = "That contact already exists");
                  return;
                }
                if (mounted) {
                  Navigator.of(dialogContext).pop();
                  setState(() {}); // refresh the contacts list
                }
              },
              child: Text("Add"),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildContacts(
      BuildContext context, AsyncSnapshot<Map<String, dynamic>> snapshot) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _contactsStorage.readContacts(),
      builder: (context, localSnapshot) {
        final List<dynamic> localContacts = localSnapshot.data ?? [];
        return _buildContactsList(context, snapshot, localContacts);
      },
    );
  }

  Widget _buildContactsList(BuildContext context,
      AsyncSnapshot<Map<String, dynamic>> snapshot, List<dynamic> localContacts) {
    List<Widget> children;
    if (snapshot.hasData) {
      final bool serverFailed =
          snapshot.data!.keys.join().toLowerCase().contains("error");

      // Server contacts merged with locally-added ones. A server hiccup
      // no longer means "no contacts at all" — locally-added contacts
      // (and guests, who have no server account at all) still work.
      List<dynamic> allContacts = [
        ...localContacts,
        if (!serverFailed) ...(snapshot.data!['contacts'] ?? []),
      ];

      List<dynamic> data;
      if (contactSearchController.text.isEmpty) {
        data = allContacts;
      } else {
        final searchTerm = contactSearchController.text.toString().toLowerCase();
        List<dynamic> nameMatch = allContacts
            .where((contact) =>
                RegExp(searchTerm).hasMatch(
                    contact['name']?.toString().toLowerCase() ?? ''))
            .toList();
        List<dynamic> emailMatch = allContacts
            .where((contact) =>
                RegExp(searchTerm).hasMatch(
                    contact['emailAddress']?.toString().toLowerCase() ?? ''))
            .toList();
        List<dynamic> phoneNumberMatch = allContacts
            .where((contact) =>
                RegExp(searchTerm).hasMatch(
                    contact['phoneNumber']?.toString().toLowerCase() ?? ''))
            .toList();
        data = [...nameMatch, ...emailMatch, ...phoneNumberMatch]
            .toSet()
            .toList();
      }
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
                        : FluentIcons.people_24_regular,
                    size: 40,
                    color: AppColors.textMuted),
                const SizedBox(height: 14),
                Text(
                  isSearching ? "No matches found" : "No contacts found",
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                      fontSize: 16),
                ),
                if (!isSearching) ...[
                  const SizedBox(height: 6),
                  Text(
                    "Add a contact to start sending money to them.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13.5),
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton(
                    onPressed: _showAddContactDialog,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadii.md)),
                    ),
                    child: Text("Add a contact"),
                  ),
                ],
              ],
            ),
          ),
        );
      } else {
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: 28),
            child: ListView.separated(
                padding: EdgeInsets.all(0),
                itemBuilder: (_, index) {
                  Widget contactImage;
                  if (data[index].containsKey('avatar')) {
                    contactImage = ClipOval(
                      child: AspectRatio(
                        aspectRatio: 1.0 / 1.0,
                        child: Image.network(
                          "${ApiConstants.baseUrl}/dist/images/Dutch Remit_images/brands_and_businesses/${data[index]['avatar']}",
                          height: 68,
                          width: 68,
                          fit: BoxFit.contain,
                        ),
                      ),
                    );
                  } else {
                    final nameString = data[index]['name']?.toString() ?? '';
                    final firstLetter = nameString.isNotEmpty
                        ? nameString[0].toUpperCase()
                        : '?';
                    contactImage = Text(
                      firstLetter,
                      style: TextStyle(fontSize: 20, color: AppColors.ink),
                    );
                  }

                  String tileSubtitle;

                  if (data[index].containsKey('emailAddress') &&
                      data[index].containsKey('avatar')) {
                    tileSubtitle = data[index]['emailAddress']?.toString() ?? '';
                  } else {
                    tileSubtitle = data[index]['phoneNumber']?.toString() ?? '';
                  }

                  return Container(
                    padding: EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.all(Radius.circular(AppRadii.lg)),
                      boxShadow: AppShadows.card,
                      color: Colors.white,
                    ),
                    child: ListTile(
                      contentPadding: EdgeInsets.all(0),
                      leading: CircleAvatar(
                        child: contactImage,
                        backgroundColor: AppColors.surfaceAlt,
                        radius: 36.0,
                      ),
                      title: Text(
                        data[index]['name'],
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink),
                      ),
                      subtitle: Container(
                          margin: EdgeInsets.only(top: 7.2),
                          child: Text(tileSubtitle,
                          style: TextStyle(fontSize: 13,color: AppColors.textMuted),
                          )),
                      horizontalTitleGap: 18,
                      onTap: () =>
                          _showInitiateTransactionDialogBox(data[index]),
                    ),
                  );
                },
                separatorBuilder: (_, b) => Divider(
                      height: 14,
                      color: Colors.transparent,
                    ),
                itemCount: data.length),
          );
      }
    } else if (snapshot.hasError) {
      children = <Widget>[
        Icon(
          Icons.error_outline,
          color: AppColors.danger,
          size: 60,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text('Error: ${snapshot.error}',
              style: TextStyle(color: AppColors.inkMuted)),
        )
      ];
    } else {
      return contactsLoadingList(10);
    }
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: children,
      ),
    );
  }
}


