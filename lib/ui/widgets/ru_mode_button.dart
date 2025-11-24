import 'package:flutter/material.dart';

class RuModeButton extends StatelessWidget {
  final bool isEnabled;
  final VoidCallback onTap;

  const RuModeButton({super.key, required this.isEnabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bg = isEnabled ? const Color(0xFF2AAFC0) : const Color(0xFF2F3840);
    final border = isEnabled ? Colors.transparent : Colors.white24;
    final shadow = isEnabled
        ? [
            BoxShadow(
              color: const Color(0xFF2AAFC0).withOpacity(0.25),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ]
        : [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ];

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 24),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: border, width: 1),
          boxShadow: shadow,
        ),
        child: Center(
          child: Text(
            'Режим РФ',
            style: TextStyle(
              color: isEnabled ? Colors.white : Colors.white70,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
