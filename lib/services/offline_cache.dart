import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';

/// Hive-backed cache for API responses.
///
/// Stores JSON-serialisable API responses keyed by URL/path.
/// Each entry records its timestamp so stale entries can be identified.
///
/// Design notes:
///   • Never caches financial write responses (payouts, deposits, swaps).
///   • Read-only data (balance, transactions, cards, corridors) cached
///     with a configurable TTL. Stale data is served while a fresh
///     fetch happens in the background (stale-while-revalidate).
///   • On a box error, logs and continues — never crashes the app.
class OfflineCache {
  static const String boxName = 'dr_offline_cache';

  static Box? _box;

  /// Open the Hive box. Call once during app startup.
  static Future<void> initialize() async {
    try {
      _box = await Hive.openBox(boxName);
    } catch (e) {
      // Non-fatal: app works without cache, just won't be offline-capable
      // for API responses.
      _box = null;
      debugLog('OfflineCache init failed: $e');
    }
  }

  // ── Read ──────────────────────────────────────────────────────────────────

  /// Returns the cached value for [key] if present and younger than [maxAge].
  /// Returns `null` if missing or expired.
  static Map<String, dynamic>? get(String key,
      {Duration maxAge = const Duration(minutes: 10)}) {
    try {
      final raw = _box?.get(key);
      if (raw == null) return null;

      final entry = Map<String, dynamic>.from(raw as Map);
      final ts = DateTime.tryParse(entry['_cachedAt'] as String? ?? '');
      if (ts == null) return null;

      if (DateTime.now().difference(ts) > maxAge) return null;
      return Map<String, dynamic>.from(entry['data'] as Map);
    } catch (e) {
      debugLog('OfflineCache.get error: $e');
      return null;
    }
  }

  /// Returns the stale cached value for [key] regardless of age.
  /// Useful for showing data while a fresh fetch is in progress.
  static Map<String, dynamic>? getStale(String key) {
    try {
      final raw = _box?.get(key);
      if (raw == null) return null;
      final entry = Map<String, dynamic>.from(raw as Map);
      return Map<String, dynamic>.from(entry['data'] as Map);
    } catch (e) {
      debugLog('OfflineCache.getStale error: $e');
      return null;
    }
  }

  /// Returns [DateTime] when [key] was last cached, or null.
  static DateTime? cachedAt(String key) {
    try {
      final raw = _box?.get(key);
      if (raw == null) return null;
      final entry = Map<String, dynamic>.from(raw as Map);
      return DateTime.tryParse(entry['_cachedAt'] as String? ?? '');
    } catch (_) {
      return null;
    }
  }

  // ── Write ─────────────────────────────────────────────────────────────────

  /// Caches [data] under [key] with the current timestamp.
  static Future<void> set(String key, Map<String, dynamic> data) async {
    try {
      await _box?.put(key, {
        '_cachedAt': DateTime.now().toIso8601String(),
        'data': data,
      });
    } catch (e) {
      debugLog('OfflineCache.set error: $e');
    }
  }

  /// Caches a list response under [key].
  static Future<void> setList(String key, List<dynamic> list) async {
    await set(key, {'_list': jsonEncode(list)});
  }

  static List<dynamic>? getList(String key,
      {Duration maxAge = const Duration(minutes: 10)}) {
    final entry = get(key, maxAge: maxAge);
    if (entry == null) return null;
    try {
      return jsonDecode(entry['_list'] as String) as List<dynamic>;
    } catch (_) {
      return null;
    }
  }

  // ── Cache keys for Dutch Remit ─────────────────────────────────────────

  static const String keyBalance      = 'dr:wallet:balance';
  static const String keyTransactions = 'dr:transactions:list';
  static const String keyCards        = 'dr:cards:list';
  static const String keyCorridors    = 'dr:corridors:list';
  static const String keyBankList     = 'dr:banks:'; // + countryCode

  // ── Invalidation ──────────────────────────────────────────────────────────

  static Future<void> invalidate(String key) async {
    try { await _box?.delete(key); } catch (_) {}
  }

  static Future<void> invalidateAll() async {
    try { await _box?.clear(); } catch (_) {}
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static void debugLog(String msg) {
    // ignore: avoid_print
    print('[OfflineCache] $msg');
  }
}
