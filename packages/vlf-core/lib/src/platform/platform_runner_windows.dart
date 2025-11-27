part of 'platform_runner.dart';

class PlatformRunnerWindows implements PlatformRunner {
  PlatformRunnerWindows();

  final Logger _logger = Logger(maxEntries: 5000);
  Process? _proc;
  StreamSubscription<List<int>>? _stdoutSub;
  StreamSubscription<List<int>>? _stderrSub;
  bool _stopping = false;

  @override
  Stream<String> get logs => _logger.stream;

  @override
  Future<bool> get isRunning async => _proc != null;

  @override
  Future<void> start(VlfConfig config) async {
    if (_proc != null) {
      throw Exception('Clash уже запущен');
    }

    final vless = await extractVlessFromAny(config.profileUrl);
    _logger.append('VLESS: $vless\n');

    final plan = config.routingPlan ??
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
      final debugFile = File(
        '${baseDir.path}${Platform.pathSeparator}config_debug.yaml',
      );
      await debugFile.writeAsString(yamlContent, flush: true);
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
            await stop();
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
              await stop();
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

  @override
  Future<void> stop() async {
    await _stopClashGracefully();
  }

  Future<void> _stopClashGracefully() async {
    final p = _proc;
    if (p == null) return;

    _stopping = true;

    try {
      try {
        p.kill(ProcessSignal.sigint);
      } catch (_) {
        try {
          p.kill(ProcessSignal.sigterm);
        } catch (_) {}
      }

      try {
        await p.exitCode.timeout(const Duration(seconds: 3));
      } on TimeoutException {
        try {
          p.kill(ProcessSignal.sigkill);
        } catch (_) {}
        try {
          await p.exitCode.timeout(const Duration(seconds: 2));
        } catch (_) {}

        if (Platform.isWindows) {
          try {
            await Process.run('taskkill', ['/PID', p.pid.toString(), '/T', '/F'])
                .timeout(const Duration(seconds: 2));
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
    try {
      final rc = await _proc!.exitCode;
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

  @override
  Future<void> restart(VlfConfig config) async {
    await stop();
    await start(config);
  }

  @override
  Future<void> dispose() async {
    await stop();
    _logger.dispose();
  }
}