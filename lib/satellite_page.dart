import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';

Future<Position> getGpsPosition() async {
  bool serviceEnabled;
  LocationPermission permission;

  serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    throw Exception('Location services are disabled.');
  }

  permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      throw Exception('Location permission denied.');
    }
  }

  if (permission == LocationPermission.deniedForever) {
    throw Exception('Location permission permanently denied.');
  }

  return await Geolocator.getCurrentPosition(
    desiredAccuracy: LocationAccuracy.high,
  );
}

// helper function
Position copyPositionWith(
  Position original, {
  double? latitude,
  double? longitude,
}) {
  return Position(
    latitude: latitude ?? original.latitude,
    longitude: longitude ?? original.longitude,
    timestamp: original.timestamp,
    accuracy: original.accuracy,
    altitude: original.altitude,
    altitudeAccuracy: original.altitudeAccuracy,
    heading: original.heading,
    headingAccuracy: original.headingAccuracy,
    speed: original.speed,
    speedAccuracy: original.speedAccuracy,
  );
}

class SatellitePage extends StatefulWidget {
  const SatellitePage({Key? key}) : super(key: key);

  @override
  State<SatellitePage> createState() => _SatellitePageState();
}

class _SatellitePageState extends State<SatellitePage> {
  MapLibreMapController? _controller;

  final String baseUrlTimes = "https://tiles.astrotempo.org";
  final String baseUrlTiles = "https://sttiles.astrotempo.org";

  String selectedProduct = "acht";
  static const Map<String, String> _productLabels = {
    "acht": "Cloud top temperature",
    "cod": "Cloud optical depth",
    "acha": "Cloud top height",
    "none": "No satellite layer",
  };
  List<String> availableTimes = [];
  int currentFrame = 100;

  bool isPlaying = false;
  Timer? _animationTimer;

  bool _circleMenuExpanded = false;

  bool _distanceCirclesVisible = false;
  bool _horizonCirclesVisible = false;

  bool _gpsLocationVisible = false;
  bool _tapLocationVisible = false;

  bool _layersInitialized = false;
  static const int _bufferCount = 12;
  int _activeIndex = 0;
  Position _userPosition = Position(
    longitude: -49.0,
    latitude: -25.0,
    timestamp: DateTime(2026),
    accuracy: 10.0,
    altitude: 900.0,
    altitudeAccuracy: 25.0,
    heading: 0.0,
    headingAccuracy: 1.0,
    speed: 0.0,
    speedAccuracy: 1.0,
  );
  Position _tapPosition = Position(
    longitude: -49.0,
    latitude: -25.0,
    timestamp: DateTime(2026),
    accuracy: 10.0,
    altitude: 900.0,
    altitudeAccuracy: 25.0,
    heading: 0.0,
    headingAccuracy: 1.0,
    speed: 0.0,
    speedAccuracy: 1.0,
  );
  Timer? _debounce;
  final Duration _debounceDuration = const Duration(milliseconds: 50);

  Timer? _refreshTimer;

  final List<String> products = ["acht", "cod", "acha", "none"];

