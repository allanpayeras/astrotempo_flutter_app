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
      // darkTheme: ThemeData.dark(),
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
  String? _error;
  final TextEditingController _cityController = TextEditingController();
  @override
  void initState() {
    super.initState();
    _initLocation();
  }
  @override
  void dispose() {
    // 🧹 Limpamos o controller quando a página é destruída
    _cityController.dispose();
    super.dispose();
  }

  Future<void> _initLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _error = "Location services are disabled.";
          _loading = false;
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      //PERMISSION DENIED IF YOU CHOOSE NOT
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() {
          _error = "Location permission denied.";
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
        _error = e.toString();
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

   // new changes, if lat ant lon not null, have a forecast page.
    Widget forecastTab;
    if(_lat != null && _lon != null){

      forecastTab =ForecastPage(lat: _lat!, lon: _lon!);
    }else {
      //Window search for cities
      forecastTab = Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("No location founded."),
              const SizedBox(height: 16),

            // 1. Controller text
              TextField(
                controller: _cityController,
                decoration: const InputDecoration(
                  labelText: 'Enter the city',
                  prefixIcon: Icon(Icons.location_city),
                ),
              ),
              const SizedBox(height: 12),

            // 2. Manual button
              ElevatedButton.icon(
                onPressed: ()async {
              // capture the text with this button
                  setState(() {
                    _loading = true;
                    _error = null;
                  });

                  // 2.call the new class
                  final cityService = Pickup_city();
                  final coords = await cityService.getCoordinates(_cityController.text);

                  // 3. update the widget
                  setState(() {
                    if (coords != null) {
                      // Acessamos os valores do Record usando o ponto!
                      _lat = coords.lat;
                      _lon = coords.lon;
                    } else {
                      _error = "City no founded.";
                    }
                    _loading = false; // stop loading
                  });
                },
                icon: const Icon(Icons.search),
                label: const Text("Search city"),
              ),
              const SizedBox(height: 12),
              // 3. button when we call again location
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _loading = true;
                  });
                  _initLocation();
                },
                icon: const Icon(Icons.my_location),
                label: const Text("Try set location again."),
              ),
            ],
          ),
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
class Pickup_city{
  Future<({double lat, double lon})?> getCoordinates(String cityName) async {
    if (cityName.trim().isEmpty) return null;

    try {
      final uri = Uri.parse(
        'https://geocoding-api.open-meteo.com/v1/search?name=${Uri.encodeComponent(cityName)}&count=1&language=pt&format=json',
      );
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['results'] != null && (data['results'] as List).isNotEmpty) {
          final firstResult = data['results'][0];
          double lat = (firstResult['latitude'] as num).toDouble();
          double lon = (firstResult['longitude'] as num).toDouble();

          lat = lat.clamp(-90.0, 90.0);
          if (lon < 0) lon = lon + 360.0;
          lon = lon.clamp(0.0, 360.0);

          return(lat:lat,lon:lon);
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}

// class _MainPageState extends State<MainPage> {
//   int _currentIndex = 0;
//
//   final List<Widget> _pages = const [
//     ForecastPage(lat: -25.394, lon: 310.786),
//     SatellitePage(),
//   ];
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       body: IndexedStack(index: _currentIndex, children: _pages),
//       bottomNavigationBar: Theme(
//         data: Theme.of(context).copyWith(
//           splashFactory: NoSplash.splashFactory,
//           highlightColor: Colors.transparent,
//           splashColor: Colors.transparent,
//         ),
//         child: NavigationBar(
//           height: 60.0,
//           labelPadding: EdgeInsets.zero,
//           selectedIndex: _currentIndex,
//           onDestinationSelected: (index) {
//             setState(() {
//               _currentIndex = index;
//             });
//           },
//           indicatorColor: Colors.transparent,
//           overlayColor: MaterialStateProperty.all(Colors.transparent),
//           destinations: const [
//             NavigationDestination(
//               icon: Icon(Icons.wb_cloudy_outlined),
//               selectedIcon: Icon(Icons.wb_cloudy),
//               label: 'Forecast',
//             ),
//             NavigationDestination(
//               icon: Icon(Icons.satellite_alt_outlined),
//               selectedIcon: Icon(Icons.satellite_alt),
//               label: 'Satellite',
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }
