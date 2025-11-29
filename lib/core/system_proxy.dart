import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

typedef _CommandRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

class _PlatformProbe {
  final bool isWindows;
  final bool isMacOs;
  final bool isLinux;

  _PlatformProbe()
    : isWindows = Platform.isWindows,
      isMacOs = Platform.isMacOS,
      isLinux = Platform.isLinux;

  _PlatformProbe.custom({
    required this.isWindows,
    required this.isMacOs,
    required this.isLinux,
  });
}

/// Controls host OS proxy settings when the app works in PROXY mode.
class SystemProxy {
  static _CommandRunner _runner = _defaultRunner;
  static _PlatformProbe _platform = _PlatformProbe();
  static File? _stateFileOverride;
  static bool _isProxyEnabled = false;

  static File get _stateFile {
    if (_stateFileOverride != null) {
      return _stateFileOverride!;
    }
    final sep = Platform.pathSeparator;
    return File('${Directory.current.path}$sep.system_proxy_state');
  }

  static Future<void> enableProxy({
    required int httpPort,
    required int socksPort,
  }) async {
    if (_isProxyEnabled) return;

    if (_platform.isWindows) {
      await _enableWindows(httpPort, socksPort);
    } else if (_platform.isMacOs) {
      await _enableMac(httpPort, socksPort);
    } else if (_platform.isLinux) {
      await _enableLinux(httpPort, socksPort);
    } else {
      debugPrint('System proxy enable skipped: unsupported platform');
      return;
    }

    _isProxyEnabled = true;
    try {
      await _stateFile.writeAsString('active');
    } catch (_) {}
  }

  static Future<void> disableProxy() async {
    final stateExists = await _stateFile.exists();
    if (!_isProxyEnabled && !stateExists) {
      return;
    }

    if (_platform.isWindows) {
      await _disableWindows();
    } else if (_platform.isMacOs) {
      await _disableMac();
    } else if (_platform.isLinux) {
      await _disableLinux();
    } else {
      return;
    }

    _isProxyEnabled = false;
    try {
      if (await _stateFile.exists()) {
        await _stateFile.delete();
      }
    } catch (_) {}
  }

  static Future<void> restoreIfDirty() async {
    if (!await _stateFile.exists()) {
      return;
    }
    _isProxyEnabled = true;
    await disableProxy();
  }

  static Future<void> _enableWindows(int httpPort, int socksPort) async {
    const key =
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';
    await _run('reg', [
      'add',
      key,
      '/v',
      'ProxyEnable',
      '/t',
      'REG_DWORD',
      '/d',
      '1',
      '/f',
    ]);

    final proxyHost = '127.0.0.1:$httpPort';
    await _run('reg', [
      'add',
      key,
      '/v',
      'ProxyServer',
      '/t',
      'REG_SZ',
      '/d',
      proxyHost,
      '/f',
    ]);

    await _runOptional('reg', [
      'add',
      key,
      '/v',
      'ProxyHttp1.1',
      '/t',
      'REG_DWORD',
      '/d',
      '1',
      '/f',
    ]);

    await _run('reg', [
      'add',
      key,
      '/v',
      'ProxyOverride',
      '/t',
      'REG_SZ',
      '/d',
      '<local>;localhost;127.0.0.1',
      '/f',
    ]);

    await _run('RunDll32.exe', ['wininet.dll,InternetSetOption']);

    final netshServer =
        'proxy-server="http=$proxyHost;https=$proxyHost;socks=127.0.0.1:$socksPort"';
    const bypass = 'bypass-list="localhost;127.0.0.1"';
    await _runOptional('netsh', [
      'winhttp',
      'set',
      'proxy',
      netshServer,
      bypass,
    ]);
  }

  static Future<void> _disableWindows() async {
    const key =
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';
    await _run('reg', [
      'add',
      key,
      '/v',
      'ProxyEnable',
      '/t',
      'REG_DWORD',
      '/d',
      '0',
      '/f',
    ]);

    await _run('reg', [
      'add',
      key,
      '/v',
      'ProxyServer',
      '/t',
      'REG_SZ',
      '/d',
      '',
      '/f',
    ]);

    await _run('RunDll32.exe', ['wininet.dll,InternetSetOption']);
    await _runOptional('netsh', ['winhttp', 'reset', 'proxy']);
  }

