import 'package:flutter/material.dart';
import 'satellite_page.dart';

void main() {
  runApp(const AstroApp());
}

class AstroApp extends StatelessWidget {
  const AstroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: SatellitePage());
  }
}
