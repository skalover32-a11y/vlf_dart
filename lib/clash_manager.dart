import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:vlf_core/vlf_core.dart'
    show
        Logger,
        VlfConnectionStatus,
        VlfWorkMode,
        VlfWorkModeExtension,
        buildRoutingRulesPlan;

import 'platform/platform_locator.dart';
import 'platform/platform_runner.dart';

/// Менеджер процесса Clash Meta (mihomo) для управления VPN-туннелем.
/// API аналогичен SingboxManager для упрощения интеграции.
class ClashManager {
  final Logger logger = Logger();
  final PlatformRunner _runner;
  StreamSubscription<String>? _runnerLogsSub;

  /// Notifier состояния подключения для UI (disconnected/connecting/connected)
  final ValueNotifier<VlfConnectionStatus> connectionStatusNotifier =
      ValueNotifier<VlfConnectionStatus>(VlfConnectionStatus.disconnected);

  /// Backward-compatible bool notifier used across legacy UI pieces
  final ValueNotifier<bool> isRunningNotifier = ValueNotifier<bool>(false);

  bool _awaitingStartupAck = false;

    ClashManager({PlatformRunner? runner})
      : _runner = runner ?? PlatformLocator.runner {
    _runnerLogsSub = _runner.logs.listen(
      (event) {
        logger.append(event);
        _handleLogEvent(event);
      },
      onError: (error, _) {
        logger.append('[Runner] $error\n');
      },
    );
  }

  void _handleLogEvent(String event) {
    final lower = event.toLowerCase();

    // Detect early readiness markers to switch UI immediately.
    if (_awaitingStartupAck && _isStartupReadyLine(lower)) {
      _markConnected();
    }

    if (lower.contains('clash завершился') || lower.contains('остановлен пользователем')) {
      _awaitingStartupAck = false;
      _setStatus(VlfConnectionStatus.disconnected);
    }

    if (_awaitingStartupAck &&
        (lower.contains('fatal') ||
            lower.contains('panic') ||
            lower.contains('cannot') ||
            lower.contains('failed to')) &&
        !lower.contains('failed to resolve')) {
      _awaitingStartupAck = false;
      _setStatus(VlfConnectionStatus.error);
    }
  }

  bool _isStartupReadyLine(String text) {
    return text.contains('запускаю clash meta') ||
        text.contains('clash запущен') ||
        text.contains('start initial configuration') ||
        text.contains('tun adapter listening') ||
        text.contains('start http') ||
        text.contains('start mixed') ||
        text.contains('start tun') ||
        text.contains('tun mode enabled');
  }

  void _setStatus(VlfConnectionStatus status) {
    if (connectionStatusNotifier.value == status) return;
    connectionStatusNotifier.value = status;
    final isConnected = status == VlfConnectionStatus.connected;
    if (isRunningNotifier.value != isConnected) {
      isRunningNotifier.value = isConnected;
    }
  }

  void _markConnected() {
    _awaitingStartupAck = false;
    _setStatus(VlfConnectionStatus.connected);
  }

  /// Запуск Clash Meta (mihomo) с генерацией конфигурации.
  ///
  /// [profileUrl] — VLESS-подписка (строка vless://, URL или base64)
  /// [baseDir] — рабочая директория (где будет config.yaml и откуда запускается mihomo.exe)
  /// [ruMode] — режим работы:
  ///   * false (ГЛОБАЛЬНЫЙ): весь трафик через VPN, кроме локального
  ///   * true (РФ-РЕЖИМ): российский трафик (RU GeoIP) в обход VPN, остальное через VPN
  /// [siteExcl] — список доменов для исключения из VPN (DIRECT)
  /// [appExcl] — список процессов для исключения из VPN (DIRECT)
  /// [workMode] — режим работы туннеля (TUN или PROXY)
  Future<void> start(
    String profileUrl,
    Directory baseDir, {
    bool ruMode = false, // ГЛОБАЛЬНЫЙ режим по умолчанию
    List<String> siteExcl = const [],
    List<String> appExcl = const [],
    VlfWorkMode workMode = VlfWorkMode.tun, // TUN по умолчанию
  }) async {
    final routingPlan = buildRoutingRulesPlan(
      ruMode: ruMode,
      siteExcl: siteExcl,
      appExcl: appExcl,
    );

    final modeLabel = ruMode ? 'RU' : 'GLOBAL';
    final workModeLabel = workMode.displayName;
    logger.append(
      'Clash config mode=$modeLabel/$workModeLabel rules=${routingPlan.rules.length} '
      'apps=${routingPlan.appCount} sites=${routingPlan.domainCount} '
      'ruRules=${routingPlan.ruCount}\n',
    );

    final config = PlatformRunnerConfig(
      profileUrl: profileUrl,
      baseDir: baseDir,
      ruMode: ruMode,
      siteExclusions: List<String>.from(siteExcl),
      appExclusions: List<String>.from(appExcl),
      workMode: workMode,
      routingPlan: routingPlan,
    );

    _awaitingStartupAck = true;
    _setStatus(VlfConnectionStatus.connecting);

    try {
      await _runner.startTunnel(config);
      _markConnected();
    } catch (e) {
      _awaitingStartupAck = false;
      _setStatus(VlfConnectionStatus.error);
      rethrow;
    }
  }

  /// Остановка Clash
  Future<void> stop() async {
    _awaitingStartupAck = false;
    await _runner.stopTunnel();
    _setStatus(VlfConnectionStatus.disconnected);
  }

  /// Освобождение ресурсов (останавливает раннер и закрывает лог-подписки)
  Future<void> dispose() async {
    await _runnerLogsSub?.cancel();
    await _runner.dispose();
    _awaitingStartupAck = false;
    _setStatus(VlfConnectionStatus.disconnected);
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

  /// Проверка наличия прав администратора (Windows)
  Future<bool> isWindowsAdmin() async {
    if (!Platform.isWindows) return Future.value(false);
    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        r"(New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)",
      ]);
      final out = (result.stdout ?? '').toString().toLowerCase();
      return out.contains('true');
    } catch (_) {
      return false;
    }
  }

  /// Перезапуск приложения с правами администратора (Windows)
  Future<bool> relaunchAsAdmin(List<String> extraArgs) async {
    if (!Platform.isWindows) return false;
    try {
      final exe = Platform.resolvedExecutable;
      final argsEscaped = extraArgs
          .map((a) => a.replaceAll('"', '""'))
          .join(' ');
      final ps =
          'Start-Process -FilePath "${exe.replaceAll('"', '""')}" -ArgumentList "$argsEscaped" -Verb RunAs';
      await Process.start('powershell', [
        '-NoProfile',
        '-Command',
        ps,
      ], runInShell: false);
      return true;
    } catch (_) {
      return false;
    }
  }
}

