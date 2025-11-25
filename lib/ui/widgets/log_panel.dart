import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/vlf_core.dart';

class LogPanel extends StatefulWidget {
  final VlfCore core;

  const LogPanel({super.key, required this.core});

  @override
  State<LogPanel> createState() => _LogPanelState();
}

class _LogPanelState extends State<LogPanel> {
  final List<String> _items = [];
  StreamSubscription<String>? _sub;
  final ScrollController _scrollController = ScrollController();
  bool _autoScroll = true; // Автоскролл включен по умолчанию
  static const int _maxLogLines = 5000; // Буфер логов

  @override
  void initState() {
    super.initState();
    // Предзагружаем историю логов, чтобы не терять ленту при рестартах/переключениях
    try {
      _items.addAll(widget.core.logHistory);
    } catch (_) {}

    // Подписка на поток логов (ВСЕГДА активна, без паузы)
    _sub = widget.core.logStream.listen((line) {
      setState(() {
        _items.add(line);
        // Ограничение буфера: удаляем старые строки
        if (_items.length > _maxLogLines) {
          _items.removeAt(0);
        }
      });

      // Автоскролл к последней строке (если включен)
      if (_autoScroll) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        });
      }
    });

    // Отслеживание ручной прокрутки пользователем
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    
    final position = _scrollController.position;
    final isAtBottom = position.pixels >= position.maxScrollExtent - 50;
    
    // Включаем автоскролл, если пользователь вернулся вниз
    if (isAtBottom && !_autoScroll) {
      setState(() {
        _autoScroll = true;
      });
    } 
    // Отключаем автоскролл, если пользователь прокрутил вверх
    else if (!isAtBottom && _autoScroll) {
      setState(() {
        _autoScroll = false;
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Text(
                  'Логи',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                // Индикатор автоскролла
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _autoScroll ? const Color(0xFF10B981) : const Color(0xFF6B7280),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _autoScroll ? Icons.arrow_downward : Icons.pause,
                        size: 14,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _autoScroll ? 'Авто' : 'Стоп',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Кнопка "Вниз" (появляется когда автоскролл выключен)
                if (!_autoScroll)
                  GestureDetector(
                    onTap: () {
                      if (_scrollController.hasClients) {
                        _scrollController.animateTo(
                          _scrollController.position.maxScrollExtent,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        );
                        setState(() {
                          _autoScroll = true;
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E2A36),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(
                        Icons.vertical_align_bottom,
                        size: 16,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                  ),
              ],
            ),
            Row(
              children: [
                Text(
                  '${_items.length} записей',
                  style: const TextStyle(color: Color(0xFF9CA3AF)),
                ),
                const SizedBox(width: 12),
                // Кнопка очистки логов
                GestureDetector(
                  onTap: () {
                    widget.core.clearLogs();
                    setState(() {
                      _items.clear();
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E2A36),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: const [
                        Icon(
                          Icons.delete_outline,
                          size: 14,
                          color: Color(0xFF9CA3AF),
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Очистить',
                          style: TextStyle(
                            color: Color(0xFF9CA3AF),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Контейнер с логами и скроллбаром
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF071426),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Scrollbar(
            controller: _scrollController,
            thumbVisibility: true,
            thickness: 8.0,
            radius: const Radius.circular(4),
            child: SelectionArea(
              child: ListView.builder(
                controller: _scrollController,
                reverse: false,
                shrinkWrap: true,
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: _items.length,
                itemBuilder: (context, index) {
                  final line = _items[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8.0,
                      vertical: 6.0,
                    ),
                    child: Text(
                      line,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
