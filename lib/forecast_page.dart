import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'dart:ui' as ui;

/// =======================================================
/// DATA MODELS
/// =======================================================

class HourlyForecast {
  final DateTime time;
  final double cloud; // 0–100
  final double transparency; // 0–1
  final double temp;
  final double dew;

  HourlyForecast({
    required this.time,
    required this.cloud,
    required this.transparency,
    required this.temp,
    required this.dew,
  });
}

class MoonMinute {
  final DateTime time;
  final double? illumination; // null if below horizon

  MoonMinute({required this.time, required this.illumination});
}

class SunTimes {
  final DateTime sunrise;
  final DateTime sunset;
  final DateTime astronomicalSunrise;
  final DateTime astronomicalSunset;

  SunTimes({
    required this.sunrise,
    required this.sunset,
    required this.astronomicalSunrise,
    required this.astronomicalSunset,
  });
}

class DailyCloudSummary {
  final DateTime day;
  final double c0_6;
  final double c6_12;
  final double c12_18;
  final double c18_24;
  final double moon;

  DailyCloudSummary({
    required this.day,
    required this.c0_6,
    required this.c6_12,
    required this.c12_18,
    required this.c18_24,
    required this.moon,
  });
}

class LocationResult {
  final String name;
  final String country;
  final String? state;
  final double lat;
  final double lon;

  LocationResult({
    required this.name,
    required this.country,
    required this.lat,
    required this.lon,
    this.state,
  });

  factory LocationResult.fromJson(Map<String, dynamic> json) {
    return LocationResult(
      name: json["name"],
      country: json["country"] ?? "",
      state: json["admin1"], // ← state / province
      lat: (json["latitude"] as num).toDouble(),
      lon: (json["longitude"] as num).toDouble(),
    );
  }
}

/// =======================================================
/// PAGE
/// =======================================================

class ForecastPage extends StatefulWidget {
  final double lat;
  final double lon;

  const ForecastPage({super.key, required this.lat, required this.lon});

  @override
  State<ForecastPage> createState() => _ForecastPageState();
}

class _ForecastPageState extends State<ForecastPage> {
  List<HourlyForecast> hourly = [];
  List<MoonMinute> moon = [];
  List<SunTimes> sun = [];

  bool loading = true;
  bool _initialCenteringDone = false;

  final double hourWidth = 35;

  double detailedScrollOffset = 0;
  DateTime? centeredViewTime;
  DateTime? selectedTime;
  late final ScrollController detailedScrollController;
  late final ScrollController dayScrollController;
  bool _syncingScroll = false;

  late double currentLat;
  late double currentLon;

  String locationLabel = "";

