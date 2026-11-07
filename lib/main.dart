import 'package:astrotempo/forecast_page.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';
import 'satellite_page.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

final ThemeData astroDeepSpaceTheme = ThemeData.dark().copyWith(
  // =====================================================
  // CORE COLORS
  // =====================================================
  scaffoldBackgroundColor: const Color(0xFF0A0E1A),

  colorScheme: const ColorScheme.dark(
    brightness: Brightness.dark,

    primary: Color(0xFF1C2541), // panels / headers
    secondary: Color(0xFF4CC9F0), // cyan accent
    surface: Color(0xFF12172A),

    onPrimary: Color(0xFFEAEAF0),
    onSecondary: Color(0xFF001219),
    onSurface: Color(0xFFEAEAF0),
  ),

  // =====================================================
  // TYPOGRAPHY (night optimized)
  // =====================================================
  textTheme: const TextTheme(
    titleLarge: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      color: Color(0xFFEAEAF0),
    ),

    titleMedium: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w500,
      color: Color(0xFFEAEAF0),
    ),

    bodyLarge: TextStyle(fontSize: 15, color: Color(0xFFD1D5DB)),

    bodyMedium: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)),

    labelLarge: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: Color(0xFF4CC9F0),
    ),
  ),

  // =====================================================
  // APP BAR
  // =====================================================
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFF0A0E1A),
    elevation: 0,
    centerTitle: true,
    titleTextStyle: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: Color(0xFFEAEAF0),
    ),
    iconTheme: IconThemeData(color: Color(0xFF4CC9F0)),
  ),

  // =====================================================
  // CARDS
  // =====================================================
  cardTheme: CardThemeData(
    color: const Color(0xFF1E2852).withValues(alpha: 0.8),
    elevation: 2,
    margin: const EdgeInsets.all(8),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  ),

  // =====================================================
  // FLOATING ACTION BUTTON
  // =====================================================
  floatingActionButtonTheme: const FloatingActionButtonThemeData(
    backgroundColor: Color(0xFF1E2852), // same as cards
    foregroundColor: Color(0xFFBFC5CF), // light grey
    elevation: 3,
    focusElevation: 4,
    hoverElevation: 4,
    highlightElevation: 5,
  ),

  // =====================================================
  // BUTTONS
  // =====================================================
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFF1C2541),
      foregroundColor: const Color(0xFFBFC5CF),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  ),

  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(foregroundColor: const Color(0xFF4CC9F0)),
  ),

  // =====================================================
  // NAVIGATION BAR
  // =====================================================
  navigationBarTheme: NavigationBarThemeData(
    backgroundColor: const Color(0xFF12172A),
    elevation: 0,
    height: 60,

    indicatorColor: const Color(0x0012172A),

    iconTheme: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) {
        return const IconThemeData(color: Color(0xFFBFC5CF));
      }
      return const IconThemeData(color: Color(0xFF9CA3AF));
    }),

    labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>((states) {
      if (states.contains(WidgetState.selected)) {
        return const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Color(0xFFBFC5CF),
        );
      }
      return const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w400,
        color: Color(0xFF9CA3AF),
      );
    }),
  ),

  // =====================================================
  // DIVIDERS
  // =====================================================
  dividerTheme: const DividerThemeData(color: Color(0xFF1F2937), thickness: 1),

  // =====================================================
  // ICONS
  // =====================================================
  iconTheme: const IconThemeData(color: Color(0xFFBFC5CF), size: 22),

  // =====================================================
  // INPUT FIELDS
  // =====================================================
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: const Color(0xFF12172A),

    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFF1F2937)),
    ),

    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFF1F2937)),
    ),

    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFF4CC9F0), width: 1.5),
    ),

    labelStyle: const TextStyle(color: Color(0xFF9CA3AF)),
  ),

  // =====================================================
  // LIST TILES
  // =====================================================
  listTileTheme: const ListTileThemeData(
    iconColor: Color(0xFF4CC9F0),
    textColor: Color(0xFFEAEAF0),
  ),

  // =====================================================
  // TOOLTIP
  // =====================================================
  tooltipTheme: TooltipThemeData(
    decoration: BoxDecoration(
      color: const Color(0xFF1C2541),
      borderRadius: BorderRadius.circular(8),
    ),
    textStyle: const TextStyle(color: Color(0xFFEAEAF0)),
  ),
);

void main() {
  runApp(const AstroApp());
}

