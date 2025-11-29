import 'dart:io';
import 'lib/clash_config.dart';

void main() async {
  final vless =
      'vless://cc0bf5d6-f57d-4969-ae07-5954b5aeac64@troynichek-live.ru:10745?encryption=none&flow=xtls-rprx-vision&security=reality&sni=caprover.com&fp=random&pbk=8xDmZ6DBcNQg5c5DHbUDY6zvaBoe0tU2_hvToLFimw0&sid=7d69ea50&type=tcp';

  print('=' * 70);
  print('ТЕСТ 1: ГЛОБАЛЬНЫЙ РЕЖИМ БЕЗ ИСКЛЮЧЕНИЙ');
  print('=' * 70);
  final test1 = await buildClashConfig(vless, false, [], []);
  File('config_test1.yaml').writeAsStringSync(test1);
  _printRules(test1);
  _validateRules(test1, expectRF: false, expectExcl: false);

  print('\n${'=' * 70}');
  print('ТЕСТ 2: ГЛОБАЛЬНЫЙ РЕЖИМ С ИСКЛЮЧЕНИЯМИ');
  print('=' * 70);
  final test2 = await buildClashConfig(
    vless,
    false,
    ['kinopoisk.ru', 'vk.com'],
    ['chrome.exe', 'Telegram.exe'],
  );
  File('config_test2.yaml').writeAsStringSync(test2);
  _printRules(test2);
  _validateRules(test2, expectRF: false, expectExcl: true);

  print('\n${'=' * 70}');
  print('ТЕСТ 3: РФ-РЕЖИМ БЕЗ ИСКЛЮЧЕНИЙ');
  print('=' * 70);
  final test3 = await buildClashConfig(vless, true, [], []);
  File('config_test3.yaml').writeAsStringSync(test3);
  _printRules(test3);
  _validateRules(test3, expectRF: true, expectExcl: false);

  print('\n${'=' * 70}');
  print('ТЕСТ 4: РФ-РЕЖИМ С ИСКЛЮЧЕНИЯМИ');
  print('=' * 70);
  final test4 = await buildClashConfig(
    vless,
    true,
    ['kinopoisk.ru', 'vk.com'],
    ['chrome.exe', 'Telegram.exe'],
  );
  File('config_test4.yaml').writeAsStringSync(test4);
  _printRules(test4);
  _validateRules(test4, expectRF: true, expectExcl: true);

  print('\n${'=' * 70}');
  print('ТЕСТ 5: РФ-РЕЖИМ С 2ip.ru В ИСКЛЮЧЕНИЯХ (проверка дубликатов)');
  print('=' * 70);
  final test5 = await buildClashConfig(vless, true, ['2ip.ru'], []);
  File('config_test5.yaml').writeAsStringSync(test5);
  _printRules(test5);
  _validateNoDuplicates(test5, '2ip.ru');

  print('\n✅ ВСЕ ТЕСТЫ ПРОЙДЕНЫ!');
}

void _printRules(String config) {
  final lines = config.split('\n');
  bool inRules = false;
  for (final line in lines) {
    if (line.startsWith('rules:')) inRules = true;
    if (inRules) print(line);
  }
}

void _validateRules(
  String config, {
  required bool expectRF,
  required bool expectExcl,
}) {
  final lines = config.split('\n');
  final hasRFRules = lines.any((l) => l.contains('DOMAIN-SUFFIX,ru,DIRECT'));
  final hasExcl = lines.any(
    (l) => l.contains('kinopoisk.ru') || l.contains('chrome.exe'),
  );
  final hasMatch = lines.any((l) => l.contains('MATCH,VLF'));

  if (expectRF != hasRFRules) {
    throw Exception('❌ РФ-правила: ожидалось $expectRF, получено $hasRFRules');
  }
  if (expectExcl != hasExcl) {
    throw Exception('❌ Исключения: ожидалось $expectExcl, получено $hasExcl');
  }
  if (!hasMatch) {
    throw Exception('❌ Нет финального правила MATCH,VLF');
  }

  print(
    '✅ Валидация пройдена: РФ=$expectRF, Исключения=$expectExcl, MATCH=true',
  );
}

void _validateNoDuplicates(String config, String domain) {
  final lines = config.split('\n');
  final domainRules = lines
      .where((l) => l.contains('DOMAIN-SUFFIX,$domain,DIRECT'))
      .toList();

  if (domainRules.length > 1) {
    throw Exception(
      '❌ Найдено ${domainRules.length} дубликатов для $domain:\n${domainRules.join("\n")}',
    );
  }

  print('✅ Дубликатов для $domain не найдено (правил: ${domainRules.length})');
}
