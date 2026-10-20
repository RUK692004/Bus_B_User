-- BusBee database schema (PostgreSQL 13+ with PostGIS).
-- Safe to run more than once:  psql -d busbee_db -f db/schema.sql
--
-- Geometry columns store points as (lng, lat) in SRID 4326:
--   ST_SetSRID(ST_MakePoint(lng, lat), 4326);  ST_X(geom) = lng, ST_Y(geom) = lat.

CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TABLE IF NOT EXISTS users (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  name          text        NOT NULL,
  email         text        NOT NULL UNIQUE,  -- stored lower-cased by the API
  password_hash text        NOT NULL,
  role          text        NOT NULL DEFAULT 'user',
  created_at    timestamptz NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS buses (
  id             uuid  PRIMARY KEY DEFAULT gen_random_uuid(),
  bus_number     text  NOT NULL,
  bus_name       text,
  start_location text  NOT NULL,
  end_location   text  NOT NULL,
  -- Ordered intermediate stop names, e.g. ["Kaloor", "MG Road"].
  stops          jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(stops) = 'array')
);

-- /api/buses/search matches bus_number case-insensitively.
CREATE UNIQUE INDEX IF NOT EXISTS buses_bus_number_lower_idx ON buses (LOWER(bus_number));

-- Latest known position per bus, upserted by the WebSocket server.
CREATE TABLE IF NOT EXISTS bus_locations (
  bus_id     uuid                  PRIMARY KEY REFERENCES buses (id) ON DELETE CASCADE,
  geom       geometry(Point, 4326) NOT NULL,
  heading    double precision      NOT NULL DEFAULT 0,
  updated_at timestamptz           NOT NULL DEFAULT NOW()
);

-- /api/buses/nearby filters with ST_DWithin on geom::geography.
CREATE INDEX IF NOT EXISTS bus_locations_geog_idx ON bus_locations USING GIST ((geom::geography));

-- Saved route polyline for the map, in travel order.
CREATE TABLE IF NOT EXISTS route_coordinates (
  id     bigserial             PRIMARY KEY,
  bus_id uuid                  NOT NULL REFERENCES buses (id) ON DELETE CASCADE,
  seq    integer               NOT NULL,
  name   text,
  geom   geometry(Point, 4326) NOT NULL,
  UNIQUE (bus_id, seq)
);
