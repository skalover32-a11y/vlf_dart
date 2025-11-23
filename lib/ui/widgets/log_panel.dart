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

  @override
  void initState() {
    super.initState();
    _sub = widget.core.logStream.listen((line) {
      setState(() {
        _items.add(line);
        if (_items.length > 1000) _items.removeAt(0);
      });

      // After the new frame, scroll to bottom to show latest log
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    });
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
            const Text('Логи', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            Text('${_items.length} записей', style: const TextStyle(color: Color(0xFF9CA3AF))),
          ],
        ),
        const SizedBox(height: 8),
        // Let the ListView fill remaining vertical space inside this Column.
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF071426),
              borderRadius: BorderRadius.circular(24),
            ),
            child: ListView.builder(
              controller: _scrollController,
              reverse: false,
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final line = _items[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
                  child: Text(line, style: const TextStyle(color: Colors.white70, fontFamily: 'monospace', fontSize: 13)),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
