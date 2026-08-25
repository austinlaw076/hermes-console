/// Returns a human-readable relative timestamp for a Unix-seconds value.
///
/// Examples: "just now", "5m ago", "3h ago", "2d ago", "14/6".
/// [languageCode] accepts app codes (`en`/`es`/`zh`) or full locale names.
String relativeTime(double ts, {String languageCode = 'en', DateTime? now}) {
  final dt = DateTime.fromMillisecondsSinceEpoch((ts * 1000).toInt());
  final diff = (now ?? DateTime.now()).difference(dt);
  final code = languageCode.toLowerCase().replaceAll('-', '_');
  final isEs = code.startsWith('es');
  final isZh = code.startsWith('zh') &&
      (code.contains('hant') ||
          code.startsWith('zh_hk') ||
          code.startsWith('zh_tw') ||
          code.startsWith('zh_mo') ||
          code == 'zh');
  if (diff.isNegative || diff.inMinutes < 1) {
    if (isEs) return 'ahora';
    if (isZh) return '剛剛';
    return 'just now';
  }
  if (diff.inHours < 1) {
    if (isEs) return '${diff.inMinutes} min';
    if (isZh) return '${diff.inMinutes} 分鐘前';
    return '${diff.inMinutes}m ago';
  }
  if (diff.inDays < 1) {
    if (isEs) return '${diff.inHours} h';
    if (isZh) return '${diff.inHours} 小時前';
    return '${diff.inHours}h ago';
  }
  if (diff.inDays < 7) {
    if (isEs) return '${diff.inDays} d';
    if (isZh) return '${diff.inDays} 日前';
    return '${diff.inDays}d ago';
  }
  return '${dt.day}/${dt.month}';
}
