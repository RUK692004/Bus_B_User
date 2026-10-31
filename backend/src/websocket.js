'use strict';

const { WebSocketServer, WebSocket } = require('ws');
const jwt = require('jsonwebtoken');
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

// Last persistence error message, used to avoid logging the same failure on every update.
let lastPersistError = null;

const HEARTBEAT_INTERVAL_MS = 30000;

// Bus ids are uuids (see db/schema.sql).
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

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

function sendError(ws, message) {
  sendJson(ws, { type: 'error', message });
}

/** True when a subscription target means "every bus". */
function isAllBuses(target) {
  return target === '*' || target === 'all';
}

/** Reads the bus id from a message, accepting both naming styles. */
function busIdFrom(msg) {
  return msg.busId || msg.bus_id;
}

/**
 * Builds the outgoing `location_update` payload. Each field is repeated under
 * both naming styles so clients can read either.
 * @param {string|number} busId
 * @param {{ lat: number, lng: number, heading?: number, speed?: number, updatedAt?: string }} location
 */
function locationPayload(busId, location) {
  const id = String(busId);
  return {
    type: 'location_update',
    busId: id,
    bus_id: id,
    lat: location.lat,
    latitude: location.lat,
    lng: location.lng,
    longitude: location.lng,
    heading: location.heading ?? 0,
    speed: location.speed ?? 0,
    updatedAt: location.updatedAt || new Date().toISOString(),
  };
}

/** Parses a numeric field that may arrive as a number or a numeric string. */
function toNumber(value) {
  return typeof value === 'number' ? value : parseFloat(value);
}

/**
 * Helper to update database in background (best-effort, non-blocking).
 * @param {string|number} busId
 * @param {number} lat
 * @param {number} lng
 * @param {number} heading
 * @param {number} speed
 */
async function persistLocationToDb(busId, lat, lng, heading, speed) {
  try {
    const { query } = require('./db');
    await query(
      `INSERT INTO bus_locations (bus_id, geom, heading, speed, updated_at)
       VALUES ($1, ST_SetSRID(ST_MakePoint($2, $3), 4326), $4, $5, NOW())
       ON CONFLICT (bus_id)
       DO UPDATE SET geom = EXCLUDED.geom, heading = EXCLUDED.heading,
                     speed = EXCLUDED.speed, updated_at = NOW()`,
      [busId, lng, lat, heading || 0, speed || 0]
    );
  } catch (err) {
    // Non-fatal: live tracking keeps working from the in-memory cache. Log each
    // distinct error once so an unavailable database doesn't flood the console.
    // Connection failures (e.g. ECONNREFUSED) can have an empty message, so fall back to the code.
    const reason = err.message || err.code || String(err);
    if (reason !== lastPersistError) {
      lastPersistError = reason;
      console.warn(`[WebSocket] Failed to persist location for bus ${busId}:`, reason);
    }
    return;
  }
  lastPersistError = null;
}

/**
 * Broadcast location update to relevant subscribers.
 * @param {string} busId
 * @param {object} locationData
 */
function broadcastLocation(busId, locationData) {
  const jsonString = JSON.stringify(locationPayload(busId, locationData));
  const recipients = [...(busSubscribers.get(String(busId)) || []), ...allBusSubscribers];

  for (const client of recipients) {
    if (client.readyState === WebSocket.OPEN) {
      client.send(jsonString);
    }
  }
}

// ---------------------------------------------------------------------------
// Subscription bookkeeping
// ---------------------------------------------------------------------------

/** Returns the decoded token when it is valid and belongs to a driver, otherwise null. */
function verifyDriverToken(token) {
  if (!token) return null;
  try {
    const user = jwt.verify(token, process.env.JWT_SECRET);
    return user.role === 'driver' ? user : null;
  } catch {
    return null;
  }
}

/**
 * Checks whether a driver may send locations for a bus: the token must belong
 * to a user with role 'driver' and the bus must exist.
 * @returns {Promise<string|null>} An error message, or null when allowed.
 */
async function authorizeDriver(busId, token) {
  if (!busId) return 'Missing busId in registration.';
  if (!UUID_RE.test(String(busId))) return 'Invalid busId. Bus ids are uuids.';
  if (!verifyDriverToken(token)) return 'Driver login required. Send a valid driver token.';

  try {
    const { query } = require('./db');
    const { rowCount } = await query('SELECT 1 FROM buses WHERE id = $1', [busId]);
    if (rowCount === 0) return `Unknown bus ${busId}.`;
  } catch (err) {
    // The driver is already authenticated, so keep live tracking working
    // while the database is unreachable instead of rejecting them.
    console.warn('[WebSocket] Could not check that bus exists, allowing driver:', err.message || err.code);
  }
  return null;
}

