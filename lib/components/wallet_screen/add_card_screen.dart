import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:dutch_remit/components/add_card_screen/card_flipper.dart';

import 'package:dutch_remit/utilities/card_identifier.dart';
import 'package:dutch_remit/utilities/app_theme.dart';
import 'package:dutch_remit/utilities/make_api_request.dart';
import 'package:dutch_remit/components/shared/transaction_receipt_dialog.dart';

class AddCardScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  final String? userAuthKey;
  final Map<String, String> identity;
  const AddCardScreen({
    Key? key,
    required this.user,
    this.userAuthKey,
    required this.identity,
  }) : super(key: key);

  @override
  _AddCardScreenState createState() => _AddCardScreenState();
}

class _AddCardScreenState extends State<AddCardScreen>
    with SingleTickerProviderStateMixin {
  late List<Widget> cardInputFields;
  late TextEditingController _cardNumberInputController;
  late TextEditingController _expiryDateInputController;
  late TextEditingController _cvvInputController;
  late TextEditingController _cardHolderInputController;

  late CardFlippingController cardFlipper;

  late FocusScopeNode cardDetailsFocusNodes;
  late AnimationController cardSwitcher;
  late Animation<double> sides;

  Map<String, String> cardDetails = {
    'cardNumber': '',
    'expiryDate': '',
    'cvv': '',
    'cardHolder': ''
  };

  int _currentStep = 0;
  bool _isSubmitting = false;
  String? _linkErrorMessage;
  String cardBrand = "default";
  Image currentCardFrontSideImage = Image.asset(
    'assets/images/card_flow_assets/default-frontside.png',
    key: ValueKey(0),
  );
  late Image currentCardBackSideImage;

  @override
  void initState() {
    super.initState();
    _cardNumberInputController = TextEditingController(text: "");
    _expiryDateInputController = TextEditingController(text: "");
    _cvvInputController = TextEditingController(text: "");
    _cardHolderInputController = TextEditingController(text: "");

    cardFlipper = CardFlippingController();

    cardDetailsFocusNodes = FocusScopeNode();
    cardInputFields = getCardInputFields();
    cardSwitcher =
        AnimationController(vsync: this, duration: Duration(milliseconds: 900));

    sides = Tween<double>(begin: 0.0, end: 1.0).animate(cardSwitcher);

    currentCardBackSideImage =
        Image.asset('assets/images/card_flow_assets/$cardBrand-backside.png');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    precacheImage(currentCardFrontSideImage.image, context);
    precacheImage(currentCardBackSideImage.image, context);
  }

  @override
  void dispose() {
    _cardNumberInputController.dispose();
    _expiryDateInputController.dispose();
    _cvvInputController.dispose();
    _cardHolderInputController.dispose();
    cardSwitcher.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget cardFrontSide = Stack(
      children: [
        AnimatedSwitcher(
          duration: Duration(milliseconds: 900),
          reverseDuration: Duration(seconds: 210),
          switchInCurve: Curves.linear,
          child: currentCardFrontSideImage,
          transitionBuilder: (Widget child, sides) {
            return AnimatedBuilder(
              animation: sides,
              child: child,
              builder: (BuildContext context, Widget? child) {
                return ClipPath(
                  clipper: CardClipperLeftToRight2(sideValue: sides.value),
                  child: child,
                );
              },
            );
          },
        ),
        Positioned.fill(
            child: Align(
          alignment: Alignment.center,
          child: Text(
            _cardNumberInputController.text.isEmpty
                ? "XXXX XXXX XXXX 1234"
                : _cardNumberInputController.text,
            style: TextStyle(
              fontFamily: 'OCRA',
              color: Colors.white,
              fontSize: 19,
              shadows: <Shadow>[
                Shadow(
                  offset: Offset(1.0, 1.0),
                  blurRadius: 3.0,
                  color: Color.fromARGB(255, 0, 0, 0).withOpacity(0.2),
                ),
                Shadow(
                  offset: Offset(1.0, 1.0),
                  blurRadius: 8.0,
                  color: cardLabelColors[cardBrand]!.withOpacity(0.5),
                ),
              ],
            ),
          ),
        )),
        Positioned(
            left: 16,
            bottom: 30,
            child: Wrap(
              direction: Axis.vertical,
              spacing: 3.6,
              children: [
                Text(
                  'CARD HOLDER',
                  style: GoogleFonts.inconsolata(
                    color: cardLabelColors[cardBrand],
                    fontSize: 11,
                  ),
                ),
                Text(
                  _cardHolderInputController.text.isEmpty
                      ? "JOHN DOE"
                      : _cardHolderInputController.text.toUpperCase(),
                  style: TextStyle(
                    fontFamily: 'OCRA',
                    color: Colors.white,
                    fontSize: 14,
                    shadows: <Shadow>[
                      Shadow(
                        offset: Offset(1.0, 1.0),
                        blurRadius: 3.0,
                        color: Color.fromARGB(255, 0, 0, 0).withOpacity(0.2),
                      ),
                      Shadow(
                        offset: Offset(1.0, 1.0),
                        blurRadius: 8.0,
                        color: cardLabelColors[cardBrand]!.withOpacity(0.5),
                      ),
                    ],
                  ),
                )
              ],
            )),
        Positioned(
            right: 18,
            bottom: 30,
            child: Wrap(
              direction: Axis.vertical,
              spacing: 3.6,
              children: [
                Text(
                  'EXPIRES',
                  style: GoogleFonts.inconsolata(
                    color: cardLabelColors[cardBrand],
                    fontSize: 11,
                  ),
                ),
                Text(
                  _expiryDateInputController.text.isEmpty
                      ? "MM/YY"
                      : _expiryDateInputController.text,
                  style: TextStyle(
                    fontFamily: 'OCRA',
                    color: Colors.white,
                    fontSize: 14,
                    shadows: <Shadow>[
                      Shadow(
                        offset: Offset(1.0, 1.0),
                        blurRadius: 3.0,
                        color: Color.fromARGB(255, 0, 0, 0).withOpacity(0.2),
                      ),
                      Shadow(
                        offset: Offset(1.0, 1.0),
                        blurRadius: 8.0,
                        color: cardLabelColors[cardBrand]!.withOpacity(0.5),
                      ),
                    ],
                  ),
                )
              ],
            ))
      ],
    );

    Widget cardBackSide = Stack(
      children: [
        currentCardBackSideImage,
        Positioned(
            right: 27,
            top: (MediaQuery.of(context).size.width - 60) * .22,
            child: Text(
              _cvvInputController.text.isEmpty
                  ? "123"
                  : _cvvInputController.text,
              style: GoogleFonts.inconsolata(
                color: Colors.black,
                fontSize: 18,
              ),
            ))
      ],
    );

    Widget cardHoldingSpace = Container(
        // width: double.infinity,
        width: MediaQuery.of(context).size.width,
        height: 9 * MediaQuery.of(context).size.width / 16,
        padding: EdgeInsets.symmetric(horizontal: 30),
        child: CardFlipper(
            cardFlippingController: cardFlipper,
            transitionDuration: Duration(milliseconds: 960),
            frontSide: cardFrontSide,
            backSide: cardBackSide));

    Widget stepDots = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(cardInputFields.length, (i) {
        final bool isActive = i == _currentStep;
        final bool isDone = i < _currentStep;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: isActive ? 22 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: isActive || isDone ? AppColors.primary : AppColors.border,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );

    Widget cardInputFieldsSpace = Container(
      width: MediaQuery.of(context).size.width,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          stepDots,
          const SizedBox(height: 20),
          FocusScope(
            node: cardDetailsFocusNodes,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0.08, 0), end: Offset.zero)
                      .animate(animation),
                  child: child,
                ),
              ),
              child: KeyedSubtree(
                key: ValueKey(_currentStep),
                child: cardInputFields[_currentStep],
              ),
            ),
          ),
        ],
      ),
    );
    Widget goBackToPreviousStepButton = TextButton(
        onPressed: backToPreviousStep,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          foregroundColor: AppColors.primary,
        ),
        child: Text(
          "Back",
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ));
    Widget goToNextStepButton = ElevatedButton(
        onPressed: proceedToNextStep,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
        ),
        child: Text(
          "Next",
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
        ));
    Widget completedAllStepsButton = ElevatedButton(
        onPressed: _isSubmitting ? null : _tryAddingCard,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
        ),
        child: _isSubmitting
            ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
            : Text(
                "Done",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
              ));

    Widget cardInputNavigationButtons = Container(
      width: MediaQuery.of(context).size.width,
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_linkErrorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(_linkErrorMessage!, style: TextStyle(color: AppColors.danger, fontSize: 13)),
            ),
          _currentStep < 3
          ? Row(
              children: [
                if (_currentStep > 0) ...[
                  Expanded(child: goBackToPreviousStepButton),
                  const SizedBox(width: 12),
                ],
                Expanded(flex: _currentStep > 0 ? 1 : 1, child: goToNextStepButton),
              ],
            )
          : _cardHolderInputController.text.isNotEmpty
              ? SizedBox(width: double.infinity, child: completedAllStepsButton)
              : SizedBox(width: double.infinity, child: goBackToPreviousStepButton),
        ],
      ),
    );


    return WillPopScope(
      onWillPop: () => Future.value(false),
      child: Scaffold(
        backgroundColor: AppColors.surfaceSunken,
        appBar: MediaQuery.of(context).viewInsets.bottom == 0
            ? AppBar(
                title: Text("Add New Card"),
                centerTitle: true,
                backgroundColor: Colors.transparent,
                elevation: 0,
                foregroundColor: AppColors.ink,
                leading: IconButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    icon: Icon(Icons.arrow_back)),
              )
            : null,
        body: Container(
          height: MediaQuery.of(context).size.height,
          width: MediaQuery.of(context).size.width,
          child: Stack(
            children: [
              Positioned(
                bottom: MediaQuery.of(context).viewInsets.bottom == 0 ? null : 0,
                child: Column(
                  children: <Widget>[
                    SizedBox(
                      height: MediaQuery.of(context).viewInsets.bottom == 0 ? 16 : 84,
                    ),
                    cardHoldingSpace,
                    SizedBox(
                      height: MediaQuery.of(context).size.height > 700 ? 36 : 18,
                    ),
                    cardInputFieldsSpace,
                    cardInputNavigationButtons,
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _tryAddingCard() async {
    FocusManager.instance.primaryFocus?.unfocus();

    final expiryParts = _expiryDateInputController.text.split('/');
    if (expiryParts.length != 2 || _cardNumberInputController.text.replaceAll(' ', '').isEmpty) {
      setState(() => _linkErrorMessage = "Please complete every field.");
      return;
    }

    setState(() {
      _isSubmitting = true;
      _linkErrorMessage = null;
    });

    // The CVV is read here to send this one request and is never
    // stored anywhere past this call — see Backend/src/routes/cards.js
    // POST /link and linked_cards' schema comment for why.
    final result = await sendData(
      urlPath: "/api/v1/cards/link",
      data: {
        ...widget.identity,
        'cardNumber': _cardNumberInputController.text.replaceAll(' ', ''),
        'expiryMonth': expiryParts[0],
        'expiryYear': expiryParts[1],
        'cvv': _cvvInputController.text,
        'cardholderName': _cardHolderInputController.text.trim(),
      },
      authKey: widget.userAuthKey,
    );

    // Clear the CVV field the instant the request has been sent —
    // nothing downstream in this widget needs it again.
    _cvvInputController.clear();

    if (!mounted) return;

    if (result.containsKey('apiRequestError') || result['error'] != null) {
      setState(() {
        _isSubmitting = false;
        _linkErrorMessage = result['error']?.toString() ?? result['apiRequestError'].toString();
      });
      return;
    }

    setState(() => _isSubmitting = false);

    final linkedCard = result['linkedCard'] is Map ? Map<String, dynamic>.from(result['linkedCard']) : {};
    final feeCharged = double.tryParse(result['feeCharged']?.toString() ?? '') ?? 2.1;

    await showTransactionReceipt(
      context,
      title: "Card linked",
      amountLine: linkedCard['masked_card_number']?.toString() ?? "Card linked",
      fields: [
        ReceiptField("Card", linkedCard['masked_card_number']?.toString() ?? '—'),
        ReceiptField("Retrieval fee", "\$${feeCharged.toStringAsFixed(2)}"),
      ],
      reference: 'DR-LINK-${DateTime.now().millisecondsSinceEpoch}',
    );

    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  //? FUNCTION FOR MOVING TO NEXT STEP
  void proceedToNextStep() {
    int temporaryStepStore = _currentStep;
    if (_currentStep < cardInputFields.length - 1) {
      temporaryStepStore++;

      if (temporaryStepStore == 2 || temporaryStepStore == 3) {
        cardFlipper.flipCard().then((bool flipped) {
          if (flipped) {
            setState(() {
              _currentStep = temporaryStepStore;
            });
            cardDetailsFocusNodes.nextFocus();
          }
        });
      } else {
        setState(() {
          _currentStep = temporaryStepStore;
        });
        cardDetailsFocusNodes.nextFocus();
      }
    }
  }

//? FUNCTION FOR RETURNING TO PREVIOUS STEP
  void backToPreviousStep() {
    int temporaryStepStore = _currentStep;
    if (_currentStep > 0) {
      temporaryStepStore -= 1;

      if (temporaryStepStore == 2 || temporaryStepStore == 1) {
        cardFlipper.flipCard().then((bool flipped) {
          if (flipped) {
            setState(() {
              _currentStep = temporaryStepStore;
            });
            cardDetailsFocusNodes.previousFocus();
          }
        });
      } else {
        setState(() {
          _currentStep = temporaryStepStore;
        });
        cardDetailsFocusNodes.previousFocus();
      }
    }
  }

//? FUNCTION FOR FORMATTING CARD NUMBER
  String _formatCardNumber(String currentCardNumber) {
    String formattedCardNumber = "";
    if (cardBrand == 'american-express' ||
        RegExp(r'^3[47]').hasMatch(currentCardNumber)) {
      for (var i = 0; i < currentCardNumber.length; i++) {
        formattedCardNumber += currentCardNumber[i];
        if (i == 3 || i == 9) {
          formattedCardNumber += ' ';
        }
      }
    } else {
      for (var i = 0; i < currentCardNumber.length; i++) {
        formattedCardNumber += currentCardNumber[i];
        if ((i + 1) % 4 == 0) {
          formattedCardNumber += ' ';
        }
      }
    }
    return formattedCardNumber.trim();
  }

  Map<String, int> cardNumberMaxLengths = {
    'american-express': 15,
    'discover': 16,
    'maestro': 16,
    'mastercard': 16,
    'visa': 16,
  };

  Map<String, Color> cardLabelColors = {
    'american-express': Colors.transparent,
    'discover': AppColors.danger,
    'maestro': Color(0xff90e0ff),
    'mastercard': Color(0xff590d22),
    'visa': Color(0xffe0aaff),
    'default': Colors.white
  };

  List<Widget> getCardInputFields() {
    TextStyle inputLabelStyle = TextStyle(
        color: AppColors.textMuted, fontWeight: FontWeight.w600, fontSize: 13, letterSpacing: 0.4);
    TextStyle inputTextStyle = TextStyle(
        color: AppColors.ink, fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: 1.2);
    InputDecoration cleanDecoration = InputDecoration(
      filled: true,
      fillColor: AppColors.surfaceAlt,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md), borderSide: BorderSide.none),
    );

    return [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("CARD NUMBER", style: inputLabelStyle),
          const SizedBox(height: 10),
          TextField(
            controller: _cardNumberInputController,
            enableSuggestions: false,
            showCursor: true,
            autofocus: true,
            autocorrect: false,
            autofillHints: null,
            onChanged: _onCardNumberChanged,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            style: inputTextStyle,
            inputFormatters: [
              LengthLimitingTextInputFormatter(19),
              FilteringTextInputFormatter.allow(RegExp('[0-9]'))
            ],
            decoration: cleanDecoration.copyWith(hintText: "1234 5678 9012 3456"),
          ),
        ],
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("EXPIRY DATE", style: inputLabelStyle),
          const SizedBox(height: 10),
          TextField(
            controller: _expiryDateInputController,
            showCursor: true,
            autofocus: true,
            enableSuggestions: false,
            autocorrect: false,
            autofillHints: null,
            onChanged: _onExpiryDateChanged,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            style: inputTextStyle,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
              _ExpiryDateInputFormatter(),
            ],
            decoration: cleanDecoration.copyWith(hintText: "MM/YY"),
          ),
        ],
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("CVV / CVC", style: inputLabelStyle),
          const SizedBox(height: 10),
          TextField(
            controller: _cvvInputController,
            onChanged: (value) {
              setState(() {});
              if (value.length == 3) {
                proceedToNextStep();
              }
            },
            showCursor: true,
            autofocus: true,
            enableSuggestions: false,
            autocorrect: false,
            autofillHints: null,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            style: inputTextStyle,
            inputFormatters: [
              LengthLimitingTextInputFormatter(3),
              FilteringTextInputFormatter.allow(RegExp('[0-9]'))
            ],
            decoration: cleanDecoration.copyWith(hintText: "123"),
          ),
        ],
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("CARD HOLDER'S NAME", style: inputLabelStyle),
          const SizedBox(height: 10),
          TextField(
            controller: _cardHolderInputController,
            keyboardType: TextInputType.visiblePassword,
            textInputAction: TextInputAction.done,
            showCursor: true,
            autofocus: true,
            enableSuggestions: false,
            autocorrect: false,
            autofillHints: null,
            onChanged: (value) {
              setState(() {});
            },
            onSubmitted: (_) => _tryAddingCard(),
            style: inputTextStyle.copyWith(fontSize: 18, letterSpacing: 0.6),
            inputFormatters: [
              LengthLimitingTextInputFormatter(19),
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z]|\s'))
            ],
            decoration: cleanDecoration.copyWith(hintText: "JOHN DOE"),
          ),
        ],
      ),
    ];
  }

  void _onExpiryDateChanged(value) {
    setState(() {});
    if (RegExp(r"^\d{1,2}\/\d{2}$").hasMatch(_expiryDateInputController.text)) {
      proceedToNextStep();
    }
  }

  void _onCardNumberChanged(value) {
    var cursorPos = _cardNumberInputController.selection.base.offset;

    String formattedCardNumber = _formatCardNumber(value.replaceAll(' ', ''));
    _cardNumberInputController.value = TextEditingValue(
      text: formattedCardNumber,
      selection: TextSelection.fromPosition(TextPosition(
          offset: (formattedCardNumber.length -
                  value.replaceAll(' ', '').length +
                  cursorPos)
              .toInt())),
    );
    setState(() {});
    String currentCardBrand = identifyCardShorter(value);
    if (currentCardBrand != cardBrand) {
      setState(() {
        cardBrand = currentCardBrand;
        if (cardBrand == 'default') {
          currentCardFrontSideImage = Image.asset(
            'assets/images/card_flow_assets/default-frontside.png',
            key: ValueKey(1),
          );

          currentCardBackSideImage = Image.asset(
              'assets/images/card_flow_assets/$cardBrand-backside.png');
        } else {
          int randomValueKey = Random().nextInt(20) + 2;
          currentCardFrontSideImage = Image.asset(
            'assets/images/card_flow_assets/$cardBrand-frontside.png',
            key: ValueKey(randomValueKey),
          );

          currentCardBackSideImage = Image.asset(
              'assets/images/card_flow_assets/$cardBrand-backside.png');
        }
        precacheImage(currentCardFrontSideImage.image, context);
        precacheImage(currentCardBackSideImage.image, context);
      });
    }

    if (cardBrand != 'default' &&
        _cardNumberInputController.text.replaceAll(' ', '').length ==
            cardNumberMaxLengths[cardBrand]) {
      proceedToNextStep();
    }
  }

  String formatExpiryDate(String value) {
    // Legacy manual formatter kept only as a fallback for any external
    // caller — actual live formatting now happens synchronously in
    // _ExpiryDateInputFormatter below, which fixed a lag/cursor-jump
    // bug caused by this method's async setState + manual cursor math
    // running on every keystroke.
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length <= 2) return digits;
    return '${digits.substring(0, 2)}/${digits.substring(2, digits.length > 4 ? 4 : digits.length)}';
  }
}

