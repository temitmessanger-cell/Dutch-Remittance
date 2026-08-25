import 'package:flutter/material.dart';
import 'package:dutch_remit/utilities/app_theme.dart';
import 'package:dutch_remit/utilities/url_external_launcher.dart';
import 'package:dutch_remit/utilities/receipt_downloader.dart';

const String kSupportEmail = 'ikomihenry@dubiabank.com';
const String kSupportWhatsAppNumber = '+12897912474';
const String kSupportWhatsAppUrl = 'https://wa.me/12897912474';
const String kSupportPhoneUrl = 'tel:+12897912474';

class ReceiptField {
  final String label;
  final String value;
  const ReceiptField(this.label, this.value);
}

/// The standard "help with this transaction" footer — shown at the
/// end of every completed transaction/receipt, per the standing
/// instruction to always surface real support contact info rather
/// than leaving a user stranded after a payment.
class SupportContactFooter extends StatelessWidget {
  const SupportContactFooter({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text("Need help with this transaction?",
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () => launchExternalURL('mailto:$kSupportEmail'),
          child: Text(kSupportEmail,
              style: TextStyle(
                  fontSize: 12.5,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline)),
        ),
        const SizedBox(height: 6),
        Text("For urgent matters, 24/7 support:",
            style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
        const SizedBox(height: 4),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 14,
          children: [
            GestureDetector(
              onTap: () => launchExternalURL(kSupportWhatsAppUrl),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chat_bubble_rounded, size: 14, color: AppColors.success),
                  const SizedBox(width: 4),
                  Text("WhatsApp",
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.success)),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => launchExternalURL(kSupportPhoneUrl),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.call_rounded, size: 14, color: AppColors.primary),
                  const SizedBox(width: 4),
                  Text("Call $kSupportWhatsAppNumber",
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.primary)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Pops up immediately after a payment/transfer/deposit/withdrawal
/// completes — before it ever shows up in the Transactions tab —
/// with a full breakdown, a downloadable copy, and the support
/// contact footer. Every money-movement flow should call this on
/// success instead of just a SnackBar/toast.
Future<void> showTransactionReceipt(
  BuildContext context, {
  required String title,
  required String amountLine,
  required List<ReceiptField> fields,
  required String reference,
}) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.lg)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 640),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(color: AppColors.successBg, shape: BoxShape.circle),
                child: Icon(Icons.check_rounded, color: AppColors.success, size: 32),
              ),
              const SizedBox(height: 14),
              Text(title,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.ink)),
              const SizedBox(height: 4),
              Text(amountLine,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.primary)),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration:
                    BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(AppRadii.md)),
                child: Column(
                  children: [
                    for (final f in fields) _receiptRow(f.label, f.value),
                    _receiptRow("Reference", reference),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _downloadReceipt(title, amountLine, fields, reference),
                  icon: Icon(Icons.download_rounded, size: 18, color: AppColors.primary),
                  label:
                      Text("Download receipt", style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
                  ),
                  child: Text("Done", style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 16),
              Divider(color: AppColors.divider),
              const SizedBox(height: 12),
              const SupportContactFooter(),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget _receiptRow(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
          const SizedBox(width: 10),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.end,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.ink)),
          ),
        ],
      ),
    );

Future<void> _downloadReceipt(
    String title, String amountLine, List<ReceiptField> fields, String reference) async {
  final buffer = StringBuffer()
    ..writeln("Dutch Remit — Receipt")
    ..writeln(title)
    ..writeln(amountLine)
    ..writeln('');
  for (final f in fields) {
    buffer.writeln("${f.label}: ${f.value}");
  }
  buffer
    ..writeln("Reference: $reference")
    ..writeln('')
    ..writeln("For any issues contact: $kSupportEmail")
    ..writeln("For urgent matters, 24/7 support: WhatsApp/call $kSupportWhatsAppNumber");

  await downloadReceiptText(buffer.toString(), "dutch-remit-receipt-$reference.txt");
}
