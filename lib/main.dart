import 'package:flutter/material.dart';
import 'package:openswipe/screens/review_screen.dart';
import 'package:openswipe/util/permissions.dart';

void main() {
  runApp(const OpenSwipeApp());
}

class OpenSwipeApp extends StatelessWidget {
  const OpenSwipeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OpenSwipe',
      home: PermissionGate(child: const ReviewScreen()),
    );
  }
}
