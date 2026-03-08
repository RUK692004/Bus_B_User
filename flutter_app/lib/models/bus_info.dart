class BusInfo {
  final String name;
  final String number;
  final double distanceKm;
  final String? start;
  final String? end;
  final List<String> stops;

  const BusInfo({
    required this.name,
    required this.number,
    required this.distanceKm,
    this.start,
    this.end,
    this.stops = const [],
  });
}

