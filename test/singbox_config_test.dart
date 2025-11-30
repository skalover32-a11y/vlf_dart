import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vlf_core/src/singbox_config.dart';
import 'package:vlf_core/src/vlf_models.dart';

void main() {
  group('SingboxConfigBuilder', () {
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

    test('non-Android keeps default DoH without doh.pub', () {
      final builder = SingboxConfigBuilder(
        runtime,
        platformOverrideIsAndroid: false,
      );
      final map = Map<String, dynamic>.from(
        jsonDecode(builder.toJsonString()) as Map,
      );

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

      expect(directDns['address'], equals('https://dns.google/dns-query'));
      expect(localDns['address'], equals('local'));

      final dnsRules = List<Map<String, dynamic>>.from(
        dns['rules'] as List,
      );
      expect(dnsRules.length, 2);
      expect(dnsRules.first['server'], equals('dns-direct'));

      final route = Map<String, dynamic>.from(map['route'] as Map);
      expect(route['default_domain_resolver'], equals('dns-direct'));

      expect(builder.toJsonString().contains('dns.google'), isTrue);
      expect(builder.toJsonString().contains('doh.pub'), isFalse);
    });

    test('Android builds UDP DNS block with fakeip', () {
      final builder = SingboxConfigBuilder(
        runtime,
        platformOverrideIsAndroid: true,
      );
      final map = Map<String, dynamic>.from(
        jsonDecode(builder.toJsonString()) as Map,
      );

      final dns = Map<String, dynamic>.from(map['dns'] as Map);
      final servers = List<Map<String, dynamic>>.from(
        dns['servers'] as List,
      );

      expect(dns['strategy'], equals('prefer_ipv4'));
      final fakeIp = Map<String, dynamic>.from(dns['fakeip'] as Map);
      expect(fakeIp['enabled'], isTrue);
      expect(fakeIp['inet4_range'], equals('198.18.0.0/15'));
      expect(fakeIp['inet6_range'], equals('fc00::/18'));

      expect(servers.length, equals(2));
      final serverTags = servers.map((e) => e['tag']).toSet();
      expect(serverTags.contains('dns-google-udp'), isTrue);
      expect(serverTags.contains('dns-cloudflare-udp'), isTrue);
      for (final server in servers) {
        expect(server['address'], anyOf('udp://8.8.8.8', 'udp://1.1.1.1'));
        expect(server['detour'], equals('proxy'));
      }

      expect(dns['final'], equals('dns-google-udp'));

      final route = Map<String, dynamic>.from(map['route'] as Map);
      expect(route['default_domain_resolver'], equals('dns-google-udp'));
      expect(builder.toJsonString().contains('udp://'), isTrue);
      expect(builder.toJsonString().contains('doh.pub'), isFalse);
    });
  });
}
