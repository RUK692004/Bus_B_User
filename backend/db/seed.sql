-- Sample data for local development. Run after schema.sql:
--   psql -d busbee_db -f db/seed.sql
-- Re-running it replaces the sample buses (matched by bus_number).

DELETE FROM buses WHERE bus_number IN ('KL-07-101', 'KL-07-202');

WITH bus AS (
  INSERT INTO buses (id, bus_number, bus_name, start_location, end_location, stops)
  VALUES ('11111111-1111-1111-1111-111111111101', 'KL-07-101', 'Aluva - Vyttila',
          'Aluva', 'Vyttila', '["Kalamassery", "Edappally", "Kaloor", "Palarivattom"]')
  RETURNING id
)
INSERT INTO route_coordinates (bus_id, seq, name, geom)
SELECT bus.id, p.seq, p.name, ST_SetSRID(ST_MakePoint(p.lng, p.lat), 4326)
FROM bus, (VALUES
  (0, 'Aluva',        76.3516, 10.1076),
  (1, 'Kalamassery',  76.3196, 10.0542),
  (2, 'Edappally',    76.3087, 10.0261),
  (3, 'Kaloor',       76.2999,  9.9971),
  (4, 'Palarivattom', 76.3080, 10.0030),
  (5, 'Vyttila',      76.3210,  9.9658)
) AS p(seq, name, lng, lat);

INSERT INTO buses (id, bus_number, bus_name, start_location, end_location, stops)
VALUES ('11111111-1111-1111-1111-111111111202', 'KL-07-202', 'Fort Kochi - Kakkanad',
        'Fort Kochi', 'Kakkanad', '["Thoppumpady", "Vyttila", "Palarivattom"]');

-- A current position for the first bus so /api/buses/nearby has something to return.
INSERT INTO bus_locations (bus_id, geom, heading, updated_at)
VALUES ('11111111-1111-1111-1111-111111111101', ST_SetSRID(ST_MakePoint(76.3087, 10.0261), 4326), 180, NOW())
ON CONFLICT (bus_id) DO UPDATE SET geom = EXCLUDED.geom, heading = EXCLUDED.heading, updated_at = NOW();