function registerDriver(ws, busId) {
  ws.clientInfo.role = 'driver';
  ws.clientInfo.registeredBusId = String(busId);
  console.log(`[WebSocket] Driver registered for bus ${busId}`);
}

/**
 * Authorizes and registers a driver, replying with `driver_registered` or `error`.
 * Drivers should wait for `driver_registered` before sending locations.
 */
async function registerDriverIfAllowed(ws, busId, token) {
  const error = await authorizeDriver(busId, token);
  if (error) return sendError(ws, error);

  registerDriver(ws, busId);
  sendJson(ws, {
    type: 'driver_registered',
    busId: String(busId),
    message: `Driver registered for bus ${busId}`,
  });
}

function subscribeToAll(ws) {
  ws.clientInfo.role = 'user';
  allBusSubscribers.add(ws);
}

function subscribeToBus(ws, busId) {
  ws.clientInfo.role = 'user';
  ws.clientInfo.subscribedBuses.add(busId);
  if (!busSubscribers.has(busId)) {
    busSubscribers.set(busId, new Set());
  }
  busSubscribers.get(busId).add(ws);
}

function unsubscribeFromBus(ws, busId) {
  ws.clientInfo.subscribedBuses.delete(busId);
  const subs = busSubscribers.get(busId);
  if (subs) {
    subs.delete(ws);
    if (subs.size === 0) {
      busSubscribers.delete(busId);
    }
  }
}

function unsubscribeFromEverything(ws) {
  allBusSubscribers.delete(ws);
  for (const busId of [...ws.clientInfo.subscribedBuses]) {
    unsubscribeFromBus(ws, busId);
  }
}

/** Sends the cached location for a bus, if there is one. Returns whether it did. */
function replayCachedLocation(ws, busId) {
  const cached = busLocations.get(busId);
  if (!cached) return false;
  sendJson(ws, locationPayload(busId, cached));
  return true;
}

// ---------------------------------------------------------------------------
// Message handlers
// ---------------------------------------------------------------------------

function handleRegisterDriver(ws, msg) {
  return registerDriverIfAllowed(ws, busIdFrom(msg), msg.token);
}

function handleLocationUpdate(ws, msg) {
  // Only a registered driver may send locations, and only for its own bus.
  const busId = ws.clientInfo.registeredBusId;
  if (!busId) {
    return sendError(ws, 'Register as a driver before sending locations.');
  }
  const requestedBusId = busIdFrom(msg);
  if (requestedBusId && String(requestedBusId) !== busId) {
    return sendError(ws, `This connection can only send locations for bus ${busId}.`);
  }

  const lat = typeof msg.lat === 'number' ? msg.lat : parseFloat(msg.latitude);
  const lng = typeof msg.lng === 'number' ? msg.lng : parseFloat(msg.longitude);
  const heading = toNumber(msg.heading) || 0;
  const speed = toNumber(msg.speed) || 0;

  if (isNaN(lat) || isNaN(lng)) {
    return sendError(
      ws,
      'Invalid location data. lat (or latitude) and lng (or longitude) are required numbers.'
    );
  }

  const updatedAt = msg.timestamp || new Date().toISOString();
  const locationRecord = { busId: String(busId), lat, lng, heading, speed, updatedAt };

  busLocations.set(String(busId), locationRecord);
  broadcastLocation(busId, locationRecord);
  persistLocationToDb(busId, lat, lng, heading, speed); // non-blocking

  sendJson(ws, { type: 'location_ack', busId: String(busId), updatedAt });
}

function handleSubscribe(ws, msg) {
  const busId = busIdFrom(msg);
  if (!busId) {
    return sendError(ws, 'Missing busId in subscribe request.');
  }

  if (isAllBuses(busId)) {
    return handleSubscribeAll(ws);
  }

  const idStr = String(busId);
  subscribeToBus(ws, idStr);
  sendJson(ws, {
    type: 'subscribed',
    busId: idStr,
    message: `Subscribed to location updates for bus ${idStr}`,
  });
  replayCachedLocation(ws, idStr);
}

function handleSubscribeAll(ws) {
  subscribeToAll(ws);
  sendJson(ws, {
    type: 'subscribed',
    busId: '*',
    message: 'Subscribed to location updates for all buses',
  });
}

