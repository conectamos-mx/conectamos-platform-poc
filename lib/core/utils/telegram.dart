// ADR-413 — Extracted Telegram expiry check (pure function).
// TZ handling preserved: .toUtc() on BOTH sides of comparison.

/// True if [expiresAt] is in the past (UTC comparison).
/// Uses `.toUtc()` on both DateTime.now() and the parsed timestamp.
bool isTelegramExpired(String? expiresAt) {
  if (expiresAt == null) return false;
  try {
    return DateTime.now().toUtc().isAfter(DateTime.parse(expiresAt).toUtc());
  } catch (_) {
    return false;
  }
}
