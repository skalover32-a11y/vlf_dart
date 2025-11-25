/// Генератор YAML-конфигурации для Clash Meta (mihomo) из VLESS-подписки.
/// Основан на референсном скрипте build_config_clash.ps1.
/// 
/// Поддерживает только TUN-режим (без отдельного proxy-режима).
/// Конфигурация включает:
/// - DNS (DoH через 1.1.1.1 и dns.google)
/// - TUN с auto-route и auto-detect-interface
/// - VLESS прокси с Reality
/// - Правила маршрутизации:
///   * GLOBAL режим (ruMode = false): весь трафик через VPN, кроме локального
///   * РФ режим (ruMode = true): российский трафик DIRECT, остальное через VPN
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
  buffer.writeln('dns:');
  buffer.writeln('  enabled: true');
  buffer.writeln('  ipv6: false');
  buffer.writeln('  listen: 0.0.0.0:1053');
  buffer.writeln('  enhanced-mode: fake-ip');
  buffer.writeln('  fake-ip-range: 198.18.0.1/16');
  buffer.writeln('  fake-ip-filter:');
  buffer.writeln('    - "*.lan"');
  buffer.writeln('    - "localhost.ptlogin2.qq.com"');
  buffer.writeln('  default-nameserver:');
  buffer.writeln('    - 1.1.1.1');
  buffer.writeln('    - 8.8.8.8');
  buffer.writeln('  nameserver:');
  buffer.writeln('    - https://1.1.1.1/dns-query');
  buffer.writeln('    - https://dns.google/dns-query');
  
  // В РФ-режиме используем российские DNS для .ru/.su/.рф доменов
  // (чтобы они резолвились через местные DNS и шли DIRECT)
  if (ruMode) {
    buffer.writeln('  nameserver-policy:');
    buffer.writeln('    "+.ru": ["https://dns.yandex.ru/dns-query", "77.88.8.8"]');
    buffer.writeln('    "+.su": ["https://dns.yandex.ru/dns-query", "77.88.8.8"]');
    buffer.writeln('    "+.рф": ["https://dns.yandex.ru/dns-query", "77.88.8.8"]');
  }
  buffer.writeln('');

  // TUN конфигурация (ключевая часть для VPN-режима)
  buffer.writeln('tun:');
  buffer.writeln('  enable: true');
  buffer.writeln('  stack: system');
  buffer.writeln('  auto-route: true');
  buffer.writeln('  auto-detect-interface: true');
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

  // Группы прокси
  buffer.writeln('proxy-groups:');
  buffer.writeln('  - name: "VLF"');
  buffer.writeln('    type: select');
  buffer.writeln('    proxies:');
  buffer.writeln('      - "VLF-PROXY"');
  buffer.writeln('');

  // ==================== ПРАВИЛА МАРШРУТИЗАЦИИ ====================
  // Порядок правил критически важен! Clash проверяет их сверху вниз.
  buffer.writeln('rules:');
  
  // 1. Локальный/приватный трафик ВСЕГДА идёт напрямую (в обоих режимах)
  buffer.writeln('  - GEOIP,private,DIRECT,no-resolve');
  
  if (ruMode) {
    // ========== РЕЖИМ РФ (ruMode = true) ==========
    // Российский трафик идёт DIRECT (в обход VPN),
    // остальное — через VPN (VLF).
    
    buffer.writeln('  # --- РФ-режим: российский трафик в обход VPN ---');
    buffer.writeln('  - DOMAIN-SUFFIX,ru,DIRECT');
    buffer.writeln('  - DOMAIN-SUFFIX,su,DIRECT');
    buffer.writeln('  - DOMAIN-SUFFIX,рф,DIRECT');
    buffer.writeln('  - GEOIP,RU,DIRECT,no-resolve');
    
    // Пользовательские исключения (дополнительные домены/процессы DIRECT)
    for (final domain in siteExcl) {
      if (domain.trim().isNotEmpty) {
        buffer.writeln('  - DOMAIN-SUFFIX,$domain,DIRECT');
      }
    }
    for (final proc in appExcl) {
      if (proc.trim().isNotEmpty) {
        buffer.writeln('  - PROCESS-NAME,$proc,DIRECT');
      }
    }
    
    // Всё остальное через VPN
    buffer.writeln('  - MATCH,VLF');
    
  } else {
    // ========== ГЛОБАЛЬНЫЙ РЕЖИМ (ruMode = false) ==========
    // Весь трафик (кроме локального) через VPN,
    // но с возможностью исключений для отдельных доменов/процессов.
    
    buffer.writeln('  # --- Глобальный режим: весь трафик через VPN ---');
    
    // Пользовательские исключения (домены/процессы в обход VPN)
    for (final domain in siteExcl) {
      if (domain.trim().isNotEmpty) {
        buffer.writeln('  - DOMAIN-SUFFIX,$domain,DIRECT');
      }
    }
    for (final proc in appExcl) {
      if (proc.trim().isNotEmpty) {
        buffer.writeln('  - PROCESS-NAME,$proc,DIRECT');
      }
    }
    
    // Всё остальное через VPN
    buffer.writeln('  - MATCH,VLF');
  }

  return buffer.toString();
}
