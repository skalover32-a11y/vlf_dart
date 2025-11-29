import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vlf_core/src/singbox_config.dart';
import 'package:vlf_core/src/vlf_models.dart';

void main() {
  group('SingboxConfigBuilder', () {
    test('builds full tun configuration with route metadata', () {
      const runtime = VlfRuntimeConfig(
        outbound: VlfOutbound(
          server: 'server.example.com',
          port: 443,
          uuid: '123e4567-e89b-12d3-a456-426614174000',
          flow: 'xtls-rprx-vision',
          security: 'reality',
          publicKey: 'abcd',
          shortId: 'ef',
          sni: 'server.example.com',
          fingerprint: 'random',
        ),
        mode: VlfWorkMode.tun,
        routes: VlfRouteConfig(
          ruMode: true,
          domainExclusions: ['example.com'],
          appExclusions: ['app.exe'],
        ),
      );

      final builder = SingboxConfigBuilder(runtime);
      final json = builder.toJsonString();
      final map = Map<String, dynamic>.from(jsonDecode(json));

      expect(map['log'], containsPair('level', 'info'));

      final dns = Map<String, dynamic>.from(map['dns'] as Map);
      expect(dns['independent_cache'], isTrue);

      final dnsServers = List<Map<String, dynamic>>.from(
        dns['servers'] as List,
      );
      expect(dnsServers.length, equals(2));
      final directDns = dnsServers
          .firstWhere((server) => server['tag'] == 'dns-direct');
      final localDns = dnsServers
          .firstWhere((server) => server['tag'] == 'dns-local');

      expect(directDns['address'], equals('https://doh.pub/dns-query'));
      expect(directDns['detour'], equals('direct'));
      expect(directDns['address_resolver'], equals('dns-local'));
      expect(localDns['address'], equals('local'));

      final dnsRules = List<Map<String, dynamic>>.from(
        dns['rules'] as List,
      );
      expect(dnsRules.length, 2);
      expect(dnsRules.first['server'], equals('dns-direct'));

      final inbounds = map['inbounds'] as List<dynamic>;
      expect(inbounds, isNotEmpty);
      expect(inbounds.first['type'], equals('tun'));
      expect(inbounds.first['address'], equals(['10.0.0.2/30']));
      expect(inbounds.first.containsKey('inet4_address'), isFalse);
      expect(inbounds.first['platform'], equals('android'));

      final outbounds = map['outbounds'] as List<dynamic>;
      final outboundTags = outbounds
          .map((item) => (item as Map<String, dynamic>)['tag'])
          .whereType<String>()
          .toSet();
      expect(outboundTags.contains('proxy'), isTrue);
      expect(outboundTags.contains('direct'), isTrue);
      expect(outboundTags.contains('bypass'), isTrue);
      expect(outboundTags.contains('block'), isTrue);

      final primaryOutbound =
          outbounds.firstWhere(
                (item) =>
            (item as Map<String, dynamic>)['tag'] == 'proxy',
              )
              as Map<String, dynamic>;
      final tls = primaryOutbound['tls'] as Map<String, dynamic>;
      final utls = tls['utls'] as Map<String, dynamic>;
      expect(utls['fingerprint'], equals('randomized'));

      final route = map['route'] as Map<String, dynamic>;
      expect(route['final'], equals('proxy'));
      expect(route['auto_detect_interface'], isFalse);
      expect(route['default_domain_resolver'], equals('dns-direct'));

      final rules = route['rules'] as List<dynamic>;
      expect(rules.length, 3);
      final udpRule = rules.firstWhere(
        (rule) => (rule as Map<String, dynamic>)['network'] == 'udp',
      ) as Map<String, dynamic>;
      expect(udpRule['outbound'], equals('block'));
      expect(udpRule['port'], contains(5353));

      expect(json.contains('"geoip"'), isFalse);
    });
  });
}
