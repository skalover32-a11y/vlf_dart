import 'package:flutter_test/flutter_test.dart';
import 'package:vlf_core/vlf_core.dart';

void main() {
  group('buildRoutingRules', () {
    test('GLOBAL режим без исключений', () {
      final rules = buildRoutingRules(
        ruMode: false,
        siteExcl: const [],
        appExcl: const [],
      );

      expect(
        rules,
        equals(const [
          'GEOIP,private,DIRECT-GROUP,no-resolve',
          'MATCH,VLF-PROXY-GROUP',
        ]),
      );
    });

    test('GLOBAL режим с исключениями и дедупликацией', () {
      final rules = buildRoutingRules(
        ruMode: false,
        siteExcl: const [' yandex.ru ', 'vk.com', 'YANDEX.RU'],
        appExcl: const ['chrome.exe', 'Chrome.EXE', 'Telegram.exe'],
      );

      expect(
        rules,
        equals(const [
          'PROCESS-NAME,chrome.exe,DIRECT-GROUP',
          'PROCESS-NAME,Telegram.exe,DIRECT-GROUP',
          'DOMAIN-SUFFIX,yandex.ru,DIRECT-GROUP',
          'DOMAIN-SUFFIX,vk.com,DIRECT-GROUP',
          'GEOIP,private,DIRECT-GROUP,no-resolve',
          'MATCH,VLF-PROXY-GROUP',
        ]),
      );
    });

    test('РФ режим добавляет РФ-блок', () {
      final rules = buildRoutingRules(
        ruMode: true,
        siteExcl: const [],
        appExcl: const [],
      );

      expect(
        rules,
        equals(const [
          'GEOIP,private,DIRECT-GROUP,no-resolve',
          'DOMAIN-SUFFIX,ru,DIRECT-GROUP',
          'DOMAIN-SUFFIX,su,DIRECT-GROUP',
          'DOMAIN-SUFFIX,рф,DIRECT-GROUP',
          'DOMAIN-SUFFIX,2ip.ru,DIRECT-GROUP',
          'GEOIP,RU,DIRECT-GROUP,no-resolve',
          'MATCH,VLF-PROXY-GROUP',
        ]),
      );
    });

    test('РФ режим без дубликатов 2ip.ru при пользовательском исключении', () {
      final rules = buildRoutingRules(
        ruMode: true,
        siteExcl: const ['2ip.ru', 'gosuslugi.ru '],
        appExcl: const ['steam.exe', 'Steam.exe', 'chrome.exe'],
      );

      expect(
        rules,
        equals(const [
          'PROCESS-NAME,steam.exe,DIRECT-GROUP',
          'PROCESS-NAME,chrome.exe,DIRECT-GROUP',
          'DOMAIN-SUFFIX,2ip.ru,DIRECT-GROUP',
          'DOMAIN-SUFFIX,gosuslugi.ru,DIRECT-GROUP',
          'GEOIP,private,DIRECT-GROUP,no-resolve',
          'DOMAIN-SUFFIX,ru,DIRECT-GROUP',
          'DOMAIN-SUFFIX,su,DIRECT-GROUP',
          'DOMAIN-SUFFIX,рф,DIRECT-GROUP',
          'GEOIP,RU,DIRECT-GROUP,no-resolve',
          'MATCH,VLF-PROXY-GROUP',
        ]),
      );
    });
  });
}
