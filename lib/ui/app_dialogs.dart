import 'package:flutter/material.dart';

/// Utilities for styled dialogs and snackbars used across the app.

/// Wraps a dialog widget in a scaling wrapper so it fits on small windows.
Widget appDialogWrapper(
  Widget dialog, {
  double? width,
  double maxWidth = 380.0,
}) {
  final effectiveMax = width ?? maxWidth;
  return Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: effectiveMax),
        child: Material(color: Colors.transparent, child: dialog),
      ),
    ),
  );
}

/// Build a styled AlertDialog with app theme defaults.
AlertDialog buildAppAlert({
  Widget? title,
  Widget? content,
  List<Widget>? actions,
}) {
  return AlertDialog(
    backgroundColor: const Color(0xFF17232D),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    title: title,
    content: content,
    actions: actions,
  );
}

/// Build a styled SimpleDialog (for lists/choices).
SimpleDialog buildAppSimpleDialog({Widget? title, List<Widget>? children}) {
  return SimpleDialog(
    backgroundColor: const Color(0xFF17232D),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    title: title,
    children: children ?? [],
  );
}

/// Show a floating, styled SnackBar matching the app theme.
void showAppSnackBar(
  BuildContext context,
  String message, {
  Color? background,
  Duration? duration,
}) {
  final sb = SnackBar(
    content: Text(message, style: const TextStyle(color: Colors.white)),
    behavior: SnackBarBehavior.floating,
    backgroundColor: background ?? const Color(0xFF1F2A30),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    duration: duration ?? const Duration(seconds: 3),
  );
  ScaffoldMessenger.of(context).showSnackBar(sb);
}
