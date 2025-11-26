import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vlf_dart/core/system_proxy.dart';

void main() {
  late List<List<String>> commands;
  late Directory tempDir;
  late File stateFile;

  setUp(() async {
    commands = [];
    tempDir = await Directory.systemTemp.createTemp('sysproxy_win');
    stateFile = File('${tempDir.path}/state');

    SystemProxy.debugReset();
    SystemProxy.debugOverrideStateFile(stateFile);
    SystemProxy.debugOverridePlatform(isWindows: true, isMacOs: false, isLinux: false);
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

  test('enable configures WinINET registry and refreshes', () async {
    await SystemProxy.enableProxy(httpPort: 7890, socksPort: 7891);

    expect(commands, isNotEmpty);
    final key = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';
    expect(commands[0], ['reg', 'add', key, '/v', 'ProxyEnable', '/t', 'REG_DWORD', '/d', '1', '/f']);
    expect(commands[1][0], 'reg');
    expect(commands[2][0], 'reg');
    expect(commands[3], ['RunDll32.exe', 'wininet.dll,InternetSetOption']);
    expect(commands.last[0], anyOf('RunDll32.exe', 'netsh'));
    expect(await stateFile.exists(), isTrue);
  });

  test('disable turns proxy off and clears state', () async {
    await SystemProxy.enableProxy(httpPort: 7890, socksPort: 7891);
    commands.clear();

    await SystemProxy.disableProxy();

    final key = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';
    expect(commands.first, ['reg', 'add', key, '/v', 'ProxyEnable', '/t', 'REG_DWORD', '/d', '0', '/f']);
    expect(commands.any((c) => c.first == 'RunDll32.exe'), isTrue);
    expect(await stateFile.exists(), isFalse);
  });

  test('restoreIfDirty disables leftover proxy', () async {
    await stateFile.writeAsString('active');

    await SystemProxy.restoreIfDirty();

    expect(commands.first.first, 'reg');
    expect(await stateFile.exists(), isFalse);
  });
}
