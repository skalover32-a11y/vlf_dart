import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Найти первую vless:// ссылку в тексте. Возвращает null если нет.
String? _findFirstVless(String text) {
  if (text.isEmpty) return null;
  for (final line in LineSplitter.split(text)) {
    final s = line.trim();
    if (s.startsWith('vless://')) return s;
  }
  // также попробуем найти в середине строки (без переноса)
  final idx = text.indexOf('vless://');
  if (idx != -1) {
    // возьмём до ближайшего пробела или конца строки
    final tail = text.substring(idx);
    final match = RegExp(r'^(vless://\S+)').firstMatch(tail);
    if (match != null) return match.group(1);
  }
  return null;
}

/// Извлекает первую vless:// ссылку из произвольного ввода.
/// Логика: 1) ищем vless:// в raw, 2) если raw выглядит как URL (http/https) - скачиваем и ищем в теле,
/// 3) иначе пробуем считать raw как base64 и искать vless:// в декодированном тексте.
Future<String> extractVlessFromAny(String raw) async {
  final s = raw.trim();
  if (s.isEmpty) throw Exception('Пустой текст подписки');

  // 1) прямой vless в тексте
  final direct = _findFirstVless(s);
  if (direct != null) return direct;

  // 2) если это HTTP/HTTPS URL — скачиваем и повторяем попытку на теле ответа
  final lower = s.toLowerCase();
  if (lower.startsWith('http://') || lower.startsWith('https://')) {
    // network fetch: increase timeout and retry once on timeout to avoid
    // spurious failures on slow connections.
    final timeoutDuration = const Duration(seconds: 20);
    try {
      final uri = Uri.parse(s);
      http.Response resp;
      try {
        resp = await http.get(uri).timeout(timeoutDuration);
      } on TimeoutException {
        // first attempt timed out — try once more with a longer timeout
        resp = await http.get(uri).timeout(timeoutDuration * 2);
      }
      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode} при получении подписки');
      }
      final body = resp.body;
      final fromBody = _findFirstVless(body);
      if (fromBody != null) return fromBody;
      // если в теле нет — попробуем декодировать тело как base64 (на случай compact)
      try {
        final compact = body.replaceAll(RegExp(r'\s+'), '');
        final decoded = base64.decode(compact);
        final decodedText = utf8.decode(decoded, allowMalformed: true);
        final fromDecoded = _findFirstVless(decodedText);
        if (fromDecoded != null) return fromDecoded;
      } catch (_) {
        // ignore base64 errors from body
      }
      throw Exception('Не найден vless:// в теле ответа');
    } on FormatException catch (e) {
      throw Exception('Неверный URL: $e');
    } on SocketException catch (e) {
      throw Exception('Сетевая ошибка при получении подписки: $e');
    }
  }

  // 3) пробуем считать как base64
  final compact = s.replaceAll(RegExp(r'\s+'), '');
  try {
    final decoded = base64.decode(compact);
    final decodedText = utf8.decode(decoded, allowMalformed: true);
    final fromDecoded = _findFirstVless(decodedText);
    if (fromDecoded != null) return fromDecoded;
    throw Exception('В декодированном тексте не найден vless://');
  } on FormatException catch (_) {
    throw Exception(
      'Не удалось распарсить подписку: невалидный base64 или отсутствует vless://',
    );
  }
}

/// Попытка извлечь имя профиля из vless:// ссылки.
/// Берёт фрагмент после `#` и возвращает декодированный текст, либо пустую строку.
String extractNameFromVless(String vless) {
  try {
    final uri = Uri.parse(vless);
    final frag = uri.fragment;
    if (frag.isNotEmpty) {
      try {
        return Uri.decodeComponent(frag);
      } catch (_) {
        return frag;
      }
    }
  } catch (_) {}
  return '';
}
