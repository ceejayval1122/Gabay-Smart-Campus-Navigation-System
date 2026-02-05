import 'package:flutter/material.dart';
import '../screens/debug/debug_screen.dart';

class DebugFab extends StatelessWidget {
  const DebugFab({super.key});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      mini: true,
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const DebugScreen(),
          ),
        );
      },
      backgroundColor: const Color(0xFF63C1E3),
      child: const Icon(Icons.bug_report, color: Colors.white),
      tooltip: 'Debug Logs',
    );
  }
}
