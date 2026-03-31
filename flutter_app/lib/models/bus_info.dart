class BusInfo {
  /// Firestore document id for the bus (used for `bus_locations/{id}`).
  final String? id;
  final String name;
  final String number;
  final double distanceKm;
  final String? start;
  final String? end;
  final List<String> stops;

  const BusInfo({
    this.id,
    required this.name,
    required this.number,
    required this.distanceKm,
    this.start,
    this.end,
    this.stops = const [],
  });
}

