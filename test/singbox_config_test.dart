import 'lib/singbox_config.dart';

Future<void> main() async {
  final builderAndroid = SingboxConfigBuilder(
    vlessUrl:
        'vless://uuid@example.com:443?security=reality&pbk=key&sid=id&sni=example.com',
    ruMode: false,
    siteExclusions: const [],
    appExclusions: const [],
    isAndroid: true,
  );

  final configAndroid = await builderAndroid.toMap();
  assert(configAndroid['dns'] != null, 'DNS block must exist on Android.');

  final servers = configAndroid['dns']['servers'] as List<dynamic>;
  assert(
    servers.any((s) => s['address'] == 'udp://8.8.8.8' && s['detour'] == 'proxy'),
    'Android DNS should include Google with proxy detour.',
  );
  assert(
    configAndroid['dns']['strategy'] == 'prefer_ipv4',
    'Android DNS should prefer IPv4.',
  );

  final builderOther = SingboxConfigBuilder(
    vlessUrl: 'vless://uuid@example.com:443',
    ruMode: false,
    siteExclusions: const [],
    appExclusions: const [],
    isAndroid: false,
  );

  final configOther = await builderOther.toMap();
  assert(!configOther.containsKey('dns'), 'DNS should be Android-only by default.');
}
