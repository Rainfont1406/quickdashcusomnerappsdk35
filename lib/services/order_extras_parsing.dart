// Shared, defensive parser for OrderModel/CartProduct's `extras` field
// (2026-09-09). Was duplicated inline in 3 places (OrdersScreen.dart,
// OrderDetailsScreen.dart x2) with inconsistent levels of defense - two of
// the three stripped backslashes, one didn't. That gap is exactly how a
// real, live production order (vendor_orders/859656439 - confirmed
// directly against Firestore, not guessed) slipped through: one `extras`
// entry was several thousand literal backslash characters, and
// OrdersScreen's copy of this logic - the one missing backslash handling -
// rendered it as a giant broken-looking block filling the whole screen.
//
// Centralizing this so every caller gets the same defense, and so a future
// fix here reaches all of them at once instead of needing to be
// hand-reapplied in N places (which is exactly how the original gap
// happened - one call site got patched, the others didn't). Also adds a
// defense the original code never had anywhere: a max-length sanity check.
// Backslash-stripping alone only protects against THIS specific corruption
// shape - a future bug that stuffs some other kind of oversized garbage
// into this field (not pure backslashes) would sail straight through the
// same way. A real add-on/customization name is never remotely
// kMaxExtraLength characters; anything longer is corrupted data, full stop,
// regardless of what characters it's made of.
const int kMaxExtraLength = 80;

List<String> parseOrderExtras(dynamic raw) {
  List<String> items;
  if (raw is List) {
    items = raw.map((e) => e.toString()).toList();
  } else if (raw is String && raw.isNotEmpty && raw != '[]') {
    final cleaned = raw.replaceAll('[', '').replaceAll(']', '').replaceAll('"', '');
    // Support both comma-separated (current format) and slash-separated
    // (old format, per the pre-existing OrdersScreen comment this
    // preserves) - only one separator is ever used per string, so picking
    // whichever is actually present is safe.
    final sep = cleaned.contains(',') ? ',' : '/';
    items = cleaned.split(sep);
  } else {
    return const [];
  }

  return items.map(_cleanExtra).where((s) {
    if (s.isEmpty || s == 'null' || s == '[]') return false;
    return s.length <= kMaxExtraLength;
  }).toList();
}

String _cleanExtra(String s) {
  s = s.replaceAll('"', '').replaceAll('\\', '').trim();
  while (s.startsWith('/')) {
    s = s.substring(1).trim();
  }
  while (s.endsWith('/')) {
    s = s.substring(0, s.length - 1).trim();
  }
  return s;
}
