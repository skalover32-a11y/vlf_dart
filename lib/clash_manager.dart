import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:vlf_core/vlf_core.dart';
import 'platform/platform_runner.dart';
import 'platform/platform_locator.dart';

/// Менеджер процесса Clash Meta (mihomo) для управления VPN-туннелем.
/// Делегирует платформо-специфичную логику к PlatformRunner.
class ClashManager {
  late final PlatformRunner _runner;
  StreamSubscription<String>? _logSub;
  
  final Logger logger = Logger();

  /// Notifier для состояния работы mihomo (подписывайтесь из UI)
  final ValueNotifier<bool> isRunningNotifier = ValueNotifier<bool>(false);

  ClashManager() {
    _runner = createPlatformRunner();
    // Forward platform runner logs to our logger
    _logSub = _runner.logStream.listen((msg) {
      logger.append(msg);
    });
  }

  bool get isRunning => _runner.isRunning;

  /// Запуск Clash Meta (mihomo) с генерацией конфигурации.
  ///
  /// [profileUrl] — VLESS-подписка (строка vless://, URL или base64)
  /// [baseDir] — рабочая директория
  /// [ruMode] — режим работы (false=GLOBAL, true=RU)
  /// [siteExcl] — список доменов для исключения из VPN
  /// [appExcl] — список процессов для исключения из VPN
  /// [workMode] — режим работы туннеля (TUN или PROXY)
  Future<void> start(
    String profileUrl,
    Directory baseDir, {
    bool ruMode = false,
    List<String> siteExcl = const [],
    List<String> appExcl = const [],
    VlfWorkMode workMode = VlfWorkMode.tun,
  }) async {
    final config = PlatformConfig(
      profileUrl: profileUrl,
      baseDir: baseDir,
      ruMode: ruMode,
      siteExclusions: siteExcl,
      appExclusions: appExcl,
      workMode: workMode,
    );

    try {
      await _runner.start(config);
      isRunningNotifier.value = true;
    } catch (e) {
      isRunningNotifier.value = false;
      rethrow;
    }
  }

  /// Остановка Clash
  Future<void> stop() async {
    await _runner.stop();
    isRunningNotifier.value = false;
  }

  /// Быстрая остановка (для выхода из приложения)
  Future<void> quickStop() async {
    await _runner.quickStop();
    isRunningNotifier.value = false;
  }

  /// Мягкая остановка Clash (алиас для stop)
  Future<void> stopClashGracefully() async {
    await stop();
  }

  /// Освобождение ресурсов
  Future<void> dispose() async {
    await _logSub?.cancel();
    await _runner.dispose();
  }

  /// Получение текущего внешнего IP через системный стек
  /// (используется PowerShell для прохождения через TUN)
  Future<String> updateIp() async {
    if (Platform.isWindows) {
      try {
        final result = await Process.run('powershell', [
          '-NoProfile',
          '-Command',
          r'(Invoke-WebRequest -Uri "https://api.ipify.org?format=text" -UseBasicParsing).Content.Trim()',
        ], runInShell: false).timeout(const Duration(seconds: 10));

        if (result.exitCode == 0) {
          final ip = (result.stdout?.toString() ?? '').trim();
          if (ip.isNotEmpty &&
              !ip.contains('error') &&
              !ip.contains('Exception')) {
            return ip;
          }
        }
      } catch (_) {}
    }

    // Fallback к прямому HttpClient
    try {
      final client = HttpClient();
      try {
        final req = await client.getUrl(
          Uri.parse('https://api.ipify.org?format=text'),
        );
        final resp = await req.close();
        if (resp.statusCode != 200) return '-';
        final ip = await resp.transform(utf8.decoder).join();
        return ip.trim();
      } finally {
        client.close(force: true);
      }
    } catch (_) {
      return '-';
    }
  }

  /// Проверка наличия прав администратора
  Future<bool> isWindowsAdmin() async {
    return await _runner.isElevated();
  }

  /// Перезапуск приложения с правами администратора
  Future<bool> relaunchAsAdmin(List<String> extraArgs) async {
    try {
      await _runner.relaunchElevated();
      return true;
    } catch (_) {
      return false;
    }
  }
}
