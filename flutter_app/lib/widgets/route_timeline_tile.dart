import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Where a stop is relative to the bus.
enum TimelineStopState { passed, current, next, upcoming }

/// One stop in the vertical route timeline ("Where is my Train" style).
///
/// Each tile draws its stop dot plus the connector down to the next stop; the
/// connector overflows into the next tile so consecutive tiles join up. Tiles
/// must be laid out at exactly [height] (e.g. `ListView(itemExtent: ...)`) so
/// the bus icon lands at the right place between two stops.
class RouteTimelineTile extends StatelessWidget {
  static const double height = 72;
  static const double _railWidth = 48;
  static const double _dotY = 20;

  static const Color _passedColor = AppColors.ink;
  static const Color _aheadColor = AppColors.divider;

  final String name;

  /// Position in the route (0 = start).
  final int index;
  final int totalStops;
  final TimelineStopState state;

  /// How much of the connector below this stop the bus has covered (0–1).
  final double connectorProgress;

  /// When the bus is between this stop and the next, how far along (0–1).
  final double? busFraction;

  /// Greys out the bus icon when the last location is old.
  final bool busIsStale;

  const RouteTimelineTile({
    super.key,
    required this.name,
    required this.index,
    required this.totalStops,
    this.state = TimelineStopState.upcoming,
    this.connectorProgress = 0,
    this.busFraction,
    this.busIsStale = false,
  });

  bool get _isFirst => index == 0;
  bool get _isLast => index == totalStops - 1;

  String get _label => _isFirst
      ? 'Start'
      : _isLast
          ? 'Destination'
          : 'Stop $index';

  String? get _statusText => switch (state) {
        TimelineStopState.current => 'Bus is here',
        TimelineStopState.next => 'Next stop',
        TimelineStopState.passed => 'Passed',
        TimelineStopState.upcoming => null,
      };

  @override
  Widget build(BuildContext context) {
    final status = _statusText;
    final isHighlighted = state == TimelineStopState.current || state == TimelineStopState.next;

    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _railWidth,
            height: height,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                if (!_isLast) ..._connector(),
                Positioned(top: _dotY - 8, child: _dot()),
                if (state == TimelineStopState.current)
                  Positioned(top: _dotY - 14, child: _busIcon())
                else if (busFraction != null)
                  Positioned(top: _dotY - 14 + busFraction! * height, child: _busIcon()),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: _dotY - 10, right: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body.copyWith(
                      fontFamily: isHighlighted ? AppFonts.display : AppFonts.body,
                      color: state == TimelineStopState.passed ? AppColors.muted : AppColors.ink,
                      fontSize: isHighlighted ? 17 : 15,
                      fontWeight: isHighlighted ? FontWeight.w700 : FontWeight.w500,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    status == null ? _label : '$_label · $status',
                    style: AppText.label.copyWith(
                      color: isHighlighted ? AppColors.violet : AppColors.faint,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The line from this stop's dot to the next stop's dot, split into the
  /// covered part (above the bus) and the part still ahead.
  List<Widget> _connector() {
    final progress = connectorProgress.clamp(0.0, 1.0);
    return [
      Positioned(
        top: _dotY,
        height: height,
        child: Container(width: 4, color: _aheadColor),
      ),
      if (progress > 0)
        Positioned(
          top: _dotY,
          height: height * progress,
          child: Container(width: 4, color: _passedColor),
        ),
    ];
  }

  Widget _dot() {
    final reached = state == TimelineStopState.passed || state == TimelineStopState.current;
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: reached ? _passedColor : AppColors.paper,
        border: Border.all(
          color: state == TimelineStopState.next
              ? AppColors.violet
              : reached
                  ? _passedColor
                  : AppColors.faint,
          width: 3,
        ),
      ),
    );
  }

  Widget _busIcon() {
    return Container(
      key: const ValueKey('timeline_bus_icon'),
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: busIsStale ? AppColors.faint : AppColors.sun,
        border: Border.all(color: AppColors.ink, width: 2),
      ),
      child: const Icon(Icons.directions_bus, size: 16, color: AppColors.ink),
    );
  }
}
