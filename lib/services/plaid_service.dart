import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:plaid_flutter/plaid_flutter.dart';

import 'package:dutch_remit/resources/plaid_api_constants.dart';

/// A linked bank account, as returned by our own Plaid server (already
/// flattened/simplified from Plaid's raw response shape).
class PlaidLinkedAccount {
  final String accountId;
  final String name;
  final String? mask;
  final String? type;
  final String? subtype;
  final double? availableBalance;
  final double? currentBalance;
  final String? isoCurrencyCode;

  PlaidLinkedAccount({
    required this.accountId,
    required this.name,
    this.mask,
    this.type,
    this.subtype,
    this.availableBalance,
    this.currentBalance,
    this.isoCurrencyCode,
  });

  factory PlaidLinkedAccount.fromJson(Map<String, dynamic> json) {
    return PlaidLinkedAccount(
      accountId: json['accountId'],
      name: json['name'] ?? 'Account',
      mask: json['mask'],
      type: json['type'],
      subtype: json['subtype'],
      availableBalance: (json['availableBalance'] as num?)?.toDouble(),
      currentBalance: (json['currentBalance'] as num?)?.toDouble(),
      isoCurrencyCode: json['isoCurrencyCode'],
    );
  }
}

class PlaidTransaction {
  final String transactionId;
  final String name;
  final String? merchantName;
  final double amount;
  final String date;
  final bool pending;
  final String? category;

  PlaidTransaction({
    required this.transactionId,
    required this.name,
    this.merchantName,
    required this.amount,
    required this.date,
    required this.pending,
    this.category,
  });

  factory PlaidTransaction.fromJson(Map<String, dynamic> json) {
    return PlaidTransaction(
      transactionId: json['transactionId'],
      name: json['name'] ?? '',
      merchantName: json['merchantName'],
      amount: (json['amount'] as num).toDouble(),
      date: json['date'],
      pending: json['pending'] ?? false,
      category: json['category'],
    );
  }
}

class PlaidRecipient {
  final String userId;
  final String name;
  final String email;
  final bool hasLinkedBank;

  PlaidRecipient({
    required this.userId,
    required this.name,
    required this.email,
    required this.hasLinkedBank,
  });

  factory PlaidRecipient.fromJson(Map<String, dynamic> json) {
    return PlaidRecipient(
      userId: json['userId'],
      name: json['name'],
      email: json['email'],
      hasLinkedBank: json['hasLinkedBank'] ?? false,
    );
  }
}

/// Thrown when our Plaid server returns an error response. Carries the
/// human-readable message straight from the server so the UI can show it
/// directly without needing to know Plaid's internals.
class PlaidServiceException implements Exception {
  final String message;
  PlaidServiceException(this.message);
  @override
  String toString() => message;
}