class AstroApp extends StatelessWidget {
  const AstroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: astroDeepSpaceTheme,
      home: MainPage(),
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _currentIndex = 0;
  double? _lat;
  double? _lon;
  bool _loading = true;
  final TextEditingController _cityController = TextEditingController();
  List<LocationModel> _results = [];

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  @override
  void dispose() {
    _cityController.dispose();
    super.dispose();
  }

  Future<void> _initLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _loading = false;
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() {
          _loading = false;
        });
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      double lat = position.latitude;
      double lon = position.longitude;

      // Enforce latitude bounds (-90, 90)
      lat = lat.clamp(-90.0, 90.0);

      // Convert longitude from [-180, 180] to [0, 360]
      if (lon < 0) {
        lon = lon + 360.0;
      }

      lon = lon.clamp(0.0, 360.0);

      setState(() {
        _lat = lat;
        _lon = lon;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.grey[300]),
              const SizedBox(height: 10.0),
              const Text('Obtaining current location'),
            ],
          ),
        ),
      );
    }

    // if lat ant lon not null, go to forecast page.
    // else ask user to manually enter location
    Widget forecastTab;
    if (_lat != null && _lon != null) {
      forecastTab = ForecastPage(lat: _lat!, lon: _lon!);
    } else {
      forecastTab = Padding(
        padding: EdgeInsetsGeometry.only(
          left: 30,
          right: 30,
          top: 50,
          bottom: 30,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Live search TextField
            TextField(
              controller: _cityController,
              decoration: const InputDecoration(
                labelText: 'Enter city name',
                hintText: "Type city name...",
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (text) async {
                if (text.trim().isEmpty) {
                  setState(() {
                    _results = [];
                  });
                  return;
                }

                try {
                  final results = await searchLocation(text);
                  setState(() {
                    _results = results;
                  });
                } catch (e) {
                  setState(() {});
                }
              },
            ),
            const SizedBox(height: 12),

            // 2. Dynamic Results List
            if (_results.isNotEmpty)
              Expanded(
                child: ListView.builder(
                  shrinkWrap: false,
                  itemCount: _results.length,
                  itemBuilder: (context, i) {
                    final loc = _results[i];
                    return ListTile(
                      leading: const Icon(Icons.location_on_outlined),
                      title: Text(
                        loc.state != null
                            ? "${loc.name}, ${loc.state}"
                            : loc.name,
                      ),
                      subtitle: Text(loc.country),
                      onTap: () {
                        // Clear search results and text field when selected
                        setState(() {
                          _cityController.text = loc.state != null
                              ? "${loc.name}, ${loc.state}"
                              : loc.name;
                          _results = []; // Hide list after selection
                          _lat = loc.lat;
                          _lon = loc.lon;

                          if (_lon != null && _lon! < 0) {
                            _lon = _lon! + 360.0;
                          }
                        });
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      );
    }

    final pages = [forecastTab, const SatellitePage()];

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: pages),
      bottomNavigationBar: Theme(
        data: Theme.of(context).copyWith(
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          splashColor: Colors.transparent,
        ),
        child: NavigationBar(
          height: 60.0,
          labelPadding: EdgeInsets.zero,
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          indicatorColor: Colors.transparent,
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.wb_cloudy_outlined),
              selectedIcon: Icon(Icons.wb_cloudy),
              label: 'Forecast',
            ),
            NavigationDestination(
              icon: Icon(Icons.satellite_alt_outlined),
              selectedIcon: Icon(Icons.satellite_alt),
              label: 'Satellite',
            ),
          ],
        ),
      ),
    );
  }
}

class LocationModel {
  final String name;
  final String? state;
  final String country;
  final double lat;
  final double lon;

  LocationModel({
    required this.name,
    this.state,
    required this.country,
    required this.lat,
    required this.lon,
  });

  factory LocationModel.fromJson(Map<String, dynamic> json) {
    return LocationModel(
      name: json['name'] ?? '',
      state: json['admin1'],
      country: json['country'] ?? '',
      lat: (json['latitude'] as num).toDouble(),
      lon: (json['longitude'] as num).toDouble(),
    );
  }
}

Future<List<LocationModel>> searchLocation(String cityName) async {
  if (cityName.trim().isEmpty) return [];

  try {
    final uri = Uri.parse(
      'https://geocoding-api.open-meteo.com/v1/search?name=$cityName&count=10&language=en&format=json',
    );
    final response = await http.get(uri);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);

      if (data['results'] != null && (data['results'] as List).isNotEmpty) {
        return (data['results'] as List)
            .map((item) => LocationModel.fromJson(item))
            .toList();
      }
    }
    return [];
  } catch (e) {
    return [];
  }
}
