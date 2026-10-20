'use strict';

const { WebSocket } = require('ws');
const app = require('./src/server');

const PORT = process.env.PORT || 5000;
const WS_URL = `ws://localhost:${PORT}`;

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
  const userWs = new WebSocket(WS_URL);
  let userConnectedMsg = null;
  let userReceivedLocation = null;

  userWs.on('message', (data) => {
    const msg = JSON.parse(data.toString());
    if (msg.type === 'connected') {
      userConnectedMsg = msg;
    } else if (msg.type === 'location_update') {
      userReceivedLocation = msg;
    }
  });

  await new Promise((resolve) => userWs.on('open', resolve));
  await sleep(200);

  assert(userConnectedMsg !== null, 'User client received connection greeting');

  // 2. User subscribes to bus-101
  userWs.send(JSON.stringify({ type: 'subscribe', busId: 'bus-101' }));
  await sleep(200);

  // 3. Driver client connects and registers
  const driverWs = new WebSocket(WS_URL);
  let driverAck = null;

  driverWs.on('message', (data) => {
    const msg = JSON.parse(data.toString());
    if (msg.type === 'location_ack') {
      driverAck = msg;
    }
  });

  await new Promise((resolve) => driverWs.on('open', resolve));
  await sleep(100);

  driverWs.send(JSON.stringify({ type: 'register_driver', busId: 'bus-101' }));
  await sleep(200);

  // 4. Driver pushes location update
  const sampleLat = 9.9312;
  const sampleLng = 76.2673;
  const sampleHeading = 120;
  const sampleSpeed = 42.5;

  driverWs.send(
    JSON.stringify({
      type: 'location_update',
      busId: 'bus-101',
      lat: sampleLat,
      lng: sampleLng,
      heading: sampleHeading,
      speed: sampleSpeed,
    })
  );

  await sleep(300);

  assert(driverAck !== null && driverAck.busId === 'bus-101', 'Driver received location ACK');
  assert(
    userReceivedLocation !== null &&
      userReceivedLocation.busId === 'bus-101' &&
      userReceivedLocation.lat === sampleLat &&
      userReceivedLocation.lng === sampleLng &&
      userReceivedLocation.heading === sampleHeading &&
      userReceivedLocation.speed === sampleSpeed,
    'User client received real-time bus location update without polling'
  );

  // 5. New User connects and subscribes -> should get cached location immediately
  const userWs2 = new WebSocket(WS_URL);
  let user2ImmediateLocation = null;

  userWs2.on('message', (data) => {
    const msg = JSON.parse(data.toString());
    if (msg.type === 'location_update') {
      user2ImmediateLocation = msg;
    }
  });

  await new Promise((resolve) => userWs2.on('open', resolve));
  userWs2.send(JSON.stringify({ type: 'subscribe', busId: 'bus-101' }));
  await sleep(200);

  assert(
    user2ImmediateLocation !== null && user2ImmediateLocation.busId === 'bus-101',
    'New subscriber immediately receives latest known cached location'
  );

  // 6. Test ping / pong
  let pongReceived = false;
  userWs.on('message', (data) => {
    const msg = JSON.parse(data.toString());
    if (msg.type === 'pong') pongReceived = true;
  });
  userWs.send(JSON.stringify({ type: 'ping' }));
  await sleep(200);
  assert(pongReceived === true, 'Ping / Pong heartbeat works');

  // 7. Subscribing through the connection query string replays the cached location
  const queryUser = await connect(`${WS_URL}?role=user&busId=bus-101`);
  await sleep(200);
  assert(
    queryUser.messages.some((m) => m.type === 'location_update' && m.busId === 'bus-101'),
    'Query-string subscriber receives cached location on connect'
  );

  // 8. ?subscribe=* receives updates for any bus
  const allUser = await connect(`${WS_URL}?subscribe=*`);
  await sleep(100);

  // 9. Aliases: action/sub + bus_id for users, event/update_location + latitude/longitude strings for drivers
  const aliasUser = await connect(WS_URL);
  aliasUser.ws.send(JSON.stringify({ action: 'sub', bus_id: 'bus-202' }));
  await sleep(100);
  assert(
    aliasUser.messages.some((m) => m.type === 'subscribed' && m.busId === 'bus-202'),
    'Subscribe accepts "action"/"sub" and "bus_id" aliases'
  );

  driverWs.send(JSON.stringify({ event: 'update_location', bus_id: 'bus-202', latitude: '1.5', longitude: '2.5' }));
  await sleep(200);
  const aliasUpdate = aliasUser.messages.find((m) => m.type === 'location_update' && m.busId === 'bus-202');
  assert(
    aliasUpdate !== undefined &&
      aliasUpdate.lat === 1.5 && aliasUpdate.latitude === 1.5 &&
      aliasUpdate.lng === 2.5 && aliasUpdate.longitude === 2.5 &&
      aliasUpdate.bus_id === 'bus-202' && aliasUpdate.heading === 0 && aliasUpdate.speed === 0,
    'Driver aliases are parsed and broadcast under both naming styles'
  );
  assert(
    allUser.messages.some((m) => m.type === 'location_update' && m.busId === 'bus-202'),
    '?subscribe=* subscriber receives updates for other buses'
  );

  // 10. A registered driver can omit busId on location updates
  driverWs.send(JSON.stringify({ type: 'location', lat: 3, lng: 4 }));
  await sleep(200);
  assert(
    queryUser.messages.some((m) => m.type === 'location_update' && m.busId === 'bus-101' && m.lat === 3),
    'Location update without busId uses the registered driver bus'
  );

  // 11. get_location returns the cached location, or not_found
  aliasUser.ws.send(JSON.stringify({ type: 'get_location', busId: 'bus-101' }));
  aliasUser.ws.send(JSON.stringify({ type: 'get_location', busId: 'bus-missing' }));
  await sleep(200);
  assert(
    aliasUser.messages.some((m) => m.type === 'location_update' && m.busId === 'bus-101' && m.lat === 3),
    'get_location returns the latest cached location'
  );
  assert(
    aliasUser.messages.some((m) => m.type === 'not_found' && m.busId === 'bus-missing'),
    'get_location for an unknown bus returns not_found'
  );

  // 12. unsubscribe stops further updates
  aliasUser.ws.send(JSON.stringify({ type: 'unsubscribe', busId: 'bus-202' }));
  await sleep(100);
  assert(
    aliasUser.messages.some((m) => m.type === 'unsubscribed' && m.busId === 'bus-202'),
    'unsubscribe is acknowledged'
  );
  const beforeCount = aliasUser.messages.filter((m) => m.type === 'location_update' && m.busId === 'bus-202').length;
  driverWs.send(JSON.stringify({ type: 'location_update', busId: 'bus-202', lat: 5, lng: 6 }));
  await sleep(200);
  const afterCount = aliasUser.messages.filter((m) => m.type === 'location_update' && m.busId === 'bus-202').length;
  assert(afterCount === beforeCount, 'No updates are delivered after unsubscribe');

  // 13. Error replies
  aliasUser.ws.send('not json');
  aliasUser.ws.send(JSON.stringify({ type: 'does_not_exist' }));
  aliasUser.ws.send(JSON.stringify({ type: 'subscribe' }));
  aliasUser.ws.send(JSON.stringify({ type: 'location_update', busId: 'bus-x', lat: 'abc', lng: 1 }));
  await sleep(200);
  const errors = aliasUser.messages.filter((m) => m.type === 'error').map((m) => m.message);
  assert(errors.some((e) => e.includes('Invalid JSON')), 'Invalid JSON returns an error');
  assert(errors.some((e) => e.includes('Unknown message type')), 'Unknown message type returns an error');
  assert(errors.some((e) => e.includes('Missing busId in subscribe')), 'Subscribe without busId returns an error');
  assert(errors.some((e) => e.includes('Invalid location data')), 'Invalid coordinates return an error');

  // Close sockets
  userWs.close();
  userWs2.close();
  driverWs.close();
  queryUser.ws.close();
  allUser.ws.close();
  aliasUser.ws.close();

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
