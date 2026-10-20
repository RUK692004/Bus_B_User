# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

BusBee user-side app: a Flutter client (`flutter_app/`) for searching buses and tracking them live, backed by a Node/Express 5 + PostgreSQL (PostGIS) API with a WebSocket server (`backend/`). The project was migrated off Firebase/Firestore; nothing Firebase-related remains (don't reintroduce the `google-services` Gradle plugin). A separate driver app (not in this repo) is expected to push locations over the WebSocket.

## Commands

### Backend (`backend/`)
```sh
npm install
cp .env.example .env      # set DB_* and JWT_SECRET (PORT defaults to 5000)
npm run dev               # nodemon src/server.js
npm start                 # node src/server.js
npm test                  # node test_ws.js — boots the server in-process and runs WebSocket integration checks
psql -d busbee_db -f db/schema.sql   # create tables (idempotent; needs PostGIS)
psql -d busbee_db -f db/seed.sql     # optional sample buses/routes around Kochi
```
`npm test` starts the real server on `PORT`, so stop any running dev server first. It does not need a database (location persistence failures are only logged). `test_ws.js` covers the whole WebSocket protocol (aliases, query-string subscriptions, errors); extend it when you change `websocket.js`. There is no linter or unit-test framework for the backend, and no migration tool: `db/schema.sql` is the source of truth for the schema, so update it with any query that needs new columns.

### Flutter (`flutter_app/`)
```sh
flutter pub get
flutter run                                   # add -d chrome / -d <device>
flutter run --dart-define=API_BASE_URL=http://<host>:5000 --dart-define=WS_BASE_URL=ws://<host>:5000
flutter analyze                               # lints: package:flutter_lints/flutter.yaml
flutter test                                  # all tests
flutter test test/services/bus_service_test.dart          # one file
flutter test --plain-name "substring of test name"        # one test
```

## Architecture

### Backend
- `src/server.js` creates an `http.Server` wrapping the Express app and attaches the WebSocket server (`src/websocket.js`) to the **same port**. It exports `app` with `app.server`/`app.wss` attached (used by `test_ws.js` to shut down).
- REST routes: `GET /api/health`, `/api/auth` (`POST signup`, `POST login`, `GET /me` behind the `protect` JWT middleware in `src/middleware/auth.js`) and `/api/buses` (`search?number=`, `trips?from=&to=`, `nearby?lat=&lng=&radius=` (metres, default 2000), `:id/route`). In `busRoutes.js`, `/:id/route` must stay last. Bus routes and the WebSocket are currently unauthenticated.
- Responses are JSON. Errors are always `{ message }`; unknown routes return 404 `{ message: 'Route not found.' }` (the Flutter `BusService` prefix fallback keys on this text). Success shapes: auth → `{ token, user }` / `{ user }`; search → `{ bus }`; trips/nearby → `{ buses }`; route → `{ route }`.
- Auth: bcrypt hashes, JWT signed with `JWT_SECRET`, 7-day expiry, payload `{ id, name, email, role }`. Emails are lower-cased. `signup` accepts `role` from the request body (default `'user'`). There is no refresh-token endpoint.
- `src/db.js` exposes a `pg` Pool (idle-client errors are logged, not fatal) and a `query(text, params)` helper; always use parameterised queries. The schema is in `db/schema.sql`: `users`, `buses` (uuid `id`; `stops` is a JSONB array of stop-name strings), `bus_locations` (one row per bus, `geom` point SRID 4326), `route_coordinates` (`bus_id`, `seq`, `name`, `geom`). Bus ids are uuids, so WebSocket updates for non-uuid bus ids still broadcast but fail to persist. PostGIS points are (lng, lat): `ST_MakePoint(lng, lat)`, `ST_X` = lng, `ST_Y` = lat.
- `searchTrips` matches buses where `from` comes before `to` in the ordered sequence `start_location → stops[] → end_location` (case-insensitive exact names). `nearby` only returns buses that have a row in `bus_locations`.
- **WebSocket protocol** (`src/websocket.js`): live state is held **in memory**, so it only works on a single server instance. Every connection first gets `{ type: 'connected' }`. Drivers send `register_driver` / `location_update` (`busId`, `lat`/`latitude`, `lng`/`longitude`, `heading`, `speed`) and receive `driver_registered` / `location_ack`. The server caches the latest location per bus, broadcasts it to subscribers, and upserts it into `bus_locations` in the background (failures are logged once per distinct error and otherwise ignored). Users send `subscribe` / `unsubscribe` / `subscribe_all` / `get_location` / `ping` and receive `subscribed`, `unsubscribed`, `not_found`, `pong`, or `error`. They can also subscribe through the connection query string (`?role=user&busId=…`, `?subscribe=*`). New subscribers get the cached location immediately. Outgoing `location_update` payloads repeat each field under both naming styles (`busId`+`bus_id`, `lat`+`latitude`, `lng`+`longitude`), so clients can read either. Message types are accepted under several aliases (`msg.type || msg.action || msg.event`), dispatched through the `messageHandlers` map to one `handle*` function per type; build outgoing location messages with `locationPayload()`. A 30 s ping/pong heartbeat terminates dead sockets.

### Flutter client
- `lib/main.dart` calls `determineInitialScreen()`, which validates the stored JWT through `AuthService.getCurrentUser()` (`/api/auth/me`). It routes to `BusSearchScreen`, or to `LoginScreen` when there is no token or the token is invalid (it clears the token on 401/403/404). Navigation uses plain `Navigator.push` with `MaterialPageRoute`; Settings logs out with `pushAndRemoveUntil` back to `LoginScreen`. There is no router package and no state-management library (`setState` only). The app uses a fixed dark theme.
- Screens (`lib/screens/`): `LoginScreen` ↔ `SignUpScreen` → `BusSearchScreen` (search by bus number, by from/to trip, and "nearby" via `LocationService`) → `BusRouteDetailsScreen` (Google Map with route polyline, stop markers, and the live bus marker from the WebSocket stream; can open the route in Google Maps through `url_launcher`). `SettingsScreen` holds logout.
- Screens hold UI and state only; logic lives in services and reusable widgets live in `lib/widgets/` (`BusCard`, `RouteStopTile`). `services/location_service.dart` (`LocationService`) wraps permissions, GPS and reverse geocoding and throws `LocationException` with a user-facing message. `services/route_resolver.dart` (`RouteResolver`) turns a `BusInfo` into map points: it uses `/api/buses/:id/route` when that returns at least 2 points, otherwise it geocodes `BusInfo.routeStopNames`, adding hints such as "Kochi, Kerala, India" (capped at 8 stops off-web). `utils/google_maps_links.dart` builds the "Open in Google Maps" URL.
- `BusRouteDetailsScreen` subscribes with `bus.id ?? bus.number`. On web it polls `isGoogleMapsLoaded()` for up to about 6 s before showing the map.
- `services/api_client.dart`: `ApiClient` wraps `package:http` (15 s timeout), adds the bearer token when a call passes `requiresAuth: true` (through an injected `tokenProvider`), and turns every failure (HTTP ≥ 400, timeouts, network, bad JSON) into `ApiException(message, statusCode, data)`, taking `message` from the server's `message`/`error` field. The default base URL comes from `--dart-define=API_BASE_URL`, falling back to `http://10.0.2.2:5000` on the Android emulator and `http://localhost:5000` elsewhere.
- `services/auth_service.dart`: stores tokens in `flutter_secure_storage` (`auth_access_token`, plus `auth_refresh_token` if the server ever returns one) and re-exports `api_client.dart` and the models, so screens usually import only `auth_service.dart`.
- `services/bus_service.dart`: REST calls under `/api/buses` (on a route-not-found 404 it retries with `/api/v1/buses` and keeps whichever prefix worked). `searchBusByNumber` returns `null` on 404. `subscribeBusLocation()` opens a `WebSocketChannel`, sends `subscribe`, emits `location_update` maps, and sends `unsubscribe` on cancel. When the socket drops it reconnects and resubscribes with exponential backoff (1 s doubling to 30 s, reset on any message) until cancelled. Tests inject a `connect` factory to exercise this; an injected `channel` without `connect` is used once and the stream closes when it ends. The WS URL comes from `WS_BASE_URL` or is derived from the HTTP base URL (`http`→`ws`, `https`→`wss`).
- Models (`lib/models/`): `BusInfo.fromJson` accepts both snake_case backend keys and camelCase/legacy Firestore keys (`bus_number`/`busNumber`/`number`, `distance_km`/`distanceKm`, `start_location`/`start`, …). Keep that tolerance when you change payloads. `UserModel` and `AuthResponse` are plain classes with hand-written `fromJson`/`toJson` (no codegen).
- **Testability through constructor injection:** screens take optional `authService`/`busService`/`locationService` parameters (and `BusRouteDetailsScreen` takes a `routeResolver` and `wsChannel`) and create defaults once (in `initState` or a `late final` field, never in a getter), services take `ApiClient`/`FlutterSecureStorage`, `ApiClient` takes an `http.Client`, and `subscribeBusLocation` takes a `channel`. Tests use `MockClient` from `package:http/testing.dart` plus the fakes in `test/test_helpers.dart` (`FakeSecureStorage`, `FakeLocationService`, `FakeWebSocketChannel`, which exposes `incoming`/`outgoing` stream controllers); `RouteResolver` takes a `geocode` function. Keep new services and screens injectable the same way.
- `utils/google_maps_availability.dart` uses a conditional export (`dart.library.js_interop`) to detect whether the Google Maps JS API loaded on web, using `dart:js_interop` (the stub always returns `true`). Don't use the deprecated `dart:js`. The Maps API keys are configured in `web/index.html` and `android/app/src/main/AndroidManifest.xml`.
- Errors are not swallowed silently: Flutter code logs caught exceptions with `debugPrint` (prefixed by area, e.g. `[BusSearch]`) before showing a user-facing message or falling back; the backend logs with `console.error`/`console.warn`. Keep new `catch` blocks consistent with this.
