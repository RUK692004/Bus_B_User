'use strict';

// Isolate the test from any local database: point pg at a closed port so bus
// existence checks and location persistence fail (and are tolerated) every
// time, whether or not Postgres is running. dotenv never overrides these.
process.env.DB_HOST = '127.0.0.1';
process.env.DB_PORT = '1';
process.env.JWT_SECRET = process.env.JWT_SECRET || 'test-secret';

const { WebSocket } = require('ws');
const jwt = require('jsonwebtoken');
const app = require('./src/server');

const PORT = process.env.PORT || 5000;
const WS_URL = `ws://localhost:${PORT}`;

// Bus ids are uuids; the driver must be registered for a uuid bus.
const BUS_A = 'aaaaaaaa-0000-4000-8000-000000000101';
const BUS_B = 'aaaaaaaa-0000-4000-8000-000000000202';

const driverToken = jwt.sign({ id: 'driver-1', role: 'driver' }, process.env.JWT_SECRET);
const userToken = jwt.sign({ id: 'user-1', role: 'user' }, process.env.JWT_SECRET);

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/** Opens a socket and records every JSON message it receives. */
async function connect(url) {
  const ws = new WebSocket(url);
  const messages = [];
  ws.on('message', (data) => messages.push(JSON.parse(data.toString())));
  await new Promise((resolve) => ws.on('open', resolve));
  return { ws, messages };
}

/**
 * Resolves with the first recorded message matching `predicate`, or null after
 * `timeoutMs`. Driver registration waits on a database lookup, so its replies
 * can take longer than a fixed sleep.
 */
async function waitFor(messages, predicate, timeoutMs = 5000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const found = messages.find(predicate);
    if (found) return found;
    await sleep(50);
  }
  return null;
}

