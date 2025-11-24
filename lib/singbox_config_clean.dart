import 'dart:io';

/// Clean implementation of buildSingboxConfig ported from Python reference.
Future<Map<String, dynamic>> buildSingboxConfig(
  String vlessUrl,
  bool ruMode,
  List<String> siteExcl,
  List<String> appExcl, {
  bool resolveToIp = false,
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
  final fp = qget('fp', '') != '' ? qget('fp', '') : 'chrome';
  final pbk = qget('pbk', '');
  final sid = qget('sid', '');
  final sni = qget('sni', '') != '' ? qget('sni', '') : server;
  final network = qget('type', 'tcp');

  final Map<String, dynamic> tls = {
    'enabled': true,
    'server_name': sni,
    'utls': {'enabled': true, 'fingerprint': fp},
  };
  if (security == 'reality') {
    tls['reality'] = {'enabled': true, 'public_key': pbk, 'short_id': sid};
  }

  final Map<String, dynamic> outboundProxy = {
    'type': 'vless',
    'tag': 'proxy-out',
    'server': server,
    'server_port': port,
    'uuid': uuid,
    'network': network,
    'tls': tls,
  };
  if (flow.isNotEmpty) {
    outboundProxy['flow'] = flow;
  }

  final Map<String, dynamic> outboundDirect = {'type': 'direct', 'tag': 'direct'};

  // DNS server entry in new format (sing-box 1.12+)
  final Map<String, dynamic> dns = {
    'servers': [
      {
        'tag': 'dns-direct',
        'address': 'udp://1.1.1.1',
        'address_strategy': 'prefer_ipv4',
        'detour': 'direct',
      }
    ]
  };

  final Map<String, dynamic> inboundTun = {
    'type': 'tun',
    'tag': 'tun-in',
    'interface_name': 'vlf_tun',
    'mtu': 1500,
    'address': ['172.19.0.1/28'],
    'auto_route': true,
    'strict_route': true,
    'sniff': true,
  };

  final List<Map<String, dynamic>> rules = [];
  rules.add({'action': 'sniff'});
  rules.add({'protocol': 'dns', 'action': 'hijack-dns'});

  try {
    if (server.isNotEmpty) {
      final addrs = await InternetAddress.lookup(server);
      if (addrs.isNotEmpty) {
        final serverIp = addrs.first.address;
        rules.add({'ip_cidr': ['$serverIp/32'], 'outbound': 'direct'});
        if (resolveToIp) {
          outboundProxy['server'] = serverIp;
        }
      }
    }
  } catch (_) {
    // ignore lookup errors
  }

  if (ruMode) {
    rules.add({'domain_suffix': ['ru', 'su', 'рф'], 'outbound': 'direct'});
  }

  if (siteExcl.isNotEmpty) {
    rules.add({'domain': siteExcl, 'outbound': 'direct'});
  }

  for (final name in appExcl) {
    rules.add({'process_name': name, 'outbound': 'direct'});
  }

  final Map<String, dynamic> route = {
    'auto_detect_interface': true,
    'rules': rules,
    'final': 'proxy-out',
  };

  final Map<String, dynamic> config = {
    'log': {'level': 'info', 'timestamp': true},
    'dns': dns,
    'inbounds': [inboundTun],
    'outbounds': [outboundProxy, outboundDirect],
    'route': route,
  };

  return config;
}