  @override
  void initState() {
    super.initState();

    _refreshTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _refreshTimes(),
    );
  }

  @override
  void dispose() {
    _animationTimer?.cancel();
    _debounce?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  // ============================
  // Map Initialization
  // ============================

  void _onMapCreated(MapLibreMapController controller) async {
    _controller = controller;
    await _initialize();
    setState(() {
      _gpsLocationVisible = true;
    });
    await _updateUserLocation();
    await Future.delayed(Duration(milliseconds: 1000));
    await _centerOnUser();
  }

  Future<void> _initialize() async {
    await _fetchTimes();
    await _initializePermanentLayers();
    await _initializeLayers();
  }

  // ============================
  // Fetch Available Times
  // ============================

  Future<void> _fetchTimes() async {
    if (selectedProduct == "none") {
      setState(() {
        availableTimes = [];
      });
      return;
    }

    final response = await http.get(
      Uri.parse("$baseUrlTimes/timestamps/$selectedProduct"),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      availableTimes = List<String>.from(data["timestamps"]);

      setState(() {
        availableTimes = availableTimes.sublist(
          availableTimes.length - _bufferCount,
        );

        // Keep current frame if possible
        if (currentFrame >= availableTimes.length) {
          currentFrame = availableTimes.isNotEmpty
              ? availableTimes.length - 1
              : 0;
        }

        _activeIndex = currentFrame;
      });
    }
  }

  // ============================
  // Initialize Double Buffer Layers
  // ============================
  Future<void> _initializePermanentLayers() async {
    // Empty initial gps user location source
    await _controller!.addGeoJsonSource("user_position_source", {
      "type": "FeatureCollection",
      "features": [],
    });

    await _controller!.addCircleLayer(
      "user_position_source",
      "user_position_layer",
      CircleLayerProperties(
        visibility: _gpsLocationVisible ? "visible" : "none",
        circleRadius: 6,
        circleColor: "#2196F3",
        circleStrokeColor: "#FFFFFF",
        circleStrokeWidth: 2,
        circleOpacity: 1.0,
      ),
    );

    // Empty initial tap location source
    await _controller!.addGeoJsonSource("tap_position_source", {
      "type": "FeatureCollection",
      "features": [],
    });

    await _controller!.addCircleLayer(
      "tap_position_source",
      "tap_position_layer",
      CircleLayerProperties(
        visibility: _tapLocationVisible ? "visible" : "none",
        circleRadius: 6,
        circleColor: "#F44336",
        circleStrokeColor: "#FFFFFF",
        circleStrokeWidth: 2,
        circleOpacity: 1.0,
      ),
    );
  }

  Future<void> _initializeLayers() async {
    if (selectedProduct == "none") {
      // // Cleanup any leftover layers
      for (int i = 0; i < _bufferCount; i++) {
        try {
          await _controller!.removeLayer("goes-layer-$i");
        } catch (_) {}
        try {
          await _controller!.removeSource("goes-source-$i");
        } catch (_) {}
      }
    }

    if (_controller == null || availableTimes.isEmpty) return;

    // // Cleanup any leftover layers
    for (int i = 0; i < _bufferCount; i++) {
      try {
        await _controller!.removeLayer("goes-layer-$i");
      } catch (_) {}
      try {
        await _controller!.removeSource("goes-source-$i");
      } catch (_) {}
    }

    // Initialize buffers
    for (int i = 0; i < _bufferCount; i++) {
      int frameIndex = i % availableTimes.length;

      await _controller!.addSource(
        "goes-source-$i",
        RasterSourceProperties(
          tiles: [
            "$baseUrlTiles/tiles/$selectedProduct/${availableTimes[frameIndex]}/{z}/{x}/{y}.png",
          ],
          tileSize: 256.0,
        ),
      );

      await _controller!.addLayer(
        "goes-source-$i",
        "goes-layer-$i",
        RasterLayerProperties(
          visibility: frameIndex == currentFrame ? "visible" : "none",
          rasterFadeDuration: 0.0,
        ),
        belowLayerId: "road_service_case",
      );
    }

    _layersInitialized = true;
  }

  // ============================
  // Update satellite data timestamps
  // ============================

  // in case new sat data comes in
  Future<void> _refreshTimes() async {
    if (!mounted || selectedProduct == "none") return;

    final oldTimes = List<String>.from(availableTimes);

    await _fetchTimes();

    // If timestamps changed, reinitialize layers
    if (oldTimes.isNotEmpty &&
        availableTimes.isNotEmpty &&
        oldTimes.last != availableTimes.last) {
      await _initializeLayers();
    }
  }

  // ============================
  // Smooth Crossfade Transition
  // ============================

  Future<void> _transitionToFrame() async {
    if (_controller == null || !_layersInitialized) return;

    final newFrame = currentFrame;
    if (newFrame == _activeIndex) return;

    final oldLayerId = "goes-layer-$_activeIndex";
    final newLayerId = "goes-layer-$newFrame";

    // Apply both changes without awaiting between them
    await Future.wait([
      _controller!.setLayerProperties(
        newLayerId,
        const RasterLayerProperties(
          visibility: "visible",
          rasterFadeDuration: 0.0,
        ),
      ),
      _controller!.setLayerProperties(
        oldLayerId,
        const RasterLayerProperties(
          visibility: "none",
          rasterFadeDuration: 0.0,
        ),
      ),
    ]);

    _activeIndex = newFrame;
  }

  // ============================
  // Frame Control
  // ============================

  void _setFrame(int index) {
    setState(() {
      currentFrame = index;
    });
    _transitionToFrame();
  }

  void _play() {
    if (isPlaying || availableTimes.isEmpty) return;

    setState(() => isPlaying = true);

    _animationTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      int next = (currentFrame + 1) % availableTimes.length;
      _setFrame(next);
    });
  }

  void _pause() {
    _animationTimer?.cancel();
    setState(() => isPlaying = false);
  }

  void _togglePlay() {
    isPlaying ? _pause() : _play();
  }

  // ============================
  // Product Change
  // ============================

  Future<void> _changeProduct(String product) async {
    _pause();

    setState(() {
      selectedProduct = product;
      availableTimes = [];
      _layersInitialized = false;
    });

    await _fetchTimes();
    await _initializeLayers();
  }

  void _openProductSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(
        context,
      ).colorScheme.primary.withValues(alpha: 0.95),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Select Satellite Product",
                style: TextStyle(
                  // color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              ...products.map(
                (product) => ListTile(
                  title: Text(
                    // product.toUpperCase(),
                    _productLabels[product] ?? product.toUpperCase(),
                    style: const TextStyle(color: Colors.white),
                  ),
                  trailing: selectedProduct == product
                      ? const Icon(Icons.check, color: Colors.green)
                      : null,
                  onTap: () {
                    Navigator.pop(context);
                    _changeProduct(product);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _updateTapPosition() async {
    if (_tapLocationVisible) {
      // disable horizon circles
      _removeDistanceCircles();
      _removeHorizonCircles();

      // if a previous tap location is active, remove it
      try {
        await _controller!.removeLayer("tap-position-layer");
      } catch (_) {}
      try {
        await _controller!.removeSource("tap-position-layer");
      } catch (_) {}

      // create a marker and place it in tap position
      final geoJson = {
        "type": "FeatureCollection",
        "features": [
          {
            "type": "Feature",
            "geometry": {
              "type": "Point",
              "coordinates": [_tapPosition.longitude, _tapPosition.latitude],
            },
          },
        ],
      };
      await _controller!.setGeoJsonSource("tap_position_source", geoJson);

      // if horizon circles were active, show them in new tap coords.
      if (_distanceCirclesVisible) {
        _addDistanceCircles(_tapPosition);
      }

      if (_horizonCirclesVisible) {
        _addHorizonCircles(_tapPosition);
      }
    }

    await _controller!.setLayerVisibility(
      "tap_position_layer",
      _tapLocationVisible,
    );
  }

  // ============================
  // Distance Circles (Real meters)
  // ============================

  void _removeHorizonCircles() {
    try {
      _controller!.removeLayer("horizon_circles_layer");
    } catch (_) {}
    try {
      _controller!.removeSource("horizon_circles_source");
    } catch (_) {}
  }

  void _removeDistanceCircles() {
    try {
      _controller!.removeLayer("distance_circles_layer");
    } catch (_) {}
    try {
      _controller!.removeSource("distance_circles_source");
    } catch (_) {}
  }

  Future<void> _addHorizonCircles(Position pos) async {
    if (_controller == null) return;

    const radii = [5500.0, 19200.0, 35500.0]; // meters

    // Remove old source/layer if exists
    _removeHorizonCircles();

    List features = [];

    for (double radius in radii) {
      final circleCoords = _generateCircle(pos.latitude, pos.longitude, radius);

      features.add({
        "type": "Feature",
        "geometry": {
          "type": "Polygon",
          "coordinates": [circleCoords],
        },
        "properties": {"radius": radius},
      });
    }

    final geoJson = {"type": "FeatureCollection", "features": features};

    await _controller!.addGeoJsonSource("horizon_circles_source", geoJson);

    // Add only border (no fill layer)
    await _controller!.addLineLayer(
      "horizon_circles_source",
      "horizon_circles_layer",
      LineLayerProperties(
        lineColor: "#00FFFF",
        lineWidth: 1.0,
        lineOpacity: 0.8,
      ),
      belowLayerId: "user_position_layer",
    );
  }

  Future<void> _addDistanceCircles(Position pos) async {
    if (_controller == null) return;

    const radii = [50000.0, 100000.0, 200000.0]; // meters

    // Remove old source/layer if exists
    _removeDistanceCircles();

    List features = [];

    for (double radius in radii) {
      final circleCoords = _generateCircle(pos.latitude, pos.longitude, radius);

      features.add({
        "type": "Feature",
        "geometry": {
          "type": "Polygon",
          "coordinates": [circleCoords],
        },
        "properties": {"radius": radius},
      });
    }

    final geoJson = {"type": "FeatureCollection", "features": features};

    await _controller!.addGeoJsonSource("distance_circles_source", geoJson);

    // Add only border (no fill layer)
    await _controller!.addLineLayer(
      "distance_circles_source",
      "distance_circles_layer",
      LineLayerProperties(
        lineColor: "#E4EBEB",
        lineWidth: 1.0,
        lineOpacity: 1.0,
        lineDasharray: [2.0, 2.0], // dash length, gap length
      ),
      belowLayerId: "user_position_layer",
    );
  }

  List<List<double>> _generateCircle(
    double lat,
    double lon,
    double radiusMeters,
  ) {
    const int points = 128;
    const double earthRadius = 6378137.0;

    final double angularDistance = radiusMeters / earthRadius;
    final double latRad = lat * pi / 180.0;
    final double lonRad = lon * pi / 180.0;

    List<List<double>> coordinates = [];

    for (int i = 0; i <= points; i++) {
      final double bearing = 2 * pi * i / points;

      final double newLat = asin(
        sin(latRad) * cos(angularDistance) +
            cos(latRad) * sin(angularDistance) * cos(bearing),
      );

      final double newLon =
          lonRad +
          atan2(
            sin(bearing) * sin(angularDistance) * cos(latRad),
            cos(angularDistance) - sin(latRad) * sin(newLat),
          );

      coordinates.add([newLon * 180.0 / pi, newLat * 180.0 / pi]);
    }

    return coordinates;
  }

  // ============================
  // Timestamp Box
  // ============================

  String _getFrameTimestamp() {
    if (availableTimes.isEmpty) {
      return "";
    }

    String rawTimestamp = availableTimes[currentFrame];
    rawTimestamp = "${rawTimestamp.replaceAll("_", "T")}Z";

    // Timestamp formatting
    if (rawTimestamp.length == 16) {
      // Define input format
      DateTime utc = DateTime.parse(rawTimestamp);
      DateTime localTime = utc.toLocal();
      if (localTime.second >= 30) {
        localTime = localTime.add(Duration(minutes: 1));
      }
      return DateFormat("MMMM d, HH:mm").format(localTime);
    } else {
      return "";
    }
  }

  Future<void> _updateUserLocation() async {
    if (_gpsLocationVisible) {
      _removeDistanceCircles();
      _removeHorizonCircles();

      final userPosition = await getGpsPosition();

      setState(() {
        _userPosition = userPosition;
      });

      final geoJson = {
        "type": "FeatureCollection",
        "features": [
          {
            "type": "Feature",
            "geometry": {
              "type": "Point",
              "coordinates": [_userPosition.longitude, _userPosition.latitude],
            },
          },
        ],
      };

      await _controller!.setGeoJsonSource("user_position_source", geoJson);

      // if horizon circles were active, show them in new tap coords.
      if (_distanceCirclesVisible) {
        _addDistanceCircles(_userPosition);
      }

      if (_horizonCirclesVisible) {
        _addHorizonCircles(_userPosition);
      }
    }

    await _controller!.setLayerVisibility(
      "user_position_layer",
      _gpsLocationVisible,
    );
  }

  Future<void> _centerOnUser() async {
    await Future.delayed(Duration(milliseconds: 1000));
    await _controller!.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(_userPosition.latitude, _userPosition.longitude),
        5.5, // zoom level
      ),
      duration: Duration(milliseconds: 2000),
    );
  }

  void _onSliderChanged(double value) {
    final newFrame = value.toInt();

    setState(() {
      currentFrame = newFrame;
    });

    // Debounced Map update
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    _debounce = Timer(_debounceDuration, () {
      _transitionToFrame(); // Only triggers after 100ms of inactivity
    });
  }

  // ============================
  // UI
  // ============================

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        MapLibreMap(
          styleString: "styles/map_style.json",
          initialCameraPosition: const CameraPosition(
            target: LatLng(-15, -50),
            zoom: 3,
          ),
          onMapCreated: _onMapCreated,
          cameraTargetBounds: CameraTargetBounds(
            LatLngBounds(
              southwest: LatLng(-45.0, -90.0),
              northeast: LatLng(20.0, -20.0),
            ),
          ),
          onMapClick: (point, latlon) {
            setState(() {
              _gpsLocationVisible = false;
              _tapLocationVisible = true;
              _tapPosition = copyPositionWith(
                _tapPosition,
                latitude: latlon.latitude,
                longitude: latlon.longitude,
              );
            });
            _updateUserLocation();
            _updateTapPosition();
          },
          minMaxZoomPreference: MinMaxZoomPreference(2.5, 17),
          attributionButtonMargins: Point(-100, -100),
          rotateGesturesEnabled: false,
          tiltGesturesEnabled: false,
          scrollGesturesEnabled: true,
          zoomGesturesEnabled: true,
          compassEnabled: false,
        ),
        SafeArea(
          child: Stack(
            children: [
              // Positioned(top: 10, left: 10, child: _buildTimestampBox()),
              Positioned(
                top: 30,
                right: 10,
                child: FloatingActionButton(
                  backgroundColor: Theme.of(context)
                      .floatingActionButtonTheme
                      .backgroundColor
                      ?.withValues(alpha: 0.95),
                  onPressed: _openProductSelector,
                  child: const Icon(Icons.layers),
                ),
              ),

              Positioned(
                bottom: 155,
                right: 10,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_circleMenuExpanded) ...[
                      FloatingActionButton.extended(
                        heroTag: "distance_btn",
                        label: const Text("Distance"),
                        icon: const Icon(Icons.radio_button_unchecked),
                        backgroundColor: _distanceCirclesVisible
                            ? Colors.blue
                            : Theme.of(context)
                                  .floatingActionButtonTheme
                                  .backgroundColor
                                  ?.withValues(alpha: 0.95),
                        onPressed: () {
                          setState(() {
                            Position circlesPosition = _gpsLocationVisible
                                ? _userPosition
                                : _tapPosition;

                            if (_distanceCirclesVisible) {
                              _removeDistanceCircles();
                              _distanceCirclesVisible = false;
                            } else {
                              _addDistanceCircles(circlesPosition);
                              _distanceCirclesVisible = true;
                            }
                          });
                        },
                      ),

                      const SizedBox(width: 8),

                      FloatingActionButton.extended(
                        heroTag: "horizon_btn",
                        label: const Text("Horizon"),
                        icon: const Icon(Icons.circle_outlined),
                        backgroundColor: _horizonCirclesVisible
                            ? Colors.blue
                            : Theme.of(context)
                                  .floatingActionButtonTheme
                                  .backgroundColor
                                  ?.withValues(alpha: 0.95),
                        onPressed: () {
                          setState(() {
                            Position circlesPosition = _gpsLocationVisible
                                ? _userPosition
                                : _tapPosition;

                            if (_horizonCirclesVisible) {
                              _removeHorizonCircles();
                              _horizonCirclesVisible = false;
                            } else {
                              _addHorizonCircles(circlesPosition);
                              _horizonCirclesVisible = true;
                            }
                          });
                        },
                      ),

                      const SizedBox(width: 8),
                    ],

                    FloatingActionButton(
                      heroTag: "circle_menu",
                      backgroundColor: Theme.of(context)
                          .floatingActionButtonTheme
                          .backgroundColor
                          ?.withValues(alpha: 0.95),
                      onPressed: () {
                        setState(() {
                          _circleMenuExpanded = !_circleMenuExpanded;
                        });
                      },
                      child: Icon(
                        _circleMenuExpanded
                            ? Icons.close
                            : Icons.circle_outlined,
                      ),
                    ),
                  ],
                ),
              ),

              Positioned(
                bottom: 90,
                right: 10,
                child: FloatingActionButton(
                  backgroundColor: Theme.of(context)
                      .floatingActionButtonTheme
                      .backgroundColor
                      ?.withValues(alpha: 0.95),
                  onPressed: () {
                    setState(() {
                      _gpsLocationVisible = true;
                      _tapLocationVisible = false;
                    });

                    _updateTapPosition();
                    _updateUserLocation();
                    _centerOnUser();
                  },
                  child: const Icon(Icons.my_location),
                ),
              ),
              if (selectedProduct != "none" && availableTimes.isNotEmpty)
                Positioned(
                  height: 80,
                  left: 0,
                  right: 0,
                  bottom: 5,
                  child: Card(
                    color: Theme.of(context)
                        .floatingActionButtonTheme
                        .backgroundColor
                        ?.withValues(alpha: 0.95),
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Theme(
                            data: Theme.of(context).copyWith(
                              splashFactory: NoSplash.splashFactory,
                              highlightColor: Colors.transparent,
                              splashColor: Colors.transparent,
                            ),
                            child: IconButton(
                              icon: Icon(
                                isPlaying ? Icons.pause : Icons.play_arrow,
                              ),
                              iconSize: 40,
                              highlightColor: Colors.black.withValues(
                                alpha: 0.0,
                              ),
                              enableFeedback: false,
                              onPressed: _togglePlay,
                            ),
                          ),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 14.0),
                                  child: Text(
                                    _getFrameTimestamp(),
                                    style: const TextStyle(
                                      color: Color(0xFFBFC5CF),
                                      height: 0.4,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 3,
                                    activeTrackColor: Color(0xFFBFC5CF),
                                    inactiveTrackColor: Color(0xFF20274A),
                                    thumbColor: Colors.blueGrey.shade500,
                                    overlayColor: Colors.blue.withValues(
                                      alpha: 0.0,
                                    ),
                                    thumbShape: HandleThumbShape(),
                                    thumbSize: const WidgetStatePropertyAll(
                                      Size(17, 17),
                                    ),
                                  ),
                                  child: Slider(
                                    min: 0,
                                    max: (availableTimes.length - 1).toDouble(),
                                    value: currentFrame.toDouble(),
                                    divisions: availableTimes.length - 1,
                                    onChanged: (value) {
                                      _onSliderChanged(value.toDouble());
                                    },
                                    padding: const EdgeInsets.only(
                                      // bottom: 0.0,
                                      left: 15.0,
                                      right: 20.0,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
