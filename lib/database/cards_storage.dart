import 'dart:math';

import 'package:hive/hive.dart';
import 'package:dutch_remit/utilities/make_api_request.dart';

/// Persists the user's saved payment cards.
///
/// Backed by Hive (works identically on mobile, desktop, and web — unlike
/// the previous dart:io File implementation, which silently failed on web
/// since dart:io has no File support there). Public API is unchanged so
/// every existing call site keeps working without modification.
class CardsStorage {
  static const String boxName = 'dutch_remit_available_cards';
  static const String _dataKey = 'availableCards';

  Future<Box> get _box async {
    if (Hive.isBoxOpen(boxName)) {
      return Hive.box(boxName);
    }
    return Hive.openBox(boxName);
  }

  Future<Map<String, dynamic>> get randomCard async {
    var _availableCards = (await readAvailableCards())['availableCards'];

    return _availableCards[Random().nextInt(_availableCards.length)];
  }

  Future<bool> initializeAvailableCards(String userAuthKey) async {
    try {
      final contents = await readAvailableCards();
      if (contents.containsKey('availableCards')) {
        //* pre-existing cards loaded
        return true;
      } else {
        try {
          Map<String, dynamic> availableCards = await getData(
              urlPath: "/Dutch Remit/v1/available-cards", authKey: userAuthKey);
          if (availableCards.keys.join().toLowerCase().contains("error")) {
            return false;
          } else {
            final box = await _box;
            await box.put(_dataKey, availableCards['availableCards']);
            //* the cards have been saved in app memory
            return true;
          }
        } catch (er) {
          return false;
        }
      }
    } catch (e) {
      return false;
    }
  }

  Future<Map<String, dynamic>> readAvailableCards() async {
    try {
      final box = await _box;
      final List<dynamic> rawCards =
          List<dynamic>.from(box.get(_dataKey, defaultValue: <dynamic>[]));
      final List<dynamic> cards = rawCards
          .map((card) => Map<String, dynamic>.from(card as Map))
          .toList();
      return {'availableCards': cards};
    } catch (e) {
      return {"localDBError": "unable to parse data"};
    }
  }

  void updateAvailableCards(Map<String, dynamic> cardData) async {
    final box = await _box;
    final List<dynamic> cards =
        List<dynamic>.from(box.get(_dataKey, defaultValue: <dynamic>[]));
    cards.add(cardData);
    await box.put(_dataKey, cards);
    print("new card added");
  }

  Future<bool> deleteCard(String cardNumber) async {
    try {
      final box = await _box;
      final List<dynamic> rawCards =
          List<dynamic>.from(box.get(_dataKey, defaultValue: <dynamic>[]));
      final List<dynamic> cards = rawCards
          .map((card) => Map<String, dynamic>.from(card as Map))
          .toList();

      List<dynamic> newCardsSet = cards
          .where((card) =>
              card['cardNumber'].replaceAll(' ', '') !=
              cardNumber.replaceAll(' ', ''))
          .toList();
      await box.put(_dataKey, newCardsSet);
      //* card has been deleted
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> deleteFile() async {
    try {
      final box = await _box;
      await box.delete(_dataKey);
      //* THE LOCAL CARDS DATA HAS BEEN DELETED
      return true;
    } catch (e) {
     //* THE LOCAL CARDS DATA HAS NOT BEEN DELETED
      return false;
    }
  }

  Future<bool> resetLocallySavedCards() async {
    try {
      final box = await _box;
      await box.put(_dataKey, <dynamic>[]);
      //* RESET CARDS DATA SUCCESSFUL
      return true;
    } catch (e) {
    //* RESET CARDS DATA UNSUCCESSFUL
      return false;
    }
  }
}

