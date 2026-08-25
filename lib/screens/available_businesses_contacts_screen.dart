import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:dutch_remit/hadwin_components.dart';
import 'package:dutch_remit/screens/my_qr_code_screen.dart';
import 'package:dutch_remit/screens/enter_code_manually_screen.dart';

import 'package:provider/provider.dart';
import 'package:dutch_remit/utilities/app_theme.dart';

class AvailableBusinessesAndContactsScreen extends StatefulWidget {
  final String transactionType;
  final Map<String, dynamic> user;
  const AvailableBusinessesAndContactsScreen(
      {Key? key, required this.transactionType, required this.user})
      : super(key: key);

  @override
  _AvailableBusinessesAndContactsScreenState createState() =>
      _AvailableBusinessesAndContactsScreenState();
}

class _AvailableBusinessesAndContactsScreenState
    extends State<AvailableBusinessesAndContactsScreen> {
  late String transactionButton;
  late TextEditingController contactSearchController;

List<String> searchHintsList = [
      'Search...',
      'Search for a contact by their name',
      'Search for a business',
      'Search by their phone number',
      'Search by their email id',
      'Search by their website'
    ];
    int currentSearchHintIndex = 0;
    Timer? _updateContactsSearchingHintTimer;
  @override
  void initState() {
    super.initState();
    transactionButton = widget.transactionType == 'debit' ? "Pay" : 'Request';
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
    String userAuthKey =
        Provider.of<UserLoginStateProvider>(context).userLoginAuthKey;
    

    String currentSearchHint = searchHintsList[currentSearchHintIndex];
    return Scaffold(
    
    backgroundColor: AppColors.scaffold,
      // backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        leading: IconButton(
            onPressed: () {
              FocusManager.instance.primaryFocus?.unfocus();
              Future.delayed(Duration(milliseconds: 200),
                  (() => Navigator.of(context).pop()));
            },
            icon: Icon(Icons.arrow_back, color: AppColors.ink)),
        title: Text(
          "Businesses and Contacts",
          style: TextStyle(fontSize: 17.5),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.ink,
        actions: [
          IconButton(
              onPressed: () {
                Navigator.push(
                    context,
                    SlideRightRoute(
                        page: widget.transactionType == 'debit'
                            ? EnterCodeManuallyScreen()
                            : MyQrCodeScreen(user: widget.user)));
              },
              icon: Icon(FluentIcons.qr_code_28_regular,
                  color: AppColors.ink)),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 10,
          ),
          Container(
            margin: EdgeInsets.symmetric(vertical: 12, horizontal: 28),
            child: TextField(
              controller: contactSearchController,
              onChanged: (value) {
                setState(() {});
              },
              style: TextStyle(color: AppColors.textMuted),
              decoration: InputDecoration(
                  focusedBorder: OutlineInputBorder(
                      borderSide:
                          BorderSide(color: AppColors.surfaceAlt, width: 1.618),
                      borderRadius: BorderRadius.all(Radius.circular(16))),
                  enabledBorder: OutlineInputBorder(
                      borderSide:
                          BorderSide(color: AppColors.surfaceAlt, width: 1.618),
                      borderRadius: BorderRadius.all(Radius.circular(16))),
                  hintText: currentSearchHint,
                  hintStyle: TextStyle(color: AppColors.textMuted)),
            ),
          ),
          Expanded(
            child: Container(
              width: double.infinity,
              child: FutureBuilder<List<dynamic>>(
                future: Future.wait([
                  getData(
                      urlPath: "/Dutch Remit/v2/businesses-and-brands",
                      authKey: userAuthKey),
                  getData(
                      urlPath: "/Dutch Remit/v3/all-contacts", authKey: userAuthKey)
                ]),
                builder: (context, snapshot) {
                  List<Widget> children;
                  if (snapshot.hasData) {
                    if (snapshot.data![0].keys
                            .join()
                            .toLowerCase()
                            .contains("error") ||
                        snapshot.data![1].keys
                            .join()
                            .toLowerCase()
                            .contains("error")) {
                      Map<String, dynamic> error = snapshot.data![0].keys
                              .join()
                              .toLowerCase()
                              .contains("error")
                          ? snapshot.data![0]
                          : snapshot.data![1];
                      WidgetsBinding.instance!.addPostFrameCallback(
                          (_) => showErrorAlert(context, error));

                     

                      return contactsLoadingList(10);
                    } else {
                      List<dynamic> data;
                   
                      if (contactSearchController.text.isEmpty) {
                        data = [
                          ...snapshot.data![0]['businesses'],
                          ...snapshot.data![1]['contacts']
                        ];
                      } else {
                        data = [
                          ...snapshot.data![0]['businesses'],
                          ...snapshot.data![1]['contacts']
                        ];
                   
                        final searchTerm =
                            contactSearchController.text.toString().toLowerCase();
                        List<dynamic> nameMatch = data
                            .where((contact) =>
                                RegExp(searchTerm).hasMatch(
                                    contact['name']?.toString().toLowerCase() ?? ''))
                            .toList();
                        List<dynamic> emailMatch = data
                            .where((contact) =>
                                contact.containsKey('emailAddress') &&
                                RegExp(searchTerm).hasMatch(
                                    contact['emailAddress']
                                        ?.toString()
                                        .toLowerCase() ?? ''))
                            .toList();
                        List<dynamic> phoneNumberMatch = data
                            .where((contact) =>
                                contact.containsKey('phoneNumber') &&
                                RegExp(searchTerm).hasMatch(
                                    contact['phoneNumber']
                                        ?.toString()
                                        .toLowerCase() ?? ''))
                            .toList();
                        List<dynamic> webSiteMatch = data
                            .where((contact) =>
                                contact.containsKey('homepage') &&
                                RegExp(searchTerm).hasMatch(
                                    contact['homepage']
                                        ?.toString()
                                        .toLowerCase() ?? ''))
                            .toList();
                        data = [
                          ...nameMatch,
                          ...emailMatch,
                          ...phoneNumberMatch,
                          ...webSiteMatch
                        ].toSet().toList();
                      }
                      data.sort((a, b) {
                        final aName = a['name']?.toString().toLowerCase() ?? '';
                        final bName = b['name']?.toString().toLowerCase() ?? '';
                        return aName.compareTo(bName);
                      });
                      if (data.isEmpty) {
                        final bool isSearching =
                            contactSearchController.text.isNotEmpty;
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
                                    size: 40,
                                    color: AppColors.textMuted),
                                const SizedBox(height: 14),
                                Text(
                                  isSearching
                                      ? "No matches found"
                                      : "No businesses or contacts found",
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.ink,
                                      fontSize: 16),
                                ),
                                if (!isSearching) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    "Check back later, or add a contact from the Recipients tab.",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color: AppColors.textMuted, fontSize: 13.5),
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
                                if (data[index].containsKey('homepage') &&
                                    data[index].containsKey('avatar')) {
                                  contactImage = ClipOval(
                                    child: AspectRatio(
                                      aspectRatio: 1.0 / 1.0,
                                      child: ColorFiltered(
                                        colorFilter: ColorFilter.mode(
                                        
                                          AppColors.ink,
                                          BlendMode.color,
                                        ),
                                        child: ColorFiltered(
                                          colorFilter: ColorFilter.mode(
                                            Colors.grey,
                                            BlendMode.saturation,
                                          ),
                                          child: Image.network(
                                            "${ApiConstants.baseUrl}/dist/images/Dutch Remit_images/brands_and_businesses/${data[index]['avatar']}",
                                            height: 72,
                                            width: 72,
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                } else if (data[index]
                                        .containsKey('emailAddress') &&
                                    data[index].containsKey('avatar')) {
                                  contactImage = ClipOval(
                                    child: AspectRatio(
                                      aspectRatio: 1.0 / 1.0,
                                      child: Image.network(
                                        "${ApiConstants.baseUrl}/dist/images/Dutch Remit_images/brands_and_businesses/${data[index]['avatar']}",
                                        height: 72,
                                        width: 72,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  );
                                } else {
                                  contactImage = Text(
                                    data[index]['name'][0].toUpperCase(),
                                    style: TextStyle(
                                        fontSize: 20, color: AppColors.ink),
                                  );
                                }

                                String tileSubtitle;

                                if (data[index].containsKey('emailAddress') &&
                                    data[index].containsKey('avatar')) {
                                  tileSubtitle = data[index]['emailAddress'];
                                } else if (data[index]
                                        .containsKey('homepage') &&
                                    data[index].containsKey('avatar')) {
                                  tileSubtitle = data[index]['homepage'];
                                } else {
                                  tileSubtitle = data[index]['phoneNumber'];
                                }

                                return Container(
                                  padding: EdgeInsets.all(5),
                                  decoration: BoxDecoration(
                                    borderRadius:
                                        BorderRadius.all(Radius.circular(AppRadii.lg)),
                                    boxShadow: AppShadows.card,
                                    color: Colors.white,
                                  ),
                                  child: ListTile(
                                    contentPadding: EdgeInsets.all(0),
                                    horizontalTitleGap: 18,
                                    leading: CircleAvatar(
                                        radius: 38,
                                        backgroundColor: AppColors.surfaceAlt,
                                        child: contactImage),
                                    title: Text(
                                      data[index]['name'],
                                      style: TextStyle(
                                          fontSize: 16.5,
                                          color: AppColors.ink),
                                    ),
                                    subtitle: Container(
                                        margin: EdgeInsets.only(top: 7.2),
                                        child: Text(tileSubtitle,style: TextStyle(fontSize: 13,color: AppColors.textMuted),)),
                                    onTap: () {
                                      Navigator.push(
                                          context,
                                          SlideRightRoute(
                                              page: FundTransferScreen(
                                            otherParty: data[index],
                                            transactionType:
                                                widget.transactionType,
                                          )));
                                    },
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
                    }
                  } else if (snapshot.hasError) {
                    children = <Widget>[
                      const Icon(
                        Icons.error_outline,
                        color: Colors.red,
                        size: 60,
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text('Error: ${snapshot.error}'),
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
                },
              ),
            ),
          )
        ],
      ),
    );
  }
}

