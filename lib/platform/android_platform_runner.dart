import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:vlf_core/vlf_core.dart';
import 'package:vlf_core/src/vlf_models.dart' as vm show VlfOutbound, VlfRouteConfig, VlfRuntimeConfig, VlfWorkMode;
import 'package:vlf_core/src/clash_builder.dart';
import 'package:vlf_core/src/singbox_config.dart';
import 'package:vlf_core/src/vlf_paths.dart';

import 'platform_runner.dart';

/// Android заглушка: не запускает бинарники, общается через MethodChannel
class AndroidPlatformRunner implements PlatformRunner {
  static const MethodChannel _channel = MethodChannel('vlf_android_engine');
  static const EventChannel _statusChannel = EventChannel('vlf_android_engine/status');
  static const EventChannel _logChannel = EventChannel('vlf_android_engine/logs');

  final Logger _logger = Logger();
  bool _running = false;
  final StreamController<String> _statusCtl = StreamController<String>.broadcast();
  StreamSubscription? _statusSub;
  StreamSubscription? _logSub;

  @override
  Stream<String> get logStream => _logger.stream;

  @override
  bool get isRunning => _running;

  @override
  Stream<String> get statusStream => _statusCtl.stream;

  @override
  Future<void> start(PlatformConfig config) async {
    final runtime = _buildRuntimeConfig(config);
    final singboxBuilder = SingboxConfigBuilder(runtime);
    final singboxJson = singboxBuilder.toJsonString();
    final previewLen = math.min(160, singboxJson.length);
    final preview = singboxJson.substring(0, previewLen);
    _logger.append('Android sing-box JSON prepared (${singboxJson.length} chars): $preview${singboxJson.length > previewLen ? '…' : ''}\n');

    // Persist JSON config to unified path (Android requires /data/user/0/.../files/vlf_data)
    final singboxConfigPath = await singboxBuilder.saveToDefaultLocation(
      logger: _logger,
      jsonOverride: singboxJson,
    );

    final preparePayload = {
      'json': singboxJson,
      'path': singboxConfigPath,
      'preview': preview,
    };
    await _channel.invokeMethod('prepareConfig', preparePayload);
    _logger.append('Android prepareConfig() acknowledged\n');

    final yamlForDebug = await _buildYaml(runtime);
    final basePath = await VlfPaths.getBasePath();
    final args = <String, dynamic>{
      'mode': config.workMode == VlfWorkMode.proxy ? 'proxy' : 'tun',
      'configYaml': yamlForDebug,
      'debugPaths': {
        'baseDir': basePath,
        'singboxConfig': singboxConfigPath,
      },
    };
    _logger.append('AndroidPlatformRunner.startTunnel() called with mode=${config.workMode.displayName}\n');
    // Подписка на статус из нативного слоя
    _statusSub ??= _statusChannel.receiveBroadcastStream().listen((event) {
      final s = (event ?? '').toString();
      _logger.append('Android status: $s\n');
      _statusCtl.add(s);
      // Обновляем флаг _running на основе статуса
      if (s.startsWith('starting') || s.startsWith('running')) {
        _running = true;
      }
      if (s.startsWith('stopping') || s.startsWith('stopped') || s.startsWith('error')) {
        _running = false;
      }
    }, onError: (e) {
      _logger.append('Android status error: $e\n');
      _statusCtl.add('error:$e');
      _running = false;
    });
    _logSub ??= _logChannel.receiveBroadcastStream().listen((event) {
      final line = (event ?? '').toString();
      if (line.isEmpty) {
        return;
      }
      _logger.append('VLF-SINGBOX: $line\n');
    }, onError: (e) {
      _logger.append('Android log stream error: $e\n');
    });
    await _channel.invokeMethod('startTunnel', args);
    _running = true;
    _logger.append('Android engine start invoked\n');
  }

  vm.VlfRuntimeConfig _buildRuntimeConfig(PlatformConfig config) {
    final outbound = _outboundFromVless(config.profileUrl);
    final routes = vm.VlfRouteConfig(
      ruMode: config.ruMode,
      domainExclusions: config.siteExclusions,
      appExclusions: config.appExclusions,
    );
    final mode = config.workMode == VlfWorkMode.proxy ? vm.VlfWorkMode.proxy : vm.VlfWorkMode.tun;
    return vm.VlfRuntimeConfig(outbound: outbound, mode: mode, routes: routes);
  }

  Future<String> _buildYaml(vm.VlfRuntimeConfig runtime) async {
    return ClashConfigBuilder(runtime).buildYaml();
  }

  vm.VlfOutbound _outboundFromVless(String vlessUrl) {
    try {
      final uri = Uri.parse(vlessUrl);
      final auth = uri.userInfo;
      final host = uri.host;
      final port = uri.port == 0 ? 443 : uri.port;
      String? qp(String k) => uri.queryParameters[k];
      return vm.VlfOutbound(
        server: host,
        port: port,
        uuid: auth,
        flow: qp('flow'),
        security: qp('security'),
        fingerprint: qp('fp'),
        publicKey: qp('pbk'),
        shortId: qp('sid'),
        sni: qp('sni'),
      );
    } catch (_) {
      return const vm.VlfOutbound(server: 'unknown', port: 443, uuid: '');
    }
  }

  @override
  Future<void> stop() async {
    _logger.append('AndroidPlatformRunner.stopTunnel() called\n');
    await _channel.invokeMethod('stopTunnel');
    _running = false;
  }

  @override
  Future<void> quickStop() async {
    await stop();
  }

  @override
  Future<bool> isElevated() async => false;

  @override
  Future<void> relaunchElevated() async {
    throw UnsupportedError('Elevation not supported on Android');
  }

  @override
  Future<void> dispose() async {
    await _statusSub?.cancel();
    _statusSub = null;
    await _logSub?.cancel();
    _logSub = null;
  }

  Future<String> getStatus() async {
    final status = await _channel.invokeMethod<String>('getStatus');
    return status ?? 'unknown';
  }
}
// (старую реализацию запуска бинарника на Android удалили как несовместимую)
