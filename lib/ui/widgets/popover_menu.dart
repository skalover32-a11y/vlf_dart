import 'package:flutter/material.dart';

class PopoverMenuItem {
  final IconData icon;
  final String text;
  final VoidCallback onTap;

  PopoverMenuItem({required this.icon, required this.text, required this.onTap});
}

class PopoverMenu extends StatelessWidget {
  final List<PopoverMenuItem> items;
  final double width;

  const PopoverMenu({super.key, required this.items, this.width = 220});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: const Color(0xFF1E2A36),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 6))],
        ),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: items.map((it) {
            return InkWell(
              onTap: it.onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 12.0),
                child: Row(
                  children: [
                    Icon(it.icon, color: const Color(0xFF9CA3AF), size: 20),
                    const SizedBox(width: 12),
                    Expanded(child: Text(it.text, style: const TextStyle(color: Colors.white, fontSize: 14))),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
