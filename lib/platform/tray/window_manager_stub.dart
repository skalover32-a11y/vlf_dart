// Stub for window_manager on non-desktop platforms (Android/iOS/Web)

class WindowManager {
  Future<void> ensureInitialized() async {}
  Future<void> waitUntilReadyToShow(dynamic options, Function callback) async {}
  Future<void> setTitle(String title) async {}
  Future<void> setSize(dynamic size) async {}
  Future<void> setMinimumSize(dynamic size) async {}
  Future<void> setMaximumSize(dynamic size) async {}
  Future<void> setResizable(bool resizable) async {}
  Future<void> show() async {}
  Future<void> hide() async {}
  Future<void> focus() async {}
  Future<void> setSkipTaskbar(bool skip) async {}
  Future<bool> isPreventClose() async => false;
  Future<void> destroy() async {}
  
  void addListener(dynamic listener) {}
  void removeListener(dynamic listener) {}
}

final windowManager = WindowManager();

class WindowOptions {
  final dynamic size;
  final bool center;
  final dynamic minimumSize;
  final String title;
  
  const WindowOptions({
    required this.size,
    required this.center,
    required this.minimumSize,
    required this.title,
  });
}

mixin WindowListener {
  void onWindowClose() {}
}
