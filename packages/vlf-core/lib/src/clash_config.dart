import 'package:meta/meta.dart';

/// Имя группы DIRECT по умолчанию.
const String _directGroupName = 'DIRECT-GROUP';

/// Имя основной VPN-группы (используется в MATCH).
const String _vpnGroupName = 'VLF-PROXY-GROUP';

typedef RoutingRulesPlan = ({
  List<String> rules,
  int appCount,
  int domainCount,
  int ruCount,
});

/// Генератор YAML-конфигурации для Clash Meta (mihomo) из VLESS-подписки.
///
/// Поддерживает только TUN-режим (без отдельного proxy-режима).
///
/// ПОРЯДОК ПРАВИЛ МАРШРУТИЗАЦИИ (строго по приоритету):
/// 1. Исключения по процессам (PROCESS-NAME,app.exe,DIRECT)
/// 2. Исключения по доменам (DOMAIN-SUFFIX,site.com,DIRECT)
/// 3. Локальные сети (GEOIP,private,DIRECT)
/// 4. РФ-режим (если ruMode=true): .ru/.su/.рф/2ip.ru + GEOIP,RU
/// 5. Всё остальное через VPN (MATCH,VLF-PROXY-GROUP)
///
/// [vlessUrl] - VLESS-подписка с параметрами Reality
/// [ruMode] - РФ-режим (true = российский трафик в обход VPN)
/// [siteExcl] - список доменов для исключения из VPN
/// [appExcl] - список процессов для исключения из VPN
Future<String> buildClashConfig(
  String vlessUrl,
  bool ruMode,
  List<String> siteExcl,
  List<String> appExcl, {
  RoutingRulesPlan? routingPlan,
}) async {
  final uri = Uri.parse(vlessUrl);
  if (uri.scheme != 'vless') {
    throw ArgumentError('Not a vless:// URL');
  }

  final uuid = uri.userInfo;
  final server = uri.host;
  final port = uri.hasPort ? uri.port : 443;

  final q = uri.queryParameters;
  String qget(String key, [String defaultVal = '']) => q[key] ?? defaultVal;

  final flow = qget('flow', '');
  final security = qget('security', '');
  final fp = qget('fp', '') != '' ? qget('fp', '') : 'random';
  final pbk = qget('pbk', '');
  final sid = qget('sid', '');
  final sni = qget('sni', '') != '' ? qget('sni', '') : server;

  // Строим YAML вручную (без зависимости от yaml пакета для простоты)
  final buffer = StringBuffer();

  // Базовые настройки Clash
  buffer.writeln('port: 7890');
  buffer.writeln('socks-port: 7891');
  buffer.writeln('mixed-port: 0');
  buffer.writeln('allow-lan: false');
  buffer.writeln('mode: rule');
  buffer.writeln('log-level: info');
  buffer.writeln('ipv6: false');
  buffer.writeln('');

  // DNS конфигурация (рабочий вариант для Windows TUN)
  buffer.writeln('dns:');
  buffer.writeln('  enable: true');
  buffer.writeln('  prefer-h3: true');
  buffer.writeln('  ipv6: false');
  buffer.writeln('  default-nameserver:');
  buffer.writeln('    - 8.8.8.8');
  buffer.writeln('    - 1.1.1.1');
  buffer.writeln('  nameserver:');
  buffer.writeln('    - https://dns.google/dns-query');
  buffer.writeln('    - https://1.1.1.1/dns-query');
  buffer.writeln('  fallback:');
  buffer.writeln('    - tls://9.9.9.9');
  buffer.writeln('    - tls://8.8.4.4');
  buffer.writeln('');

  // TUN конфигурация (ключевая часть для VPN-режима)
  buffer.writeln('tun:');
  buffer.writeln('  enable: true');
  buffer.writeln('  stack: gvisor');
  buffer.writeln('  auto-route: true');
  buffer.writeln('  auto-detect-interface: true');
  buffer.writeln('  dns-hijack:');
  buffer.writeln('    - "198.18.0.2:53"');
  buffer.writeln('  mtu: 9000');
  buffer.writeln('');

  // Генерируем уникальное имя прокси на основе сервера
  final proxyName = 'VLF-$server';

  // Прокси (VLESS с Reality)
  buffer.writeln('proxies:');
  buffer.writeln('  - name: "$proxyName"');
  buffer.writeln('    type: vless');
  buffer.writeln('    server: "$server"');
  buffer.writeln('    port: $port');
  buffer.writeln('    uuid: "$uuid"');
  if (flow.isNotEmpty) {
    buffer.writeln('    flow: "$flow"');
  }
  buffer.writeln('    udp: true');
  buffer.writeln('    tls: true');
  buffer.writeln('    servername: "$sni"');
  if (security == 'reality' && pbk.isNotEmpty) {
    buffer.writeln('    reality-opts:');
    buffer.writeln('      public-key: "$pbk"');
    buffer.writeln('      short-id: "$sid"');
  }
  buffer.writeln('    client-fingerprint: "$fp"');
  buffer.writeln('');

  // Группы прокси (КРИТИЧЕСКИ ВАЖНО: Clash требует именованные группы для DIRECT)
  buffer.writeln('proxy-groups:');

  // Группа для DIRECT-трафика (обход VPN)
  buffer.writeln('  - name: "$_directGroupName"');
  buffer.writeln('    type: select');
  buffer.writeln('    proxies:');
  buffer.writeln('      - DIRECT');
  buffer.writeln('');

  // Группа для VPN-прокси с fallback на DIRECT
  buffer.writeln('  - name: "$_vpnGroupName"');
  buffer.writeln('    type: select');
  buffer.writeln('    proxies:');
  buffer.writeln('      - "$proxyName"');
  buffer.writeln('      - DIRECT');
  buffer.writeln('');

  final plan =
      routingPlan ??
      buildRoutingRulesPlan(
        ruMode: ruMode,
        siteExcl: siteExcl,
        appExcl: appExcl,
      );
  final rules = plan.rules;
  final localRuleIndex = plan.appCount + plan.domainCount;
  final ruStartIndex = localRuleIndex + 1;
  final ruEndIndex = ruStartIndex + plan.ruCount;

  // ==================== ПРАВИЛА МАРШРУТИЗАЦИИ ====================
  // КРИТИЧЕСКИ ВАЖНЫЙ ПОРЯДОК (Clash проверяет сверху вниз):
  // 1. Исключения по процессам (приложения)
  // 2. Исключения по доменам (сайты)
  // 3. Локальные сети (GEOIP,private)
  // 4. РФ-блок (.ru/.su/.рф/2ip.ru + GEOIP,RU), если включен
  // 5. MATCH,VLF-PROXY-GROUP (всё остальное через VPN)
  buffer.writeln('rules:');

  if (plan.appCount > 0) {
    buffer.writeln('  # --- Исключения: приложения (ВЫСШИЙ ПРИОРИТЕТ) ---');
    for (var i = 0; i < plan.appCount; i++) {
      buffer.writeln('  - ${rules[i]}');
    }
    buffer.writeln('');
  }

  if (plan.domainCount > 0) {
    buffer.writeln('  # --- Исключения: домены (ВЫСШИЙ ПРИОРИТЕТ) ---');
    for (var i = plan.appCount; i < plan.appCount + plan.domainCount; i++) {
      buffer.writeln('  - ${rules[i]}');
    }
    buffer.writeln('');
  }

  buffer.writeln('  # --- Локальные сети ---');
  buffer.writeln('  - ${rules[localRuleIndex]}');
  buffer.writeln('');

  if (plan.ruCount > 0) {
    buffer.writeln('  # --- РФ-режим: российский трафик в обход VPN ---');
    for (var i = ruStartIndex; i < ruEndIndex; i++) {
      buffer.writeln('  - ${rules[i]}');
    }
    buffer.writeln('');
  }

  buffer.writeln('  # --- Всё остальное через VPN ---');
  buffer.writeln('  - ${rules.last}');

  return buffer.toString();
}

