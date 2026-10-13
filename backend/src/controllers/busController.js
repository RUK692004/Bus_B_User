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
    // Build an ordered list of stop names per bus using start_location, stops JSONB
    // array elements (as text), and end_location, then filter those where `from`
    // precedes `to` in that ordered sequence.
    const result = await query(
      `WITH ordered_stops AS (
        SELECT
          id,
          bus_number,
          bus_name,
          start_location,
          end_location,
          stops,
          -- Assign positional index: 0 = start, 1..N = stops, N+1 = end
          (
            SELECT MIN(idx)
            FROM (
              SELECT 0 AS idx, LOWER(start_location) AS name
              UNION ALL
              SELECT ordinality::int AS idx, LOWER(s.val::text) AS name
              FROM jsonb_array_elements_text(stops) WITH ORDINALITY AS s(val, ordinality)
              UNION ALL
              SELECT jsonb_array_length(stops) + 1 AS idx, LOWER(end_location) AS name
            ) all_stops
            WHERE name = LOWER($1)
          ) AS from_idx,
          (
            SELECT MIN(idx)
            FROM (
              SELECT 0 AS idx, LOWER(start_location) AS name
              UNION ALL
              SELECT ordinality::int AS idx, LOWER(s.val::text) AS name
              FROM jsonb_array_elements_text(stops) WITH ORDINALITY AS s(val, ordinality)
              UNION ALL
              SELECT jsonb_array_length(stops) + 1 AS idx, LOWER(end_location) AS name
            ) all_stops
            WHERE name = LOWER($2)
          ) AS to_idx
        FROM buses
      )
      SELECT id, bus_number, bus_name, start_location, end_location, stops
      FROM ordered_stops
      WHERE from_idx IS NOT NULL
        AND to_idx   IS NOT NULL
        AND from_idx < to_idx`,
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
