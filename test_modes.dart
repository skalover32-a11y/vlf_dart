import 'dart:io';
import 'lib/clash_config.dart';

void main() async {
  final vless = 'vless://cc0bf5d6-f57d-4969-ae07-5954b5aeac64@troynichek-live.ru:10745?encryption=none&flow=xtls-rprx-vision&security=reality&sni=caprover.com&fp=random&pbk=8xDmZ6DBcNQg5c5DHbUDY6zvaBoe0tU2_hvToLFimw0&sid=7d69ea50&type=tcp';
  
  print('=== ГЛОБАЛЬНЫЙ РЕЖИМ (ruMode = false) ===');
  final globalConfig = await buildClashConfig(vless, false, [], []);
  File('config_global.yaml').writeAsStringSync(globalConfig);
  print('Секция rules:');
  final globalLines = globalConfig.split('\n');
  bool inRules = false;
  for (final line in globalLines) {
    if (line.startsWith('rules:')) inRules = true;
    if (inRules) print(line);
  }
  
  print('\n\n=== РФ-РЕЖИМ (ruMode = true) ===');
  final ruConfig = await buildClashConfig(vless, true, ['example.com'], ['chrome.exe']);
  File('config_ru.yaml').writeAsStringSync(ruConfig);
  print('Секция rules:');
  final ruLines = ruConfig.split('\n');
  inRules = false;
  for (final line in ruLines) {
    if (line.startsWith('rules:')) inRules = true;
    if (inRules) print(line);
  }
  
  print('\n✅ Конфиги сохранены: config_global.yaml, config_ru.yaml');
}