async function runTests() {
  console.log('--- Starting WebSocket Integration Tests ---');
  await sleep(1000); // Give server a second to start listening

  let passed = 0;
  let failed = 0;

  function assert(condition, message) {
    if (condition) {
      console.log(`✅ PASS: ${message}`);
      passed++;
    } else {
      console.error(`❌ FAIL: ${message}`);
      failed++;
    }
  }

  // 1. User client connection
  const user = await connect(WS_URL);
  await sleep(200);
  assert(user.messages.some((m) => m.type === 'connected'), 'User client received connection greeting');

  // 2. User subscribes to bus A
  user.ws.send(JSON.stringify({ type: 'subscribe', busId: BUS_A }));
  await sleep(200);

  // 3. Driver registration is rejected without a valid driver token or a uuid bus id
  const rejected = await connect(WS_URL);
  rejected.ws.send(JSON.stringify({ type: 'register_driver', busId: BUS_A }));
  rejected.ws.send(JSON.stringify({ type: 'register_driver', busId: BUS_A, token: userToken }));
  rejected.ws.send(JSON.stringify({ type: 'register_driver', busId: BUS_A, token: 'not-a-jwt' }));
  rejected.ws.send(JSON.stringify({ type: 'register_driver', busId: 'bus-101', token: driverToken }));
  rejected.ws.send(JSON.stringify({ type: 'location_update', busId: BUS_A, lat: 1, lng: 2 }));
  await sleep(300);
  const rejectErrors = rejected.messages.filter((m) => m.type === 'error').map((m) => m.message);
  assert(
    rejectErrors.filter((e) => e.includes('Driver login required')).length === 3,
    'Driver registration without a driver token (missing, user role, or invalid) is rejected'
  );
  assert(rejectErrors.some((e) => e.includes('Invalid busId')), 'Driver registration with a non-uuid bus id is rejected');
  assert(
    rejectErrors.some((e) => e.includes('Register as a driver')),
    'Location updates from an unregistered connection are rejected'
  );
  assert(
    !rejected.messages.some((m) => m.type === 'driver_registered'),
    'Rejected connections are never registered as drivers'
  );

  // 4. Driver connects and registers with a driver token
  const driver = await connect(WS_URL);
  driver.ws.send(JSON.stringify({ type: 'register_driver', busId: BUS_A, token: driverToken }));
  const registered = await waitFor(driver.messages, (m) => m.type === 'driver_registered');
  assert(registered !== null && registered.busId === BUS_A, 'Driver with a valid token is registered');

  // 5. Driver pushes location update
  const sampleLat = 9.9312;
  const sampleLng = 76.2673;
  const sampleHeading = 120;
  const sampleSpeed = 42.5;

  driver.ws.send(
    JSON.stringify({
      type: 'location_update',
      busId: BUS_A,
      lat: sampleLat,
      lng: sampleLng,
      heading: sampleHeading,
      speed: sampleSpeed,
    })
  );
  await sleep(300);

  const driverAck = driver.messages.find((m) => m.type === 'location_ack');
  const userReceivedLocation = user.messages.find((m) => m.type === 'location_update');
  assert(driverAck !== undefined && driverAck.busId === BUS_A, 'Driver received location ACK');
  assert(
    userReceivedLocation !== undefined &&
      userReceivedLocation.busId === BUS_A &&
      userReceivedLocation.lat === sampleLat &&
      userReceivedLocation.lng === sampleLng &&
      userReceivedLocation.heading === sampleHeading &&
      userReceivedLocation.speed === sampleSpeed,
    'User client received real-time bus location update without polling'
  );

  // 6. A driver cannot send locations for a bus it is not registered for
  driver.ws.send(JSON.stringify({ type: 'location_update', busId: BUS_B, lat: 7, lng: 8 }));
  await sleep(200);
  assert(
    driver.messages.some((m) => m.type === 'error' && m.message.includes('can only send locations for bus')),
    'Driver location update for another bus is rejected'
  );

  // 7. New User connects and subscribes -> should get cached location immediately
  const user2 = await connect(WS_URL);
  user2.ws.send(JSON.stringify({ type: 'subscribe', busId: BUS_A }));
  await sleep(200);
  assert(
    user2.messages.some((m) => m.type === 'location_update' && m.busId === BUS_A),
    'New subscriber immediately receives latest known cached location'
  );

  // 8. Test ping / pong
  user.ws.send(JSON.stringify({ type: 'ping' }));
  await sleep(200);
  assert(user.messages.some((m) => m.type === 'pong'), 'Ping / Pong heartbeat works');

  // 9. Subscribing through the connection query string replays the cached location
  const queryUser = await connect(`${WS_URL}?role=user&busId=${BUS_A}`);
  await sleep(200);
  assert(
    queryUser.messages.some((m) => m.type === 'location_update' && m.busId === BUS_A),
    'Query-string subscriber receives cached location on connect'
  );

  // 10. ?subscribe=* receives updates for any bus
  const allUser = await connect(`${WS_URL}?subscribe=*`);
  await sleep(100);

  // 11. Drivers can register through the query string (with a token)
  const queryDriver = await connect(`${WS_URL}?role=driver&busId=${BUS_B}&token=${driverToken}`);
  assert(
    (await waitFor(queryDriver.messages, (m) => m.type === 'driver_registered' && m.busId === BUS_B)) !== null,
    'Query-string driver with a token is registered'
  );
  const queryDriverNoToken = await connect(`${WS_URL}?role=driver&busId=${BUS_B}`);
  await sleep(200);
  assert(
    queryDriverNoToken.messages.some((m) => m.type === 'error' && m.message.includes('Driver login required')),
    'Query-string driver without a token is rejected'
  );

  // 12. Aliases: action/sub + bus_id for users, event/update_location + latitude/longitude strings for drivers
  const aliasUser = await connect(WS_URL);
  aliasUser.ws.send(JSON.stringify({ action: 'sub', bus_id: BUS_B }));
  await sleep(100);
  assert(
    aliasUser.messages.some((m) => m.type === 'subscribed' && m.busId === BUS_B),
    'Subscribe accepts "action"/"sub" and "bus_id" aliases'
  );

  queryDriver.ws.send(JSON.stringify({ event: 'update_location', bus_id: BUS_B, latitude: '1.5', longitude: '2.5' }));
  await sleep(200);
  const aliasUpdate = aliasUser.messages.find((m) => m.type === 'location_update' && m.busId === BUS_B);
  assert(
    aliasUpdate !== undefined &&
      aliasUpdate.lat === 1.5 && aliasUpdate.latitude === 1.5 &&
      aliasUpdate.lng === 2.5 && aliasUpdate.longitude === 2.5 &&
      aliasUpdate.bus_id === BUS_B && aliasUpdate.heading === 0 && aliasUpdate.speed === 0,
    'Driver aliases are parsed and broadcast under both naming styles'
  );
  assert(
    allUser.messages.some((m) => m.type === 'location_update' && m.busId === BUS_B),
    '?subscribe=* subscriber receives updates for other buses'
  );

  // 13. A registered driver can omit busId on location updates
  driver.ws.send(JSON.stringify({ type: 'location', lat: 3, lng: 4 }));
  await sleep(200);
  assert(
    queryUser.messages.some((m) => m.type === 'location_update' && m.busId === BUS_A && m.lat === 3),
    'Location update without busId uses the registered driver bus'
  );

  // 14. get_location returns the cached location, or not_found
  aliasUser.ws.send(JSON.stringify({ type: 'get_location', busId: BUS_A }));
  aliasUser.ws.send(JSON.stringify({ type: 'get_location', busId: 'bus-missing' }));
  await sleep(200);
  assert(
    aliasUser.messages.some((m) => m.type === 'location_update' && m.busId === BUS_A && m.lat === 3),
    'get_location returns the latest cached location'
  );
  assert(
    aliasUser.messages.some((m) => m.type === 'not_found' && m.busId === 'bus-missing'),
    'get_location for an unknown bus returns not_found'
  );

  // 15. unsubscribe stops further updates
  aliasUser.ws.send(JSON.stringify({ type: 'unsubscribe', busId: BUS_B }));
  await sleep(100);
  assert(
    aliasUser.messages.some((m) => m.type === 'unsubscribed' && m.busId === BUS_B),
    'unsubscribe is acknowledged'
  );
  const beforeCount = aliasUser.messages.filter((m) => m.type === 'location_update' && m.busId === BUS_B).length;
  queryDriver.ws.send(JSON.stringify({ type: 'location_update', busId: BUS_B, lat: 5, lng: 6 }));
  await sleep(200);
  const afterCount = aliasUser.messages.filter((m) => m.type === 'location_update' && m.busId === BUS_B).length;
  assert(afterCount === beforeCount, 'No updates are delivered after unsubscribe');

  // 16. Error replies
  aliasUser.ws.send('not json');
  aliasUser.ws.send(JSON.stringify({ type: 'does_not_exist' }));
  aliasUser.ws.send(JSON.stringify({ type: 'subscribe' }));
  driver.ws.send(JSON.stringify({ type: 'location_update', lat: 'abc', lng: 1 }));
  await sleep(200);
  const errors = aliasUser.messages.filter((m) => m.type === 'error').map((m) => m.message);
  assert(errors.some((e) => e.includes('Invalid JSON')), 'Invalid JSON returns an error');
  assert(errors.some((e) => e.includes('Unknown message type')), 'Unknown message type returns an error');
  assert(errors.some((e) => e.includes('Missing busId in subscribe')), 'Subscribe without busId returns an error');
  assert(
    driver.messages.some((m) => m.type === 'error' && m.message.includes('Invalid location data')),
    'Invalid coordinates return an error'
  );

  // Close sockets
  for (const client of [user, rejected, driver, user2, queryUser, allUser, queryDriver, queryDriverNoToken, aliasUser]) {
    client.ws.close();
  }

  console.log(`\nResults: ${passed} passed, ${failed} failed.`);

  if (app.server) {
    app.server.close(() => {
      process.exit(failed === 0 ? 0 : 1);
    });
  } else {
    process.exit(failed === 0 ? 0 : 1);
  }
}

runTests().catch((err) => {
  console.error('Test run error:', err);
  process.exit(1);
});
