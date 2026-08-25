import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:grouped_list/grouped_list.dart';

import 'package:dutch_remit/components/fund_transfer_screen/transaction_receipt_screen.dart';

import 'package:dutch_remit/hadwin_components.dart';
import 'package:dutch_remit/utilities/app_theme.dart';

class AllTransactionActivities extends StatefulWidget {
  final Map<String, dynamic> user;
  final String userAuthKey;
  final Function setTab;
  const AllTransactionActivities(
      {Key? key,
      required this.user,
      required this.userAuthKey,
      required this.setTab})
      : super(key: key);

  @override
  AllTransactionActivitiesState createState() =>
      AllTransactionActivitiesState();
}

class AllTransactionActivitiesState extends State<AllTransactionActivities> {
  List<dynamic> allTransactions = [];
  bool isLoadingTransactions = true;
  List<bool> _activeToggleMenu = [true, false, false];
  Map<String, dynamic>? error = null;
  late TextEditingController activitySearch;
  
  Widget appBarTitle =
      Text("Payments", style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w700));
  Icon actionIcon = Icon(
    FluentIcons.search_24_regular,
    color: AppColors.ink,
  );
  @override
  void initState() {
    super.initState();

    getTransactionsFromApi();
    
    activitySearch = TextEditingController();
    
  }

  void _updateTransactions() {
    if (mounted) {
      setState(() {
       
        allTransactions.sort(
            (a, b) => b['transactionDate'].compareTo(a['transactionDate']));
        for (var transaction in allTransactions) {
          String dateResponse =
              customGroup(DateTime.parse(transaction['transactionDate']));
          transaction['dateGroup'] = dateResponse;
        }
      });
    }
  }

  void getTransactionsFromApi() async {
    final response = await Future.wait([
      getData(
          urlPath: "/Dutch Remit/v1/all-transactions", authKey: widget.userAuthKey),
      SuccessfulTransactionsStorage().getSuccessfulTransactions()
    ]);

    final bool serverFailed =
        response[0].keys.join().toLowerCase().contains("error");
    final bool localFailed =
        response[1].keys.join().toLowerCase().contains("error");

    // A dead/unreachable backend (e.g. a spun-down free-tier host)
    // shouldn't block the whole screen behind a raw exception dialog
    // when there's perfectly good locally-stored transaction history
    // to fall back on. Only show the error state if *both* sources
    // failed — otherwise degrade quietly to whichever data is available.
    if (serverFailed && localFailed) {
      setState(() {
        error = response[1];
        isLoadingTransactions = false;
      });
    } else {
      if (mounted) {
        setState(() {
          allTransactions = [
            if (!serverFailed) ...response[0]['transactions'],
            if (!localFailed) ...response[1]['transactions'],
          ];
          isLoadingTransactions = false;
        });
        _updateTransactions();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: AppColors.scaffold,
        appBar: AppBar(
          title: appBarTitle,
          centerTitle: true,
          actions: [
            IconButton(
                onPressed: () {
                  if (actionIcon.icon == FluentIcons.search_24_regular) {
                    setState(() {
                      appBarTitle = Container(
                        height: 48,
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                            color: AppColors.surfaceAlt,
                            borderRadius:
                                BorderRadius.all(Radius.circular(16.18))),
                        child: TextField(
                          controller: activitySearch,
                      
                          autofocus: true,
                          textAlignVertical: TextAlignVertical.center,
                          onChanged: (value) {
                            setState(() {});
                          },
                          style: TextStyle(color: AppColors.textMuted),
                          decoration: InputDecoration(
                              contentPadding: EdgeInsets.all(6.18),
                              focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                      color: AppColors.surfaceAlt, width: 1.618),
                                  borderRadius:
                                      BorderRadius.all(Radius.circular(16))),
                              enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                      color: AppColors.surfaceAlt, width: 1.618),
                                  borderRadius:
                                      BorderRadius.all(Radius.circular(16))),
                              hintText: 'Search...',
                              hintStyle: TextStyle(
                                color: AppColors.textMuted,
                              )),
                        ),
                      );

                      actionIcon = Icon(
                        Icons.close,
                        color: AppColors.ink,
                      );
                    });
                  
                  } else {
               
                    activitySearch.clear();
                    FocusManager.instance.primaryFocus?.unfocus();
                    setState(() {
                      appBarTitle = Text("Payments",
                          style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w700));
                      actionIcon = Icon(
                        FluentIcons.search_24_regular,
                        color: AppColors.ink,
                      );
                    });
                  }
                },
                icon: actionIcon),
          ],
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        extendBodyBehindAppBar: true,
        body: Column(children: <Widget>[
          SizedBox(
            height: 96,
          ),
          Container(
          
            decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(10)),
            child: ToggleButtons(
              borderRadius: BorderRadius.circular(10),
              color: AppColors.textMuted,
              fillColor: AppColors.primary,
              selectedColor: Colors.white,
             
              renderBorder: false,
              children: <Widget>[
                Padding(
                    padding: EdgeInsets.symmetric(horizontal: 15),
                    child: Text(
                      "All",
                      style: TextStyle(fontSize: 16),
                    )),
                Padding(
                    padding: EdgeInsets.symmetric(horizontal: 15),
                    child: Text(
                      "Sent",
                      style: TextStyle(fontSize: 16),
                    )),
                Padding(
                    padding: EdgeInsets.symmetric(horizontal: 15),
                    child: Text(
                      "Received",
                      style: TextStyle(fontSize: 16),
                    )),
              ],
              onPressed: (int index) {
                setState(() {
                  for (int buttonIndex = 0;
                      buttonIndex < _activeToggleMenu.length;
                      buttonIndex++) {
                    if (buttonIndex == index) {
                      _activeToggleMenu[buttonIndex] = true;
                    } else {
                      _activeToggleMenu[buttonIndex] = false;
                    }
                  }
                });
              },
              isSelected: _activeToggleMenu,
            ),
          ),
          SizedBox(
            height: 25,
          ),
          Expanded(
              child: Container(
            width: double.infinity,
            child: Builder(builder: (context) {
              if (error != null) {
                WidgetsBinding.instance!.addPostFrameCallback(
                    (_) => showErrorAlert(context, error!));

                return activitiesLoadingList(10);
              } else if (isLoadingTransactions) {
                return activitiesLoadingList(10);
              } else if (allTransactions.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(FluentIcons.receipt_24_regular,
                            size: 40, color: AppColors.textMuted),
                        const SizedBox(height: 14),
                        Text(
                          "No payments yet",
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink,
                              fontSize: 16),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          "Sent and received payments will show up here.",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 13.5),
                        ),
                      ],
                    ),
                  ),
                );
              } else if (error == null) {
                List<dynamic> currentTransactions;
                if (activitySearch.text.isEmpty) {
                  currentTransactions = List.from(allTransactions);
                } else {
                  List<dynamic> nameMatch = allTransactions
                      .where((transaction) =>
                          RegExp("${activitySearch.text.toLowerCase()}")
                              .hasMatch(transaction['transactionMemberName']
                                  .toLowerCase()))
                      .toList();
                  List<dynamic> dateMatch = allTransactions
                      .where((transaction) =>
                          RegExp("${activitySearch.text.toLowerCase()}")
                              .hasMatch(dateFormatter(
                                      transaction['dateGroup'],
                                      DateTime.parse(
                                          transaction['transactionDate']))
                                  .toLowerCase()))
                      .toList();
                  List<dynamic> amountMatch = allTransactions
                      .where((transaction) =>
                          RegExp("${activitySearch.text.toLowerCase()}")
                              .hasMatch(transaction['transactionAmount']
                                  .toString()
                                  .toLowerCase()))
                      .toList();
                  currentTransactions = [
                    ...nameMatch,
                    ...dateMatch,
                    ...amountMatch
                  ].toSet().toList();
                }
                if (_activeToggleMenu[1] == true) {
                  currentTransactions = currentTransactions
                      .where((transaction) =>
                          transaction['transactionType'] == 'debit')
                      .toList();
                }
                if (_activeToggleMenu[2] == true) {
                  currentTransactions = currentTransactions
                      .where((transaction) =>
                          transaction['transactionType'] == 'credit')
                      .toList();
                }

                if (currentTransactions.isEmpty) {
                  return Center(
                    child: Text('no matches found'),
                  );
                } else {
                  return Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: GroupedListView<dynamic, String>(
                      padding: EdgeInsets.all(0),
                      groupComparator: (a, b) => customGroupComparator(a, b),
                      useStickyGroupSeparators: true,
                      stickyHeaderBackgroundColor: Color.fromARGB(252, 252, 252, 252),
                      elements: currentTransactions,
                      groupBy: (transaction) => transaction['dateGroup'],
                      
                      groupSeparatorBuilder: (String groupByValue) => Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Text(
                          groupByValue,
                          style: TextStyle(color: Colors.blueGrey.shade700),
                        ),
                      ),
                      separator: Divider(
                        height: 14,
                        color: Colors.transparent,
                      ),
                      itemComparator: (a, b) =>
                          DateTime.parse(b['transactionDate'])
                              .compareTo(DateTime.parse(a['transactionDate'])),
                      itemBuilder: (context, transaction) {
                        Widget transactionMemberImage = FutureBuilder<int>(
                          future: checkUrlValidity(
                              "${ApiConstants.baseUrl}/dist/images/Dutch Remit_images/brands_and_businesses/${transaction['transactionMemberAvatar']}"),
                          builder: (context, snapshot) {
                            if (transaction.containsKey(
                                    'transactionMemberBusinessWebsite') &&
                                transaction
                                    .containsKey('transactionMemberAvatar')) {
                              return ClipOval(
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
                                        "${ApiConstants.baseUrl}/dist/images/Dutch Remit_images/brands_and_businesses/${transaction['transactionMemberAvatar']}",
                                        height: 72,
                                        width: 72,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            } else if (transaction
                                    .containsKey('transactionMemberEmail') &&
                                transaction
                                    .containsKey('transactionMemberAvatar') &&
                                snapshot.hasData) {
                              if (snapshot.data == 404) {
                                return ClipOval(
                                  child: AspectRatio(
                                    aspectRatio: 1.0 / 1.0,
                                    child: Image.network(
                                      "${ApiConstants.baseUrl}/dist/images/Dutch Remit_images/Dutch Remit_users/${transaction['transactionMemberGender']?.toString().toLowerCase() ?? ''}/${transaction['transactionMemberAvatar']}",
                                      height: 72,
                                      width: 72,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                );
                              } else {
                                return ClipOval(
                                  child: AspectRatio(
                                    aspectRatio: 1.0 / 1.0,
                                    child: Image.network(
                                      "${ApiConstants.baseUrl}/dist/images/Dutch Remit_images/brands_and_businesses/${transaction['transactionMemberAvatar']}",
                                      height: 72,
                                      width: 72,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                );
                              }
                            } else {
                              return Text(
                                transaction['transactionMemberName'][0]
                                    .toUpperCase(),
                                style: TextStyle(
                                    fontSize: 20, color: AppColors.ink),
                              );
                            }
                          },
                        );

                        return Container(
                          padding: EdgeInsets.all(5),
                        
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.all(Radius.circular(AppRadii.lg)),
                            boxShadow: AppShadows.card,
                            color: Colors.white,
                          ),
                          child: ListTile(
                            contentPadding: EdgeInsets.only(
                                left: 0, top: 0, bottom: 0, right: 6.18),
                            leading: CircleAvatar(
                                radius: 38,
                                backgroundColor: AppColors.surfaceAlt,
                                child: transactionMemberImage),
                            title: Text(
                              transaction['transactionMemberName'],
                              style: TextStyle(
                                  fontSize: 16.5, color: AppColors.ink),
                            ),
                            subtitle: Padding(
                              padding: EdgeInsets.symmetric(vertical: 5),
                              child: Text(
                                dateFormatter(
                                    transaction['dateGroup'],
                                    DateTime.parse(
                                        transaction['transactionDate'])),
                                style: TextStyle(
                                    fontSize: 12, color: AppColors.textMuted),
                              ),
                            ),
                            trailing: Text(
                              transaction['transactionType'] == "credit"
                                  ? "+ \$ ${transaction['transactionAmount'].toString()}"
                                  : "- \$ ${transaction['transactionAmount'].toString()}",
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      transaction['transactionType'] == "credit"
                                          ? AppColors.success
                                          : AppColors.danger),
                            ),
                            onTap: () => _viewTransactionReceipt(transaction),
                          ),
                        );
                      },
                    ),
                  );
                }
              } else {
                return activitiesLoadingList(10);
              }
            }),
          )),
        ]));
  }

  void _viewTransactionReceipt(Map<String, dynamic> transaction) {
    Map<String, dynamic> transactionReceipt = {};
    transactionReceipt.addAll(transaction);
    if (!transactionReceipt.containsKey('transactionInitiatorName')) {
      transactionReceipt.addAll({
        'transactionInitiatorName':
            widget.user['first_name'] + " " + widget.user['last_name'],
        'transactionInitiatorPhoneNumber': widget.user['phone_number'],
        'transactionInitiatorEmail': widget.user['email'],
        'transactionInitiatorBankName': widget.user['bankDetails'][0]
            ['bankName'],
        'transactionInitiatorUid': widget.user['uid'],
        'transactionInitiatorWalletAddress': widget.user['walletAddress']
      });
    }
    Navigator.push(
        context,
        SlideRightRoute(
            page: TransactionReceiptScreen(
          transactionReceipt: transactionReceipt,
          transactionStatus: "successful",
        )));
  }
}