/// Formats raw digit input into "MM/YY" as the user types, entirely
/// within [TextInputFormatter.formatEditUpdate] — synchronous, with no
/// setState round-trip and no manual cursor-position bookkeeping. This
/// replaces the old approach (formatting inside onChanged, then
/// re-assigning the controller's value with hand-computed cursor
/// offsets) which was the source of the laggy, jumpy expiry field.
class _ExpiryDateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final limited = digits.length > 4 ? digits.substring(0, 4) : digits;

    String formatted;
    if (limited.length <= 2) {
      formatted = limited;
    } else {
      formatted = '${limited.substring(0, 2)}/${limited.substring(2)}';
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class CardClipperLeftToRight2 extends CustomClipper<Path> {
  double sideValue;
  CardClipperLeftToRight2({required this.sideValue});
  @override
  Path getClip(Size size) {
    Path path = Path();

    if (0.3 + sideValue < 1) {
      path.lineTo(size.width * (0.3 + sideValue), 0);
      path.lineTo(size.width * sideValue, size.height);
      path.lineTo(0, size.height);
    } else {
      path.lineTo(size.width, 0);
      path.lineTo(size.width, size.height * sideValue);
      path.lineTo(size.width * sideValue, size.height);
      path.lineTo(0, size.height);
    }

    path.close();

    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) {
    return true;
  }
}

