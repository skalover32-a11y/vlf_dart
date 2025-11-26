import 'dart:io';
import 'package:vlf_core/vlf_core.dart' show buildClashConfig;

/// Тестовый скрипт для генерации Clash Meta конфигурации.
/// Генерирует config_test.yaml для проверки корректности настроек.
Future<void> main() async {
  print('Генерация тестовой конфигурации Clash Meta...');
  
  final vless =
      'vless://cc0bf5d6-f57d-4969-ae07-5954b5aeac64@troynichek-live.ru:10745?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&fp=chrome&pbk=jNXfkEqis9K4BVpJPPQWoYUY0hrait-eNp3i1wB5el0&sid=d9b2eb16&type=tcp&headerType=none';
  
  final yaml = await buildClashConfig(
    vless,
    false, // ruMode
    [], // siteExcl
    [], // appExcl
  );
  
  final out = File('config_test.yaml');
  out.writeAsStringSync(yaml, flush: true);
  print('Wrote config_test.yaml (Clash format)');
}
