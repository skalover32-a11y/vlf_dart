import 'package:flutter/material.dart';
import '../../core/vlf_core.dart';

class StatusBlock extends StatelessWidget {
  final VlfCore core;

  const StatusBlock({super.key, required this.core});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1A22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Статус:', style: TextStyle(color: Colors.white70)),
              ValueListenableBuilder<bool>(
                valueListenable: core.isConnected,
                builder: (context, connected, _) => Text(
                  connected ? 'Активен' : 'Отключено',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('IP адрес:', style: TextStyle(color: Colors.white70)),
              FutureBuilder<String>(
                future: core.getIp(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting)
                    return const Text(
                      '-',
                      style: TextStyle(color: Colors.white70),
                    );
                  return Text(
                    snap.data ?? '-',
                    style: const TextStyle(color: Colors.white),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Локация:', style: TextStyle(color: Colors.white70)),
              SizedBox(
                width: 200,
                child: FutureBuilder<String>(
                  future: core.getIpLocation(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting)
                      return const Text('-', style: TextStyle(color: Colors.white70));
                    return Text(
                      snap.data ?? '-',
                      style: const TextStyle(color: Colors.white),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