  @override
  void initState() {
    super.initState();

    currentLat = widget.lat;
    currentLon = widget.lon;

    detailedScrollController = ScrollController();
    dayScrollController = ScrollController();

    detailedScrollController.addListener(_syncDayScroll);

    fetchData();
    print(currentLat);
    print(currentLon);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final label = await reverseGeocode(currentLat, currentLon - 360.0);

      if (label != null) {
        setState(() {
          locationLabel = label;
        });
      }
    });
  }

  Future<void> fetchData() async {
    try {
      final url =
          "https://forecast.astrotempo.org/forecast"
          "?lat=$currentLat&lon=$currentLon";

      final response = await http.get(Uri.parse(url));

      if (response.statusCode != 200) {
        throw Exception("API error: ${response.statusCode}");
      }

      final json = jsonDecode(response.body);

      if (json["forecast"] == null) {
        throw Exception("Invalid API response");
      }

      hourly = (json["forecast"] as List).map((f) {
        final fh = f["forecast_hour"].toString();

        final utc = DateTime.utc(
          int.parse(fh.substring(0, 4)),
          int.parse(fh.substring(4, 6)),
          int.parse(fh.substring(6, 8)),
          int.parse(fh.substring(8, 10)),
        );

        return HourlyForecast(
          time: utc.toLocal(),
          cloud: (f["cloud"] as num).toDouble(),
          transparency: (f["transparency"] as num).toDouble(),
          temp: (f["temp"] as num).toDouble(),
          dew: (f["dewpoint"] as num).toDouble(),
        );
      }).toList();

      moon =
          (json["moon"] as List?)?.map((m) {
            return MoonMinute(
              time: DateTime.parse(m["time"]).toLocal(),
              illumination: (m["illumination"] as num?)?.toDouble(),
            );
          }).toList() ??
          [];

      sun =
          (json["sun"] as List?)?.map((s) {
            return SunTimes(
              sunrise: DateTime.parse(s["sunrise"]).toLocal(),
              sunset: DateTime.parse(s["sunset"]).toLocal(),
              astronomicalSunrise: DateTime.parse(
                s["astronomical_sunrise"],
              ).toLocal(),
              astronomicalSunset: DateTime.parse(
                s["astronomical_sunset"],
              ).toLocal(),
            );
          }).toList() ??
          [];

      setState(() => loading = false);
    } catch (e) {
      debugPrint("Forecast error: $e");

      setState(() {
        loading = false;
        hourly = [];
      });
    }
  }

  List<DateTime> get forecastDays {
    final days = <DateTime>[];

    for (var h in hourly) {
      final d = DateTime(h.time.year, h.time.month, h.time.day);
      if (!days.contains(d)) {
        days.add(d);
      }
    }

    return days;
  }

  Future<String?> reverseGeocode(double lat, double lon) async {
    try {
      final url =
          "https://nominatim.openstreetmap.org/reverse"
          "?lat=$lat&lon=$lon&format=json";

      final response = await http.get(
        Uri.parse(url),
        headers: {"User-Agent": "astrotempo-app"}, // required by Nominatim
      );

      if (response.statusCode != 200) {
        print("reverse geocode status: ${response.statusCode}");
        return null;
      }

      final json = jsonDecode(response.body);

      final address = json["address"];

      final city =
          address["city"] ??
          address["town"] ??
          address["village"] ??
          address["municipality"];

      final state = address["state"];

      if (city == null) return null;

      return state != null ? "$city, $state" : city;
    } catch (e) {
      debugPrint("Reverse geocode error: $e");
      return null;
    }
  }

  Future<void> loadCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint("Location services disabled");
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint("Location permission denied");
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint("Location permission permanently denied");
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      print(position);

      final label = await reverseGeocode(position.latitude, position.longitude);

      setState(() {
        currentLat = position.latitude;
        currentLon = position.longitude;

        if (currentLon < 0) currentLon += 360;

        if (label != null) locationLabel = label;

        loading = true;
      });

      fetchData();
    } catch (e) {
      debugPrint("Location error: $e");
    }
  }

  Future<List<LocationResult>> searchLocation(String query) async {
    if (query.isEmpty) return [];

    final url =
        "https://geocoding-api.open-meteo.com/v1/search?name=$query&count=10";

    final response = await http.get(Uri.parse(url));

    if (response.statusCode != 200) return [];

    final json = jsonDecode(response.body);

    if (json["results"] == null) return [];

    return (json["results"] as List)
        .map((e) => LocationResult.fromJson(e))
        .toList();
  }

  void openLocationSearch() {
    final controller = TextEditingController();
    List<LocationResult> results = [];

    showModalBottomSheet(
      enableDrag: true,
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final height = MediaQuery.of(context).size.height * 0.9;

        return StatefulBuilder(
          builder: (context, setModalState) {
            return SizedBox(
              height: height,
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 5.0),

                    /// HANDLE
                    SizedBox(
                      height: 20,
                      child: Center(
                        child: Container(
                          width: 60,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.grey,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 15),

                    /// TITLE
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          "Search location",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    /// SEARCH FIELD
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: TextField(
                        controller: controller,
                        decoration: const InputDecoration(
                          hintText: "Enter city name",
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (text) async {
                          final r = await searchLocation(text);
                          setModalState(() => results = r);
                        },
                      ),
                    ),

                    const SizedBox(height: 10),

                    /// RESULTS
                    Expanded(
                      child: ListView.builder(
                        itemCount: results.length,
                        itemBuilder: (context, i) {
                          final loc = results[i];

                          return ListTile(
                            title: Text(
                              loc.state != null
                                  ? "${loc.name}, ${loc.state}"
                                  : loc.name,
                            ),
                            subtitle: Text(loc.country),
                            onTap: () {
                              Navigator.pop(context);

                              setState(() {
                                currentLat = loc.lat;
                                currentLon = loc.lon;

                                if (currentLon < 0) {
                                  currentLon += 360.0;
                                }

                                locationLabel = loc.state != null
                                    ? "${loc.name}, ${loc.state}"
                                    : loc.name;

                                loading = true;
                              });

                              fetchData();
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _syncDayScroll() {
    if (_syncingScroll) return;

    _syncingScroll = true;

    final offset = detailedScrollController.offset;

    // convert hour offset -> day offset
    final dayOffset = offset / (24 * hourWidth) * 47;

    if (dayScrollController.hasClients) {
      dayScrollController.jumpTo(
        dayOffset.clamp(
          dayScrollController.position.minScrollExtent,
          dayScrollController.position.maxScrollExtent,
        ),
      );
    }

    _syncingScroll = false;
  }

  DateTime getCenteredTime(double offset, double screenWidth) {
    final centerPixel = offset + hourWidth / 5;
    final index = (centerPixel / hourWidth).floor().clamp(0, hourly.length - 1);
    return hourly[index].time;
  }

  void jumpToDay(DateTime day, void Function(void Function()) setModalState) {
    final index = hourly.indexWhere(
      (h) =>
          h.time.year == day.year &&
          h.time.month == day.month &&
          h.time.day == day.day &&
          h.time.hour == 0,
    );

    if (index == -1) return;

    final targetOffset = index * hourWidth;

    // detailedScrollController.animateTo(
    //   targetOffset,
    //   duration: const Duration(milliseconds: 350),
    //   curve: Curves.easeOut,
    // );

    detailedScrollController.jumpTo(targetOffset);

    setModalState(() {
      centeredViewTime = hourly[index].time;
    });
  }

  void openDetailedForecast(DateTime centerTime) {
    _initialCenteringDone = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            if (!_initialCenteringDone) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                final index = hourly.indexWhere(
                  (h) => h.time.isAtSameMomentAs(centerTime),
                );

                if (index >= 0) {
                  final screenWidth = MediaQuery.of(context).size.width;

                  final target =
                      index * hourWidth - screenWidth / 2 + 3 * hourWidth / 2;

                  detailedScrollController.jumpTo(max(0, target));

                  setModalState(() {
                    selectedTime = hourly[index].time;
                    centeredViewTime = hourly[index].time;
                  });

                  _initialCenteringDone = true;
                }
              });
            }

            final height = MediaQuery.of(context).size.height * 0.9;

            return SizedBox(
              height: height,
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 5),

                    /// HANDLE (drag down to dismiss)
                    SizedBox(
                      height: 20,
                      child: Center(
                        child: Container(
                          width: 60,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.grey,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 15.0),
                        child: Text("Detailed Forecast"),
                      ),
                    ),

                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 15.0),
                      child: Divider(thickness: 1.0),
                    ),
                    SizedBox(height: 10.0),

                    /// DAY LABELS
                    Padding(
                      padding: const EdgeInsets.only(left: 43.0, right: 18.0),
                      child: SingleChildScrollView(
                        controller: dayScrollController,
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          height: 50,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: forecastDays.map((day) {
                              final isActive =
                                  centeredViewTime != null &&
                                  day.year == centeredViewTime!.year &&
                                  day.month == centeredViewTime!.month &&
                                  day.day == centeredViewTime!.day;

                              final month = DateFormat("MMM").format(day);
                              final dayNum = DateFormat("dd").format(day);

                              return Row(
                                children: [
                                  GestureDetector(
                                    onTap: () {
                                      jumpToDay(day, setModalState);
                                    },
                                    child: Container(
                                      width: 42,
                                      height: 42,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: isActive
                                              ? Colors.orange
                                              : Colors.white.withValues(
                                                  alpha: 0.25,
                                                ),
                                        ),
                                        color: isActive
                                            ? Colors.orange.withValues(
                                                alpha: 0.12,
                                              )
                                            : Colors.transparent,
                                      ),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            month,
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w500,
                                              color: isActive
                                                  ? Colors.orange
                                                  : Colors.white.withValues(
                                                      alpha: 0.7,
                                                    ),
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            dayNum,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: isActive
                                                  ? Colors.orange
                                                  : Colors.white.withValues(
                                                      alpha: 0.8,
                                                    ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),

                    SizedBox(height: 5.0),

                    /// CHART AREA
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18.0,
                        vertical: 8.0,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          /// LEFT ICON LABELS
                          SizedBox(
                            width: 25,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 24),
                                _rowLabel(Icons.cloud, "Cloud"),
                                const SizedBox(height: 10),
                                _rowLabel(Icons.nightlight, "Moon"),
                                const SizedBox(height: 10),
                                _rowLabel(
                                  Icons.square_outlined,
                                  "Transparency",
                                ),
                                const SizedBox(height: 40),
                                _rowLabel(Icons.thermostat, "Temperature"),
                                const SizedBox(height: 20),
                                _rowLabel(Icons.dew_point, "Dew_point"),
                              ],
                            ),
                          ),

                          /// SCROLLABLE FORECAST
                          Expanded(
                            child: NotificationListener<ScrollNotification>(
                              onNotification: (notification) {
                                if (notification is ScrollUpdateNotification) {
                                  final screenWidth = MediaQuery.of(
                                    context,
                                  ).size.width;

                                  setModalState(() {
                                    detailedScrollOffset =
                                        detailedScrollController.offset;

                                    centeredViewTime = getCenteredTime(
                                      detailedScrollOffset,
                                      screenWidth,
                                    );
                                  });
                                }
                                return false;
                              },
                              child: SingleChildScrollView(
                                controller: detailedScrollController,
                                scrollDirection: Axis.horizontal,
                                physics: const ClampingScrollPhysics(),
                                child: SizedBox(
                                  width: hourly.length * hourWidth,
                                  height: 230,
                                  child: CustomPaint(
                                    painter: DetailedForecastPainter(
                                      hourly: hourly,
                                      moon: moon,
                                      sun: sun,
                                      hourWidth: hourWidth,
                                      selectedTime: selectedTime,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    @override
    void dispose() {
      detailedScrollController.dispose();
      dayScrollController.dispose();
      super.dispose();
    }
  }

  Widget _rowLabel(IconData icon, String text) {
    return Icon(icon, size: 15, color: Colors.white70);
    // return Expanded(
    //   child: Row(
    //     mainAxisAlignment: MainAxisAlignment.center,
    //     children: [Icon(icon, size: 14, color: Colors.white70)],
    //   ),
    // );
  }

  Color cloudColor(double v) {
    final colors = [
      const Color(0xFF005BB5),
      const Color(0xFF0069D1),
      const Color(0xFF4EA4FB),
      const Color(0xFFB8DBFF),
      const Color(0xFFE6F2FF),
    ];

    final step = min((v / 20).floor(), 4);
    return colors[step];
  }

  Widget cloudCell(double value, {VoidCallback? onTap}) {
    if (value.isNaN) return const SizedBox(height: 26);

    final color = cloudColor(value);
    final fontColor = value > 60 ? Colors.black87 : Colors.white;

    return GestureDetector(
      onTap: onTap,
      child: Center(
        child: Container(
          width: 32,
          height: 26,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: Text(
            "${value.round()}",
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.normal,
              color: fontColor,
            ),
          ),
        ),
      ),
    );
  }

  List<DailyCloudSummary> buildDailySummary() {
    final Map<DateTime, List<HourlyForecast>> grouped = {};

    for (var h in hourly) {
      final day = DateTime(h.time.year, h.time.month, h.time.day);
      grouped.putIfAbsent(day, () => []).add(h);
    }

    final today = DateTime.now();
    final todayMidnight = DateTime(today.year, today.month, today.day);

    final days =
        grouped.keys
            .where((d) => !d.isBefore(todayMidnight)) // skip past days
            .toList()
          ..sort();

    final List<DailyCloudSummary> result = [];

    for (var d in days.take(6)) {
      final list = grouped[d]!;

      double avg(int start, int end) {
        final subset = list
            .where((h) => h.time.hour >= start && h.time.hour < end)
            .toList();

        if (subset.isEmpty) return double.nan;

        final sum = subset.fold<double>(0, (a, b) => a + b.cloud);
        return sum / subset.length;
      }

      // moon illumination
      double moonIllum = double.nan;

      final moonMatch = moon.firstWhere(
        (m) =>
            m.time.year == d.year &&
            m.time.month == d.month &&
            m.time.day == d.day &&
            m.illumination != null,
        orElse: () => MoonMinute(time: d, illumination: null),
      );

      if (moonMatch.illumination != null) {
        moonIllum = moonMatch.illumination!;
      }

      result.add(
        DailyCloudSummary(
          day: d,
          c0_6: avg(0, 6),
          c6_12: avg(6, 12),
          c12_18: avg(12, 18),
          c18_24: avg(18, 24),
          moon: moonIllum,
        ),
      );
    }

    return result;
  }

  String formatDayLabel(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final d = DateTime(day.year, day.month, day.day);

    if (d == today) {
      return "Today";
    }

    return DateFormat("EEE dd").format(day);
  }

  Widget buildDailyTable() {
    final data = buildDailySummary();
    // final dayFormat = DateFormat("EEE dd");

    Widget textCell(String text) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        child: Text(
          text,
          textAlign: TextAlign.start,
          style: const TextStyle(fontSize: 12),
        ),
      );
    }

    String moonFmt(double v) {
      if (v.isNaN) return "-";
      return "${(v).round()}%";
    }

    Widget compactHeader(String text) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Center(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.65),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
    }

    Widget moonHeader() {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Center(
          child: Icon(
            Icons.nightlight,
            size: 12,
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),
      );
    }

    return Table(
      columnWidths: const {0: FixedColumnWidth(55), 5: FixedColumnWidth(37)},
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          children: [
            const SizedBox(),
            compactHeader("00\u279D06"),
            compactHeader("06\u279D12"),
            compactHeader("12\u279D18"),
            compactHeader("18\u279D24"),
            moonHeader(),
          ],
        ),
        ...data.map(
          (d) => TableRow(
            children: [
              textCell(formatDayLabel(d.day)),
              cloudCell(
                d.c0_6,
                onTap: () {
                  openDetailedForecast(
                    DateTime(d.day.year, d.day.month, d.day.day, 0),
                  );
                },
              ),
              cloudCell(
                d.c6_12,
                onTap: () {
                  openDetailedForecast(
                    DateTime(d.day.year, d.day.month, d.day.day, 6),
                  );
                },
              ),
              cloudCell(
                d.c12_18,
                onTap: () {
                  openDetailedForecast(
                    DateTime(d.day.year, d.day.month, d.day.day, 12),
                  );
                },
              ),
              cloudCell(
                d.c18_24,
                onTap: () {
                  openDetailedForecast(
                    DateTime(d.day.year, d.day.month, d.day.day, 18),
                  );
                },
              ),
              textCell(moonFmt(d.moon)),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.grey[300]),
            SizedBox(height: 10.0),
            Text('Loading forecast'),
          ],
        ),
      );
    }

    if (hourly.isEmpty) {
      return const Center(child: Text("No forecast data"));
    }

    // final totalWidth = hourly.length * hourWidth;

    return SafeArea(
      child: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    locationLabel.isEmpty
                        ? "($currentLat, $currentLon)"
                        : locationLabel,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.my_location),
                  tooltip: "Use current location",
                  onPressed: loadCurrentLocation,
                ),
                IconButton(
                  icon: const Icon(Icons.search),
                  tooltip: "Search location",
                  onPressed: openLocationSearch,
                ),
              ],
            ),
          ),
          SizedBox(
            height: 200.0,
            child: Center(child: Text('For tonight / Now')),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10.0),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.only(
                  left: 15.0,
                  right: 15.0,
                  bottom: 15.0,
                  top: 8.0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Next hours'),
                    Divider(thickness: 1.0),
                    SizedBox(height: 5.0),
                    SizedBox(
                      height: 100,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 20,
                            child: Column(
                              children: [
                                const SizedBox(
                                  height: 35,
                                ), // aligns with hour row
                                _rowLabel(Icons.cloud, "Cloud"),
                                const SizedBox(height: 20),
                                _rowLabel(Icons.nightlight, "Moon"),
                              ],
                            ),
                          ),
                          SizedBox(width: 10.0),
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: SizedBox(
                                width: hourWidth * 36,
                                height: 100,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTapUp: (details) {
                                    final dx = details.localPosition.dx;
                                    final index = (dx / hourWidth).floor();

                                    final painter = NextHoursForecastPainter(
                                      hourly: hourly,
                                      moon: moon,
                                      sun: sun,
                                      hourWidth: hourWidth,
                                    );

                                    final hours = painter.visibleHours;

                                    if (index >= 0 && index < hours.length) {
                                      openDetailedForecast(hours[index].time);
                                    }
                                  },
                                  child: CustomPaint(
                                    painter: NextHoursForecastPainter(
                                      hourly: hourly,
                                      moon: moon,
                                      sun: sun,
                                      hourWidth: hourWidth,
                                    ),
                                  ),
                                ),
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
          SizedBox(height: 20.0),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10.0),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(15.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [Text("Next days"), Divider(), buildDailyTable()],
                ),
              ),
            ),
          ),
          SizedBox(height: 20.0),
        ],
      ),
    );
  }
}

