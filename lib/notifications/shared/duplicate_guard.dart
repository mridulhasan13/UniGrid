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

  /// Returns true if this [messageId] was already seen (→ skip showing).
  static bool isAlreadySeen(String messageId) => _seen.contains(messageId);

  /// Marks [messageId] as seen. Evicts oldest if over capacity.
  static void markSeen(String messageId) {
    if (_seen.contains(messageId)) return;
    if (_seen.length >= _maxSize) {
      final oldest = _order.removeAt(0);
      _seen.remove(oldest);
    }
    _seen.add(messageId);
    _order.add(messageId);
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
