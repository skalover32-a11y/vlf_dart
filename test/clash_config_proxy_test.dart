import 'package:flutter_test/flutter_test.dart';
import 'package:vlf_core/vlf_core.dart';

void main() {
  group('PROXY mode config generation', () {
    const vlessUrl = 'vless://uuid-test@example.com:443?'
        'security=reality&pbk=test-pbk&sid=test-sid&sni=example.com&fp=chrome';

    test('buildClashConfigProxy generates valid YAML without TUN section', () async {
      final config = await buildClashConfigProxy(
        vlessUrl,
        false, // GLOBAL mode
        [],
        [],
      );

      // Verify basic structure
      expect(config, contains('port: 0')); // HTTP port disabled
      expect(config, contains('socks-port: 7891'));
      expect(config, contains('mixed-port: 7890')); // HTTP + SOCKS combined

      // Verify NO TUN section
      expect(config, isNot(contains('tun:')));
      expect(config, isNot(contains('auto-route')));
      expect(config, isNot(contains('dns-hijack')));

      // Verify DNS section exists (same as TUN)
      expect(config, contains('dns:'));
      expect(config, contains('enable: true'));

      // Verify proxy and proxy-groups exist
      expect(config, contains('proxies:'));
      expect(config, contains('proxy-groups:'));
      expect(config, contains('DIRECT-GROUP'));
      expect(config, contains('VLF-PROXY-GROUP'));

      // Verify rules section exists
      expect(config, contains('rules:'));
      expect(config, contains('MATCH,VLF-PROXY-GROUP'));
    });

    test('PROXY mode rules match TUN mode rules', () async {
      final siteExcl = ['example.com', 'test.org'];
      final appExcl = ['chrome.exe', 'firefox.exe'];

      final proxyConfig = await buildClashConfigProxy(
        vlessUrl,
        true, // RU mode
        siteExcl,
        appExcl,
      );

      final tunConfig = await buildClashConfig(
        vlessUrl,
        true, // RU mode
        siteExcl,
        appExcl,
      );

      // Extract rules sections
      final proxyRules = _extractRulesSection(proxyConfig);
      final tunRules = _extractRulesSection(tunConfig);

      // Rules should be identical between modes
      expect(proxyRules, equals(tunRules));

      // Verify specific rules exist
      expect(proxyRules, contains('PROCESS-NAME,chrome.exe,DIRECT-GROUP'));
      expect(proxyRules, contains('PROCESS-NAME,firefox.exe,DIRECT-GROUP'));
      expect(proxyRules, contains('DOMAIN-SUFFIX,example.com,DIRECT-GROUP'));
      expect(proxyRules, contains('DOMAIN-SUFFIX,test.org,DIRECT-GROUP'));
      expect(proxyRules, contains('DOMAIN-SUFFIX,ru,DIRECT-GROUP'));
      expect(proxyRules, contains('GEOIP,RU,DIRECT-GROUP,no-resolve'));
    });

    test('PROXY mode supports RF-mode correctly', () async {
      final configRu = await buildClashConfigProxy(
        vlessUrl,
        true, // RU mode
        [],
        [],
      );

      final configGlobal = await buildClashConfigProxy(
        vlessUrl,
        false, // GLOBAL mode
        [],
        [],
      );

      // RU mode should have RF rules
      expect(configRu, contains('DOMAIN-SUFFIX,ru,DIRECT-GROUP'));
      expect(configRu, contains('DOMAIN-SUFFIX,su,DIRECT-GROUP'));
      expect(configRu, contains('DOMAIN-SUFFIX,рф,DIRECT-GROUP'));
      expect(configRu, contains('GEOIP,RU,DIRECT-GROUP'));

      // GLOBAL mode should NOT have RF rules
      expect(configGlobal, isNot(contains('DOMAIN-SUFFIX,ru,DIRECT-GROUP')));
      expect(configGlobal, isNot(contains('GEOIP,RU,DIRECT-GROUP')));
    });

    test('PROXY mode handles exclusions correctly', () async {
      final config = await buildClashConfigProxy(
        vlessUrl,
        false,
        ['bank.ru', 'gosuslugi.ru'],
        ['telegram.exe'],
      );

      expect(config, contains('PROCESS-NAME,telegram.exe,DIRECT-GROUP'));
      expect(config, contains('DOMAIN-SUFFIX,bank.ru,DIRECT-GROUP'));
      expect(config, contains('DOMAIN-SUFFIX,gosuslugi.ru,DIRECT-GROUP'));
    });

    test('PROXY mode config has correct port values', () async {
      final config = await buildClashConfigProxy(vlessUrl, false, [], []);

      // Verify port configuration
      final lines = config.split('\n');
      var foundMixedPort = false;
      var foundSocksPort = false;
      var foundPort = false;

      for (final line in lines) {
        if (line.startsWith('mixed-port:')) {
          expect(line, contains('7890'));
          foundMixedPort = true;
        }
        if (line.startsWith('socks-port:')) {
          expect(line, contains('7891'));
          foundSocksPort = true;
        }
        if (line.startsWith('port:')) {
          expect(line, contains('0')); // HTTP port should be disabled
          foundPort = true;
        }
      }

      expect(foundMixedPort, isTrue, reason: 'mixed-port not found');
      expect(foundSocksPort, isTrue, reason: 'socks-port not found');
      expect(foundPort, isTrue, reason: 'port not found');
    });
  });

  group('buildRoutingRulesPlan is mode-independent', () {
    test('same rules plan for TUN and PROXY modes', () {
      final plan1 = buildRoutingRulesPlan(
        ruMode: true,
        siteExcl: ['test.com'],
        appExcl: ['app.exe'],
      );

      final plan2 = buildRoutingRulesPlan(
        ruMode: true,
        siteExcl: ['test.com'],
        appExcl: ['app.exe'],
      );

      expect(plan1.rules, equals(plan2.rules));
      expect(plan1.appCount, equals(plan2.appCount));
      expect(plan1.domainCount, equals(plan2.domainCount));
      expect(plan1.ruCount, equals(plan2.ruCount));
    });
  });
}

/// Extract rules section from config YAML (for comparison)
String _extractRulesSection(String config) {
  final lines = config.split('\n');
  final rulesStart = lines.indexWhere((l) => l.trim().startsWith('rules:'));
  if (rulesStart == -1) return '';

  final ruleLines = <String>[];
  for (var i = rulesStart + 1; i < lines.length; i++) {
    final line = lines[i];
    if (line.trim().startsWith('-')) {
      ruleLines.add(line.trim());
    } else if (line.trim().startsWith('#')) {
      // Skip comments
      continue;
    } else if (line.trim().isEmpty) {
      // Skip empty lines
      continue;
    } else {
      // End of rules section
      break;
    }
  }

  return ruleLines.join('\n');
}