/// The single point of contact between this app and the Plaid backend.
/// Every method here calls our own Netlify Functions (never Plaid
/// directly) — see /netlify/functions in the project root for what's on
/// the other end of these calls.
class PlaidService {
  static const String _base = PlaidApiConstants.baseUrl;

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final response = await http.post(
      Uri.parse('$_base$path'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400 || decoded['error'] == true) {
      throw PlaidServiceException(decoded['message']?.toString() ?? 'Something went wrong.');
    }
    return decoded;
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final response = await http.get(Uri.parse('$_base$path'));
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400 || decoded['error'] == true) {
      throw PlaidServiceException(decoded['message']?.toString() ?? 'Something went wrong.');
    }
    return decoded;
  }

  /// Step 1 of the Plaid flow: ask our server for a link_token.
  Future<String> createLinkToken(String userId) async {
    final result = await _post('/api/plaid/create-link-token', {'userId': userId});
    return result['link_token'];
  }

  /// Step 2: open the real Plaid Link popup using that token. Returns once
  /// the user finishes (successfully or not) — never throws on a normal
  /// user-cancelled exit, only on a genuine setup failure.
  ///
  /// [onSuccess] fires with (publicToken, institutionName) when the user
  /// finishes linking a bank. [onExit] fires if they back out or hit an
  /// error inside Link itself.
  Future<void> openLink({
    required String linkToken,
    required void Function(String publicToken, String? institutionName) onSuccess,
    required void Function(String? errorMessage) onExit,
  }) async {
    late StreamSubscription successSub;
    late StreamSubscription exitSub;

    successSub = PlaidLink.onSuccess.listen((LinkSuccess event) {
      final institutionName = event.metadata.institution?.name;
      onSuccess(event.publicToken, institutionName);
      successSub.cancel();
      exitSub.cancel();
    });

    exitSub = PlaidLink.onExit.listen((LinkExit event) {
      onExit(event.error?.description());
      successSub.cancel();
      exitSub.cancel();
    });

    final configuration = LinkTokenConfiguration(token: linkToken);
    await PlaidLink.open(configuration: configuration);
  }

  /// Step 3: hand the public_token to our server, which exchanges it for
  /// a permanent access_token (server-side only) and returns the linked
  /// accounts so the UI can show them immediately.
  Future<List<PlaidLinkedAccount>> exchangePublicToken({
    required String userId,
    required String publicToken,
    String? institutionName,
  }) async {
    final result = await _post('/api/plaid/exchange-public-token', {
      'userId': userId,
      'publicToken': publicToken,
      'institutionName': institutionName,
    });
    final accounts = (result['accounts'] as List)
        .map((a) => PlaidLinkedAccount.fromJson(a))
        .toList();
    return accounts;
  }

  /// Fetches the currently-linked accounts (with live balances) for a user,
  /// or an empty list if they haven't linked a bank yet.
  Future<List<PlaidLinkedAccount>> getLinkedAccounts(String userId) async {
    final result = await _get('/api/plaid/accounts?userId=${Uri.encodeQueryComponent(userId)}');
    if (result['linked'] != true) return [];
    final accounts = (result['accounts'] as List)
        .map((a) => PlaidLinkedAccount.fromJson(a))
        .toList();
    return accounts;
  }

  Future<List<PlaidTransaction>> getTransactions(String userId) async {
    final result = await _get('/api/plaid/transactions?userId=${Uri.encodeQueryComponent(userId)}');
    final transactions = (result['transactions'] as List)
        .map((t) => PlaidTransaction.fromJson(t))
        .toList();
    return transactions;
  }

  Future<List<PlaidRecipient>> getRecipients() async {
    final result = await _get('/api/plaid/recipients');
    final recipients = (result['recipients'] as List)
        .map((r) => PlaidRecipient.fromJson(r))
        .toList();
    return recipients;
  }

  /// Initiates a real bank-to-bank transfer via Plaid's Transfer product.
  /// Will throw a PlaidServiceException with a clear message if Transfer
  /// isn't enabled on the Plaid account yet — that's not a bug, just a
  /// product that needs turning on in the Plaid Dashboard first.
  Future<Map<String, dynamic>> sendTransfer({
    required String fromUserId,
    required String toUserId,
    required double amount,
    String? description,
  }) {
    return _post('/api/plaid/transfer', {
      'fromUserId': fromUserId,
      'toUserId': toUserId,
      'amount': amount,
      'description': description,
    });
  }

  /// Pushes a sandbox transfer forward (pending -> posted -> settled) so a
  /// demo doesn't sit stuck at "pending" the way real Sandbox transfers do
  /// by default.
  Future<Map<String, dynamic>> simulateTransferProgress({
    required String transferId,
    required String eventType, // posted | settled | failed | returned
  }) {
    return _post('/api/plaid/simulate-transfer', {
      'transferId': transferId,
      'eventType': eventType,
    });
  }

  /// Injects a brand-new transaction onto a linked Sandbox account so it
  /// shows up immediately the next time transactions are fetched — a
  /// simple way to demo "real-time" activity without needing the Transfer
  /// product enabled at all. Only works for accounts linked with the
  /// user_transactions_dynamic Sandbox test username.
  Future<void> simulateIncomingTransaction({
    required String userId,
    required double amount,
    String? description,
  }) {
    return _post('/api/plaid/simulate-transaction', {
      'userId': userId,
      'amount': amount,
      'description': description,
    });
  }
}
