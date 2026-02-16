import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:http/http.dart' as http;

class SatellitePage extends StatefulWidget {
  const SatellitePage({Key? key}) : super(key: key);

  @override
  State<SatellitePage> createState() => _SatellitePageState();
}

class _SatellitePageState extends State<SatellitePage> {
  MapLibreMapController? _controller;

  final String baseUrlTimes = "https://tiles.astrotempo.org";
  final String baseUrlTiles = "https://sttiles.astrotempo.org";

  String selectedProduct = "cod";
  List<String> availableTimes = [];
  int currentFrame = 0;

  bool isPlaying = false;
  Timer? _animationTimer;

  bool _layersInitialized = false;
  static const int _bufferCount = 12;
  int _activeIndex = 0;

  Timer? _debounce;
  final Duration _debounceDuration = const Duration(milliseconds: 50);

  final List<String> products = ["cod", "acht", "acha"];

  @override
  void dispose() {
    _animationTimer?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  // ============================
  // Map Initialization
  // ============================

  void _onMapCreated(MapLibreMapController controller) {
    _controller = controller;
    _initialize();
  }

  Future<void> _initialize() async {
    await _fetchTimes();
    await _initializeLayers();
  }

  // ============================
  // Fetch Available Times
  // ============================

  Future<void> _fetchTimes() async {
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

        _activeIndex = 0;
      });
    }
  }

  // ============================
  // Initialize Double Buffer Layers
  // ============================

  Future<void> _initializeLayers() async {
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

    _animationTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) {
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
      backgroundColor: Colors.black,
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
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              ...products.map(
                (product) => ListTile(
                  title: Text(
                    product.toUpperCase(),
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

  // ============================
  // Timestamp Box
  // ============================

  Widget _buildTimestampBox() {
    if (availableTimes.isEmpty) {
      return const SizedBox.shrink();
    }

    final rawTimestamp = availableTimes[currentFrame];

    // Timestamp formatting
    String formatted = rawTimestamp;
    if (rawTimestamp.contains("_") && rawTimestamp.length >= 15) {
      final date = rawTimestamp.split("_")[0];
      final time = rawTimestamp.split("_")[1];

      formatted =
          "${date.substring(0, 4)}-${date.substring(4, 6)}-${date.substring(6, 8)} "
          "${time.substring(0, 2)}:${time.substring(2, 4)}:${time.substring(4, 6)} "
          " UTC";
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Color(0xFF44403B).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        formatted,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
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
    return Scaffold(
      body: Stack(
        children: [
          MapLibreMap(
            styleString:
                "https://basemaps.cartocdn.com/gl/dark-matter-gl-style/style.json",
            initialCameraPosition: const CameraPosition(
              target: LatLng(-15.0, -47.0),
              zoom: 5,
            ),
            onMapCreated: _onMapCreated,
            // onMapIdle: _onMapIdle,
            rotateGesturesEnabled: false,
            tiltGesturesEnabled: false,
            scrollGesturesEnabled: true,
            zoomGesturesEnabled: true,
            compassEnabled: false,
          ),

          SafeArea(
            child: Stack(
              children: [
                Positioned(top: 10, left: 10, child: _buildTimestampBox()),
                Positioned(
                  top: 10,
                  right: 20,
                  child: FloatingActionButton(
                    backgroundColor: Color(0xFF44403B).withValues(alpha: 0.85),
                    onPressed: _openProductSelector,
                    child: const Icon(Icons.satellite_alt, color: Colors.white),
                  ),
                ),

                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 10,
                  child: Card(
                    color: Color(0xFF44403B).withValues(alpha: 0.85),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Player + slider
                          Row(
                            children: [
                              IconButton(
                                icon: Icon(
                                  isPlaying ? Icons.pause : Icons.play_arrow,
                                  color: Colors.white,
                                ),
                                onPressed: _togglePlay,
                              ),
                              if (availableTimes.isNotEmpty)
                                Expanded(
                                  child: Slider(
                                    min: 0,
                                    max: (availableTimes.length - 1).toDouble(),
                                    value: currentFrame.toDouble(),
                                    divisions: availableTimes.length - 1,
                                    onChanged: (value) {
                                      _onSliderChanged(value.toDouble());
                                      // _setFrame(value.toInt());
                                    },
                                  ),
                                ),
                            ],
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
      ),
    );
  }
}