function handleUnsubscribe(ws, msg) {
  const busId = busIdFrom(msg);

  if (!busId || isAllBuses(busId)) {
    unsubscribeFromEverything(ws);
    return sendJson(ws, {
      type: 'unsubscribed',
      busId: '*',
      message: 'Unsubscribed from all buses',
    });
  }

  const idStr = String(busId);
  unsubscribeFromBus(ws, idStr);
  sendJson(ws, {
    type: 'unsubscribed',
    busId: idStr,
    message: `Unsubscribed from bus ${idStr}`,
  });
}

function handleGetLocation(ws, msg) {
  const busId = busIdFrom(msg);
  if (!busId) {
    return sendError(ws, 'Missing busId in get_location request.');
  }

  const idStr = String(busId);
  if (!replayCachedLocation(ws, idStr)) {
    sendJson(ws, {
      type: 'not_found',
      busId: idStr,
      message: `No active location found for bus ${idStr}`,
    });
  }
}

function handlePing(ws) {
  sendJson(ws, { type: 'pong', timestamp: new Date().toISOString() });
}

// Message type (and its accepted aliases) -> handler.
const messageHandlers = {
  register_driver: handleRegisterDriver,
  driver_register: handleRegisterDriver,
  location_update: handleLocationUpdate,
  update_location: handleLocationUpdate,
  location: handleLocationUpdate,
  subscribe: handleSubscribe,
  sub: handleSubscribe,
  subscribe_all: handleSubscribeAll,
  unsubscribe: handleUnsubscribe,
  unsub: handleUnsubscribe,
  get_location: handleGetLocation,
  ping: handlePing,
};

// ---------------------------------------------------------------------------
// Connection lifecycle
// ---------------------------------------------------------------------------

/**
 * Applies driver registration / subscriptions passed in the connection URL,
 * e.g. `?role=driver&busId=…&token=…`, `?role=user&busId=…`, `?subscribe=*`.
 */
function applyConnectionQuery(ws, req) {
  const { role, busId, bus_id, subscribe, token } = url.parse(req.url, true).query;
  const queryBusId = busId || bus_id;

  if (role === 'driver') {
    registerDriverIfAllowed(ws, queryBusId, token).catch((err) => {
      console.error('[WebSocket] Driver registration failed:', err.message);
    });
  }

  const target = subscribe || (role === 'user' ? queryBusId : null);
  if (!target) return;

  if (isAllBuses(target)) {
    subscribeToAll(ws);
    console.log('[WebSocket] User subscribed to all buses');
  } else {
    const idStr = String(target);
    subscribeToBus(ws, idStr);
    console.log(`[WebSocket] User subscribed to bus ${idStr}`);
    replayCachedLocation(ws, idStr);
  }
}

function handleMessage(ws, rawMessage) {
  let msg;
  try {
    msg = JSON.parse(rawMessage.toString());
  } catch {
    return sendError(ws, 'Invalid JSON payload. Messages must be valid JSON.');
  }
  if (!msg || typeof msg !== 'object') {
    return sendError(ws, 'Invalid message. Messages must be JSON objects.');
  }

  const action = msg.type || msg.action || msg.event;
  const handler = Object.hasOwn(messageHandlers, action) ? messageHandlers[action] : null;
  if (!handler) {
    return sendError(ws, `Unknown message type: "${action}"`);
  }
  // Some handlers are async (driver registration queries the database).
  Promise.resolve(handler(ws, msg)).catch((err) => {
    console.error(`[WebSocket] Handler for "${action}" failed:`, err.message);
    sendError(ws, 'Internal server error.');
  });
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

  try {
    applyConnectionQuery(ws, req);
  } catch (err) {
    console.error('[WebSocket] Error parsing initial connection query:', err.message);
  }

  sendJson(ws, {
    type: 'connected',
    message: 'Connected to BusBee Real-Time Location WebSocket Server',
  });

  ws.on('message', (rawMessage) => handleMessage(ws, rawMessage));

  ws.on('close', () => unsubscribeFromEverything(ws));
  ws.on('error', (err) => {
    console.error('[WebSocket] Socket error:', err.message);
    unsubscribeFromEverything(ws);
  });
}

/**
 * Initialize WebSocketServer on top of HTTP server.
 * @param {import('http').Server} server
 * @returns {WebSocketServer}
 */
function initWebSocketServer(server) {
  const wss = new WebSocketServer({ server });

  wss.on('connection', handleConnection);

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
  }, HEARTBEAT_INTERVAL_MS);

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
