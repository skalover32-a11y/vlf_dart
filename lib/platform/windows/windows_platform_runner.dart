import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vlf_core/vlf_core.dart'
  show
    Logger,
    RoutingRulesPlan,
    VlfWorkMode,
    VlfWorkModeExtension,
    buildClashConfig,
    buildClashConfigProxy,
    buildRoutingRulesPlan,
    extractVlessFromAny;

import '../platform_runner.dart';

class WindowsPlatformRunner implements PlatformRunner {
  WindowsPlatformRunner();

  final Logger _logger = Logger(maxEntries: 5000);
  Process? _proc;
  StreamSubscription<List<int>>? _stdoutSub;
  StreamSubscription<List<int>>? _stderrSub;
  bool _stopping = false;

  @override
  Stream<String> get logs => _logger.stream;

  @override
  bool get isRunning => _proc != null;

  @override
  Future<void> startTunnel(PlatformRunnerConfig config) async {
    if (_proc != null) {
      throw Exception('Clash уже запущен');
    }
    await _launchWithConfig(config);
  }

  @override
  Future<void> reloadConfig(PlatformRunnerConfig config) async {
    if (!isRunning) {
      await startTunnel(config);
      return;
    }
    await stopTunnel();
    await startTunnel(config);
  }

  @override
  Future<void> stopTunnel() async {
    await _stopClashGracefully();
  }

  @override
  Future<void> dispose() async {
    await stopTunnel();
    _logger.dispose();
  }

  Future<void> _launchWithConfig(PlatformRunnerConfig config) async {
    final vless = await extractVlessFromAny(config.profileUrl);
    _logger.append('VLESS: $vless\n');

    final RoutingRulesPlan plan = config.routingPlan ??
        buildRoutingRulesPlan(
          ruMode: config.ruMode,
          siteExcl: config.siteExclusions,
          appExcl: config.appExclusions,
        );

    final baseDir = config.baseDir;
    final mihomoExe = File('${baseDir.path}${Platform.pathSeparator}mihomo.exe');
    if (!mihomoExe.existsSync()) {
      throw FileSystemException('mihomo.exe не найден', mihomoExe.path);
    }

    final cfgPath = File('${baseDir.path}${Platform.pathSeparator}config.yaml');
    final modeLabel = config.ruMode ? 'RU' : 'GLOBAL';
    final workModeLabel = config.workMode.displayName;
    _logger.append(
      'Clash config mode=$modeLabel/$workModeLabel rules=${plan.rules.length} '
      'apps=${plan.appCount} sites=${plan.domainCount} '
      'ruRules=${plan.ruCount}\n',
    );

    final yamlContent = config.workMode == VlfWorkMode.proxy
        ? await buildClashConfigProxy(
            vless,
            config.ruMode,
            config.siteExclusions,
            config.appExclusions,
            routingPlan: plan,
          )
        : await buildClashConfig(
            vless,
            config.ruMode,
            config.siteExclusions,
            config.appExclusions,
            routingPlan: plan,
          );

    await cfgPath.writeAsString(yamlContent, flush: true);
    _logger.append('config.yaml сгенерирован\n');

    try {
      final debugPath =
          File('${baseDir.path}${Platform.pathSeparator}config_debug.yaml');
      await debugPath.writeAsString(yamlContent, flush: true);
      _logger.append('config_debug.yaml записан для проверки\n');
    } catch (_) {}

    final env = Map<String, String>.from(Platform.environment);

    _proc = await Process.start(
      mihomoExe.path,
      ['-f', cfgPath.path],
      environment: env,
      runInShell: false,
      workingDirectory: baseDir.path,
    );

    _logger.append('Запускаю Clash Meta (mihomo)...\n');

    final stdoutDone = Completer<void>();
    final stderrDone = Completer<void>();
    final startupCompleter = Completer<bool>();
    bool hasSeenOutput = false;
    bool startupError = false;

    _stdoutSub = _proc!.stdout.listen(
      (data) {
        hasSeenOutput = true;
        try {
          final text = utf8.decode(data);
          _logger.append(text);
          if (!startupCompleter.isCompleted) {
            final lower = text.toLowerCase();
            if (lower.contains('start http') ||
                lower.contains('start mixed') ||
                lower.contains('start tun') ||
                lower.contains('tun mode enabled')) {
              startupCompleter.complete(true);
            }
          }
        } catch (_) {
          _logger.append(String.fromCharCodes(data));
        }
      },
      onDone: () {
        if (!stdoutDone.isCompleted) stdoutDone.complete();
      },
    );

    _stderrSub = _proc!.stderr.listen(
      (data) {
        hasSeenOutput = true;
        try {
          final text = utf8.decode(data);
          final lower = text.toLowerCase();
          if (lower.contains('deprecated') || lower.contains('warning:')) {
            _logger.append('[WARN] $text');
          } else {
            _logger.append('[ERR] $text');
          }

          if (!startupCompleter.isCompleted) {
            if (lower.contains('fatal') ||
                lower.contains('panic') ||
                lower.contains('cannot') ||
                lower.contains('failed to')) {
              startupError = true;
              startupCompleter.complete(false);
            }
          }
        } catch (_) {
          _logger.append('[ERR] ${String.fromCharCodes(data)}');
        }
      },
      onDone: () {
        if (!stderrDone.isCompleted) stderrDone.complete();
      },
    );

    unawaited(_monitorProcess(stdoutDone, stderrDone));

    try {
      final result = await Future.any([
        startupCompleter.future,
        Future.delayed(const Duration(seconds: 12), () => null),
      ]);

      if (result is bool) {
        if (result == false) {
          try {
            await stopTunnel();
          } catch (_) {}
          throw Exception('Clash не смог запуститься (ошибка в логах)');
        }
      } else {
        final exited = _proc == null;
        if (exited) {
          throw Exception('Clash завершился сразу после запуска');
        } else {
          if (startupError) {
            try {
              await stopTunnel();
            } catch (_) {}
            throw Exception('Clash сообщил об ошибке при старте');
          }
          if (hasSeenOutput) {
            _logger.append('Clash запущен (подтверждение по активности логов)\n');
          } else {
            _logger.append('Clash запущен (без явной стартовой строки)\n');
          }
        }
      }
    } catch (e) {
      final exited = _proc == null;
      if (exited) {
        throw Exception('Clash завершился сразу после запуска');
      }
      _logger.append('Предупреждение: ошибка при подтверждении запуска: $e\n');
    }
  }

