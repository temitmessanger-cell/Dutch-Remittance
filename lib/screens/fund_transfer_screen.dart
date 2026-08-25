import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:dutch_remit/components/fund_transfer_screen/transaction_processing_screen.dart';
import 'package:dutch_remit/database/user_data_storage.dart';
import 'package:dutch_remit/hadwin_components.dart';
import 'package:dutch_remit/screens/sign_up_screen.dart';
import 'package:dutch_remit/utilities/app_theme.dart';


class FundTransferScreen extends StatefulWidget {
  final Map<String, dynamic> otherParty;
  final String transactionType;

  const FundTransferScreen(
      {Key? key, required this.otherParty, required this.transactionType})
      : super(key: key);

  @override
  _FundTransferScreenState createState() => _FundTransferScreenState();
}

class _FundTransferScreenState extends State<FundTransferScreen> {
  late Map<String, dynamic> userData;
  late TextEditingController _transactionAmountController;
  String _controllerHelperText = "0.00";
  late String transactionButton;
  Map<String, dynamic> transactionReceipt = {};
  Map<String, dynamic>? transactionResult = null;
  bool _isGuest = false;

  late String tileSubtitle;

  @override
  void initState() {
    super.initState();
    setUserData();
    transactionButton = widget.transactionType == 'debit' ? "Send" : 'Request';
    numPadKeys =
        List<int>.generate(9, (i) => i + 1).map(_createButton).toList();

    bottomKeys = [
      ElevatedButton(
        onPressed: _addZeroes,
        child: Text(
          "0",
          style: TextStyle(
              color: AppColors.ink,
              fontSize: 24,
              fontWeight: FontWeight.w700),
        ),
        style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            shape: CircleBorder(),
            elevation: 0,
            // elevation: 0.618,
            // shadowColor: AppColors.surfaceAlt
            ),
      ),
      ElevatedButton(
        onPressed: _addDecimal,
        child: Text(
          ".",
          style: TextStyle(
              color: AppColors.ink,
              fontSize: 30,
              fontWeight: FontWeight.w700),
        ),
        style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            shape: CircleBorder(),
            // elevation: 0.618,
            elevation: 0,
            // shadowColor: AppColors.surfaceAlt
            ),
      ),
      ElevatedButton(
        onPressed: _eraseDigits,
        onLongPress: _clearTransactionAmount,
        child: Text(
          String.fromCharCode(FluentIcons.backspace_24_regular.codePoint),
          style: TextStyle(
            inherit: false,
            color: AppColors.ink,
            fontSize: 24,
            fontWeight: FontWeight.w700,
            fontFamily: FluentIcons.backspace_24_regular.fontFamily,
            package: FluentIcons.backspace_24_regular.fontPackage,
          ),
        ),
        style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            shape: CircleBorder(),
            // elevation: .618,
            // shadowColor: AppColors.surfaceAlt
            elevation: 0
            ),
      ),
    ].map((e) => Container(
      decoration: BoxDecoration(boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.1),
                                  blurRadius: 16,
                                  offset: Offset(0, 4),
                                  spreadRadius: -4)]),
      child: e,
    )).toList();
    numPadKeys.addAll(bottomKeys);
    _transactionAmountController =
        TextEditingController(text: _controllerHelperText);

    initializeTransactionReceipt();
  }

  @override
  void dispose() {
    _transactionAmountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // backgroundColor: Colors.white,
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        title: Text("$transactionButton Money",
            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.ink,
      ),
      body: Column(
        children: [
          Container(
            margin: EdgeInsets.symmetric(horizontal: 27, vertical: 3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.all(Radius.circular(AppRadii.lg)),
              boxShadow: <BoxShadow>[
                BoxShadow(
                    /*
                    color: AppColors.surfaceAlt,
                    blurRadius: 4,
                    offset: Offset(0.0, 3),
                    spreadRadius: 0
                    */
                    color: AppColors.primary.withOpacity(0.1),
                    blurRadius: 16,
                    offset: Offset(2, 8),
                    spreadRadius: -4),
              ],
              color: Colors.white,
            ),
            child: ListTile(
                contentPadding:
                    EdgeInsets.only(left: 0, top: 0, bottom: 0, right: 6.18),
                leading: CircleAvatar(
                  radius: 38,
                  backgroundColor: AppColors.surfaceAlt,
                  child: FutureBuilder<int>(
                    future: checkUrlValidity(
                        "${ApiConstants.baseUrl}/dist/images/Dutch Remit_images/brands_and_businesses/${widget.otherParty['avatar']}"),
                    builder: (context, snapshot) {
                      Widget contactImage;
                      if (widget.otherParty.containsKey('emailAddress') &&
                          widget.otherParty.containsKey('avatar') &&
                          snapshot.hasData) {
                        if (snapshot.data == 404) {
                          contactImage = ClipOval(
                            child: AspectRatio(
                              aspectRatio: 1.0 / 1.0,
                              child: Image.network(
                                "${ApiConstants.baseUrl}/dist/images/Dutch Remit_images/Dutch Remit_users/${widget.otherParty['gender']?.toString().toLowerCase() ?? ''}/${widget.otherParty['avatar']}",
                                height: 72,
                                width: 72,
                                fit: BoxFit.contain,
                              ),
                            ),
                          );
                        } else {
                          contactImage = ClipOval(
                            child: AspectRatio(
                              aspectRatio: 1.0 / 1.0,
                              child: Image.network(
                                "${ApiConstants.baseUrl}/dist/images/Dutch Remit_images/brands_and_businesses/${widget.otherParty['avatar']}",
                                height: 72,
                                width: 72,
                                fit: BoxFit.contain,
                              ),
                            ),
                          );
                        }
                      } else if (widget.otherParty.containsKey('homepage') &&
                          widget.otherParty.containsKey('avatar')) {
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
                                  "${ApiConstants.baseUrl}/dist/images/Dutch Remit_images/brands_and_businesses/${widget.otherParty['avatar']}",
                                  height: 72,
                                  width: 72,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ),
                        );
                      } else {
                        final otherPartyName =
                            widget.otherParty['name']?.toString() ?? '';
                        contactImage = Text(
                          otherPartyName.isNotEmpty
                              ? otherPartyName[0].toUpperCase()
                              : '?',
                          style:
                              TextStyle(fontSize: 20, color: AppColors.ink),
                        );
                      }

                      return contactImage;
                    },
                  ),
                ),
                title: Text(
                  widget.otherParty['name']?.toString() ?? 'Unknown',
                  style: TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink),
                ),
                subtitle: Text(tileSubtitle, style: TextStyle(fontSize: 13,color: AppColors.textMuted),)),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 27, vertical: 13),
            child: TextField(
              keyboardType: TextInputType.none,
              controller: _transactionAmountController,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppColors.surfaceAlt,
                contentPadding:
                    EdgeInsets.symmetric(vertical: 18, horizontal: 18),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                    borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                    borderSide: BorderSide(color: AppColors.primary, width: 2.0)),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                    borderSide: BorderSide.none),
                prefixIcon: Padding(
                  padding: const EdgeInsets.only(left: 18),
                  child: Text(
                    "\$",
                    style: GoogleFonts.manrope(
                        fontSize: 40,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary),
                  ),
                ),
                prefixIconConstraints: BoxConstraints(minWidth: 0, minHeight: 0),
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 190,
              padding: EdgeInsets.symmetric(horizontal: 9),
              child: GridView.count(
                crossAxisCount: 3,
                children: numPadKeys,
                crossAxisSpacing: 2,
                mainAxisSpacing: 5,
                childAspectRatio: 1.55,
              ),
            ),
          ),
          if (_isGuest)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.info_outline_rounded, size: 15, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Create an account to complete real transfers.",
                        style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Container(
            width: MediaQuery.of(context).size.width - 45,
            height: 58,
            margin: const EdgeInsets.only(bottom: 4),
            child: ElevatedButton(
              onPressed: _makeTransaction,
              child: Text(
                transactionButton,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.md))),
            ),
          ),
          SizedBox(
            height: 10,
          )
        ],
      ),
    );
  }

  void _updateHelperText(String k) {
    var cursorPos = _transactionAmountController.selection.base.offset;
    int editedOffset = _controllerHelperText.length;

    String suffixText = '', prefixText = '';

    if (cursorPos >= 0 && cursorPos < _controllerHelperText.length) {
      suffixText = _controllerHelperText.substring(cursorPos);
      prefixText = _controllerHelperText.substring(0, cursorPos);
    }

    setState(() {
      if (_controllerHelperText == "0.00") {
        _controllerHelperText = k;
        editedOffset = _controllerHelperText.length;
      } else if (cursorPos == -1 || cursorPos == _controllerHelperText.length) {
        _controllerHelperText += k;
        editedOffset = _controllerHelperText.length;
      } else {
        _controllerHelperText = prefixText + k + suffixText;
        editedOffset = cursorPos + 1;
      }
    });
    _transactionAmountController.value = TextEditingValue(
      text: _controllerHelperText,
      selection: TextSelection.fromPosition(TextPosition(offset: editedOffset)),
    );
  }

  late List<Container> bottomKeys;
  late List<Container> numPadKeys;

  void setUserData() async {
    userData = await UserDataStorage().getUserData();

    // A guest has no real account — userData will be empty or carry an
    // error marker from storage. Detect that here rather than crashing
    // further down on missing fields like bankDetails.
    final bool looksLikeGuest = userData.isEmpty ||
        userData.containsKey('localDBError') ||
        userData['email'] == null;

    if (mounted) {
      setState(() => _isGuest = looksLikeGuest);
    } else {
      _isGuest = looksLikeGuest;
    }

    if (_isGuest) return;

    transactionReceipt['transactionInitiatorName'] =
        "${userData['first_name'] ?? ''} ${userData['last_name'] ?? ''}".trim();
    transactionReceipt['transactionInitiatorEmail'] = userData['email'];
    transactionReceipt['transactionInitiatorPhoneNumber'] =
        userData['phone_number'];
    transactionReceipt['transactionInitiatorBankName'] =
        (userData['bankDetails'] is List && userData['bankDetails'].isNotEmpty)
            ? userData['bankDetails'][0]['bankName']
            : null;
    transactionReceipt['transactionInitiatorUid'] = userData['uid'];
    transactionReceipt['transactionInitiatorWalletAddress'] =
        userData['walletAddress'];
  }

  Container _createButton(digit) => Container(
        decoration: BoxDecoration(boxShadow: [
          BoxShadow(
              color: AppColors.primary.withOpacity(0.1),
              blurRadius: 16,
              offset: Offset(0, 4),
              spreadRadius: -4)
        ]),
        child: ElevatedButton(
          onPressed: () => _addDigits(digit),
          child: Text(
            digit.toString(),
            style: TextStyle(
                color: AppColors.ink,
                fontSize: 24,
                fontWeight: FontWeight.w700),
          ),
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              shape: CircleBorder(),
              elevation: 0,
              // shadowColor: AppColors.surfaceAlt
              ),
        ),
      );

  void _addDigits(int digit) {
    int cursorPos = _transactionAmountController.selection.base.offset;
    //? detect cursor position
    int validPos = cursorPos == -1 ? 0 : cursorPos;

    String desiredAmount =
        _transactionAmountController.text.substring(0, validPos) +
            digit.toString() +
            _transactionAmountController.text.substring(validPos);
    if (double.parse(desiredAmount) <= 10000 ||
        _transactionAmountController.text.isEmpty) {
      if (_controllerHelperText == "0.00") {
        _updateHelperText(digit.toString());
      } else if (!_controllerHelperText.contains('.')) {
        _updateHelperText(digit.toString());
      } else if (_controllerHelperText.contains('.') &&
          cursorPos <= _transactionAmountController.text.length - 3) {
        _updateHelperText(digit.toString());
      } else if (_controllerHelperText.contains('.') &&
          _controllerHelperText.split('.').last.length < 2) {
        _updateHelperText(digit.toString());
      }
    }
  }

  void _addZeroes() {
    int cursorPos = _transactionAmountController.selection.base.offset;

    int validPos = cursorPos == -1 ? 0 : cursorPos;

    String desiredAmount =
        _transactionAmountController.text.substring(0, validPos) +
            '0' +
            _transactionAmountController.text.substring(validPos);

    if (double.parse(desiredAmount) <= 10000 ||
        _transactionAmountController.text.isEmpty) {
      if (_controllerHelperText != "0.00" &&
          _controllerHelperText.length != 0) {
        if (!_controllerHelperText.contains('.')) {
          _updateHelperText('0');
        } else if (_controllerHelperText.contains('.') &&
            cursorPos <= _transactionAmountController.text.length - 3) {
          _updateHelperText('0');
        } else if (_controllerHelperText.contains('.') &&
            _controllerHelperText.split('.').last.length < 2) {
          _updateHelperText('0');
        }
      }
    }
  }

  void _addDecimal() {
    if (!_controllerHelperText.contains(".")) {
      setState(() {
        _controllerHelperText += ".";
      });
      _transactionAmountController.value = TextEditingValue(
        text: _controllerHelperText,
        selection: TextSelection.fromPosition(
          TextPosition(offset: _controllerHelperText.length),
        ),
      );
    }
  }

