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
  bool _autoScroll = true; // внутренний флаг: прокручивать вниз только когда пользователь на нижней границе
  static const int _maxLogLines = 5000; // Буфер логов

  bool get _isAtBottom {
    if (!_scrollController.hasClients) return true;
    final position = _scrollController.position;
    final threshold = 32.0;
    return position.pixels >= position.maxScrollExtent - threshold;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void initState() {
    super.initState();
    // Предзагружаем историю логов, чтобы не терять ленту при рестартах/переключениях
    try {
      for (final chunk in widget.core.logHistory) {
        _appendChunk(chunk);
      }
    } catch (_) {}

    // Подписка на поток логов (ВСЕГДА активна, без паузы)
    _sub = widget.core.logStream.listen((line) {
      final shouldStick = _autoScroll && _isAtBottom;
      setState(() {
        _appendChunk(line);
      });

      if (shouldStick) {
        _scrollToBottom();
      }
    });

    // Отслеживание ручной прокрутки пользователем
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final atBottom = _isAtBottom;
    if (atBottom && !_autoScroll) {
      setState(() => _autoScroll = true);
    } else if (!atBottom && _autoScroll) {
      setState(() => _autoScroll = false);
    }
  }

  void _appendChunk(String chunk) {
    if (chunk.isEmpty) return;

    final normalized = chunk
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    final lines = normalized.split('\n');
    for (final raw in lines) {
      final line = raw.trimRight();
      if (line.isEmpty) continue;
      _items.add(line);
      if (_items.length > _maxLogLines) {
        _items.removeAt(0);
      }
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
            const Text(
              'Логи',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '${_items.length} записей',
              style: const TextStyle(color: Color(0xFF9CA3AF)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Контейнер с логами и скроллбаром
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF071426),
              borderRadius: BorderRadius.circular(24),
            ),
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
              child: SelectionArea(
                child: ListView.builder(
                controller: _scrollController,
                physics: const ClampingScrollPhysics(),
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
        ),
      ],
    );
  }
}
