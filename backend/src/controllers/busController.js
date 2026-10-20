'use strict';

const { query } = require('../db');

// ---------------------------------------------------------------------------
// GET /api/buses/search?number=...
// ---------------------------------------------------------------------------
const searchBus = async (req, res) => {
  const { number } = req.query;

  if (!number) {
    return res.status(400).json({ message: 'Query param "number" is required.' });
  }

  try {
    const result = await query(
      `SELECT id, bus_number, bus_name, start_location, end_location, stops
       FROM buses
       WHERE LOWER(bus_number) = LOWER($1)
       LIMIT 1`,
      [number]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ message: 'Bus not found.' });
    }

    return res.json({ bus: result.rows[0] });
  } catch (err) {
    console.error('[busController.searchBus]', err.message);
    return res.status(500).json({ message: 'Internal server error.' });
  }
};

// ---------------------------------------------------------------------------
// GET /api/buses/trips?from=...&to=...
// Matches buses where `from` appears before `to` in the ordered route
// (start_location -> stops[] -> end_location).
// ---------------------------------------------------------------------------
const searchTrips = async (req, res) => {
  const { from, to } = req.query;

  if (!from || !to) {
    return res.status(400).json({ message: 'Query params "from" and "to" are required.' });
  }

  try {
    // route_stops lists every bus's stops with their position along the route
    // (0 = start, 1..N = stops, N+1 = end). For each bus, take the first position
    // of `from` and of `to`, and keep the bus when `from` comes first.
    const result = await query(
      `WITH route_stops AS (
        SELECT b.id, 0 AS idx, LOWER(b.start_location) AS name
        FROM buses b
        UNION ALL
        SELECT b.id, s.ordinality::int, LOWER(s.val)
        FROM buses b, jsonb_array_elements_text(b.stops) WITH ORDINALITY AS s(val, ordinality)
        UNION ALL
        SELECT b.id, jsonb_array_length(b.stops) + 1, LOWER(b.end_location)
        FROM buses b
      ),
      matches AS (
        SELECT
          id,
          MIN(idx) FILTER (WHERE name = LOWER($1)) AS from_idx,
          MIN(idx) FILTER (WHERE name = LOWER($2)) AS to_idx
        FROM route_stops
        WHERE name IN (LOWER($1), LOWER($2))
        GROUP BY id
      )
      SELECT b.id, b.bus_number, b.bus_name, b.start_location, b.end_location, b.stops
      FROM buses b
      JOIN matches m ON m.id = b.id
      WHERE m.from_idx < m.to_idx
      ORDER BY b.bus_number`,
      [from, to]
    );

    return res.json({ buses: result.rows });
  } catch (err) {
    console.error('[busController.searchTrips]', err.message);
    return res.status(500).json({ message: 'Internal server error.' });
  }
};

// ---------------------------------------------------------------------------
// GET /api/buses/nearby?lat=...&lng=...&radius=...
// Default radius = 2000 metres.
// ---------------------------------------------------------------------------
const nearbyBuses = async (req, res) => {
  const lat    = parseFloat(req.query.lat);
  const lng    = parseFloat(req.query.lng);
  const radius = parseFloat(req.query.radius) || 2000;

  if (isNaN(lat) || isNaN(lng)) {
    return res.status(400).json({ message: 'Valid "lat" and "lng" query params are required.' });
  }

  try {
    const result = await query(
      `SELECT
         b.id, b.bus_number, b.bus_name, b.start_location, b.end_location, b.stops,
         ST_Y(l.geom)  AS lat,
         ST_X(l.geom)  AS lng,
         l.heading,
         l.updated_at,
         ROUND(
           (ST_Distance(
             l.geom::geography,
             ST_MakePoint($2, $1)::geography
           ) / 1000.0)::numeric, 2
         ) AS distance_km
       FROM bus_locations l
       JOIN buses b ON b.id = l.bus_id
       WHERE ST_DWithin(
         l.geom::geography,
         ST_MakePoint($2, $1)::geography,
         $3
       )
       ORDER BY distance_km ASC`,
      [lat, lng, radius]
    );

    return res.json({ buses: result.rows });
  } catch (err) {
    console.error('[busController.nearbyBuses]', err.message);
    return res.status(500).json({ message: 'Internal server error.' });
  }
};

// ---------------------------------------------------------------------------
// GET /api/buses/:id/route
// ---------------------------------------------------------------------------
const getBusRoute = async (req, res) => {
  const { id } = req.params;

  try {
    const result = await query(
      `SELECT
         id, bus_id, seq, name,
         ST_Y(geom) AS lat,
         ST_X(geom) AS lng
       FROM route_coordinates
       WHERE bus_id = $1
       ORDER BY seq ASC`,
      [id]
    );

    return res.json({ route: result.rows });
  } catch (err) {
    console.error('[busController.getBusRoute]', err.message);
    return res.status(500).json({ message: 'Internal server error.' });
  }
};

module.exports = { searchBus, searchTrips, nearbyBuses, getBusRoute };
