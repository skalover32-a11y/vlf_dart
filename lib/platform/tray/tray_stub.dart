// Stub for tray_manager on non-desktop platforms (Android/iOS/Web)
// Provides empty implementations to avoid MissingPluginException

class TrayManager {
  void addListener(dynamic listener) {}
  void removeListener(dynamic listener) {}
  
  Future<void> setIcon(String path) async {}
  Future<void> setToolTip(String tooltip) async {}
  Future<void> setContextMenu(Menu menu) async {}
  void popUpContextMenu() {}
  Future<void> destroy() async {}
}

final trayManager = TrayManager();

class Menu {
  final List<MenuItem> items;
  Menu({required this.items});
}

class MenuItem {
  final String? key;
  final String? label;
  
  MenuItem({this.key, this.label});
  MenuItem.separator() : key = null, label = null;
}

// Mixin stubs
mixin TrayListener {
  void onTrayIconMouseDown() {}
  void onTrayIconRightMouseDown() {}
  void onTrayMenuItemClick(MenuItem menuItem) {}
}
