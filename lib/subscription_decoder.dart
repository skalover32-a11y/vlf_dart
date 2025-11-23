import 'dart:convert';

/// Декодер подписки: возвращает первую vless:// ссылку из текста или base64.
String decodeSubscriptionToVlessFromBytes(List<int> subBytes) {
  final text = utf8.decode(subBytes, allowMalformed: true).trim();
  if (text.isEmpty) throw ArgumentError('Subscription is empty');

  for (final line in LineSplitter.split(text)) {
    final s = line.trim();
    if (s.startsWith('vless://')) return s;
  }

  final compact = text.replaceAll(RegExp(r'\s+'), '');
  try {
    final decoded = base64.decode(compact);
    final decodedText = utf8.decode(decoded, allowMalformed: true);
    for (final line in LineSplitter.split(decodedText)) {
      final s = line.trim();
      if (s.startsWith('vless://')) return s;
    }
  } catch (e) {
    throw ArgumentError('Cannot decode subscription as base64: $e');
  }

  throw ArgumentError('No vless:// URL in subscription');
}
