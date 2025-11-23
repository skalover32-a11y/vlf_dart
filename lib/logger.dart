import 'dart:async';

/// Простая обёртка логирования, экспортирует поток строк для UI.
class Logger {
  final _ctrl = StreamController<String>.broadcast();
  int _lines = 0;

  void append(String text) {
    _ctrl.add(text);
    // примерно считаем количество строк
    _lines += '\n'.allMatches(text).length + (text.isNotEmpty && !text.endsWith('\n') ? 1 : 0);
  }

  Stream<String> get stream => _ctrl.stream;

  int get lines => _lines;

  void dispose() {
    _ctrl.close();
  }
}