  static Future<void> _enableMac(int httpPort, int socksPort) async {
    final services = await _macServices();
    if (services.isEmpty) {
      debugPrint('No macOS network services found for proxy setup');
      return;
    }

    for (final service in services) {
      await _run('networksetup', [
        '-setwebproxy',
        service,
        '127.0.0.1',
        '$httpPort',
      ]);
      await _run('networksetup', [
        '-setsecurewebproxy',
        service,
        '127.0.0.1',
        '$httpPort',
      ]);
      await _run('networksetup', [
        '-setproxybypassdomains',
        service,
        'localhost',
        '127.0.0.1',
      ]);
      await _run('networksetup', ['-setwebproxystate', service, 'on']);
      await _run('networksetup', ['-setsecurewebproxystate', service, 'on']);
      await _runOptional('networksetup', [
        '-setsocksfirewallproxy',
        service,
        '127.0.0.1',
        '$socksPort',
      ]);
      await _runOptional('networksetup', [
        '-setsocksfirewallproxystate',
        service,
        'on',
      ]);
    }
  }

  static Future<void> _disableMac() async {
    final services = await _macServices();
    if (services.isEmpty) return;
    for (final service in services) {
      await _run('networksetup', ['-setwebproxystate', service, 'off']);
      await _run('networksetup', ['-setsecurewebproxystate', service, 'off']);
      await _runOptional('networksetup', [
        '-setsocksfirewallproxystate',
        service,
        'off',
      ]);
    }
  }

  static Future<List<String>> _macServices() async {
    try {
      final result = await _runner('networksetup', ['-listallnetworkservices']);
      if (result.exitCode != 0) return const ['Wi-Fi'];
      final lines = result.stdout.toString().split(RegExp(r'\r?\n'));
      final services = lines
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !l.startsWith('*'))
          .toList();
      return services.isEmpty ? const ['Wi-Fi'] : services;
    } catch (_) {
      return const ['Wi-Fi'];
    }
  }

  static Future<void> _enableLinux(int httpPort, int socksPort) async {
    await _runOptional('gsettings', [
      'set',
      'org.gnome.system.proxy',
      'mode',
      'manual',
    ]);
    await _runOptional('gsettings', [
      'set',
      'org.gnome.system.proxy.http',
      'host',
      '127.0.0.1',
    ]);
    await _runOptional('gsettings', [
      'set',
      'org.gnome.system.proxy.http',
      'port',
      '$httpPort',
    ]);
    await _runOptional('gsettings', [
      'set',
      'org.gnome.system.proxy.https',
      'host',
      '127.0.0.1',
    ]);
    await _runOptional('gsettings', [
      'set',
      'org.gnome.system.proxy.https',
      'port',
      '$httpPort',
    ]);
    await _runOptional('gsettings', [
      'set',
      'org.gnome.system.proxy.socks',
      'host',
      '127.0.0.1',
    ]);
    await _runOptional('gsettings', [
      'set',
      'org.gnome.system.proxy.socks',
      'port',
      '$socksPort',
    ]);
    await _runOptional('gsettings', [
      'set',
      'org.gnome.system.proxy',
      'ignore-hosts',
      "['localhost', '127.0.0.1']",
    ]);
  }

  static Future<void> _disableLinux() async {
    await _runOptional('gsettings', [
      'set',
      'org.gnome.system.proxy',
      'mode',
      'none',
    ]);
  }

  static Future<void> _run(String executable, List<String> args) async {
    final result = await _runner(executable, args);
    if (result.exitCode != 0) {
      throw ProcessException(
        executable,
        args,
        result.stderr?.toString() ?? '',
        result.exitCode,
      );
    }
  }

  static Future<void> _runOptional(String executable, List<String> args) async {
    final result = await _runner(executable, args);
    if (result.exitCode != 0) {
      debugPrint(
        'Optional proxy command failed: $executable ${args.join(' ')} (exit ${result.exitCode})',
      );
    }
  }

  static Future<ProcessResult> _defaultRunner(
    String executable,
    List<String> arguments,
  ) {
    return Process.run(executable, arguments);
  }

  @visibleForTesting
  static void debugOverrideCommandRunner(_CommandRunner? runner) {
    _runner = runner ?? _defaultRunner;
  }

  @visibleForTesting
  static void debugOverridePlatform({
    bool? isWindows,
    bool? isMacOs,
    bool? isLinux,
  }) {
    if (isWindows == null && isMacOs == null && isLinux == null) {
      _platform = _PlatformProbe();
      return;
    }
    _platform = _PlatformProbe.custom(
      isWindows: isWindows ?? Platform.isWindows,
      isMacOs: isMacOs ?? Platform.isMacOS,
      isLinux: isLinux ?? Platform.isLinux,
    );
  }

  @visibleForTesting
  static void debugOverrideStateFile(File? file) {
    _stateFileOverride = file;
  }

  @visibleForTesting
  static void debugReset() {
    _runner = _defaultRunner;
    _platform = _PlatformProbe();
    _stateFileOverride = null;
    _isProxyEnabled = false;
  }
}
