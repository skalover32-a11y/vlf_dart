import 'package:flutter/material.dart';

class VlfCircleButton extends StatelessWidget {
  final bool isOn;
  final VoidCallback onTap;

  const VlfCircleButton({super.key, required this.isOn, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Adaptive circle size: 60% of width, max 340px
        final size = (constraints.maxWidth * 0.6).clamp(200.0, 340.0);
        final pad = 12.0;
        final gradient = isOn
            ? RadialGradient(
                colors: [Colors.greenAccent.shade200, Colors.green.shade700],
                radius: 0.9,
              )
            : LinearGradient(colors: [Color(0xFF0E0F12), Color(0xFF1A1A1A)]);

        return GestureDetector(
          onTap: onTap,
          child: Center(
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                gradient: gradient,
                shape: BoxShape.circle,
                boxShadow: isOn
                    ? [
                        BoxShadow(
                          color: Colors.green.withOpacity(0.5),
                          blurRadius: 24,
                          spreadRadius: 4,
                        ),
                      ]
                    : [],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    margin: EdgeInsets.all(pad),
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'V L F',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      Container(width: 140, height: 2, color: Colors.white24),
                      SizedBox(height: 8),
                      Text(
                        isOn ? 'ON' : 'OFF',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
