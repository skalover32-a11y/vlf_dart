import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vlf_dart/core/system_proxy.dart';

void main() {
  late List<List<String>> commands;
  late Directory tempDir;
  late File stateFile;

  setUp(() async {
    commands = [];
    tempDir = await Directory.systemTemp.createTemp('sysproxy_linux');
    stateFile = File('${tempDir.path}/state');

    SystemProxy.debugReset();
    SystemProxy.debugOverrideStateFile(stateFile);
    SystemProxy.debugOverridePlatform(isWindows: false, isMacOs: false, isLinux: true);
    SystemProxy.debugOverrideCommandRunner((exe, args) async {
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

  test('enable configures GNOME proxy schema', () async {
    await SystemProxy.enableProxy(httpPort: 7890, socksPort: 7891);

    expect(commands.map((c) => c.join(' ')).toList(), contains('gsettings set org.gnome.system.proxy mode manual'));
    expect(commands.any((c) => c.contains('org.gnome.system.proxy.http')), isTrue);
    expect(commands.any((c) => c.contains('org.gnome.system.proxy.socks')), isTrue);
    expect(await stateFile.exists(), isTrue);
  });

  test('disable resets GNOME proxy mode', () async {
    await SystemProxy.enableProxy(httpPort: 7890, socksPort: 7891);
    commands.clear();

    await SystemProxy.disableProxy();

    expect(commands.single, ['gsettings', 'set', 'org.gnome.system.proxy', 'mode', 'none']);
    expect(await stateFile.exists(), isFalse);
  });
}