/// Возвращает план построения правил маршрутизации (для логики и тестов).
RoutingRulesPlan buildRoutingRulesPlan({
  required bool ruMode,
  required List<String> siteExcl,
  required List<String> appExcl,
  String directGroupName = _directGroupName,
  String vpnGroupName = _vpnGroupName,
}) {
  final normalizedApps = _normalizeUnique(appExcl);
  final normalizedDomains = _normalizeUnique(siteExcl);

  final apps = normalizedApps
      .map((app) => 'PROCESS-NAME,$app,$directGroupName')
      .toList();

  final domains = normalizedDomains
      .map((domain) => 'DOMAIN-SUFFIX,$domain,$directGroupName')
      .toList();

  final domainKeys = normalizedDomains.map((d) => d.toLowerCase()).toSet();

  final ruRules = <String>[];
  if (ruMode) {
    const ruDomains = ['ru', 'su', 'рф'];
    for (final tld in ruDomains) {
      ruRules.add('DOMAIN-SUFFIX,$tld,$directGroupName');
    }
    if (!domainKeys.contains('2ip.ru')) {
      ruRules.add('DOMAIN-SUFFIX,2ip.ru,$directGroupName');
    }
    ruRules.add('GEOIP,RU,$directGroupName,no-resolve');
  }

  final rules = <String>[
    ...apps,
    ...domains,
    'GEOIP,private,$directGroupName,no-resolve',
    ...ruRules,
    'MATCH,$vpnGroupName',
  ];

  return (
    rules: List<String>.unmodifiable(rules),
    appCount: apps.length,
    domainCount: domains.length,
    ruCount: ruRules.length,
  );
}

