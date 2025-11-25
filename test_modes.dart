import 'dart:io';
import 'lib/clash_config.dart';

void main() async {
  final vless = 'vless://cc0bf5d6-f57d-4969-ae07-5954b5aeac64@troynichek-live.ru:10745?encryption=none&flow=xtls-rprx-vision&security=reality&sni=caprover.com&fp=random&pbk=8xDmZ6DBcNQg5c5DHbUDY6zvaBoe0tU2_hvToLFimw0&sid=7d69ea50&type=tcp';
  
  print('=' * 70);
  print('ТЕСТ 1: ГЛОБАЛЬНЫЙ РЕЖИМ БЕЗ ИСКЛЮЧЕНИЙ (ruMode = false)');
  print('=' * 70);
  final test1 = await buildClashConfig(vless, false, [], []);
  File('config_global_no_excl.yaml').writeAsStringSync(test1);
  _printRules(test1);
  
  print('\n' + '=' * 70);
  print('ТЕСТ 2: ГЛОБАЛЬНЫЙ РЕЖИМ С ИСКЛЮЧЕНИЯМИ (ruMode = false)');
  print('=' * 70);
  final test2 = await buildClashConfig(vless, false, ['kinopoisk.ru', 'vk.com'], ['chrome.exe', 'Telegram.exe']);
  File('config_global_with_excl.yaml').writeAsStringSync(test2);
  _printRules(test2);
  
  print('\n' + '=' * 70);
  print('ТЕСТ 3: РФ-РЕЖИМ БЕЗ ИСКЛЮЧЕНИЙ (ruMode = true)');
  print('=' * 70);
  final test3 = await buildClashConfig(vless, true, [], []);
  File('config_rf_no_excl.yaml').writeAsStringSync(test3);
  _printRules(test3);
  
  print('\n' + '=' * 70);
  print('ТЕСТ 4: РФ-РЕЖИМ С ИСКЛЮЧЕНИЯМИ (ruMode = true)');
  print('=' * 70);
  final test4 = await buildClashConfig(vless, true, ['kinopoisk.ru', 'vk.com'], ['chrome.exe', 'Telegram.exe']);
  File('config_rf_with_excl.yaml').writeAsStringSync(test4);
  _printRules(test4);
  
  print('\n✅ Все конфиги сохранены!');
}

void _printRules(String config) {
  final lines = config.split('\n');
  bool inRules = false;
  for (final line in lines) {
    if (line.startsWith('rules:')) inRules = true;
    if (inRules) print(line);
  }
}
