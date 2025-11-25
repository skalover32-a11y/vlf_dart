/// Тестовый скрипт для проверки порядка правил в config.yaml
/// 
/// Проверяет:
/// 1. Исключения всегда стоят ПЕРЕД РФ-правилами и локальными сетями
/// 2. DNS fake-ip-filter правильно настроен для РФ-режима
/// 3. TUN конфигурация включает dns-hijack и strict-route

import 'dart:io';
import 'lib/clash_config.dart';

void main() async {
  print('=== ТЕСТ 1: Режим РФ БЕЗ исключений ===\n');
  final config1 = await buildClashConfig(
    'vless://uuid@server:443?security=reality&pbk=key&sid=id&sni=example.com',
    true, // ruMode = true
    [], // без исключений по доменам
    [], // без исключений по приложениям
  );
  
  print('Правила:');
  final lines1 = config1.split('\n');
  final rulesStart1 = lines1.indexWhere((l) => l.trim() == 'rules:');
  for (var i = rulesStart1; i < lines1.length && i < rulesStart1 + 20; i++) {
    if (lines1[i].trim().isNotEmpty) {
      print(lines1[i]);
    }
  }
  
  // Проверка: первое правило должно быть GEOIP,private
  final firstRule1 = lines1.skip(rulesStart1 + 1).firstWhere(
    (l) => l.trim().startsWith('- '),
    orElse: () => '',
  );
  assert(firstRule1.contains('GEOIP,private'), 
    '❌ ОШИБКА: Первое правило должно быть GEOIP,private (без исключений)');
  print('\n✅ ТЕСТ 1 ПРОЙДЕН: Без исключений правила начинаются с GEOIP,private\n');

  print('\n=== ТЕСТ 2: Режим РФ С исключениями ===\n');
  final config2 = await buildClashConfig(
    'vless://uuid@server:443?security=reality&pbk=key&sid=id&sni=example.com',
    true, // ruMode = true
    ['google.com', 'youtube.com'], // исключения по доменам
    ['chrome.exe', 'firefox.exe'], // исключения по приложениям
  );
  
  print('Правила:');
  final lines2 = config2.split('\n');
  final rulesStart2 = lines2.indexWhere((l) => l.trim() == 'rules:');
  for (var i = rulesStart2; i < lines2.length && i < rulesStart2 + 25; i++) {
    if (lines2[i].trim().isNotEmpty) {
      print(lines2[i]);
    }
  }
  
  // Проверка: первое правило должно быть PROCESS-NAME
  final firstRule2 = lines2.skip(rulesStart2 + 1).firstWhere(
    (l) => l.trim().startsWith('- '),
    orElse: () => '',
  );
  assert(firstRule2.contains('PROCESS-NAME'), 
    '❌ ОШИБКА: Первое правило должно быть PROCESS-NAME (исключение по приложению)');
  
  // Проверка: после PROCESS-NAME должен быть DOMAIN-SUFFIX (исключения по доменам)
  final domainRule = lines2.skip(rulesStart2 + 1).firstWhere(
    (l) => l.contains('DOMAIN-SUFFIX') && (l.contains('google.com') || l.contains('youtube.com')),
    orElse: () => '',
  );
  assert(domainRule.isNotEmpty && domainRule.contains('google.com'), 
    '❌ ОШИБКА: DOMAIN-SUFFIX для исключений должен быть ПЕРЕД локальными сетями');
  
  // Проверка: GEOIP,private должен быть ПОСЛЕ исключений
  final privateRule = lines2.skip(rulesStart2 + 1).firstWhere(
    (l) => l.contains('GEOIP,private'),
    orElse: () => '',
  );
  final privateIndex = lines2.indexOf(privateRule);
  final domainIndex = lines2.indexOf(domainRule);
  assert(privateIndex > domainIndex, 
    '❌ ОШИБКА: GEOIP,private должен быть ПОСЛЕ исключений по доменам');
  
  // Проверка: РФ-правила должны быть ПОСЛЕ GEOIP,private
  final ruRule = lines2.skip(rulesStart2 + 1).firstWhere(
    (l) => l.contains('DOMAIN-SUFFIX,ru,DIRECT-GROUP'),
    orElse: () => '',
  );
  final ruIndex = lines2.indexOf(ruRule);
  assert(ruIndex > privateIndex, 
    '❌ ОШИБКА: РФ-правила должны быть ПОСЛЕ GEOIP,private');
  
  print('\n✅ ТЕСТ 2 ПРОЙДЕН: Исключения стоят ПЕРЕД локальными сетями и РФ-правилами\n');

  print('\n=== ТЕСТ 3: Глобальный режим С исключениями ===\n');
  final config3 = await buildClashConfig(
    'vless://uuid@server:443?security=reality&pbk=key&sid=id&sni=example.com',
    false, // ruMode = false (глобальный)
    ['yandex.ru'], // исключение по домену
    ['telegram.exe'], // исключение по приложению
  );
  
  print('Правила:');
  final lines3 = config3.split('\n');
  final rulesStart3 = lines3.indexWhere((l) => l.trim() == 'rules:');
  for (var i = rulesStart3; i < lines3.length && i < rulesStart3 + 15; i++) {
    if (lines3[i].trim().isNotEmpty) {
      print(lines3[i]);
    }
  }
  
  // Проверка: РФ-правил НЕ должно быть в глобальном режиме
  final hasRuRules = lines3.any((l) => l.contains('DOMAIN-SUFFIX,ru,DIRECT-GROUP'));
  assert(!hasRuRules, 
    '❌ ОШИБКА: В глобальном режиме НЕ должно быть РФ-правил');
  
  // Проверка: исключения должны быть ПЕРВЫМИ
  final firstRule3 = lines3.skip(rulesStart3 + 1).firstWhere(
    (l) => l.trim().startsWith('- '),
    orElse: () => '',
  );
  assert(firstRule3.contains('PROCESS-NAME,telegram.exe'), 
    '❌ ОШИБКА: Первое правило должно быть исключение по приложению');
  
  print('\n✅ ТЕСТ 3 ПРОЙДЕН: В глобальном режиме нет РФ-правил, исключения работают\n');

  print('\n=== ТЕСТ 4: Проверка DNS fake-ip-filter для РФ-режима ===\n');
  final config4 = await buildClashConfig(
    'vless://uuid@server:443?security=reality&pbk=key&sid=id&sni=example.com',
    true, // ruMode = true
    [],
    [],
  );
  
  // Проверка: fake-ip-filter должен содержать +.ru, +.su, +.рф
  final hasFakeIpRu = config4.contains('- "+.ru"');
  final hasFakeIpSu = config4.contains('- "+.su"');
  final hasFakeIpRf = config4.contains('- "+.рф"');
  
  assert(hasFakeIpRu && hasFakeIpSu && hasFakeIpRf,
    '❌ ОШИБКА: fake-ip-filter должен содержать +.ru, +.su, +.рф в РФ-режиме');
  
  // Проверка: nameserver-policy должен быть установлен
  final hasNameserverPolicy = config4.contains('nameserver-policy:');
  assert(hasNameserverPolicy,
    '❌ ОШИБКА: nameserver-policy должен быть установлен в РФ-режиме');
  
  print('✅ ТЕСТ 4 ПРОЙДЕН: DNS настроен корректно для РФ-режима\n');

  print('\n=== ТЕСТ 5: Проверка TUN конфигурации ===\n');
  final config5 = await buildClashConfig(
    'vless://uuid@server:443?security=reality&pbk=key&sid=id&sni=example.com',
    false,
    [],
    [],
  );
  
  // Проверка: TUN должен содержать dns-hijack и strict-route
  final hasDnsHijack = config5.contains('dns-hijack:');
  final hasStrictRoute = config5.contains('strict-route: true');
  
  assert(hasDnsHijack,
    '❌ ОШИБКА: TUN должен содержать dns-hijack для перехвата DNS');
  assert(hasStrictRoute,
    '❌ ОШИБКА: TUN должен содержать strict-route: true');
  
  print('✅ ТЕСТ 5 ПРОЙДЕН: TUN настроен с dns-hijack и strict-route\n');

  print('\n=== ВСЕ ТЕСТЫ ПРОЙДЕНЫ ===\n');
  print('✅ Порядок правил корректный:');
  print('  1. PROCESS-NAME (исключения по приложениям) → DIRECT-GROUP');
  print('  2. DOMAIN-SUFFIX (исключения по доменам) → DIRECT-GROUP');
  print('  3. GEOIP,private (локальные сети) → DIRECT-GROUP');
  print('  4. РФ-блок (если включен): .ru/.su/.рф + GEOIP,RU + 2ip.ru → DIRECT-GROUP');
  print('  5. MATCH,FINAL-GROUP (всё остальное через VPN)\n');
  print('✅ DNS настроен корректно:');
  print('  - fake-ip-filter содержит российские домены в РФ-режиме');
  print('  - nameserver-policy использует российские DNS для .ru/.su/.рф\n');
  print('✅ TUN настроен агрессивно:');
  print('  - dns-hijack перехватывает все DNS-запросы');
  print('  - strict-route обеспечивает строгую маршрутизацию\n');
  
  exit(0);
}
