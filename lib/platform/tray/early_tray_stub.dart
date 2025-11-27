// Mobile/web stub for early tray interceptor
import 'desktop_plugins.dart';

class EarlySystemTray with WindowListener, TrayListener {
  void onWindowClose() async {}
  
  Future<void> ensureEarlyTrayIcon() async {}
  
  void onTrayIconMouseDown() {}
  
  void onTrayMenuItemClick(MenuItem menuItem) {}
}
