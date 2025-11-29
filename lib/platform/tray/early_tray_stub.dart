// Mobile/web stub for early tray interceptor
import 'desktop_plugins.dart';

class EarlySystemTray with WindowListener, TrayListener {
  @override
  void onWindowClose() async {}

  Future<void> ensureEarlyTrayIcon() async {}

  @override
  void onTrayIconMouseDown() {}

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {}
}
