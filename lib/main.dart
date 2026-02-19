import 'package:flutter/material.dart';
import 'satellite_page.dart';

void main() {
  runApp(const AstroApp());
}

class AstroApp extends StatelessWidget {
  const AstroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SatellitePage(),
        bottomNavigationBar: BottomAppBar(
          color: Colors.grey.shade900.withValues(alpha: 1.0),
          height: 50.0,
        ),
      ),
    );
  }
}
