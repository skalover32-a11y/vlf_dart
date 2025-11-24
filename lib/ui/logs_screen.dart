import 'package:flutter/material.dart';

import '../core/vlf_core.dart';
import 'widgets/log_panel.dart';

class LogsScreen extends StatelessWidget {
  final VlfCore core;
  const LogsScreen({super.key, required this.core});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Логи'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
              Expanded(
                child: LogPanel(core: core),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