  Future<void> _stopClashGracefully() async {
    final process = _proc;
    if (process == null) return;

    _stopping = true;

    try {
      try {
        process.kill(ProcessSignal.sigint);
      } catch (_) {
        try {
          process.kill(ProcessSignal.sigterm);
        } catch (_) {}
      }

      try {
        await process.exitCode.timeout(const Duration(seconds: 3));
      } on TimeoutException {
        try {
          process.kill(ProcessSignal.sigkill);
        } catch (_) {}
        try {
          await process.exitCode.timeout(const Duration(seconds: 2));
        } catch (_) {}

        if (Platform.isWindows) {
          try {
            await Process.run(
              'taskkill',
              ['/PID', process.pid.toString(), '/T', '/F'],
            ).timeout(const Duration(seconds: 2));
          } catch (_) {}
        }
      }
    } catch (_) {}

    try {
      await _stdoutSub?.cancel();
    } catch (_) {}
    _stdoutSub = null;

    try {
      await _stderrSub?.cancel();
    } catch (_) {}
    _stderrSub = null;

    _proc = null;
    _stopping = false;
    _logger.append('Clash процесс полностью остановлен\n');
  }

  Future<void> _monitorProcess(
    Completer<void> stdoutDone,
    Completer<void> stderrDone,
  ) async {
    final process = _proc;
    if (process == null) return;
    try {
      final rc = await process.exitCode;
      await Future.wait([
        stdoutDone.future.catchError((_) {}),
        stderrDone.future.catchError((_) {}),
      ]).timeout(const Duration(seconds: 5), onTimeout: () => <void>[]);

      if (_stopping) {
        _logger.append('\nClash остановлен пользователем (exitCode=$rc)\n');
      } else {
        _logger.append('\nClash завершился с кодом $rc\n');
      }
    } catch (e) {
      _logger.append('\nClash завершился с ошибкой: $e\n');
    } finally {
      _stopping = false;
      _proc = null;
    }
  }
}
