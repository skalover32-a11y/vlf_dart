import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'singbox_config.dart';
import 'subscription_decoder.dart';
import 'logger.dart';
import 'package:flutter/foundation.dart';

class SingboxManager {
  Process? _proc;
  StreamSubscription<List<int>>? _stdoutSub;
  final Logger logger = Logger();
  // Notifier для состояния работы sing-box (подписывайтесь из UI)
  final ValueNotifier<bool> isRunningNotifier = ValueNotifier<bool>(false);

  bool get isRunning => _proc != null;

  Future<void> start(
    String profileUrl,
    Directory baseDir, {
    bool ruMode = true,
    List<String> siteExcl = const [],
    List<String> appExcl = const [],
  }) async {
    // download subscription (with graceful error handling and logging)
    final uri = Uri.parse(profileUrl);
    final client = HttpClient();
    List<int> subBytes = [];
    String vless = '';
    try {
      try {
        final req = await client.getUrl(uri);
        final resp = await req.close();
        if (resp.statusCode != 200) {
          final msg = 'Не удалось загрузить подписку: HTTP ${resp.statusCode}';
          logger.append('$msg\n');
          throw Exception(msg);
        }
        subBytes = await resp.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
      } on SocketException catch (e) {
        final msg = 'Ошибка сети при загрузке подписки: ${e.message}';
        logger.append('$msg\n');
        throw Exception(msg);
      } on HttpException catch (e) {
        final msg = 'Ошибка HTTP при загрузке подписки: ${e.message}';
        logger.append('$msg\n');
        throw Exception(msg);
      } catch (e) {
        final msg = 'Ошибка при загрузке подписки: $e';
        logger.append('$msg\n');
        throw Exception(msg);
      }

      vless = decodeSubscriptionToVlessFromBytes(subBytes);
      logger.append('VLESS: $vless\n');
    } finally {
      client.close(force: true);
    }

    final cfg = await buildSingboxConfig(vless, ruMode, siteExcl, appExcl);

    final cfgPath = File('${baseDir.path}${Platform.pathSeparator}config.json');
    final encoder = const JsonEncoder.withIndent('  ');
    await cfgPath.writeAsString(encoder.convert(cfg), flush: true);
    logger.append('config.json сгенерирован.\n');

    final singBoxExe = File('${baseDir.path}${Platform.pathSeparator}sing-box.exe');
    if (!singBoxExe.existsSync()) {
      throw FileSystemException('sing-box.exe not found', singBoxExe.path);
    }

    final env = Map<String, String>.from(Platform.environment);
    env['ENABLE_DEPRECATED_TUN_ADDRESS_X'] = 'true';
    env['ENABLE_DEPRECATED_DNS_SERVER_FORMAT'] = 'true';
    env['ENABLE_DEPRECATED_SPECIAL_OUTBOUNDS'] = 'true';

    _proc = await Process.start(
      singBoxExe.path,
      ['run', '-c', cfgPath.path],
      environment: env,
      runInShell: false,
    );
    // отметим, что процесс запущен
    isRunningNotifier.value = true;

    logger.append('Запускаю sing-box...\n');

    // слушаем stdout
    _stdoutSub = _proc!.stdout.listen((data) {
      try {
        logger.append(utf8.decode(data));
      } catch (_) {
        logger.append(String.fromCharCodes(data));
      }
    }, onDone: () async {
      final rc = await _proc!.exitCode;
      logger.append('\nsing-box завершился с кодом $rc\n');
      _proc = null;
      isRunningNotifier.value = false;
    });
  }

  Future<void> stop() async {
    if (_proc == null) return;
    try {
      _proc!.kill(ProcessSignal.sigterm);
    } catch (_) {}
    try {
      await _proc!.exitCode.timeout(const Duration(seconds: 5));
    } catch (_) {
      try {
        _proc!.kill(ProcessSignal.sigkill);
      } catch (_) {}
    }
    _proc = null;
    await _stdoutSub?.cancel();
    _stdoutSub = null;
    isRunningNotifier.value = false;
    logger.append('Туннель остановлен.\n');
  }

  Future<String> updateIp() async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse('https://api.ipify.org?format=text'));
      final resp = await req.close();
      if (resp.statusCode != 200) return '-';
      final ip = await resp.transform(utf8.decoder).join();
      return ip.trim();
    } catch (_) {
      return '-';
    } finally {
      client.close(force: true);
    }
  }

  Future<bool> isWindowsAdmin() async {
    if (!Platform.isWindows) return Future.value(false);
    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        r"(New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)"
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
      final argsEscaped = extraArgs.map((a) => a.replaceAll('"', '""')).join(' ');
      final ps = 'Start-Process -FilePath "${exe.replaceAll('"', '""')}" -ArgumentList "${argsEscaped}" -Verb RunAs';
      await Process.start('powershell', ['-NoProfile', '-Command', ps], runInShell: false);
      return true;
    } catch (_) {
      return false;
    }
  }
}
