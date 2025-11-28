import 'dart:async';
import 'package:flutter/services.dart';
import 'package:vlf_core/vlf_core.dart';
import 'package:vlf_core/src/vlf_models.dart' as vm show VlfOutbound, VlfRouteConfig, VlfRuntimeConfig, VlfWorkMode;
import 'package:vlf_core/src/clash_builder.dart';
import 'platform_runner.dart';

/// Android заглушка: не запускает бинарники, общается через MethodChannel
class AndroidPlatformRunner implements PlatformRunner {
  static const MethodChannel _channel = MethodChannel('vlf_android_engine');
  static const EventChannel _statusChannel = EventChannel('vlf_android_engine/status');

  final Logger _logger = Logger();
  bool _running = false;
  final StreamController<String> _statusCtl = StreamController<String>.broadcast();
  StreamSubscription? _statusSub;

  @override
  Stream<String> get logStream => _logger.stream;

  @override
  bool get isRunning => _running;

  @override
  Stream<String> get statusStream => _statusCtl.stream;

  @override
  Future<void> start(PlatformConfig config) async {
    final args = <String, dynamic>{
      'mode': config.workMode == VlfWorkMode.proxy ? 'proxy' : 'tun',
      'configYaml': await _buildYaml(config),
      'debugPaths': {
        'baseDir': config.baseDir.path,
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
    await _channel.invokeMethod('startTunnel', args);
    _running = true;
    _logger.append('Android engine start invoked\n');
  }

  Future<String> _buildYaml(PlatformConfig config) async {
    final outbound = _outboundFromVless(config.profileUrl);
    final routes = vm.VlfRouteConfig(
      ruMode: config.ruMode,
      domainExclusions: config.siteExclusions,
      appExclusions: config.appExclusions,
    );
    final mode = config.workMode == VlfWorkMode.proxy ? vm.VlfWorkMode.proxy : vm.VlfWorkMode.tun;
    final runtime = vm.VlfRuntimeConfig(outbound: outbound, mode: mode, routes: routes);
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
  Future<void> dispose() async {}

  Future<String> getStatus() async {
    final status = await _channel.invokeMethod<String>('getStatus');
    return status ?? 'unknown';
  }
}
// (старую реализацию запуска бинарника на Android удалили как несовместимую)
