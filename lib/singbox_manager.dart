import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'singbox_config_clean.dart';
import 'subscription_decoder.dart';
import 'logger.dart';
import 'package:flutter/foundation.dart';

class SingboxManager {
  Process? _proc;
  StreamSubscription<List<int>>? _stdoutSub;
  StreamSubscription<List<int>>? _stderrSub;
  final Logger logger = Logger();
  // Notifier для состояния работы sing-box (подписывайтесь из UI)
  final ValueNotifier<bool> isRunningNotifier = ValueNotifier<bool>(false);

  // whether stop was requested by us (so exitCode != 0 is not considered crash)
  bool _stopping = false;

  bool get isRunning => _proc != null;

  Future<void> start(
    String profileUrl,
    Directory baseDir, {
    bool ruMode = true,
    List<String> siteExcl = const [],
    List<String> appExcl = const [],
  }) async {
    // resolve subscription source (vless string, http url, or base64)
    String vless = '';
    try {
      vless = await extractVlessFromAny(profileUrl);
      logger.append('VLESS: $vless\n');
    } catch (e) {
      final msg = 'Ошибка при получении подписки: $e';
      logger.append('$msg\n');
      throw Exception(msg);
    }

    if (_proc != null) {
      throw Exception('sing-box already running');
    }

    final cfgPath = File('${baseDir.path}${Platform.pathSeparator}config.json');
    // ensure sing-box.exe is present before generating config so we can
    // probe its version and choose compatible config fields
    final singBoxExe = File(
      '${baseDir.path}${Platform.pathSeparator}sing-box.exe',
    );
    if (!singBoxExe.existsSync()) {
      throw FileSystemException('sing-box.exe not found', singBoxExe.path);
    }

    final cfg = await buildSingboxConfig(
      vless,
      ruMode,
      siteExcl,
      appExcl,
    );
    // Do not modify `cfg` here — generator `buildSingboxConfig` produces the
    // config in the expected form (matching provided release `config.json`).
    final encoder = const JsonEncoder.withIndent('  ');
    final jsonText = encoder.convert(cfg);
    await cfgPath.writeAsString(jsonText, flush: true);
    logger.append('config.json сгенерирован.\n');

    // write debug copy of generated config for manual inspection
    try {
      final debugFile = File('${baseDir.path}${Platform.pathSeparator}config_debug.json');
      await debugFile.writeAsString(jsonText, flush: true);
      logger.append('config_debug.json записан для проверки.\n');
      // Log the first route rule so we can visually confirm UDP rule is at index 0
      try {
        final route = cfg['route'] as Map<String, dynamic>?;
        final rulesList = route?['rules'] as List<dynamic>?;
        if (rulesList != null && rulesList.isNotEmpty) {
          final first = rulesList[0];
          logger.append('route.rules[0]: ${jsonEncode(first)}\n');
        } else {
          logger.append('route.rules is empty or missing\n');
        }
      } catch (e) {
        logger.append('Не удалось прочитать route.rules[0]: $e\n');
      }
    } catch (_) {}

    // Dump launcher environment and working directory for diagnostics
    try {
      final envDump = StringBuffer();
      envDump.writeln('workingDirectory=${baseDir.path}');
      envDump.writeln('platformExecutable=${Platform.resolvedExecutable}');
      envDump.writeln('environment snapshot:');
      Platform.environment.forEach((k, v) => envDump.writeln('$k=$v'));
      final envFile = File('${baseDir.path}${Platform.pathSeparator}singbox_launcher_env.txt');
      await envFile.writeAsString(envDump.toString(), flush: true);
      logger.append('Launcher environment dumped to ${envFile.path}\n');
    } catch (_) {
      // ignore env dump errors
    }

    // Log outbound target and SNI for easier TLS diagnostics (useful when resolveToIp=true)
    try {
      final out0 = cfg['outbounds'][0] as Map<String, dynamic>;
      final serverVal = out0['server']?.toString() ?? '-';
      final sniVal = (out0['tls'] is Map)
          ? (out0['tls']['server_name']?.toString() ?? '-')
          : '-';
      logger.append('Outbound target: $serverVal, SNI: $sniVal\\n');
    } catch (_) {
      // ignore logging errors
    }
    // singBoxExe already defined above

    final env = Map<String, String>.from(Platform.environment);

    _proc = await Process.start(
      singBoxExe.path,
      ['run', '-c', cfgPath.path],
      environment: env,
      runInShell: false,
      workingDirectory: baseDir.path,
    );
    // отметим, что процесс запущен
    isRunningNotifier.value = true;

    logger.append('Запускаю sing-box...\n');

    // слушаем stdout и stderr и ждём явного подтверждения старта процесса.
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
          logger.append(text);
          // detect successful startup markers
          if (!startupCompleter.isCompleted) {
            final lower = text.toLowerCase();
            if (lower.contains('sing-box started') ||
                lower.contains('tcp server started') ||
                lower.contains('started at')) {
              startupCompleter.complete(true);
            }
          }
        } catch (_) {
          logger.append(String.fromCharCodes(data));
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

          // Determine internal log level if present
          final levelMatch = RegExp(r'\b(info|warn|error|fatal)\b', caseSensitive: false).firstMatch(text);
          String prefix = '[INFO]';
          if (levelMatch != null) {
            final lvl = levelMatch.group(1)?.toLowerCase();
            if (lvl == 'info') prefix = '[INFO]';
            if (lvl == 'warn') prefix = '[WARN]';
            if (lvl == 'error' || lvl == 'fatal') prefix = '[ERR]';
          } else {
            // fallback: if text contains common error tokens
            if (lower.contains('fatal') || lower.contains('error')) prefix = '[ERR]';
          }

          // Suppress specific UDP-related error messages that are noisy and
          // don't affect TCP outbounds in this deployment. Examples:
          // - "UDP is not supported by outbound: proxy-out"
          // - other lines mentioning UDP + "not supported"
          final udpNotSupported = RegExp(r'udp.*not supported|udp is not supported|not supported by outbound', caseSensitive: false);
          if (udpNotSupported.hasMatch(lower)) {
            // drop this message completely
            return;
          }

          // Downgrade specific noisy connection-closed messages to WARN
          if (lower.contains('connection upload closed: raw-read')) {
            prefix = '[WARN]';
          }

          // Treat normal inbound/outbound and dns lines as INFO
          if (lower.contains('inbound/tun') || lower.contains('outbound/direct') || lower.contains(':53') || lower.contains('hijack-dns')) {
            prefix = '[INFO]';
          }

          logger.append('$prefix $text');

          if (!startupCompleter.isCompleted) {
            // Treat explicit fatal/parse/unknown-schema/config errors as startup failure
            if (lower.contains('fatal') ||
                lower.contains('parse') ||
                lower.contains('unknown field') ||
                lower.contains('config error')) {
              startupError = true;
              startupCompleter.complete(false);
            }
          }
        } catch (_) {
          logger.append('[ERR] ${String.fromCharCodes(data)}');
        }
      },
      onDone: () {
        if (!stderrDone.isCompleted) stderrDone.complete();
      },
    );

    // monitor process exit in background
    unawaited(
      Future(() async {
        try {
          final rc = await _proc!.exitCode;
          // wait until both stdout/stderr are done (with timeout)
          await Future.wait([
            stdoutDone.future.catchError((_) {}),
            stderrDone.future.catchError((_) {}),
          ]).timeout(const Duration(seconds: 5), onTimeout: () => <void>[]);
          if (_stopping) {
            logger.append('\nsing-box остановлен пользователем (exitCode=$rc)\n');
          } else {
            logger.append('\nsing-box завершился с кодом $rc\n');
          }
        } catch (e) {
          logger.append('\nsing-box завершился с ошибкой: $e\n');
        } finally {
          _stopping = false;
          _proc = null;
          isRunningNotifier.value = false;
        }
      }),
    );

    // Wait for explicit startup confirmation or timeout. If no explicit
    // failure occurred and the process stays alive for the grace period,
    // treat it as successfully started (this avoids false aborts when
    // only DNS/activity is present).
    try {
      final result = await Future.any([
        startupCompleter.future,
        Future.delayed(const Duration(seconds: 12), () => null),
      ]);

      if (result is bool) {
        if (result == false) {
          // explicit startup failure
          try {
            await stop();
          } catch (_) {}
          throw Exception('sing-box failed to start (startup reported error)');
        }
        // result == true => ok
      } else {
        // timed out waiting for explicit startup line; check state
        final exited = _proc == null;
        if (exited) {
          throw Exception('sing-box exited immediately after start');
        } else {
          if (startupError) {
            try {
              await stop();
            } catch (_) {}
            throw Exception('sing-box reported startup error');
          }
          // Process alive and no startup error detected -> consider started
          if (hasSeenOutput) {
            logger.append('sing-box запущен, подтверждение по активности процесса/логов (без явной стартовой строки)\n');
          } else {
            logger.append('sing-box запущен (подтверждение по специальной строке не получено, логов пока нет)\n');
          }
        }
      }
    } catch (e) {
      final exited = _proc == null;
      if (exited) {
        throw Exception('sing-box exited immediately after start');
      }
      logger.append('Предупреждение: ошибка при подтверждении запуска: $e\n');
    }
  }

  Future<void> stop() async {
    await stopSingBoxGracefully();
  }

  /// Попытка мягко остановить sing-box: сначала SIGINT (или SIGTERM на Windows),
  /// ждать до 3 секунд, затем SIGKILL если не завершился.
  Future<void> stopSingBoxGracefully() async {
    final p = _proc;
    if (p == null) return;

    try {
      // Try SIGINT first; on Windows this might throw, so fallback to SIGTERM.
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
        // didn't exit in time — force kill
        try {
          p.kill(ProcessSignal.sigkill);
        } catch (_) {}
        try {
          await p.exitCode.timeout(const Duration(seconds: 2));
        } catch (_) {}
      }
    } catch (_) {}

    // Ensure subscriptions are cancelled and state cleared
    try {
      await _stdoutSub?.cancel();
    } catch (_) {}
    _stdoutSub = null;
    try {
      await _stderrSub?.cancel();
    } catch (_) {}
    _stderrSub = null;
    _proc = null;
    isRunningNotifier.value = false;
    logger.append('sing-box process fully stopped.\n');
  }

  /// Dispose resources held by manager (alias to stop)
  Future<void> dispose() async {
    await stop();
  }

  Future<String> updateIp() async {
    // Use curl via system stack to ensure traffic goes through TUN interface
    if (Platform.isWindows) {
      try {
        final result = await Process.run(
          'powershell',
          [
            '-NoProfile',
            '-Command',
            r'(Invoke-WebRequest -Uri "https://api.ipify.org?format=text" -UseBasicParsing).Content.Trim()',
          ],
          runInShell: false,
        ).timeout(const Duration(seconds: 10));
        if (result.exitCode == 0) {
          final ip = (result.stdout?.toString() ?? '').trim();
          if (ip.isNotEmpty && !ip.contains('error') && !ip.contains('Exception')) {
            return ip;
          }
        }
      } catch (_) {}
    }
    // Fallback to direct HttpClient (may not use TUN on some platforms)
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

  /// Попытка перезапустить текущий процесс с повышенными правами (Windows).
  /// Возвращает true если команда запуска elevation была отправлена.
  Future<bool> relaunchAsAdmin(List<String> extraArgs) async {
    if (!Platform.isWindows) return false;
    try {
      final exe = Platform.resolvedExecutable;
      // Build PowerShell command to start elevated process
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
