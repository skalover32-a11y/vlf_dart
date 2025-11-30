import 'dart:convert';
import 'dart:io';

import 'logger.dart';
import 'vlf_models.dart';
import 'vlf_paths.dart';

const _tunTag = 'vlf-tun';
const _primaryOutboundTag = 'proxy';
const _directTag = 'direct';
const _bypassTag = 'bypass';
const _blockTag = 'block';
const _dnsDirectTag = 'dns-direct';
const _dnsLocalTag = 'dns-local';
const _dnsAndroidGoogleUdpTag = 'dns-google-udp';
const _dnsAndroidCloudflareUdpTag = 'dns-cloudflare-udp';
const _tunAddress = '10.0.0.2/30';
const _tunMtu = 9000;
const _tunStack = 'gvisor';
const _primaryDnsUrl = 'https://dns.google/dns-query';
const _androidDnsServers = [
  {
    'tag': _dnsAndroidGoogleUdpTag,
    'address': 'udp://8.8.8.8',
    'detour': _primaryOutboundTag,
  },
  {
    'tag': _dnsAndroidCloudflareUdpTag,
    'address': 'udp://1.1.1.1',
    'detour': _primaryOutboundTag,
  },
];
const _androidFakeIpConfig = {
  'enabled': true,
  'inet4_range': '198.18.0.0/15',
  'inet6_range': 'fc00::/18',
};

/// Строит полноценный sing-box конфиг для Android TUN режима.
class SingboxConfigBuilder {
  final VlfRuntimeConfig runtime;
  final bool? platformOverrideIsAndroid;
  const SingboxConfigBuilder(
    this.runtime, {
    this.platformOverrideIsAndroid,
  });

  bool get _isAndroidPlatform =>
      platformOverrideIsAndroid ?? Platform.isAndroid;

  /// Возвращает Map, пригодный для сериализации в JSON.
  Map<String, dynamic> toMap() {
    return {
      'log': _buildLogSection(),
      'dns': _buildDnsSection(),
      'inbounds': _buildInboundsSection(),
      'outbounds': _buildOutboundsSection(),
      'route': _buildRouteSection(),
    };
  }

  /// Сериализует конфиг в JSON-строку (мин. окружение для передачи на платформу).
  String toJsonString() => jsonEncode(toMap());

  /// Совместимость со старыми вызовами.
  String toJson() => toJsonString();

  /// Сохраняет JSON-конфиг в стандартный путь (config_singbox.json)
  /// и возвращает путь к файлу.
  Future<String> saveToDefaultLocation({
    Logger? logger,
    String? jsonOverride,
  }) async {
    final json = jsonOverride ?? toJsonString();
    final path = await VlfPaths.getSingboxConfigPath();
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(json, flush: true);
    final exists = await file.exists();
    final size = exists ? await file.length() : 0;
    if (logger != null) {
      final inboundsCount = _buildInboundsSection().length;
      final outboundsCount = _buildOutboundsSection().length;
      final rulesCount =
          (_buildRouteSection()['rules'] as List<dynamic>).length;
      logger.append(
        'Sing-box config stats: inbounds=$inboundsCount, outbounds=$outboundsCount, rules=$rulesCount\n',
      );
      logger.append('Sing-box JSON length=${json.length} chars\n');
      final dnsSection = _buildDnsSection();
      final dnsServers = (dnsSection['servers'] as List<dynamic>? ?? const [])
          .map((entry) => Map<String, dynamic>.from(entry as Map))
          .map((entry) => "${entry['tag']}=>${entry['address']}")
          .join(', ');
      if (dnsServers.isNotEmpty) {
        logger.append('Sing-box DNS servers: $dnsServers\n');
      }
      logger.append(
        'Sing-box config written to $path (exists=$exists, size=$size байт)\n',
      );
    }
    return path;
  }

  Map<String, dynamic> _buildLogSection() => const {'level': 'info'};

  Map<String, dynamic> _buildDnsSection() {
    if (_isAndroidPlatform) {
      return _buildAndroidDnsSection();
    }
    return _buildDefaultDnsSection();
  }

  Map<String, dynamic> _buildAndroidDnsSection() {
    return {
      'servers': _androidDnsServers,
      'strategy': 'prefer_ipv4',
      'fakeip': _androidFakeIpConfig,
      'final': _dnsAndroidGoogleUdpTag,
    };
  }