//? FUNCTIONS FOR DELETE BUTTON
  void _eraseDigits() {
    if (_controllerHelperText.length > 0) {
      var cursorPos = _transactionAmountController.selection.base.offset;
      int editedOffset = _controllerHelperText.length;

      setState(() {
        if (cursorPos == -1) {
          _controllerHelperText = _controllerHelperText.substring(
              0, _controllerHelperText.length - 1);
          editedOffset = _controllerHelperText.length;
        } else if (cursorPos == _controllerHelperText.length) {
          _controllerHelperText =
              _controllerHelperText.substring(0, cursorPos - 1);
          editedOffset = _controllerHelperText.length;
        } else if (cursorPos > 0 && cursorPos < _controllerHelperText.length) {
          _controllerHelperText =
              _controllerHelperText.substring(0, cursorPos - 1) +
                  _controllerHelperText.substring(
                      cursorPos, _controllerHelperText.length);
          editedOffset = cursorPos - 1;
        }
      });

      _transactionAmountController.value = TextEditingValue(
        text: _controllerHelperText,
        selection:
            TextSelection.fromPosition(TextPosition(offset: editedOffset)),
      );
    }
  }

  void _clearTransactionAmount() {
    setState(() {
      _controllerHelperText = "0.00";
    });
    _transactionAmountController.clear();
    _transactionAmountController.value = TextEditingValue(
      text: _controllerHelperText,
      selection: TextSelection.fromPosition(
        TextPosition(offset: _controllerHelperText.length),
      ),
    );
  }

  Future<void> _makeTransaction() async {
    if (_isGuest) {
      _showCreateAccountPrompt();
      return;
    }

    transactionReceipt['transactionAmount'] =
        double.parse(_transactionAmountController.text).toStringAsFixed(2);
    if (int.parse(transactionReceipt['transactionAmount'].split('.')[1]) == 0) {
      transactionReceipt['transactionAmount'] =
          double.parse(_transactionAmountController.text).toStringAsFixed(0);
    }
    Navigator.of(context).pop();
    Navigator.push(
        context,
        SlideRightRoute(
            page: TransactionProcessingScreen(
                transactionReceipt: transactionReceipt)));
  }

  void _showCreateAccountPrompt() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.lg)),
        title: Text("Create an account",
            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
        content: Text(
          "You're browsing as a guest, so transfers can't be completed yet. Create a free account to send and receive money for real.",
          style: TextStyle(color: AppColors.inkMuted, height: 1.4),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text("Not now", style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.sm)),
            ),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              Navigator.of(context).popUntil((route) => route.isFirst);
              Navigator.push(context, SlideRightRoute(page: SignUpScreen()));
            },
            child: Text("Create account"),
          ),
        ],
      ),
    );
  }

  void initializeTransactionReceipt() {
    transactionReceipt['transactionType'] = widget.transactionType;

    transactionReceipt['transactionMemberName'] = widget.otherParty['name'];
    transactionReceipt['transactionMemberWalletAddress'] =
        widget.otherParty['walletAddress'];
    if (widget.otherParty.containsKey('homepage')) {
      transactionReceipt['transactionMemberBusinessWebsite'] =
          widget.otherParty['homepage'];
    } else {
      transactionReceipt['transactionMemberEmail'] =
          widget.otherParty['emailAddress'];
      transactionReceipt['transactionMemberPhoneNumber'] =
          widget.otherParty['phoneNumber'];
    }

    if (widget.otherParty.containsKey('avatar')) {
      transactionReceipt['transactionMemberAvatar'] =
          widget.otherParty['avatar'];
    }

    if (widget.otherParty.containsKey('gender')) {
      transactionReceipt['transactionMemberGender'] =
          widget.otherParty['gender'];
    }

    //? TILE SUBTITLE TEXT
    // These map values arrive as `dynamic` from JSON/local storage and
    // can genuinely be null (a contact with no phone or email saved) —
    // assigning null straight into `tileSubtitle` (a non-nullable
    // `late String`) throws "type 'Null' is not a subtype of type
    // 'String'" the instant this screen builds. Guard every branch.
    if (widget.otherParty.containsKey('emailAddress') &&
        widget.otherParty.containsKey('avatar')) {
      tileSubtitle = widget.otherParty['emailAddress']?.toString() ?? '';
    } else if (widget.otherParty.containsKey('homepage') &&
        widget.otherParty.containsKey('avatar')) {
      tileSubtitle = widget.otherParty['homepage']?.toString() ?? '';
    } else {
      tileSubtitle = widget.otherParty['phoneNumber']?.toString() ?? '';
    }
  }
}


