import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'profile_manager.dart';

/// Builder that produces a sing-box JSON configuration map.
class SingboxConfigBuilder {
  SingboxConfigBuilder({
    required this.vlessUrl,
    required this.ruMode,
    required this.siteExclusions,
    required this.appExclusions,
    this.resolveToIp = false,
    this.outboundTag = 'proxy',
    bool? isAndroid,
  }) : isAndroid = isAndroid ?? Platform.isAndroid;

  final String vlessUrl;
  final bool ruMode;
  final List<String> siteExclusions;
  final List<String> appExclusions;
  final bool resolveToIp;
  final String outboundTag;
  final bool isAndroid;

  factory SingboxConfigBuilder.fromProfile(
    Profile profile, {
    bool ruMode = false,
    List<String> siteExclusions = const [],
    List<String> appExclusions = const [],
    bool resolveToIp = false,
    String outboundTag = 'proxy',
    bool? isAndroid,
  }) {
    return SingboxConfigBuilder(
      vlessUrl: profile.url,
      ruMode: ruMode,
      siteExclusions: siteExclusions,
      appExclusions: appExclusions,
      resolveToIp: resolveToIp,
      outboundTag: outboundTag,
      isAndroid: isAndroid,
    );
  }

  /// Build sing-box config map.
  Future<Map<String, dynamic>> toMap() async {
    final uri = Uri.parse(vlessUrl);
    if (uri.scheme != 'vless') {
      throw ArgumentError('Not a vless:// URL');
    }

    final uuid = uri.userInfo;
    final server = uri.host;
    final port = uri.hasPort ? uri.port : 443;

    final query = uri.queryParameters;
    String qget(String key, [String defaultVal = '']) => query[key] ?? defaultVal;

    final flow = qget('flow');
    final security = qget('security');
    final fp = qget('fp', 'random');
    final pbk = qget('pbk');
    final sid = qget('sid');
    final sniParam = qget('sni');
    final sni = sniParam.isNotEmpty ? sniParam : server;
    final network = qget('type', 'tcp');

    final config = <String, dynamic>{
      'log': {'level': 'info', 'timestamp': true},
      'inbounds': [
        {
          'type': 'tun',
          'tag': 'tun-in',
          'interface_name': 'vlf_tun',
          'mtu': 1500,
          'inet4_address': '172.19.0.1/28',
          'auto_route': true,
          'strict_route': true,
          'sniff': true,
        }
      ],
      'outbounds': [
        _buildProxyOutbound(
          server: server,
          port: port,
          uuid: uuid,
          flow: flow,
          security: security,
          sni: sni,
          fingerprint: fp,
          publicKey: pbk,
          shortId: sid,
          network: network,
        ),
        {'type': 'direct', 'tag': 'direct'},
      ],
      'route': await _buildRoute(server),
    };

    if (isAndroid) {
      config['dns'] = _buildAndroidDnsConfig();
    }

    return config;
  }

  /// Build and save configuration to the default Android path.
  ///
  /// Returns the written file, or null when platform is not Android.
  Future<File?> saveToDefaultLocation() async {
    if (!isAndroid) return null;

    final cfg = await toMap();
    final dir = await getApplicationSupportDirectory();
    final targetDir = Directory(
      '${dir.path}${Platform.pathSeparator}vlf_tunnel',
    );
    await targetDir.create(recursive: true);

    final file = File(
      '${targetDir.path}${Platform.pathSeparator}config_singbox.json',
    );

    final txt = const JsonEncoder.withIndent('  ').convert(cfg);
    await file.writeAsString(txt, flush: true);

    return file;
  }

  Map<String, dynamic> _buildProxyOutbound({
    required String server,
    required int port,
    required String uuid,
    required String flow,
    required String security,
    required String sni,
    required String fingerprint,
    required String publicKey,
    required String shortId,
    required String network,
  }) {
    final outbound = <String, dynamic>{
      'type': 'vless',
      'tag': outboundTag,
      'server': server,
      'server_port': port,
      'uuid': uuid,
      'network': network,
      'tls': {
        'enabled': true,
        'server_name': sni,
        'utls': {'enabled': true, 'fingerprint': fingerprint},
      },
    };

    if (security == 'reality' && publicKey.isNotEmpty) {
      outbound['tls']['reality'] = {
        'enabled': true,
        'public_key': publicKey,
        'short_id': shortId,
      };
    }

    if (flow.isNotEmpty) {
      outbound['flow'] = flow;
    }

    return outbound;
  }

  Future<Map<String, dynamic>> _buildRoute(String server) async {
    final rules = <Map<String, dynamic>>[
      {'action': 'sniff'},
      {'protocol': 'dns', 'action': 'hijack-dns'},
    ];

    if (resolveToIp && server.isNotEmpty) {
      try {
        final addresses = await InternetAddress.lookup(server);
        if (addresses.isNotEmpty) {
          rules.add({
            'ip_cidr': ['${addresses.first.address}/32'],
            'outbound': 'direct',
          });
        }
      } catch (_) {
        // ignore lookup errors
      }
    }

    if (ruMode) {
      rules.add({
        'domain_suffix': ['ru', 'su', 'рф'],
        'outbound': 'direct',
      });
    }

    if (siteExclusions.isNotEmpty) {
      rules.add({'domain': siteExclusions, 'outbound': 'direct'});
    }

    for (final app in appExclusions) {
      rules.add({'process_name': app, 'outbound': 'direct'});
    }

    return {
      'auto_detect_interface': true,
      'override_android_vpn': true,
      'rules': rules,
      'final': outboundTag,
    };
  }

  Map<String, dynamic> _buildAndroidDnsConfig() {
    final servers = _androidDnsServers
        .map((server) => {...server, 'detour': outboundTag})
        .toList();

    return {
      'servers': servers,
      'strategy': 'prefer_ipv4',
    };
  }
}

const _androidDnsServers = [
  {'tag': 'dns-google-udp', 'address': 'udp://8.8.8.8'},
  {'tag': 'dns-cloudflare-udp', 'address': 'udp://1.1.1.1'},
];
