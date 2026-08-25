import 'package:flutter/material.dart';

import 'package:dutch_remit/services/plaid_service.dart';
import 'package:dutch_remit/utilities/app_theme.dart';

/// Send money to an existing Dutch Remit user via a real Plaid Transfer
/// (bank-to-bank ACH simulation in Sandbox). Shows the transfer's status
/// progressing in real time as it's pushed forward through Plaid's
/// Sandbox simulation endpoints.
class PlaidBankTransferScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  const PlaidBankTransferScreen({Key? key, required this.user}) : super(key: key);

  @override
  State<PlaidBankTransferScreen> createState() => _PlaidBankTransferScreenState();
}

class _PlaidBankTransferScreenState extends State<PlaidBankTransferScreen> {
  final PlaidService _plaid = PlaidService();
  final TextEditingController _amountController = TextEditingController();

  List<PlaidRecipient> _recipients = [];
  PlaidRecipient? _selectedRecipient;
  bool _loadingRecipients = true;

  bool _isSending = false;
  String? _errorMessage;

  // Live transfer status tracking, once a transfer has been created.
  String? _transferId;
  String _transferStatus = '';
  bool _isSimulatingProgress = false;

  String get _userId => widget.user['email'] ?? widget.user['_id']?.toString() ?? 'demo_user';

  @override
  void initState() {
    super.initState();
    _loadRecipients();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _loadRecipients() async {
    try {
      final recipients = await _plaid.getRecipients();
      if (mounted) {
        setState(() {
          _recipients = recipients;
          _loadingRecipients = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = "Couldn't load recipients: $e";
          _loadingRecipients = false;
        });
      }
    }
  }

  Future<void> _sendTransfer() async {
    final amount = double.tryParse(_amountController.text);
    if (_selectedRecipient == null || amount == null || amount <= 0) {
      setState(() => _errorMessage = "Pick a recipient and enter a valid amount.");
      return;
    }

    setState(() {
      _isSending = true;
      _errorMessage = null;
    });

    try {
      final result = await _plaid.sendTransfer(
        fromUserId: _userId,
        toUserId: _selectedRecipient!.userId,
        amount: amount,
        description: "DutchRemit",
      );
      if (!mounted) return;
      setState(() {
        _transferId = result['transferId'];
        _transferStatus = result['status'] ?? 'pending';
        _isSending = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isSending = false;
      });
    }
  }

  Future<void> _advanceTransfer(String eventType) async {
    if (_transferId == null) return;
    setState(() => _isSimulatingProgress = true);
    try {
      final result = await _plaid.simulateTransferProgress(
        transferId: _transferId!,
        eventType: eventType,
      );
      if (!mounted) return;
      setState(() {
        _transferStatus = result['transfer']['status'] ?? _transferStatus;
        _isSimulatingProgress = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isSimulatingProgress = false;
      });
    }
  }

  void _reset() {
    setState(() {
      _transferId = null;
      _transferStatus = '';
      _amountController.clear();
      _selectedRecipient = null;
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        title: Text("Bank Transfer",
            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.ink,
      ),
      body: SafeArea(
        child: _transferId != null ? _buildStatusView() : _buildFormView(),
      ),
    );
  }

  Widget _buildFormView() {
    if (_loadingRecipients) {
      return Center(
        child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 3),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Text("Send to",
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
        const SizedBox(height: 10),
        ..._recipients.map((r) {
          final isSelected = _selectedRecipient?.userId == r.userId;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadii.lg),
              onTap: () => setState(() => _selectedRecipient = r),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                  border: Border.all(
                    color: isSelected ? AppColors.primary : AppColors.border,
                    width: isSelected ? 1.6 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: AppColors.surfaceAlt,
                      child: Text(r.name[0].toUpperCase(),
                          style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.name,
                              style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink, fontSize: 14.5)),
                          Text(r.email, style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                        ],
                      ),
                    ),
                    if (isSelected)
                      Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 20),
                  ],
                ),
              ),
            ),
          );
        }),
        const SizedBox(height: 20),
        Text("Amount",
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
        const SizedBox(height: 10),
        TextField(
          controller: _amountController,
          keyboardType: TextInputType.numberWithOptions(decimal: true),
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.ink),
          decoration: InputDecoration(
            prefixText: "\$ ",
            prefixStyle: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.primary),
            filled: true,
            fillColor: AppColors.surfaceAlt,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.md), borderSide: BorderSide.none),
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          Text(_errorMessage!, style: TextStyle(color: AppColors.danger, fontSize: 13)),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isSending ? null : _sendTransfer,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
            ),
            child: _isSending
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                : Text("Send transfer", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusView() {
    final steps = ['pending', 'posted', 'settled'];
    final currentIndex = steps.indexOf(_transferStatus);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.successBg,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.swap_horiz_rounded, color: AppColors.success, size: 28),
          ),
          const SizedBox(height: 18),
          Text("Transfer to ${_selectedRecipient?.name ?? ''}",
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.ink)),
          const SizedBox(height: 4),
          Text("\$${_amountController.text}",
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.primary)),
          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(steps.length, (i) {
              final bool reached = i <= currentIndex;
              return Expanded(
                child: Column(
                  children: [
                    Row(
                      children: [
                        if (i > 0)
                          Expanded(
                            child: Container(
                              height: 2,
                              color: i <= currentIndex ? AppColors.primary : AppColors.border,
                            ),
                          ),
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: reached ? AppColors.primary : AppColors.border,
                          ),
                          child: reached
                              ? Icon(Icons.check, size: 13, color: Colors.white)
                              : null,
                        ),
                        if (i < steps.length - 1)
                          Expanded(
                            child: Container(
                              height: 2,
                              color: i < currentIndex ? AppColors.primary : AppColors.border,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      steps[i][0].toUpperCase() + steps[i].substring(1),
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: reached ? FontWeight.w700 : FontWeight.w500,
                          color: reached ? AppColors.ink : AppColors.textMuted),
                    ),
                  ],
                ),
              );
            }),
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: AppColors.textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "In Sandbox, transfers don't move forward automatically. Use the buttons below to simulate the bank processing it — exactly like a real ACH transfer does over 1-3 business days, just instant for demo purposes.",
                    style: TextStyle(fontSize: 12, color: AppColors.inkMuted, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (_errorMessage != null) ...[
            Text(_errorMessage!, style: TextStyle(color: AppColors.danger, fontSize: 13)),
            const SizedBox(height: 12),
          ],
          if (currentIndex < steps.length - 1)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSimulatingProgress
                    ? null
                    : () => _advanceTransfer(steps[currentIndex + 1]),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
                ),
                child: _isSimulatingProgress
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                    : Text("Simulate: mark as ${steps[currentIndex + 1]}",
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              ),
            )
          else
            Text("Transfer complete",
                style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _reset,
            child: Text("Send another transfer", style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }
}
