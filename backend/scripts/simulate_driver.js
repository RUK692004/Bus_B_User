'use strict';

// Pretends to be the driver app for local testing: registers as a driver for a
// bus and sends a location every few seconds, moving along the bus's saved
// route (route_coordinates). Loops back to the start at the end of the route.
//
//   npm run simulate                    # first seeded bus (KL-07-101)
//   npm run simulate -- <bus-uuid>      # any bus with route coordinates
//
// Needs the backend running and the same .env (it signs its own driver token
// with JWT_SECRET, so no driver account is required).

require('dotenv').config();
const { WebSocket } = require('ws');
const jwt = require('jsonwebtoken');
const { pool, query } = require('../src/db');

const BUS_ID = process.argv[2] || '11111111-1111-1111-1111-111111111101';
const PORT = process.env.PORT || 5000;
const INTERVAL_MS = 2000;
const STEPS_BETWEEN_POINTS = 10; // smaller = faster bus

async function loadRoute(busId) {
  const { rows } = await query(
    `SELECT name, ST_Y(geom) AS lat, ST_X(geom) AS lng
     FROM route_coordinates WHERE bus_id = $1 ORDER BY seq`,
    [busId]
  );
  return rows;
}

/** Points between consecutive route points, so the bus moves smoothly. */
function interpolate(route) {
  const path = [];
  for (let i = 0; i < route.length - 1; i++) {
    const a = route[i];
    const b = route[i + 1];
    for (let s = 0; s < STEPS_BETWEEN_POINTS; s++) {
      const t = s / STEPS_BETWEEN_POINTS;
      path.push({ lat: a.lat + (b.lat - a.lat) * t, lng: a.lng + (b.lng - a.lng) * t, near: a.name });
    }
  }
  const last = route[route.length - 1];
  path.push({ lat: last.lat, lng: last.lng, near: last.name });
  return path;
}

/** Compass bearing in degrees from one point to the next. */
function bearing(from, to) {
  const rad = Math.PI / 180;
  const dLng = (to.lng - from.lng) * rad;
  const y = Math.sin(dLng) * Math.cos(to.lat * rad);
  const x = Math.cos(from.lat * rad) * Math.sin(to.lat * rad) -
    Math.sin(from.lat * rad) * Math.cos(to.lat * rad) * Math.cos(dLng);
  return (Math.atan2(y, x) / rad + 360) % 360;
}

async function main() {
  const route = await loadRoute(BUS_ID);
  await pool.end();
  if (route.length < 2) {
    console.error(`[Simulator] Bus ${BUS_ID} has fewer than 2 route_coordinates. Run db/seed.sql or pass another bus id.`);
    process.exit(1);
  }
  const path = interpolate(route);

  const token = jwt.sign({ id: 'simulator', name: 'Simulator', role: 'driver' }, process.env.JWT_SECRET, {
    expiresIn: '1d',
  });
  const ws = new WebSocket(`ws://localhost:${PORT}`);
  let index = 0;
  let timer = null;

  ws.on('open', () => {
    ws.send(JSON.stringify({ type: 'register_driver', busId: BUS_ID, token }));
  });

  ws.on('message', (data) => {
    const msg = JSON.parse(data.toString());
    if (msg.type === 'error') {
      console.error('[Simulator] Server error:', msg.message);
    } else if (msg.type === 'driver_registered') {
      console.log(`[Simulator] Registered for bus ${BUS_ID}. Sending a location every ${INTERVAL_MS / 1000}s (Ctrl+C to stop).`);
      timer = setInterval(() => {
        const point = path[index];
        const next = path[(index + 1) % path.length];
        ws.send(JSON.stringify({
          type: 'location_update',
          lat: point.lat,
          lng: point.lng,
          heading: bearing(point, next),
          speed: 30,
        }));
        console.log(`[Simulator] ${point.lat.toFixed(5)}, ${point.lng.toFixed(5)} (after ${point.near})`);
        index = (index + 1) % path.length;
      }, INTERVAL_MS);
    }
  });

  ws.on('close', () => {
    clearInterval(timer);
    console.log('[Simulator] Disconnected from server.');
    process.exit(0);
  });
  ws.on('error', (err) => {
    console.error(`[Simulator] Could not connect to ws://localhost:${PORT}. Is the backend running?`, err.message);
  });
}

main().catch((err) => {
  console.error('[Simulator] Failed:', err.message || err.code);
  process.exit(1);
});
