class BusInfo {
  final String? id;
  final String name;
  final String number;
  final double distanceKm;
  final String? start;
  final String? end;
  final List<String> stops;
  final double? lat;
  final double? lng;

  const BusInfo({
    this.id,
    required this.name,
    required this.number,
    required this.distanceKm,
    this.start,
    this.end,
    this.stops = const [],
    this.lat,
    this.lng,
  });

  factory BusInfo.fromJson(
    Map<String, dynamic> json, {
    String? id,
    double defaultDistanceKm = 0.0,
  }) {
    final rawNumber = (json['bus_number'] ?? json['busNumber'] ?? json['number'] ?? 'UNKNOWN')
        .toString()
        .trim();

    final rawName = (json['bus_name'] ?? json['busName'] ?? json['routeName'] ?? json['name'] ?? '')
        .toString()
        .trim();
    final name = rawName.isNotEmpty ? rawName : 'Bus $rawNumber';

    final stopsRaw = json['stops'];
    final List<String> stopsList;
    if (stopsRaw is List) {
      stopsList = stopsRaw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
    } else {
      stopsList = const [];
    }

    final rawDistance = json['distance_km'] ?? json['distanceKm'] ?? defaultDistanceKm;
    double parsedDistance = defaultDistanceKm;
    if (rawDistance is num) {
      parsedDistance = rawDistance.toDouble();
    } else if (rawDistance is String) {
      parsedDistance = double.tryParse(rawDistance) ?? defaultDistanceKm;
    }

    final rawLat = json['lat'] ?? json['latitude'];
    final rawLng = json['lng'] ?? json['longitude'];

    return BusInfo(
      id: id ?? json['id']?.toString(),
      name: name,
      number: rawNumber,
      distanceKm: parsedDistance,
      start: (json['start_location'] ?? json['start'])?.toString(),
      end: (json['end_location'] ?? json['end'])?.toString(),
      stops: stopsList,
      lat: rawLat is num ? rawLat.toDouble() : null,
      lng: rawLng is num ? rawLng.toDouble() : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'number': number,
      'distanceKm': distanceKm,
      if (start != null) 'start': start,
      if (end != null) 'end': end,
      'stops': stops,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
    };
  }
}
