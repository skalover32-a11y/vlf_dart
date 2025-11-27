import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vlf_core/vlf_core.dart';
import 'platform_runner.dart';

/// Windows implementation using mihomo.exe subprocess
class WindowsPlatformRunner implements PlatformRunner {
  Process? _proc;
  StreamSubscription<List<int>>? _stdoutSub;
  StreamSubscription<List<int>>? _stderrSub;
  
  final Logger _logger = Logger();
  bool _stopping = false;

  @override
  Stream<String> get logStream => _logger.stream;

  @override
  bool get isRunning => _proc != null;

  @override
  Future<void> start(PlatformConfig config) async {
    // 1. Extract VLESS from subscription
    String vless = '';
    try {
      vless = await extractVlessFromAny(config.profileUrl);
      _logger.append('VLESS: $vless\n');
    } catch (e) {
      final msg = 'Ошибка при получении подписки: $e';
      _logger.append('$msg\n');
      throw Exception(msg);
    }

    if (_proc != null) {
      throw Exception('Clash уже запущен');
    }

    // 2. Check mihomo.exe exists
    final mihomoExe = File(
      '${config.baseDir.path}${Platform.pathSeparator}mihomo.exe',
    );
    if (!mihomoExe.existsSync()) {
      throw FileSystemException('mihomo.exe не найден', mihomoExe.path);
    }

    // 3. Generate config.yaml
    final cfgPath = File(
      '${config.baseDir.path}${Platform.pathSeparator}config.yaml',
    );
    final routingPlan = buildRoutingRulesPlan(
      ruMode: config.ruMode,
      siteExcl: config.siteExclusions,
      appExcl: config.appExclusions,
    );

    final modeLabel = config.ruMode ? 'RU' : 'GLOBAL';
    final workModeLabel = config.workMode.displayName;
    _logger.append(
      'Clash config mode=$modeLabel/$workModeLabel rules=${routingPlan.rules.length} '
      'apps=${routingPlan.appCount} sites=${routingPlan.domainCount} '
      'ruRules=${routingPlan.ruCount}\n',
    );

    // Generate config based on work mode
    final yamlContent = config.workMode == VlfWorkMode.proxy
        ? await buildClashConfigProxy(
            vless,
            config.ruMode,
            config.siteExclusions,
            config.appExclusions,
            routingPlan: routingPlan,
          )
        : await buildClashConfig(
            vless,
            config.ruMode,
            config.siteExclusions,
            config.appExclusions,
            routingPlan: routingPlan,
          );

    await cfgPath.writeAsString(yamlContent, flush: true);
    _logger.append('config.yaml сгенерирован\n');

    // Debug copy
    try {
      final debugFile = File(
        '${config.baseDir.path}${Platform.pathSeparator}config_debug.yaml',
      );
      await debugFile.writeAsString(yamlContent, flush: true);
      _logger.append('config_debug.yaml записан для проверки\n');
    } catch (_) {}

    // 4. Start mihomo.exe
    final env = Map<String, String>.from(Platform.environment);

    _proc = await Process.start(
      mihomoExe.path,
      ['-f', cfgPath.path],
      environment: env,
      runInShell: false,
      workingDirectory: config.baseDir.path,
    );

    _logger.append('Запускаю Clash Meta (mihomo)...\n');

    // 5. Listen to stdout and stderr
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

    // 6. Monitor process exit in background
    unawaited(
      Future(() async {
        try {
          final rc = await _proc!.exitCode;
          await Future.wait([
            stdoutDone.future.catchError((_) {}),
            stderrDone.future.catchError((_) {}),
          ]).timeout(const Duration(seconds: 5), onTimeout: () => <void>[]);

          if (_stopping) {
            _logger.append('\nClash остановлен пользователем (exitCode=$rc)\n');
          } else {
            _logger.append('\n[!] Clash завершился неожиданно (exitCode=$rc)\n');
          }
        } catch (e) {
          if (!_stopping) {
            _logger.append('\n[ERR] Ошибка мониторинга процесса: $e\n');
          }
        } finally {
          _proc = null;
          await _stdoutSub?.cancel();
          await _stderrSub?.cancel();
          _stdoutSub = null;
          _stderrSub = null;
        }
      }),
    );

    // 7. Wait for startup confirmation
    final timeout = Duration(seconds: config.workMode == VlfWorkMode.proxy ? 5 : 12);
    bool started = false;

    try {
      started = await startupCompleter.future.timeout(
        timeout,
        onTimeout: () {
          if (!hasSeenOutput) {
            return false;
          }
          return !startupError;
        },
      );
    } catch (_) {
      started = false;
    }

    if (!started) {
      await stop();
      throw Exception('Clash не запустился в течение $timeout');
    }

    _logger.append('Clash Meta успешно запущен!\n');
  }

  @override
  Future<void> stop() async {
    if (_proc == null) return;

    _logger.append('Останавливаю Clash...\n');
    _stopping = true;

    try {
      _proc!.kill(ProcessSignal.sigint);
      await _proc!.exitCode.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          _logger.append('Принудительная остановка Clash...\n');
          _proc?.kill(ProcessSignal.sigkill);
          return _proc?.exitCode ?? -1;
        },
      );
    } catch (e) {
      _logger.append('Ошибка при остановке: $e\n');
      _proc?.kill(ProcessSignal.sigkill);
    }

    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
    _proc = null;
    _stopping = false;

    _logger.append('Clash остановлен\n');
  }

  @override
  Future<void> quickStop() async {
    if (_proc == null) return;
    
    _stopping = true;
    try {
      _proc?.kill(ProcessSignal.sigkill);
      await _stdoutSub?.cancel();
      await _stderrSub?.cancel();
    } catch (_) {}
    
    _stdoutSub = null;
    _stderrSub = null;
    _proc = null;
  }

  @override
  Future<bool> isElevated() async {
    if (!Platform.isWindows) return false;
    
    try {
      final result = await Process.run(
        'powershell',
        ['-Command', '[bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))'],
      );
      return result.stdout.toString().trim().toLowerCase() == 'true';
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> relaunchElevated() async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Elevation only supported on Windows');
    }

    try {
      final exePath = Platform.resolvedExecutable;
      await Process.start(
        'powershell',
        [
          '-Command',
          'Start-Process',
          '-FilePath',
          '"$exePath"',
          '-Verb',
          'RunAs',
        ],
        runInShell: true,
      );
      exit(0);
    } catch (e) {
      _logger.append('Ошибка при перезапуске с правами администратора: $e\n');
      rethrow;
    }
  }

  @override
  Future<void> dispose() async {
    await stop();
    _logger.dispose();
  }
}
