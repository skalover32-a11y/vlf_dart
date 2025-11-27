import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vlf_tunnel/core/system_proxy.dart';

void main() {
  late List<List<String>> commands;
  late Directory tempDir;
  late File stateFile;

  setUp(() async {
    commands = [];
    tempDir = await Directory.systemTemp.createTemp('sysproxy_mac');
    stateFile = File('${tempDir.path}/state');

    SystemProxy.debugReset();
    SystemProxy.debugOverrideStateFile(stateFile);
    SystemProxy.debugOverridePlatform(isWindows: false, isMacOs: true, isLinux: false);
    SystemProxy.debugOverrideCommandRunner((exe, args) async {
      if (exe == 'networksetup' && args.length == 1 && args.first == '-listallnetworkservices') {
        return ProcessResult(0, 0, 'Ethernet\nWi-Fi\n', '');
      }
      commands.add([exe, ...args]);
      return ProcessResult(0, 0, '', '');
    });
  });

  tearDown(() async {
    SystemProxy.debugReset();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('enable applies proxy settings to available services', () async {
    await SystemProxy.enableProxy(httpPort: 7890, socksPort: 7891);

    expect(commands.length, equals(14)); // 7 commands per service * 2 services
    expect(commands.first, ['networksetup', '-setwebproxy', 'Ethernet', '127.0.0.1', '7890']);
    expect(commands[7], ['networksetup', '-setwebproxy', 'Wi-Fi', '127.0.0.1', '7890']);
    expect(await stateFile.exists(), isTrue);
  });

  test('disable turns proxies off for all services', () async {
    await SystemProxy.enableProxy(httpPort: 7890, socksPort: 7891);
    commands.clear();

    await SystemProxy.disableProxy();

    expect(commands.where((c) => c.contains('off')).length, equals(6));
    expect(commands.first, ['networksetup', '-setwebproxystate', 'Ethernet', 'off']);
    expect(
      commands.last,
      ['networksetup', '-setsocksfirewallproxystate', 'Wi-Fi', 'off'],
    );
    expect(await stateFile.exists(), isFalse);
  });
}
