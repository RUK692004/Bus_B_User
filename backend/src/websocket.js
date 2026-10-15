'use strict';

const { WebSocketServer, WebSocket } = require('ws');
const url = require('url');

// ---------------------------------------------------------------------------
// In-Memory State (Single Server MVP)
// ---------------------------------------------------------------------------
// Latest known location for each bus: busId -> { busId, lat, lng, heading, speed, updatedAt }
const busLocations = new Map();

// Bus subscribers: busId -> Set<WebSocket>
const busSubscribers = new Map();

// Subscribers listening to all buses: Set<WebSocket>
const allBusSubscribers = new Set();

/**
 * Safely send a JSON message to a WebSocket client.
 * @param {WebSocket} ws
 * @param {object} data
 */
function sendJson(ws, data) {
  if (ws.readyState === WebSocket.OPEN) {
    try {
      ws.send(JSON.stringify(data));
    } catch (err) {
      console.error('[WebSocket] Failed to send message:', err.message);
    }
  }
}

/**
 * Helper to update database in background (best-effort, non-blocking).
 * @param {string|number} busId
 * @param {number} lat
 * @param {number} lng
 * @param {number} heading
 */
async function persistLocationToDb(busId, lat, lng, heading) {
  try {
    const { query } = require('./db');
    await query(
      `INSERT INTO bus_locations (bus_id, geom, heading, updated_at)
       VALUES ($1, ST_SetSRID(ST_MakePoint($2, $3), 4326), $4, NOW())
       ON CONFLICT (bus_id)
       DO UPDATE SET geom = EXCLUDED.geom, heading = EXCLUDED.heading, updated_at = NOW()`,
      [busId, lng, lat, heading || 0]
    );
  } catch (err) {
    // Non-fatal: database might not be configured or available in MVP/test environments.
  }
}

/**
 * Broadcast location update to relevant subscribers.
 * @param {string} busId
 * @param {object} locationData
 */
function broadcastLocation(busId, locationData) {
  const payload = {
    type: 'location_update',
    busId: String(busId),
    bus_id: String(busId),
    lat: locationData.lat,
    latitude: locationData.lat,
    lng: locationData.lng,
    longitude: locationData.lng,
    heading: locationData.heading ?? 0,
    speed: locationData.speed ?? 0,
    updatedAt: locationData.updatedAt || new Date().toISOString(),
  };

  const jsonString = JSON.stringify(payload);

  // 1. Send to subscribers of this specific bus
  const subs = busSubscribers.get(String(busId));
  if (subs) {
    for (const client of subs) {
      if (client.readyState === WebSocket.OPEN) {
        client.send(jsonString);
      }
    }
  }

  // 2. Send to global subscribers
  for (const client of allBusSubscribers) {
    if (client.readyState === WebSocket.OPEN) {
      client.send(jsonString);
    }
  }
}

/**
 * Handle new WebSocket connection.
 * @param {WebSocket} ws
 * @param {import('http').IncomingMessage} req
 */
