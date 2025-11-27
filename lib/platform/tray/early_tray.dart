// Conditional export for early tray interceptor
export 'early_tray_impl.dart'
    if (dart.library.js) 'early_tray_stub.dart'
    if (dart.library.html) 'early_tray_stub.dart';
