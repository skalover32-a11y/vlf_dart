import 'dart:io';
import 'package:vlf_dart/clash_config.dart';

/// Тестовый скрипт для проверки генерации Clash-конфигурации
Future<void> main() async {
  // Тестовая VLESS-подписка
  const testVless = 'vless://cc0bf5d6-f57d-4969-ae07-5954b5aeac64@troynichek-live.ru:10745'
      '?encryption=none&flow=xtls-rprx-vision&fp=random'
      '&pbk=8xDmZ6DBcNQg5c5DHbUDY6zvaBoe0tU2_hvToLFimw0'
      '&security=reality&sid=7d69ea50&sni=caprover.com'
      '&spx=%2FIXRJ5SAfm5F2Lt5&type=tcp#vlfFIN-249717973@bot';

  print('Генерация Clash конфигурации из VLESS...\n');

  try {
    final yaml = await buildClashConfig(
      testVless,
      true, // ruMode
      ['example.com'], // siteExcl
      ['chrome.exe'], // appExcl
    );

    print('Сгенерированный config.yaml:');
    print('=' * 60);
    print(yaml);
    print('=' * 60);

    // Сохраняем в файл
    final file = File('config_test_clash.yaml');
    await file.writeAsString(yaml);
    print('\nКонфигурация сохранена в: ${file.absolute.path}');
  } catch (e, st) {
    print('Ошибка: $e');
    print(st);
    exit(1);
  }
}
