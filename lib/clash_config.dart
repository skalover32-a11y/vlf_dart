/// Генератор YAML-конфигурации для Clash Meta (mihomo) из VLESS-подписки.
/// 
/// Поддерживает только TUN-режим (без отдельного proxy-режима).
/// 
/// ПОРЯДОК ПРАВИЛ МАРШРУТИЗАЦИИ (строго по приоритету):
/// 1. Исключения по процессам (PROCESS-NAME,app.exe,DIRECT)
/// 2. Исключения по доменам (DOMAIN-SUFFIX,site.com,DIRECT)
/// 3. Локальные сети (GEOIP,private,DIRECT)
/// 4. РФ-режим (если ruMode=true):
///    - DOMAIN-SUFFIX,ru/su/рф,DIRECT
///    - GEOIP,RU,DIRECT
///    - DOMAIN-SUFFIX,2ip.ru,DIRECT
/// 5. Всё остальное через VPN (MATCH,VLF)
/// 
/// [vlessUrl] - VLESS-подписка с параметрами Reality
/// [ruMode] - РФ-режим (true = российский трафик в обход VPN)
/// [siteExcl] - список доменов для исключения из VPN
/// [appExcl] - список процессов для исключения из VPN
Future<String> buildClashConfig(
  String vlessUrl,
  bool ruMode,
  List<String> siteExcl,
  List<String> appExcl,
) async {
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

  // DNS конфигурация
  // КРИТИЧЕСКИ ВАЖНО: fake-ip режим необходим для корректной работы DOMAIN-SUFFIX правил
  // НО он не должен мешать DIRECT-трафику (через fake-ip-filter)
  buffer.writeln('dns:');
  buffer.writeln('  enabled: true');
  buffer.writeln('  ipv6: false');
  buffer.writeln('  listen: 0.0.0.0:1053');
  buffer.writeln('  enhanced-mode: fake-ip');
  buffer.writeln('  fake-ip-range: 198.18.0.1/16');
  buffer.writeln('  fake-ip-filter:');
  buffer.writeln('    - "*.lan"');
  buffer.writeln('    - "localhost.ptlogin2.qq.com"');
  
  // В РФ-режиме добавляем .ru/.su/.рф в fake-ip-filter
  // чтобы они резолвились через реальные DNS, а не fake-ip
  if (ruMode) {
    buffer.writeln('    - "+.ru"');
    buffer.writeln('    - "+.su"');
    buffer.writeln('    - "+.рф"');
  }
  
  buffer.writeln('  default-nameserver:');
  buffer.writeln('    - 1.1.1.1');
  buffer.writeln('    - 8.8.8.8');
  
  // В РФ-режиме используем nameserver-policy для российских доменов
  if (ruMode) {
    buffer.writeln('  nameserver-policy:');
    buffer.writeln('    "+.ru": ["77.88.8.8", "77.88.8.1"]');
    buffer.writeln('    "+.su": ["77.88.8.8", "77.88.8.1"]');
    buffer.writeln('    "+.рф": ["77.88.8.8", "77.88.8.1"]');
  }
  
  buffer.writeln('  nameserver:');
  buffer.writeln('    - https://1.1.1.1/dns-query');
  buffer.writeln('    - https://dns.google/dns-query');
  buffer.writeln('');

  // TUN конфигурация (ключевая часть для VPN-режима)
  // Агрессивный перехват всего трафика с автоматическим роутингом
  buffer.writeln('tun:');
  buffer.writeln('  enable: true');
  buffer.writeln('  stack: system');
  buffer.writeln('  auto-route: true');
  buffer.writeln('  auto-detect-interface: true');
  buffer.writeln('  dns-hijack:');
  buffer.writeln('    - any:53');
  buffer.writeln('    - tcp://any:53');
  buffer.writeln('  strict-route: true');
  buffer.writeln('');

  // Прокси (VLESS с Reality)
  buffer.writeln('proxies:');
  buffer.writeln('  - name: "VLF-PROXY"');
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
  buffer.writeln('  - name: "DIRECT-GROUP"');
  buffer.writeln('    type: select');
  buffer.writeln('    proxies:');
  buffer.writeln('      - DIRECT');
  buffer.writeln('');
  
  // Группа для VPN-прокси с fallback на DIRECT
  buffer.writeln('  - name: "VLF-PROXY-GROUP"');
  buffer.writeln('    type: select');
  buffer.writeln('    proxies:');
  buffer.writeln('      - "VLF-PROXY"');
  buffer.writeln('      - DIRECT');
  buffer.writeln('');
  
  // Финальная группа для MATCH (весь остальной трафик)
  buffer.writeln('  - name: "FINAL-GROUP"');
  buffer.writeln('    type: select');
  buffer.writeln('    proxies:');
  buffer.writeln('      - "VLF-PROXY"');
  buffer.writeln('      - DIRECT');
  buffer.writeln('');

  // ==================== ПРАВИЛА МАРШРУТИЗАЦИИ ====================
  // КРИТИЧЕСКИ ВАЖНЫЙ ПОРЯДОК (Clash проверяет сверху вниз):
  // 1. Исключения по процессам (приложения) — ВЫСШИЙ ПРИОРИТЕТ
  // 2. Исключения по доменам (сайты) — ВЫСШИЙ ПРИОРИТЕТ
  // 3. Локальные сети (GEOIP,private)
  // 4. РФ-режим (если включен): .ru/.su/.рф + GEOIP,RU + 2ip.ru
  // 5. MATCH,VLF (всё остальное через VPN)
  
  buffer.writeln('rules:');
  
  // ========== БЛОК 1: ИСКЛЮЧЕНИЯ ПО ПРИЛОЖЕНИЯМ ==========
  // Эти процессы идут через DIRECT-GROUP (минуя VPN) независимо от режима
  // ВАЖНО: исключения ВСЕГДА стоят ПЕРВЫМИ, даже перед локальными сетями
  if (appExcl.isNotEmpty) {
    buffer.writeln('  # --- Исключения: приложения (ВЫСШИЙ ПРИОРИТЕТ) ---');
    for (final proc in appExcl) {
      if (proc.trim().isNotEmpty) {
        buffer.writeln('  - PROCESS-NAME,$proc,DIRECT-GROUP');
      }
    }
    buffer.writeln('');
  }
  
  // ========== БЛОК 2: ИСКЛЮЧЕНИЯ ПО ДОМЕНАМ ==========
  // Эти сайты идут через DIRECT-GROUP (минуя VPN) независимо от режима
  // ВАЖНО: исключения ВСЕГДА стоят ПЕРВЫМИ, даже перед локальными сетями
  if (siteExcl.isNotEmpty) {
    buffer.writeln('  # --- Исключения: домены (ВЫСШИЙ ПРИОРИТЕТ) ---');
    for (final domain in siteExcl) {
      if (domain.trim().isNotEmpty) {
        buffer.writeln('  - DOMAIN-SUFFIX,$domain,DIRECT-GROUP');
      }
    }
    buffer.writeln('');
  }
  
  // ========== БЛОК 3: ЛОКАЛЬНЫЕ СЕТИ ==========
  // Локальный/приватный трафик ВСЕГДА идёт через DIRECT-GROUP
  buffer.writeln('  # --- Локальные сети ---');
  buffer.writeln('  - GEOIP,private,DIRECT-GROUP,no-resolve');
  buffer.writeln('');
  
  // ========== БЛОК 4: РЕЖИМ РФ (если включен) ==========
  if (ruMode) {
    // РФ-режим: российский трафик идёт через DIRECT-GROUP (в обход VPN)
    buffer.writeln('  # --- РФ-режим: российский трафик в обход VPN ---');
    buffer.writeln('  - DOMAIN-SUFFIX,ru,DIRECT-GROUP');
    buffer.writeln('  - DOMAIN-SUFFIX,su,DIRECT-GROUP');
    buffer.writeln('  - DOMAIN-SUFFIX,рф,DIRECT-GROUP');
    buffer.writeln('  - GEOIP,RU,DIRECT-GROUP,no-resolve');
    
    // Добавляем 2ip.ru только если его нет в пользовательских исключениях
    if (!siteExcl.contains('2ip.ru')) {
      buffer.writeln('  - DOMAIN-SUFFIX,2ip.ru,DIRECT-GROUP');
    }
    buffer.writeln('');
  }
  
  // ========== БЛОК 5: ВСЁ ОСТАЛЬНОЕ ЧЕРЕЗ VPN ==========
  buffer.writeln('  # --- Всё остальное через VPN ---');
  buffer.writeln('  - MATCH,FINAL-GROUP');

  return buffer.toString();
}
