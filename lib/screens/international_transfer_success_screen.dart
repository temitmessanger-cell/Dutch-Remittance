import 'package:flutter/material.dart';
import 'package:dutch_remit/utilities/app_theme.dart';
import 'package:dutch_remit/utilities/currency_country_data.dart';
import 'package:dutch_remit/components/shared/transaction_receipt_dialog.dart';

/// Shown after a successful international transfer is recorded. Kept
/// simple and consistent with the rest of the app's success states
/// rather than introducing a fourth distinct "done" pattern.
class InternationalTransferSuccessScreen extends StatelessWidget {
  final String sendCurrency;
  final String receiveCurrency;
  final double sendAmount;
  final double receiveAmount;
  final String arrivalEstimate;

  const InternationalTransferSuccessScreen({
    Key? key,
    required this.sendCurrency,
    required this.receiveCurrency,
    required this.sendAmount,
    required this.receiveAmount,
    required this.arrivalEstimate,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final receiveInfo = currencyInfoFor(receiveCurrency);

    return Scaffold(
      backgroundColor: AppColors.scaffold,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 40, 28, 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: AppColors.successBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.check_rounded, color: AppColors.success, size: 44),
              ),
              const SizedBox(height: 24),
              Text("Transfer sent",
                  style: TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.ink)),
              const SizedBox(height: 8),
              Text(
                "${receiveInfo.flagEmoji}  ${receiveAmount.toStringAsFixed(2)} $receiveCurrency will arrive $arrivalEstimate.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14.5, color: AppColors.textMuted, height: 1.4),
              ),
              const SizedBox(height: 36),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () =>
                      Navigator.of(context).popUntil((route) => route.isFirst),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadii.md)),
                  ),
                  child: Text("Done",
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ),
              const SizedBox(height: 22),
              Divider(color: AppColors.divider),
              const SizedBox(height: 14),
              const SupportContactFooter(),
            ],
          ),
        ),
      ),
    );
  }
}
