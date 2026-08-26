import 'dart:math';

import 'package:dutch_remit/utilities/make_api_request.dart';

/// The user's available payment cards.
///
/// Previously Hive-backed (device-global, not per-user) — the same
/// cross-user leak as the transactions and contacts stores. Cards are
/// now read straight from the backend (GET /Dutch Remit/v1/available-cards),
/// which is correctly scoped to the authenticated user, and nothing is
/// cached on-device. Method signatures are unchanged so all call sites
/// still compile.
///
/// To read cards the caller must have initialized this store with a
/// valid auth key at least once in the session (see
/// initializeAvailableCards) — the key is held only in memory for the
/// lifetime of the object, never written to disk.
class CardsStorage {
  static const String boxName = 'dutch_remit_available_cards';

  // Singleton: previously each `CardsStorage()` was an independent Hive
  // handle onto the same on-disk box, so they all saw the same data.
  // Now that cards live in memory (backend-driven, no Hive), a shared
  // instance preserves that "one source everywhere" behaviour — without
  // it, a fresh CardsStorage() in one screen wouldn't see the cards
  // another screen loaded. All the existing `CardsStorage()` call sites
  // keep working unchanged and transparently share this instance.
  static final CardsStorage _instance = CardsStorage._internal();
  factory CardsStorage() => _instance;
  CardsStorage._internal();

  // Held in memory only, for the lifetime of this object. Not persisted.
  String? _userAuthKey;
  List<dynamic> _cards = <dynamic>[];

  Future<Map<String, dynamic>> get randomCard async {
    final cards = (await readAvailableCards())['availableCards'] as List;
    if (cards.isEmpty) return {};
    return cards[Random().nextInt(cards.length)] as Map<String, dynamic>;
  }

  /// Fetches the user's cards from the backend and holds them in memory
  /// for this session. Returns false on error.
  Future<bool> initializeAvailableCards(String userAuthKey) async {
    _userAuthKey = userAuthKey;
    try {
      final Map<String, dynamic> availableCards = await getData(
          urlPath: "/Dutch Remit/v1/available-cards", authKey: userAuthKey);
      if (availableCards.keys.join().toLowerCase().contains("error")) {
        return false;
      }
      _cards = List<dynamic>.from(availableCards['availableCards'] ?? <dynamic>[]);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Returns the in-memory card list (populated by
  /// initializeAvailableCards). If a refresh is needed, re-initialize
  /// with the auth key. Falls back to a live fetch if we have a key but
  /// no cards yet.
  Future<Map<String, dynamic>> readAvailableCards() async {
    if (_cards.isEmpty && _userAuthKey != null) {
      await initializeAvailableCards(_userAuthKey!);
    }
    return {'availableCards': List<dynamic>.from(_cards)};
  }

  /// In-memory only; the authoritative record is created server-side
  /// when a card is actually issued.
  void updateAvailableCards(Map<String, dynamic> cardData) {
    _cards.add(cardData);
  }

  Future<bool> deleteCard(String cardNumber) async {
    _cards = _cards
        .where((card) =>
            (card['cardNumber']?.toString().replaceAll(' ', '') ?? '') !=
            cardNumber.replaceAll(' ', ''))
        .toList();
    return true;
  }

  Future<bool> deleteFile() async {
    _cards = <dynamic>[];
    _userAuthKey = null;
    return true;
  }

  Future<bool> resetLocallySavedCards() async {
    _cards = <dynamic>[];
    return true;
  }
}
