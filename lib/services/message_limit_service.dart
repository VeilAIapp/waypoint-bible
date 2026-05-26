import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Enforces the daily Companion message limit for free users.
///
/// Storage keys use flutter_secure_storage so they cannot be trivially edited
/// on rooted Android devices (EncryptedSharedPreferences) or jailbroken iOS
/// devices (Keychain). All date comparisons use ISO-8601 strings so they sort
/// lexicographically without parsing.
///
/// Clock-manipulation defences:
///   • first_open_date in the future → treated as day 2+ (forward-clock install)
///   • max_date_seen > today → clock was rolled back → do not reset count
class MessageLimitService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const String _keyFirstOpen = 'msg_first_open_date';
  static const String _keyMaxDateSeen = 'msg_max_date_seen';
  static const String _keyDailyCount = 'msg_daily_count';
  static const String _keyCountDate = 'msg_count_date';

  static const int dailyFreeLimit = 2;

  static String _today() => DateTime.now().toIso8601String().substring(0, 10);

  // ── Initialisation ──────────────────────────────────────────────────────────

  /// Call once at app start. Writes today's date as the install date — once only,
  /// never overwritten. Must be the very first storage operation so the timestamp
  /// is as accurate as possible.
  static Future<void> recordFirstOpenIfNeeded() async {
    final existing = await _storage.read(key: _keyFirstOpen);
    if (existing == null) {
      await _storage.write(key: _keyFirstOpen, value: _today());
    }
  }

  // ── Day-1 check ─────────────────────────────────────────────────────────────

  /// Returns true ONLY on the calendar day the app was first installed AND the
  /// device clock has not been rolled back since.
  ///
  /// Returns false (→ restricted) if:
  ///   • first_open_date is missing or empty
  ///   • first_open_date is in the future (clock was advanced at install time)
  ///   • max_date_seen > today (clock was rolled back to reach day 1 again)
  ///   • first_open_date ≠ today
  static Future<bool> isDay1() async {
    final today = _today();
    final firstOpen = await _storage.read(key: _keyFirstOpen);

    if (firstOpen == null || firstOpen.isEmpty) return false;
    if (firstOpen.compareTo(today) > 0) return false; // future date = tampered
    // If max_date_seen is ahead of today the clock was rolled back.
    final maxDateSeen = await _storage.read(key: _keyMaxDateSeen) ?? today;
    if (maxDateSeen.compareTo(today) > 0) return false;

    return firstOpen == today;
  }

  // ── Daily count ─────────────────────────────────────────────────────────────

  /// Returns the current message count for today, resetting to 0 on a genuine
  /// new calendar day. Clock-rollback protection: if the device date is behind
  /// the highest date ever seen, the count is NOT reset.
  static Future<int> refreshAndGetCount() async {
    final today = _today();
    final maxDateSeen =
        await _storage.read(key: _keyMaxDateSeen) ?? '0000-00-00';
    final countDate =
        await _storage.read(key: _keyCountDate) ?? '0000-00-00';
    int count =
        (int.tryParse(await _storage.read(key: _keyDailyCount) ?? '0') ?? 0)
            .clamp(0, 9999);

    if (today.compareTo(maxDateSeen) > 0) {
      // Genuine new high-water mark — advance max_date_seen.
      await _storage.write(key: _keyMaxDateSeen, value: today);
    } else if (today.compareTo(maxDateSeen) < 0) {
      // Clock was rolled back — do NOT reset, return unchanged count.
      return count;
    }
    // today == maxDateSeen (or we just advanced it to today).

    if (today.compareTo(countDate) > 0) {
      // New calendar day — reset count.
      count = 0;
      await _storage.write(key: _keyDailyCount, value: '0');
      await _storage.write(key: _keyCountDate, value: today);
    }

    return count;
  }

  /// Returns true if a free user is allowed to send another message right now.
  static Future<bool> canSendMessage() async {
    if (await isDay1()) return true;
    return (await refreshAndGetCount()) < dailyFreeLimit;
  }

  /// Records one message as consumed. Call this immediately when the API
  /// request is dispatched — before awaiting the response — so that app-kill
  /// between send and response still counts the message.
  ///
  /// Count is clamped at 0 minimum and never decrements.
  static Future<void> recordMessageSent() async {
    final today = _today();
    final countDate =
        await _storage.read(key: _keyCountDate) ?? '0000-00-00';
    if (countDate != today) {
      // Date crossed since last check — reset then record 1.
      await _storage.write(key: _keyCountDate, value: today);
      await _storage.write(key: _keyDailyCount, value: '1');
      return;
    }
    int count =
        (int.tryParse(await _storage.read(key: _keyDailyCount) ?? '0') ?? 0)
            .clamp(0, 9999);
    await _storage.write(key: _keyDailyCount, value: (count + 1).toString());
  }
}
