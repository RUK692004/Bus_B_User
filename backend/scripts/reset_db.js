'use strict';

// Drops the app's tables and recreates them from db/schema.sql, so the
// database in .env matches the codebase exactly. For local development only.
//
//   npm run db:reset                 # rebuild empty tables
//   npm run db:reset -- --seed       # rebuild and load db/seed.sql
//   npm run db:reset -- --force      # also allowed when tables contain rows
//
// Only tables created in schema.sql are dropped (PostGIS's spatial_ref_sys and
// anything else stays). It refuses to run against a non-local DB_HOST, and
// refuses to delete rows unless --force is given.

require('dotenv').config();
const fs = require('fs');
const path = require('path');
const { pool } = require('../src/db');

const args = process.argv.slice(2);
const FORCE = args.includes('--force');
const SEED = args.includes('--seed');

const dbDir = path.join(__dirname, '..', 'db');
const schemaSql = fs.readFileSync(path.join(dbDir, 'schema.sql'), 'utf8');
const tables = [...schemaSql.matchAll(/CREATE TABLE IF NOT EXISTS (\w+)/g)].map((m) => m[1]);

const LOCAL_HOSTS = ['localhost', '127.0.0.1', '::1'];

async function main() {
  if (!LOCAL_HOSTS.includes(process.env.DB_HOST)) {
    console.error(`[db:reset] Refusing to reset non-local database host "${process.env.DB_HOST}".`);
    process.exit(1);
  }

  const client = await pool.connect();
  try {
    let totalRows = 0;
    for (const table of tables) {
      const exists = await client.query('SELECT to_regclass($1) AS t', [`public.${table}`]);
      if (!exists.rows[0].t) continue;
      const { rows } = await client.query(`SELECT COUNT(*)::int AS n FROM ${table}`);
      if (rows[0].n > 0) console.log(`[db:reset] ${table} has ${rows[0].n} row(s).`);
      totalRows += rows[0].n;
    }
    if (totalRows > 0 && !FORCE) {
      console.error('[db:reset] Tables contain data that would be deleted. Re-run with --force to delete it.');
      process.exit(1);
    }

    await client.query('BEGIN');
    await client.query(`DROP TABLE IF EXISTS ${tables.join(', ')} CASCADE`);
    await client.query(schemaSql);
    if (SEED) await client.query(fs.readFileSync(path.join(dbDir, 'seed.sql'), 'utf8'));
    await client.query('COMMIT');

    console.log(`[db:reset] Recreated ${tables.join(', ')} in "${process.env.DB_NAME}"${SEED ? ' and loaded seed data' : ''}.`);
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    throw err;
  } finally {
    client.release();
    await pool.end();
  }
}

main().catch((err) => {
  console.error('[db:reset] Failed, nothing was changed:', err.message || err.code);
  process.exit(1);
});
