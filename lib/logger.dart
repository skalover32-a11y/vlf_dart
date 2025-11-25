import 'dart:async';

/// Простая обёртка логирования с сохранением истории и стримом для UI.
class Logger {
  final _ctrl = StreamController<String>.broadcast();
  final List<String> _buffer = <String>[];
  int _lines = 0;
  int _maxEntries;

  Logger({int maxEntries = 5000}) : _maxEntries = maxEntries;

  /// Добавить текст в лог.
  /// Текст может содержать несколько строк; сохраняем как один элемент буфера,
  /// но счётчик строк увеличиваем по количеству переводов.
  void append(String text) {
    _ctrl.add(text);

    _buffer.add(text);
    if (_buffer.length > _maxEntries) {
      _buffer.removeAt(0);
    }

    // Примерная оценка количества строк для метрик
    _lines += '\n'.allMatches(text).length +
        (text.isNotEmpty && !text.endsWith('\n') ? 1 : 0);
  }

  /// Текущий стрим логов (подписывайтесь в UI).
  Stream<String> get stream => _ctrl.stream;

  /// Количество лог-строк (оценочно).
  int get lines => _lines;

  /// История логов за текущую сессию приложения.
  List<String> get history => List.unmodifiable(_buffer);

  /// Очистка истории логов (по явной команде пользователя).
  void clear() {
    _buffer.clear();
    _lines = 0;
    _ctrl.add('— логи очищены пользователем —\n');
  }

  void dispose() {
    _ctrl.close();
  }
}
