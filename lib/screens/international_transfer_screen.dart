import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dutch_remit/database/currency_conversion_service.dart';
import 'package:dutch_remit/utilities/app_theme.dart';
import 'package:dutch_remit/utilities/currency_country_data.dart';
import 'package:dutch_remit/utilities/slide_right_route.dart';
import 'package:dutch_remit/components/international_transfer/currency_picker_sheet.dart';
import 'package:dutch_remit/screens/international_transfer_review_screen.dart';
import 'package:dutch_remit/components/shared/transfer_info_widgets.dart';

/// "Global Transfer" sub-tab content: pick a send and receive currency,
/// type an amount, and see a real, live exchange rate quote (sourced
/// from the same Frankfurter/ECB-backed service the rest of the app
/// uses) — matching the "You send / They get" layout from Wise's own
/// transfer screen. This is the general-purpose corridor, open to any
/// of the 31 currencies this app can really price.
class GlobalTransferTabContent extends StatefulWidget {
  final Map<String, dynamic> user;
  const GlobalTransferTabContent({Key? key, required this.user}) : super(key: key);

  @override
  State<GlobalTransferTabContent> createState() =>
      _GlobalTransferTabContentState();
}

class _GlobalTransferTabContentState
    extends State<GlobalTransferTabContent> {
  final CurrencyConversionService _currencyService = CurrencyConversionService();
  final TextEditingController _amountController =
      TextEditingController(text: '1000');

  String _sendCurrency = 'USD';
  String _receiveCurrency = 'PHP';

  double? _convertedAmount;
  double? _exchangeRate;
  bool _isQuoting = false;
  String? _quoteError;

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _fetchQuote();
    _amountController.addListener(_onAmountChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _amountController.removeListener(_onAmountChanged);
    _amountController.dispose();
    super.dispose();
  }

  void _onAmountChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _fetchQuote);
  }

  Future<void> _fetchQuote() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      setState(() {
        _convertedAmount = null;
        _exchangeRate = null;
        _quoteError = null;
      });
      return;
    }

    setState(() {
      _isQuoting = true;
      _quoteError = null;
    });

    final result = await _currencyService.convertWithRate(
      amount: amount,
      base: _sendCurrency,
      target: _receiveCurrency,
    );

    if (!mounted) return;
    setState(() {
      _isQuoting = false;
      if (result == null) {
        _quoteError = "Couldn't fetch a live rate right now. Try again shortly.";
        _convertedAmount = null;
        _exchangeRate = null;
      } else {
        _convertedAmount = result['amount'];
        _exchangeRate = result['rate'];
      }
    });
  }

  Future<void> _pickSendCurrency() async {
    final picked = await showCurrencyPicker(context, currentCode: _sendCurrency);
    if (picked != null && picked != _sendCurrency) {
      setState(() => _sendCurrency = picked);
      _fetchQuote();
    }
  }

  Future<void> _pickReceiveCurrency() async {
    final picked = await showCurrencyPicker(context, currentCode: _receiveCurrency);
    if (picked != null && picked != _receiveCurrency) {
      setState(() => _receiveCurrency = picked);
      _fetchQuote();
    }
  }

  void _swapCurrencies() {
    setState(() {
      final temp = _sendCurrency;
      _sendCurrency = _receiveCurrency;
      _receiveCurrency = temp;
    });
    _fetchQuote();
  }

  void _continue() {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) return;
    if (_convertedAmount == null || _exchangeRate == null) return;

    Navigator.push(
      context,
      SlideRightRoute(
        page: InternationalTransferReviewScreen(
          user: widget.user,
          sendCurrency: _sendCurrency,
          receiveCurrency: _receiveCurrency,
          sendAmount: amount,
          receiveAmount: _convertedAmount!,
          exchangeRate: _exchangeRate!,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sendInfo = currencyInfoFor(_sendCurrency);
    final receiveInfo = currencyInfoFor(_receiveCurrency);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Column(
                  children: [
                    _currencyAmountCard(
                      label: "You send",
                      currencyInfo: sendInfo,
                      controller: _amountController,
                      editable: true,
                      onTapCurrency: _pickSendCurrency,
                    ),
                    const SizedBox(height: 4),
                    _currencyAmountCard(
                      label: "They get",
                      currencyInfo: receiveInfo,
                      displayValue: _isQuoting
                          ? null
                          : (_convertedAmount != null
                              ? _formatAmount(_convertedAmount!)
                              : '—'),
                      editable: false,
                      onTapCurrency: _pickReceiveCurrency,
                      isLoading: _isQuoting,
                    ),
                  ],
                ),
                // Centered — sits astride the seam between the two cards,
                // not pinned to the trailing edge.
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: GestureDetector(
                      onTap: _swapCurrencies,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.scaffold, width: 3),
                        ),
                        child: Icon(Icons.swap_vert_rounded,
                            color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (_quoteError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_quoteError!,
                    style: TextStyle(color: AppColors.danger, fontSize: 13)),
              ),
            if (_exchangeRate != null && !_isQuoting)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lock_outline_rounded, size: 15, color: AppColors.textMuted),
                    const SizedBox(width: 8),
                    Text(
                      "1 $_sendCurrency = ${_exchangeRate!.toStringAsFixed(4)} $_receiveCurrency",
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink),
                    ),
                    const Spacer(),
                    Text("Live mid-market rate",
                        style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                  ],
                ),
              ),
            const SizedBox(height: 14),
            const FeeTiersRow(),
            const DeliveryTimeRow(range: "Instant · 1 min to 1 day"),
            const SizedBox(height: 14),
            TrustBadgesWrap(badges: const [
              "Live exchange rate",
              "Fees included",
              "Mobile money & bank",
              "Arrives in seconds",
              "Cheapest fees",
            ]),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (_convertedAmount != null && !_isQuoting) ? _continue : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  disabledBackgroundColor: AppColors.border,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 17),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.md)),
                ),
                child: Text("Continue",
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
              ),
            ),
          ],
    );
  }

  String _formatAmount(double amount) {
    final isWhole = amount == amount.roundToDouble();
    return isWhole ? amount.toStringAsFixed(0) : amount.toStringAsFixed(2);
  }

  Widget _currencyAmountCard({
    required String label,
    required CurrencyCountryInfo currencyInfo,
    TextEditingController? controller,
    String? displayValue,
    required bool editable,
    required VoidCallback onTapCurrency,
    bool isLoading = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 13, color: AppColors.primary, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                if (editable)
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                    style: TextStyle(
                        fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.ink),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  )
                else if (isLoading)
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: AppColors.primary),
                  )
                else
                  Text(displayValue ?? '—',
                      style: TextStyle(
                          fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.ink)),
              ],
            ),
          ),
          InkWell(
            onTap: onTapCurrency,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(AppRadii.pill),
              ),
              child: Row(
                children: [
                  Text(currencyInfo.flagEmoji, style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 6),
                  Text(currencyInfo.currencyCode,
                      style: TextStyle(
                          fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 14)),
                  const SizedBox(width: 2),
                  Icon(Icons.keyboard_arrow_down_rounded,
                      color: AppColors.textMuted, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
