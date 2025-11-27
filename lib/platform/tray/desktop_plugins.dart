// Conditional exports for desktop-only plugins
// On desktop: exports real window_manager and tray_manager
// On mobile/web: exports stubs to avoid MissingPluginException

export 'desktop_plugins_impl.dart'
    if (dart.library.js) 'desktop_plugins_stub.dart'
    if (dart.library.html) 'desktop_plugins_stub.dart';
