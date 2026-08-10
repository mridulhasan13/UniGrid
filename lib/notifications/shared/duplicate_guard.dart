/// ─────────────────────────────────────────────────────────────────────────────
/// DuplicateGuard
///
/// In-memory rolling cache of processed notification message IDs.
/// Prevents the same notification from being shown more than once —
/// whether caused by multiple onMessage listeners, fast re-delivery, or
/// sender/receiver being on the same device.
/// ─────────────────────────────────────────────────────────────────────────────
class DuplicateGuard {
  DuplicateGuard._();

  // Rolling window — keeps last 300 IDs then evicts oldest
  static final List<String> _order = [];
  static final Set<String> _seen = {};
  static const int _maxSize = 300;

  /// Strips platform prefixes (e.g. 'native_', 'web_', 'ww_', 'wa_', 'aa_', 'aw_')
  /// to ensure cross-medium duplicate detection for the same underlying message.
  static String _canonicalId(String messageId) {
    String clean = messageId;
    for (final prefix in ['native_', 'web_', 'ww_', 'wa_', 'aa_', 'aw_']) {
      if (clean.startsWith(prefix)) {
        clean = clean.substring(prefix.length);
        break;
      }
    }
    return clean;
  }

  /// Returns true if this [messageId] was already seen (→ skip showing).
  static bool isAlreadySeen(String messageId) {
    final key = _canonicalId(messageId);
    return _seen.contains(key);
  }

  /// Marks [messageId] as seen. Evicts oldest if over capacity.
  static void markSeen(String messageId) {
    final key = _canonicalId(messageId);
    if (_seen.contains(key)) return;
    if (_seen.length >= _maxSize) {
      final oldest = _order.removeAt(0);
      _seen.remove(oldest);
    }
    _seen.add(key);
    _order.add(key);
  }

  /// Convenience — checks AND marks in one call.
  /// Returns true if it was already seen (caller should skip).
  /// Returns false if it was new (caller should proceed and show).
  static bool checkAndMark(String messageId) {
    if (isAlreadySeen(messageId)) return true;
    markSeen(messageId);
    return false;
  }

  /// Clear all state (useful for testing).
  static void reset() {
    _seen.clear();
    _order.clear();
  }
}
