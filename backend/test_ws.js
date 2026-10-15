'use strict';

const { WebSocket } = require('ws');
const app = require('./src/server');

const PORT = process.env.PORT || 5000;
const WS_URL = `ws://localhost:${PORT}`;

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
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

  // Close sockets
  userWs.close();
  userWs2.close();
  driverWs.close();

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