class NextHoursForecastPainter extends CustomPainter {
  final List<HourlyForecast> hourly;
  final List<MoonMinute> moon;
  final List<SunTimes> sun;
  final double hourWidth;

  final double xMargin = 4.0;
  final double yMargin = 20.0;

  NextHoursForecastPainter({
    required this.hourly,
    required this.moon,
    required this.sun,
    required this.hourWidth,
  });

  // Layout
  late final double rowHours = 15 + yMargin;
  late final double rowCloud = 15 + yMargin;
  late final double rowMoon = 15 + yMargin;

  // =======================================================
  // TIME WINDOW (Current hour included)
  // =======================================================

  DateTime get windowStart {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, now.hour);
  }

  DateTime get windowEnd => windowStart.add(const Duration(hours: 36));

  List<HourlyForecast> get visibleHours {
    final start = windowStart;
    final end = windowEnd;

    final filtered =
        hourly
            .where((h) => !h.time.isBefore(start) && h.time.isBefore(end))
            .toList()
          ..sort((a, b) => a.time.compareTo(b.time));

    return filtered.take(36).toList();
  }

  List<MoonMinute> get visibleMoon {
    final start = windowStart;
    final end = windowEnd;

    return moon
        .where((m) => !m.time.isBefore(start) && m.time.isBefore(end))
        .toList();
  }

  List<SunTimes> get visibleSun {
    final start = windowStart;
    final end = windowEnd;

    return sun.where((s) {
      return s.astronomicalSunset.isAfter(start) &&
          s.astronomicalSunrise.isBefore(end);
    }).toList();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final hours = visibleHours;
    if (hours.isEmpty) return;

    final moonData = visibleMoon;
    final sunData = visibleSun;

    double y = 0;

    drawSunShading(canvas, size, hours, sunData);

    drawHourAxis(canvas, y, hours);
    y += rowHours;

    drawCloudRow(canvas, y, hours);
    y += rowCloud;

    drawMoonRow(canvas, y, hours, moonData);
    y += rowMoon;
  }

  // =======================================================
  // HOUR AXIS
  // =======================================================

  void drawHourAxis(Canvas canvas, double y, List<HourlyForecast> hours) {
    final formatter = DateFormat("HH");

    for (int i = 0; i < hours.length; i++) {
      final x = i * hourWidth + hourWidth / 2;

      drawText(
        canvas,
        formatter.format(hours[i].time),
        Offset(x - hourWidth / 5, y + 5),
        fontSize: 11,
        bold: true,
      );
    }
  }

  // =======================================================
  // TIME → X
  // =======================================================

  double timeToX(DateTime t, List<HourlyForecast> hours) {
    final start = hours.first.time;
    final diff = t.difference(start).inMinutes;
    return diff / 60.0 * hourWidth;
  }

  // =======================================================
  // SUN SHADING
  // =======================================================

  void drawSunShading(
    Canvas canvas,
    Size size,
    List<HourlyForecast> hours,
    List<SunTimes> sunData,
  ) {
    for (var s in sunData) {
      final dayStart = timeToX(s.sunrise, hours);
      final dayEnd = timeToX(s.sunset, hours);
      final twilightStart = timeToX(s.astronomicalSunrise, hours);
      final twilightEnd = timeToX(s.astronomicalSunset, hours);

      canvas.drawRect(
        Rect.fromLTRB(dayStart, 0, dayEnd, size.height),
        Paint()..color = const Color(0xFF26305A).withValues(alpha: 1.0),
        // Paint()..color = Colors.white.withValues(alpha: 0.09),
      );

      canvas.drawRect(
        Rect.fromLTRB(twilightStart, 0, dayStart, size.height),
        Paint()..color = const Color(0xFF26305A).withValues(alpha: 0.5),
        // Paint()..color = Colors.white.withValues(alpha: 0.05),
      );

      canvas.drawRect(
        Rect.fromLTRB(dayEnd, 0, twilightEnd, size.height),
        Paint()..color = const Color(0xFF26305A).withValues(alpha: 0.5),
        // Paint()..color = Colors.white.withValues(alpha: 0.05),
      );
    }
  }

  // =======================================================
  // CLOUD ROW
  // =======================================================

  // void drawCloudRow(Canvas canvas, double y, List<HourlyForecast> hours) {
  //   for (int i = 0; i < hours.length; i++) {
  //     final rect = Rect.fromLTWH(
  //       i * hourWidth + xMargin / 2.0,
  //       y,
  //       hourWidth - xMargin,
  //       rowCloud - yMargin,
  //     );
  //
  //     final radius = (rowCloud - yMargin) / 2;
  //     final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
  //
  //     canvas.drawRRect(rrect, Paint()..color = cloudColor(hours[i].cloud));
  //   }
  // }

  void drawCloudRow(Canvas canvas, double y, List<HourlyForecast> hours) {
    for (int i = 0; i < hours.length; i++) {
      final rect = Rect.fromLTWH(
        i * hourWidth + xMargin / 2.0,
        y,
        hourWidth - xMargin,
        rowCloud - yMargin,
      );

      final radius = (rowCloud - yMargin) / 2;
      final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));

      final cloudValue = hours[i].cloud.round();

      canvas.drawRRect(rrect, Paint()..color = cloudColor(hours[i].cloud));

      final fontColor = cloudValue > 60 ? Colors.black87 : Colors.white;

      double xOffset = cloudValue < 10
          ? 3
          : cloudValue < 100
          ? 6
          : 8.5;

      // CLOUD NUMBER
      drawText(
        canvas,
        "$cloudValue",
        Offset(
          rect.left + rect.width / 2 - xOffset,
          rect.top + rect.height / 2 - 6,
        ),
        fontSize: 10,
        fontColor: fontColor,
      );
    }
  }

  Color cloudColor(double v) {
    final colors = [
      const Color(0xFF005BB5),
      const Color(0xFF0069D1),
      const Color(0xFF4EA4FB),
      const Color(0xFFB8DBFF),
      const Color(0xFFE6F2FF),
    ];
    final step = min((v / 20).floor(), 4);
    return colors[step];
  }

  // =======================================================
  // MOON ROW
  // =======================================================

  void drawMoonRow(
    Canvas canvas,
    double y,
    List<HourlyForecast> hours,
    List<MoonMinute> moonData,
  ) {
    for (var m in moonData) {
      if (m.illumination == null) continue;

      final x = timeToX(m.time, hours);

      canvas.drawRect(
        Rect.fromLTWH(x, y, 2, rowMoon - yMargin),
        Paint()..color = cloudColor(m.illumination!),
      );
    }
  }

  void drawText(
    Canvas canvas,
    String text,
    Offset offset, {
    Color fontColor = Colors.white,
    double fontSize = 10,
    bool bold = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          color: fontColor,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// =======================================================
/// CUSTOM PAINTER
/// =======================================================

class DetailedForecastPainter extends CustomPainter {
  final List<HourlyForecast> hourly;
  final List<MoonMinute> moon;
  final List<SunTimes> sun;
  final double hourWidth;
  final DateTime? selectedTime;

  final double xMargin = 4.0;
  final double yMargin = 10.0;

  DetailedForecastPainter({
    required this.hourly,
    required this.moon,
    required this.sun,
    required this.hourWidth,
    this.selectedTime,
  });

  // Layout
  final double rowHours = 25;
  late final double rowCloud = 15 + yMargin;
  late final double rowMoon = 15 + yMargin;
  late final double rowTrans = 25 + yMargin;
  final double rowTemp = 100;

  void drawSelectedTime(Canvas canvas, Size size) {
    if (selectedTime == null) return;

    final x = timeToX(selectedTime!);

    // subtle highlight band
    canvas.drawRect(
      Rect.fromLTWH(x, 0, hourWidth, size.height),
      Paint()..color = Colors.orange.withValues(alpha: 0.12),
    );

    // center line
    // canvas.drawLine(
    //   Offset(x, 0),
    //   Offset(x, size.height),
    //   Paint()
    //     ..color = Colors.orange
    //     ..strokeWidth = 3,
    // );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (hourly.isEmpty) return;

    double y = 0;

    drawSunShading(canvas, size);
    drawSelectedTime(canvas, size);

    drawHourAxis(canvas, y);
    y += rowHours;

    drawCloudRow(canvas, y);
    y += rowCloud;

    drawMoonRow(canvas, y);
    y += rowMoon;

    drawTransparencyRow(canvas, y);
    y += rowTrans;

    drawTemperatureRow(canvas, y);

    // drawNowLine(canvas, size);
  }

  // =======================================================
  // HOUR AXIS
  // =======================================================

  void drawHourAxis(Canvas canvas, double y) {
    final formatter = DateFormat("HH");

    for (int i = 0; i < hourly.length; i++) {
      final x = i * hourWidth + hourWidth / 2;

      drawText(
        canvas,
        formatter.format(hourly[i].time),
        Offset(x - hourWidth / 5, y + 5),
        fontSize: 11,
        bold: true,
      );

      // vertical grid line
      canvas.drawLine(
        Offset(i * hourWidth, y),
        Offset(i * hourWidth, 360),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.05)
          ..strokeWidth = 1,
      );
    }

    // // Day labels at noon
    // final noonTimes = <DateTime>{};
    // for (var h in hourly) {
    //   if (h.time.hour == 12) {
    //     noonTimes.add(DateTime(h.time.year, h.time.month, h.time.day, 12));
    //   }
    // }
    //
    // for (var n in noonTimes) {
    //   final x = timeToX(n);
    //
    //   drawText(
    //     canvas,
    //     DateFormat("EEE dd MMM").format(n),
    //     Offset(x - 40, y - 2),
    //     fontSize: 13,
    //     bold: true,
    //   );
    // }
  }

  // =======================================================
  // TIME → X
  // =======================================================

  double timeToX(DateTime t) {
    final start = hourly.first.time;
    final diff = t.difference(start).inMinutes;
    return diff / 60.0 * hourWidth;
  }

  // =======================================================
  // SUN SHADING
  // =======================================================

  void drawSunShading(Canvas canvas, Size size) {
    for (var s in sun) {
      final dayStart = timeToX(s.sunrise);
      final dayEnd = timeToX(s.sunset);
      final twilightStart = timeToX(s.astronomicalSunrise);
      final twilightEnd = timeToX(s.astronomicalSunset);

      canvas.drawRect(
        Rect.fromLTRB(dayStart, 0, dayEnd, size.height),
        Paint()..color = const Color(0xFF26305A).withValues(alpha: 1.0),
        // Paint()..color = Colors.white.withValues(alpha: 0.09),
      );

      canvas.drawRect(
        Rect.fromLTRB(twilightStart, 0, dayStart, size.height),
        Paint()..color = const Color(0xFF26305A).withValues(alpha: 0.5),
        // Paint()..color = Colors.white.withValues(alpha: 0.05),
      );

      canvas.drawRect(
        Rect.fromLTRB(dayEnd, 0, twilightEnd, size.height),
        Paint()..color = const Color(0xFF26305A).withValues(alpha: 0.5),
        // Paint()..color = Colors.white.withValues(alpha: 0.05),
      );
    }
  }

  // =======================================================
  // CLOUD ROW
  // =======================================================

  void drawCloudRow(Canvas canvas, double y) {
    for (int i = 0; i < hourly.length; i++) {
      final rect = Rect.fromLTWH(
        i * hourWidth + xMargin / 2.0,
        y,
        hourWidth - xMargin,
        rowCloud - yMargin,
      );

      final radius = (rowCloud - yMargin) / 2;
      final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));

      final cloudValue = hourly[i].cloud.round();

      canvas.drawRRect(rrect, Paint()..color = cloudColor(hourly[i].cloud));

      final fontColor = cloudValue > 60 ? Colors.black87 : Colors.white;

      double xOffset = cloudValue < 10
          ? 3
          : cloudValue < 100
          ? 6
          : 8.5;

      // CLOUD NUMBER
      drawText(
        canvas,
        "$cloudValue",
        Offset(
          rect.left + rect.width / 2 - xOffset,
          rect.top + rect.height / 2 - 6,
        ),
        fontSize: 10,
        fontColor: fontColor,
      );
    }
  }

  Color cloudColor(double v) {
    final colors = [
      Color(0xFF005BB5),
      Color(0xFF0069D1),
      Color(0xFF4EA4FB),
      Color(0xFFB8DBFF),
      Color(0xFFE6F2FF),
    ];
    final step = min((v / 20).floor(), 4);
    return colors[step];
  }

  // =======================================================
  // MOON ROW
  // =======================================================

  void drawMoonRow(Canvas canvas, double y) {
    for (var m in moon) {
      if (m.illumination == null) continue;

      final x = timeToX(m.time);

      canvas.drawRect(
        Rect.fromLTWH(x, y, 2, rowMoon - yMargin),
        Paint()..color = cloudColor(m.illumination!),
      );
    }
  }

  // =======================================================
  // TRANSPARENCY
  // =======================================================

  void drawTransparencyRow(Canvas canvas, double y) {
    for (int i = 0; i < hourly.length; i++) {
      final rect = Rect.fromLTWH(
        i * hourWidth + xMargin / 2.0,
        y,
        hourWidth - xMargin,
        rowTrans - yMargin - 10.0,
      );
      final radius = (rowCloud - yMargin) / 2;
      final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));

      canvas.drawRRect(
        rrect,
        Paint()..color = cloudColor((1 - hourly[i].transparency) * 100),
      );
    }
  }

  // =======================================================
  // TEMP + DEW
  // =======================================================

  void drawTemperatureRow(Canvas canvas, double y) {
    final temps = hourly.map((e) => e.temp).toList();
    final dew = hourly.map((e) => e.dew).toList();

    final minT = min(temps.reduce(min), dew.reduce(min));
    final maxT = max(temps.reduce(max), dew.reduce(max));

    final tempPath = Path();
    final dewPath = Path();

    for (int i = 0; i < hourly.length; i++) {
      final x = i * hourWidth + hourWidth / 2;

      final tempNorm = (hourly[i].temp - minT) / (maxT - minT);
      final dewNorm = (hourly[i].dew - minT) / (maxT - minT);

      final tempY = y + rowTemp * (1 - tempNorm);
      final dewY = y + rowTemp * (1 - dewNorm);

      if (i == 0) {
        tempPath.moveTo(x, tempY);
        dewPath.moveTo(x, dewY);
      } else {
        tempPath.lineTo(x, tempY);
        dewPath.lineTo(x, dewY);
      }

      // Temperature label
      drawText(
        canvas,
        hourly[i].temp.toStringAsFixed(0),
        Offset(x - 10, tempY - 14),
      );

      // Dew label
      drawText(
        canvas,
        hourly[i].dew.toStringAsFixed(0),
        Offset(x - 10, dewY + 4),
        fontSize: 9,
      );
    }

    canvas.drawPath(
      tempPath,
      Paint()
        ..color = Colors.orange
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke,
    );

    canvas.drawPath(
      dewPath,
      Paint()
        ..color = Colors.green
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
  }

  // =======================================================
  // NOW LINE
  // =======================================================

  void drawNowLine(Canvas canvas, Size size) {
    final now = DateTime.now();
    final x = timeToX(now);

    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      Paint()
        ..color = Colors.red
        ..strokeWidth = 3,
    );
  }

  void drawText(
    Canvas canvas,
    String text,
    Offset offset, {
    Color fontColor = Colors.white,
    double fontSize = 10,
    bool bold = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          color: fontColor,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
