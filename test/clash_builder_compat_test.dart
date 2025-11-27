import 'package:flutter_test/flutter_test.dart';
import 'package:vlf_core/src/vlf_models.dart' as core;
import 'package:vlf_core/src/clash_builder.dart';
import 'package:vlf_core/src/clash_config.dart' as legacy;

void main() {
  test('ClashConfigBuilder produces identical YAML to legacy for TUN', () async {
    final outbound = core.VlfOutbound(
      server: 'example.com',
      port: 443,
      uuid: '00000000-0000-0000-0000-000000000000',
      security: 'reality',
      publicKey: 'pubkey',
      shortId: 'sid',
      fingerprint: 'random',
      sni: 'example.com',
    );
    final runtime = core.VlfRuntimeConfig(
      outbound: outbound,
      mode: core.VlfWorkMode.tun,
      routes: const core.VlfRouteConfig(
        ruMode: true,
        domainExclusions: ['2ip.ru', 'yandex.ru'],
        appExclusions: ['browser.exe'],
      ),
    );

    final builder = ClashConfigBuilder(runtime);
    final yamlNew = await builder.buildYaml();

    final yamlLegacy = await legacy.buildClashConfig(
      outbound.toVlessUrl(),
      runtime.routes.ruMode,
      runtime.routes.domainExclusions,
      runtime.routes.appExclusions,
    );

    expect(yamlNew, equals(yamlLegacy));
  });

  test('ClashConfigBuilder produces identical YAML to legacy for PROXY', () async {
    final outbound = core.VlfOutbound(
      server: 'example.org',
      port: 443,
      uuid: '11111111-1111-1111-1111-111111111111',
      fingerprint: 'random',
      sni: 'example.org',
    );
    final runtime = core.VlfRuntimeConfig(
      outbound: outbound,
      mode: core.VlfWorkMode.proxy,
      routes: const core.VlfRouteConfig(
        ruMode: false,
        domainExclusions: [],
        appExclusions: [],
      ),
    );

    final builder = ClashConfigBuilder(runtime);
    final yamlNew = await builder.buildYaml();

    final yamlLegacy = await legacy.buildClashConfigProxy(
      outbound.toVlessUrl(),
      runtime.routes.ruMode,
      runtime.routes.domainExclusions,
      runtime.routes.appExclusions,
    );

    expect(yamlNew, equals(yamlLegacy));
  });
}