function handleConnection(ws, req) {
  ws.isAlive = true;
  ws.clientInfo = {
    role: 'unknown',
    registeredBusId: null,
    subscribedBuses: new Set(),
  };

  ws.on('pong', () => {
    ws.isAlive = true;
  });

  // Parse URL query params if any
  try {
    const parsedUrl = url.parse(req.url, true);
    const { role, busId, bus_id, subscribe } = parsedUrl.query;

    if (role === 'driver') {
      const bId = busId || bus_id;
      if (bId) {
        ws.clientInfo.role = 'driver';
        ws.clientInfo.registeredBusId = String(bId);
        console.log(`[WebSocket] Driver registered for bus ${bId}`);
      }
    }

    const subTarget = subscribe || (role === 'user' ? (busId || bus_id) : null);
    if (subTarget) {
      ws.clientInfo.role = 'user';
      if (subTarget === '*' || subTarget === 'all') {
        allBusSubscribers.add(ws);
        console.log('[WebSocket] User subscribed to all buses');
      } else {
        const idStr = String(subTarget);
        ws.clientInfo.subscribedBuses.add(idStr);
        if (!busSubscribers.has(idStr)) {
          busSubscribers.set(idStr, new Set());
        }
        busSubscribers.get(idStr).add(ws);
        console.log(`[WebSocket] User subscribed to bus ${idStr}`);

        // Replay cached location if available
        if (busLocations.has(idStr)) {
          const cached = busLocations.get(idStr);
          sendJson(ws, {
            type: 'location_update',
            busId: idStr,
            bus_id: idStr,
            lat: cached.lat,
            latitude: cached.lat,
            lng: cached.lng,
            longitude: cached.lng,
            heading: cached.heading ?? 0,
            speed: cached.speed ?? 0,
            updatedAt: cached.updatedAt,
          });
        }
      }
    }
  } catch (err) {
    console.error('[WebSocket] Error parsing initial connection query:', err.message);
  }

  // Welcome message
  sendJson(ws, {
    type: 'connected',
    message: 'Connected to BusBee Real-Time Location WebSocket Server',
  });

  // Handle incoming messages
  ws.on('message', async (rawMessage) => {
    let msg;
    try {
      msg = JSON.parse(rawMessage.toString());
    } catch {
      return sendJson(ws, {
        type: 'error',
        message: 'Invalid JSON payload. Messages must be valid JSON.',
      });
    }

    const action = msg.type || msg.action || msg.event;

    switch (action) {
      // ---------------------------------------------------------------------
      // Driver registration
      // ---------------------------------------------------------------------
      case 'register_driver':
      case 'driver_register': {
        const busId = msg.busId || msg.bus_id;
        if (!busId) {
          return sendJson(ws, { type: 'error', message: 'Missing busId in registration.' });
        }
        ws.clientInfo.role = 'driver';
        ws.clientInfo.registeredBusId = String(busId);
        console.log(`[WebSocket] Driver registered for bus ${busId}`);
        return sendJson(ws, {
          type: 'driver_registered',
          busId: String(busId),
          message: `Driver registered for bus ${busId}`,
        });
      }

      // ---------------------------------------------------------------------
      // Location update from driver
      // ---------------------------------------------------------------------
      case 'location_update':
      case 'update_location':
      case 'location': {
        const busId = msg.busId || msg.bus_id || ws.clientInfo.registeredBusId;
        const lat = typeof msg.lat === 'number' ? msg.lat : parseFloat(msg.latitude);
        const lng = typeof msg.lng === 'number' ? msg.lng : parseFloat(msg.longitude);
        const heading = typeof msg.heading === 'number' ? msg.heading : parseFloat(msg.heading) || 0;
        const speed = typeof msg.speed === 'number' ? msg.speed : parseFloat(msg.speed) || 0;

        if (!busId || isNaN(lat) || isNaN(lng)) {
          return sendJson(ws, {
            type: 'error',
            message: 'Invalid location data. busId, lat (or latitude), and lng (or longitude) are required numbers.',
          });
        }

        const updatedAt = msg.timestamp || new Date().toISOString();
        const locationRecord = {
          busId: String(busId),
          lat,
          lng,
          heading,
          speed,
          updatedAt,
        };

        // Cache in memory
        busLocations.set(String(busId), locationRecord);

        // Broadcast to user subscribers
        broadcastLocation(busId, locationRecord);

        // Async persist to DB (non-blocking)
        persistLocationToDb(busId, lat, lng, heading);

        // Acknowledge driver
        return sendJson(ws, {
          type: 'location_ack',
          busId: String(busId),
          updatedAt,
        });
      }

      // ---------------------------------------------------------------------
      // User subscription to a bus
      // ---------------------------------------------------------------------
      case 'subscribe':
      case 'sub': {
        const busId = msg.busId || msg.bus_id;
        if (!busId) {
          return sendJson(ws, { type: 'error', message: 'Missing busId in subscribe request.' });
        }

        ws.clientInfo.role = 'user';

        if (busId === '*' || busId === 'all') {
          allBusSubscribers.add(ws);
          sendJson(ws, {
            type: 'subscribed',
            busId: '*',
            message: 'Subscribed to location updates for all buses',
          });
        } else {
          const idStr = String(busId);
          ws.clientInfo.subscribedBuses.add(idStr);
          if (!busSubscribers.has(idStr)) {
            busSubscribers.set(idStr, new Set());
          }
          busSubscribers.get(idStr).add(ws);

          sendJson(ws, {
            type: 'subscribed',
            busId: idStr,
            message: `Subscribed to location updates for bus ${idStr}`,
          });

          // Replay cached location if available
          if (busLocations.has(idStr)) {
            const cached = busLocations.get(idStr);
            sendJson(ws, {
              type: 'location_update',
              busId: idStr,
              bus_id: idStr,
              lat: cached.lat,
              latitude: cached.lat,
              lng: cached.lng,
              longitude: cached.lng,
              heading: cached.heading ?? 0,
              speed: cached.speed ?? 0,
              updatedAt: cached.updatedAt,
            });
          }
        }
        return;
      }

      // ---------------------------------------------------------------------
      // User subscription to all buses
      // ---------------------------------------------------------------------
      case 'subscribe_all': {
        ws.clientInfo.role = 'user';
        allBusSubscribers.add(ws);
        return sendJson(ws, {
          type: 'subscribed',
          busId: '*',
          message: 'Subscribed to location updates for all buses',
        });
      }

      // ---------------------------------------------------------------------
      // User unsubscription
      // ---------------------------------------------------------------------
      case 'unsubscribe':
      case 'unsub': {
        const busId = msg.busId || msg.bus_id;
        if (!busId || busId === '*' || busId === 'all') {
          allBusSubscribers.delete(ws);
          for (const bId of ws.clientInfo.subscribedBuses) {
            const subs = busSubscribers.get(bId);
            if (subs) {
              subs.delete(ws);
            }
          }
          ws.clientInfo.subscribedBuses.clear();
          return sendJson(ws, {
            type: 'unsubscribed',
            busId: '*',
            message: 'Unsubscribed from all buses',
          });
        }

        const idStr = String(busId);
        ws.clientInfo.subscribedBuses.delete(idStr);
        const subs = busSubscribers.get(idStr);
        if (subs) {
          subs.delete(ws);
        }
        return sendJson(ws, {
          type: 'unsubscribed',
          busId: idStr,
          message: `Unsubscribed from bus ${idStr}`,
        });
      }

      // ---------------------------------------------------------------------
      // Get current location (on-demand snapshot)
      // ---------------------------------------------------------------------
      case 'get_location': {
        const busId = msg.busId || msg.bus_id;
        if (!busId) {
          return sendJson(ws, { type: 'error', message: 'Missing busId in get_location request.' });
        }
        const idStr = String(busId);
        if (busLocations.has(idStr)) {
          const cached = busLocations.get(idStr);
          return sendJson(ws, {
            type: 'location_update',
            busId: idStr,
            bus_id: idStr,
            lat: cached.lat,
            latitude: cached.lat,
            lng: cached.lng,
            longitude: cached.lng,
            heading: cached.heading ?? 0,
            speed: cached.speed ?? 0,
            updatedAt: cached.updatedAt,
          });
        }
        return sendJson(ws, {
          type: 'not_found',
          busId: idStr,
          message: `No active location found for bus ${idStr}`,
        });
      }

      // ---------------------------------------------------------------------
      // Ping / Pong
      // ---------------------------------------------------------------------
      case 'ping': {
        return sendJson(ws, { type: 'pong', timestamp: new Date().toISOString() });
      }

      default: {
        return sendJson(ws, {
          type: 'error',
          message: `Unknown message type: "${action}"`,
        });
      }
    }
  });

  // Handle client disconnect and cleanup
  const cleanup = () => {
    allBusSubscribers.delete(ws);
    for (const busId of ws.clientInfo.subscribedBuses) {
      const subs = busSubscribers.get(busId);
      if (subs) {
        subs.delete(ws);
        if (subs.size === 0) {
          busSubscribers.delete(busId);
        }
      }
    }
    ws.clientInfo.subscribedBuses.clear();
  };

  ws.on('close', cleanup);
  ws.on('error', (err) => {
    console.error('[WebSocket] Socket error:', err.message);
    cleanup();
  });
}

/**
 * Initialize WebSocketServer on top of HTTP server.
 * @param {import('http').Server} server
 * @returns {WebSocketServer}
 */
function initWebSocketServer(server) {
  const wss = new WebSocketServer({ server });

  wss.on('connection', (ws, req) => {
    handleConnection(ws, req);
  });

  // Heartbeat ping interval to detect stale/dead connections
  const interval = setInterval(() => {
    for (const ws of wss.clients) {
      if (ws.isAlive === false) {
        ws.terminate();
        continue;
      }
      ws.isAlive = false;
      ws.ping();
    }
  }, 30000);

  wss.on('close', () => {
    clearInterval(interval);
  });

  console.log('[WebSocket] WebSocket Server initialized.');
  return wss;
}

module.exports = {
  initWebSocketServer,
  broadcastLocation,
  busLocations,
};
