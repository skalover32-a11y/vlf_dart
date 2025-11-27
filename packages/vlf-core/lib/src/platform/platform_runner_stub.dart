part of 'platform_runner.dart';

class PlatformRunnerStub implements PlatformRunner {
  PlatformRunnerStub();

  UnsupportedError _error() =>
      UnsupportedError('PlatformRunner is not supported on this platform');

  @override
  Future<void> start(VlfConfig config) => Future.error(_error());

  @override
  Future<void> stop() => Future.error(_error());

  @override
  Stream<String> get logs => Stream<String>.error(_error());

  @override
  Future<bool> get isRunning => Future.error(_error());

  @override
  Future<void> restart(VlfConfig config) => Future.error(_error());

  @override
  Future<void> dispose() => Future.error(_error());
}