import 'package:flutter/material.dart';

class BusIllustration extends StatelessWidget {
  const BusIllustration({super.key});

  Widget circle({
    required double size,
    required Color color,
    String? text,
    bool solid = false,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: solid ? color : color.withOpacity(0.15),
        border: Border.all(color: color.withOpacity(0.4), width: 2),
      ),
      alignment: Alignment.center,
      child: text != null
          ? Text(
              text,
              style: TextStyle(
                color: solid ? Colors.black : color,
                fontWeight: FontWeight.bold,
                fontSize: size * 0.18,
              ),
            )
          : null,
    );
  }

  Widget pole(double height) {
    return Container(width: 4, height: height, color: Colors.grey.shade700);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 300,
      child: Stack(
        alignment: Alignment.center,
        children: [
          /// Big dark teal background circle
          Positioned(
            top: 40,
            child: circle(
              size: 200,
              color: const Color(0xFF0A3F52),
              solid: true,
            ),
          ),

          /// Medium teal circles
          Positioned(
            left: 40,
            top: 90,
            child: circle(size: 120, color: const Color(0xFF1E88A8)),
          ),

          Positioned(
            right: 40,
            top: 100,
            child: circle(size: 110, color: const Color(0xFF1E88A8)),
          ),

          Positioned(
            bottom: 60,
            child: circle(size: 100, color: const Color(0xFF1E88A8)),
          ),

          /// STOP white circle
          Positioned(
            right: 70,
            top: 110,
            child: circle(
              size: 95,
              color: Colors.white,
              text: "STOP",
              solid: true,
            ),
          ),

          /// 55 M circle
          Positioned(
            bottom: 40,
            child: circle(
              size: 85,
              color: Colors.white,
              text: "55 M",
              solid: true,
            ),
          ),

          /// Left faded circle
          Positioned(
            left: 20,
            top: 130,
            child: circle(
              size: 95,
              color: Colors.white,
              text: "55.M",
              solid: true,
            ),
          ),

          /// Vertical poles
          Positioned(left: 110, bottom: 20, child: pole(140)),
          Positioned(left: 130, bottom: 20, child: pole(120)),
          Positioned(right: 110, bottom: 20, child: pole(130)),
          Positioned(right: 90, bottom: 20, child: pole(150)),

          /// Bus icon
          Positioned(
            bottom: 10,
            left: 40,
            child: Icon(Icons.directions_bus, size: 40, color: Colors.white),
          ),
        ],
      ),
    );
  }
}
