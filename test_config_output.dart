import 'lib/clash_config.dart';

void main() async {
  final config = await buildClashConfig(
    'vless://test-uuid@server.example.com:443?security=reality&pbk=testkey123&sid=80&sni=test.com&flow=xtls-rprx-vision',
    true, // РФ-режим
    ['google.com', 'youtube.com'], // Исключения по доменам
    ['chrome.exe', 'firefox.exe'], // Исключения по приложениям
  );
  
  print(config);
}
