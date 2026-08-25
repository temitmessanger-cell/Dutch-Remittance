import 'package:flutter/material.dart';

import 'package:dutch_remit/services/plaid_service.dart';
import 'package:dutch_remit/utilities/app_theme.dart';

/// A self-contained screen for the whole Plaid experience:
/// - Linking a bank account (real Plaid Link popup, real Sandbox banks)
/// - Viewing the linked account's real (Sandbox) balance + transactions
/// - Sending money to another Dutch Remit user via a simulated
///   bank-to-bank transfer
///
/// This screen talks ONLY to PlaidService, which talks ONLY to our own
/// backend server — no Plaid secret ever exists in this file or anywhere
/// else in the Flutter app.
class LinkBankAccountScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  const LinkBankAccountScreen({Key? key, required this.user}) : super(key: key);

  @override
  State<LinkBankAccountScreen> createState() => _LinkBankAccountScreenState();
}

enum _LoadState { idle, creatingLinkToken, openingPlaid, exchangingToken, ready, error }

class _LinkBankAccountScreenState extends State<LinkBankAccountScreen> {
  final PlaidService _plaid = PlaidService();

  _LoadState _state = _LoadState.idle;
  String? _errorMessage;

  List<PlaidLinkedAccount> _linkedAccounts = [];
  String? _institutionName;

  String get _userId => widget.user['email'] ?? widget.user['_id']?.toString() ?? 'demo_user';

  @override
  void initState() {
    super.initState();
    _loadExistingLink();
  }

  Future<void> _loadExistingLink() async {
    try {
      final accounts = await _plaid.getLinkedAccounts(_userId);
      if (accounts.isNotEmpty && mounted) {
        setState(() {
          _linkedAccounts = accounts;
          _state = _LoadState.ready;
        });
      }
    } catch (e) {
      // No existing link yet, or server unreachable — either way, just
      // leave the user at the "connect a bank" entry state.
    }
  }

  Future<void> _startLinkFlow() async {
    setState(() {
      _state = _LoadState.creatingLinkToken;
      _errorMessage = null;
    });

    try {
      final linkToken = await _plaid.createLinkToken(_userId);

      setState(() => _state = _LoadState.openingPlaid);

      await _plaid.openLink(
        linkToken: linkToken,
        onSuccess: (publicToken, institutionName) async {
          setState(() => _state = _LoadState.exchangingToken);
          try {
            final accounts = await _plaid.exchangePublicToken(
              userId: _userId,
              publicToken: publicToken,
              institutionName: institutionName,
            );
            if (!mounted) return;
            setState(() {
              _linkedAccounts = accounts;
              _institutionName = institutionName;
              _state = _LoadState.ready;
            });
          } catch (e) {
            if (!mounted) return;
            setState(() {
              _state = _LoadState.error;
              _errorMessage = e.toString();
            });
          }
        },
        onExit: (errorMessage) {
          if (!mounted) return;
          setState(() {
            // A user backing out of Link isn't an error — just go back
            // to the idle "connect a bank" state quietly.
            _state = errorMessage == null ? _LoadState.idle : _LoadState.error;
            _errorMessage = errorMessage;
          });
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _LoadState.error;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        title: Text("Linked Bank",
            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.ink,
      ),
      body: SafeArea(
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _LoadState.creatingLinkToken:
        return _buildLoadingState("Preparing secure connection…");
      case _LoadState.openingPlaid:
        return _buildLoadingState("Opening your bank's login…");
      case _LoadState.exchangingToken:
        return _buildLoadingState("Linking your account…");
      case _LoadState.ready:
        return _buildLinkedState();
      case _LoadState.error:
        return _buildErrorState();
      case _LoadState.idle:
        return _buildEmptyState();
    }
  }

  Widget _buildLoadingState(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(
                strokeWidth: 3, color: AppColors.primary),
          ),
          const SizedBox(height: 18),
          Text(message,
              style: TextStyle(color: AppColors.inkMuted, fontSize: 14.5)),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.account_balance_rounded,
                  color: AppColors.primary, size: 32),
            ),
            const SizedBox(height: 20),
            Text("Connect a bank account",
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
            const SizedBox(height: 8),
            Text(
              "Securely link your bank to send and receive money directly, powered by Plaid.",
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 13.5, height: 1.4),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _startLinkFlow,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.md)),
                ),
                child: Text("Connect with Plaid",
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 40),
            const SizedBox(height: 16),
            Text("Couldn't connect",
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink)),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? "Something went wrong. Please try again.",
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 13.5, height: 1.4),
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: () => setState(() => _state = _LoadState.idle),
              child: Text("Try again"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLinkedState() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            boxShadow: AppShadows.raised,
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.account_balance_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_institutionName ?? "Linked Bank",
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15.5)),
                    const SizedBox(height: 2),
                    Text("${_linkedAccounts.length} account${_linkedAccounts.length == 1 ? '' : 's'} connected",
                        style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12.5)),
                  ],
                ),
              ),
              Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text("ACCOUNTS",
            style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6)),
        const SizedBox(height: 10),
        ..._linkedAccounts.map((account) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadii.lg),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                    boxShadow: AppShadows.card,
                  ),
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(AppRadii.sm),
                      ),
                      child: Icon(Icons.account_balance_wallet_outlined,
                          color: AppColors.primary, size: 18),
                    ),
                    title: Text(account.name,
                        style: TextStyle(
                            fontWeight: FontWeight.w600, color: AppColors.ink, fontSize: 15)),
                    subtitle: Text(
                      account.mask != null ? "•••• ${account.mask}" : (account.subtype ?? ''),
                      style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                    ),
                    trailing: Text(
                      account.currentBalance != null
                          ? "\$${account.currentBalance!.toStringAsFixed(2)}"
                          : '—',
                      style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 14.5),
                    ),
                  ),
                ),
              ),
            )),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: _startLinkFlow,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            minimumSize: Size(double.infinity, 0),
          ),
          child: Text("Connect another bank", style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}
