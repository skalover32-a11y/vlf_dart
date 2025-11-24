import 'package:flutter/material.dart';

class VlfHeader extends StatelessWidget {
  final VoidCallback onMenuTap;
  final VoidCallback onAddTap;

  const VlfHeader({super.key, required this.onMenuTap, required this.onAddTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        GestureDetector(
          onTap: onMenuTap,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF15202A),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.menu, color: Colors.white, size: 20),
          ),
        ),
        const Expanded(
          child: Center(
            child: Text(
              'VLF tunnel',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        GestureDetector(
          onTap: onAddTap,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF15202A),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.add, color: Colors.white, size: 20),
          ),
        ),
      ],
    );
  }
}