  Map<String, dynamic> _buildDefaultDnsSection() {
    final targetDomain = runtime.outbound.server;
    return {
      'independent_cache': true,
      'servers': [
        {
          'tag': _dnsDirectTag,
          'address': _primaryDnsUrl,
          'address_resolver': _dnsLocalTag,
          'detour': _directTag,
          'strategy': '',
        },
        {
          'tag': _dnsLocalTag,
          'address': 'local',
          'detour': _directTag,
        },
      ],
      'rules': [
        {'outbound': 'any', 'server': _dnsDirectTag},
        {
          'domain': [if (targetDomain.isNotEmpty) targetDomain],
          'domain_keyword': const <String>[],
          'domain_regex': const <String>[],
          'domain_suffix': const <String>[],
          'geosite': const <String>[],
          'server': _dnsDirectTag,
        },
      ],
    };
  }

  List<Map<String, dynamic>> _buildInboundsSection() {
    if (runtime.mode != VlfWorkMode.tun) {
      // Пока поддерживаем только TUN на Android. Другие режимы будут добавлены позднее.
    }
    return [
      {
        'type': 'tun',
        'tag': _tunTag,
        'address': [_tunAddress],
        'mtu': _tunMtu,
        'auto_route': true,
        'strict_route': true,
        'stack': _tunStack,
        'sniff': true,
      },
    ];
  }

  List<Map<String, dynamic>> _buildOutboundsSection() {
    final outbounds = <Map<String, dynamic>>[
      _buildPrimaryOutbound(),
      {'type': 'direct', 'tag': _directTag},
      {'type': 'direct', 'tag': _bypassTag},
      {'type': 'block', 'tag': _blockTag},
    ];
    return outbounds;
  }

  Map<String, dynamic> _buildPrimaryOutbound() {
    final o = runtime.outbound;
    final outbound = {
      'type': 'vless',
      'tag': _primaryOutboundTag,
      'server': o.server,
      'server_port': o.port,
      'uuid': o.uuid,
      'packet_encoding': 'xudp',
      'flow': o.flow,
      'tls': _buildTlsSection(o),
    };

    outbound.removeWhere(
      (key, value) => value == null || (value is String && value.isEmpty),
    );
    return outbound;
  }

  Map<String, dynamic> _buildRouteSection() {
    // TODO: добавить правила для ruMode и пользовательских исключений,
    // когда переедем на rule_set или новые DNS rule'ы.
    final resolverTag =
      _isAndroidPlatform ? _dnsAndroidGoogleUdpTag : _dnsDirectTag;
    return {
      'auto_detect_interface': false,
      'default_domain_resolver': resolverTag,
      'rules': [
        {
          'network': 'udp',
          'port': const [135, 137, 138, 139, 5353],
          'outbound': _blockTag,
        },
        {
          'ip_cidr': const ['224.0.0.0/3', 'ff00::/8'],
          'outbound': _blockTag,
        },
        {
          'source_ip_cidr': const ['224.0.0.0/3', 'ff00::/8'],
          'outbound': _blockTag,
        },
      ],
      'final': _primaryOutboundTag,
    };
  }
}

Map<String, dynamic> _buildTlsSection(VlfOutbound outbound) {
  final tls = <String, dynamic>{'enabled': true};

  if (outbound.sni?.isNotEmpty ?? false) {
    tls['server_name'] = outbound.sni;
  }

  final fingerprint = _normalizeFingerprint(outbound.fingerprint);
  tls['utls'] = {'enabled': true, 'fingerprint': fingerprint};

  if (outbound.security == 'reality' &&
      (outbound.publicKey?.isNotEmpty ?? false)) {
    tls['reality'] = {
      'enabled': true,
      'public_key': outbound.publicKey,
      if (outbound.shortId?.isNotEmpty ?? false) 'short_id': outbound.shortId,
    };
  }

  return tls;
}

String _normalizeFingerprint(String? fingerprint) {
  if (fingerprint == null || fingerprint.isEmpty) {
    return 'chrome';
  }
  final value = fingerprint.toLowerCase();
  if (value == 'random') {
    return 'randomized';
  }
  return value;
}