/// Плоский список правил (удобно использовать в тестах).
@visibleForTesting
List<String> buildRoutingRules({
  required bool ruMode,
  required List<String> siteExcl,
  required List<String> appExcl,
}) {
  return buildRoutingRulesPlan(
    ruMode: ruMode,
    siteExcl: siteExcl,
    appExcl: appExcl,
  ).rules;
}

/// Генератор YAML-конфигурации для Clash Meta (mihomo) в PROXY режиме.
///
/// PROXY режим:
/// - НЕ использует TUN интерфейс (не требует wintun.dll, не нужны права администратора)
/// - Запускает HTTP/SOCKS прокси на localhost (mixed-port: 7890, socks-port: 7891)
/// - Правила маршрутизации идентичны TUN режиму (РФ-режим, исключения работают так же)
/// - Приложения должны быть настроены на использование прокси вручную
///
/// Параметры идентичны [buildClashConfig], но без TUN секции.
Future<String> buildClashConfigProxy(
  String vlessUrl,
  bool ruMode,
  List<String> siteExcl,
  List<String> appExcl, {
  RoutingRulesPlan? routingPlan,
}) async {
  final uri = Uri.parse(vlessUrl);
  if (uri.scheme != 'vless') {
    throw ArgumentError('Not a vless:// URL');
  }

  final uuid = uri.userInfo;
  final server = uri.host;
  final port = uri.hasPort ? uri.port : 443;

  final q = uri.queryParameters;
  String qget(String key, [String defaultVal = '']) => q[key] ?? defaultVal;

  final flow = qget('flow', '');
  final security = qget('security', '');
  final fp = qget('fp', '') != '' ? qget('fp', '') : 'random';
  final pbk = qget('pbk', '');
  final sid = qget('sid', '');
  final sni = qget('sni', '') != '' ? qget('sni', '') : server;

  final buffer = StringBuffer();

  // Базовые настройки Clash (PROXY режим: mixed-port вместо TUN)
  buffer.writeln('port: 0');  // Отключаем отдельный HTTP порт
  buffer.writeln('socks-port: 7891');
  buffer.writeln('mixed-port: 7890');  // HTTP + SOCKS на одном порту
  buffer.writeln('allow-lan: false');
  buffer.writeln('mode: rule');
  buffer.writeln('log-level: info');
  buffer.writeln('ipv6: false');
  buffer.writeln('');

  // DNS конфигурация (идентична TUN режиму)
  buffer.writeln('dns:');
  buffer.writeln('  enable: true');
  buffer.writeln('  prefer-h3: true');
  buffer.writeln('  ipv6: false');
  buffer.writeln('  default-nameserver:');
  buffer.writeln('    - 8.8.8.8');
  buffer.writeln('    - 1.1.1.1');
  buffer.writeln('  nameserver:');
  buffer.writeln('    - https://dns.google/dns-query');
  buffer.writeln('    - https://1.1.1.1/dns-query');
  buffer.writeln('  fallback:');
  buffer.writeln('    - tls://9.9.9.9');
  buffer.writeln('    - tls://8.8.4.4');
  buffer.writeln('');

  // PROXY режим: НЕТ TUN секции (главное отличие от TUN режима)

  // Генерируем уникальное имя прокси на основе сервера
  final proxyName = 'VLF-$server';

  // Прокси (VLESS с Reality) - идентично TUN режиму
  buffer.writeln('proxies:');
  buffer.writeln('  - name: "$proxyName"');
  buffer.writeln('    type: vless');
  buffer.writeln('    server: "$server"');
  buffer.writeln('    port: $port');
  buffer.writeln('    uuid: "$uuid"');
  if (flow.isNotEmpty) {
    buffer.writeln('    flow: "$flow"');
  }
  buffer.writeln('    udp: true');
  buffer.writeln('    tls: true');
  buffer.writeln('    servername: "$sni"');
  if (security == 'reality' && pbk.isNotEmpty) {
    buffer.writeln('    reality-opts:');
    buffer.writeln('      public-key: "$pbk"');
    buffer.writeln('      short-id: "$sid"');
  }
  buffer.writeln('    client-fingerprint: "$fp"');
  buffer.writeln('');

  // Группы прокси - идентично TUN режиму
  buffer.writeln('proxy-groups:');
  buffer.writeln('  - name: "$_directGroupName"');
  buffer.writeln('    type: select');
  buffer.writeln('    proxies:');
  buffer.writeln('      - DIRECT');
  buffer.writeln('');
  buffer.writeln('  - name: "$_vpnGroupName"');
  buffer.writeln('    type: select');
  buffer.writeln('    proxies:');
  buffer.writeln('      - "$proxyName"');
  buffer.writeln('      - DIRECT');
  buffer.writeln('');

  // Правила маршрутизации - идентично TUN режиму (переиспользуем общую функцию)
  final plan =
      routingPlan ??
      buildRoutingRulesPlan(
        ruMode: ruMode,
        siteExcl: siteExcl,
        appExcl: appExcl,
      );
  final rules = plan.rules;
  final localRuleIndex = plan.appCount + plan.domainCount;
  final ruStartIndex = localRuleIndex + 1;
  final ruEndIndex = ruStartIndex + plan.ruCount;

  buffer.writeln('rules:');

  if (plan.appCount > 0) {
    buffer.writeln('  # --- Исключения: приложения (ВЫСШИЙ ПРИОРИТЕТ) ---');
    for (var i = 0; i < plan.appCount; i++) {
      buffer.writeln('  - ${rules[i]}');
    }
    buffer.writeln('');
  }

  if (plan.domainCount > 0) {
    buffer.writeln('  # --- Исключения: домены (ВЫСШИЙ ПРИОРИТЕТ) ---');
    for (var i = plan.appCount; i < plan.appCount + plan.domainCount; i++) {
      buffer.writeln('  - ${rules[i]}');
    }
    buffer.writeln('');
  }

  buffer.writeln('  # --- Локальные сети ---');
  buffer.writeln('  - ${rules[localRuleIndex]}');
  buffer.writeln('');

  if (plan.ruCount > 0) {
    buffer.writeln('  # --- РФ-режим: российский трафик в обход VPN ---');
    for (var i = ruStartIndex; i < ruEndIndex; i++) {
      buffer.writeln('  - ${rules[i]}');
    }
    buffer.writeln('');
  }

  buffer.writeln('  # --- Всё остальное через VPN ---');
  buffer.writeln('  - ${rules.last}');

  return buffer.toString();
}

List<String> _normalizeUnique(List<String> source) {
  final result = <String>[];
  final seen = <String>{};
  for (final item in source) {
    final trimmed = item.trim();
    if (trimmed.isEmpty) continue;
    final lower = trimmed.toLowerCase();
    if (seen.add(lower)) {
      result.add(trimmed);
    }
  }
  return result;
}
