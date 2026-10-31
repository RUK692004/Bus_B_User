'use strict';

// Compares the database in .env with db/schema.sql, without changing anything.
//
//   npm run db:check
//
// It builds schema.sql inside a temporary schema in one transaction, compares
// its tables, columns, geometry types and indexes with `public`, then rolls
// the transaction back. Exits with code 1 when they differ.

require('dotenv').config();
const fs = require('fs');
const path = require('path');
const { pool } = require('../src/db');

const TEMP = 'schema_check';
const schemaSql = fs.readFileSync(path.join(__dirname, '..', 'db', 'schema.sql'), 'utf8');

/** Tables, columns, geometry types and indexes of one schema, as comparable strings. */
async function describe(client, schema) {
  const strip = (s) => (s || '').replaceAll(`${schema}.`, '');
  const items = new Map();

  const columns = await client.query(
    // Base tables only: PostGIS also adds views (geometry_columns, ...) to public.
    `SELECT c.table_name, c.column_name, c.udt_name, c.is_nullable, c.column_default
     FROM information_schema.columns c
     JOIN information_schema.tables t
       ON t.table_schema = c.table_schema AND t.table_name = c.table_name
     WHERE c.table_schema = $1 AND t.table_type = 'BASE TABLE'
       AND c.table_name <> 'spatial_ref_sys'`,
    [schema]
  );
  for (const c of columns.rows) {
    const nullable = c.is_nullable === 'NO' ? 'NOT NULL' : 'NULL';
    items.set(
      `column ${c.table_name}.${c.column_name}`,
      `${c.udt_name} ${nullable} default=${strip(c.column_default) || 'none'}`
    );
  }

  const geometry = await client.query(
    `SELECT f_table_name, f_geometry_column, type, srid
     FROM geometry_columns WHERE f_table_schema = $1`,
    [schema]
  );
  for (const g of geometry.rows) {
    items.set(`geometry ${g.f_table_name}.${g.f_geometry_column}`, `${g.type} SRID ${g.srid}`);
  }

  const indexes = await client.query(
    `SELECT indexname, indexdef FROM pg_indexes
     WHERE schemaname = $1 AND tablename <> 'spatial_ref_sys'`,
    [schema]
  );
  for (const i of indexes.rows) {
    items.set(`index ${i.indexname}`, strip(i.indexdef));
  }

  return items;
}

async function main() {
  const client = await pool.connect();
  let differences = 0;
  try {
    await client.query('BEGIN');
    await client.query(`CREATE SCHEMA ${TEMP}`);
    await client.query(`SET LOCAL search_path TO ${TEMP}, public`);
    await client.query(schemaSql);

    const expected = await describe(client, TEMP);
    const actual = await describe(client, 'public');

    for (const [key, want] of expected) {
      const have = actual.get(key);
      if (have === undefined) {
        console.log(`MISSING   ${key}\n          expected: ${want}`);
        differences++;
      } else if (have !== want) {
        console.log(`DIFFERENT ${key}\n          expected: ${want}\n          database: ${have}`);
        differences++;
      }
    }
    for (const [key, have] of actual) {
      if (!expected.has(key)) {
        console.log(`EXTRA     ${key}\n          database: ${have}`);
        differences++;
      }
    }
  } finally {
    await client.query('ROLLBACK').catch(() => {});
    client.release();
    await pool.end();
  }

  if (differences === 0) {
    console.log(`Database "${process.env.DB_NAME}" matches db/schema.sql.`);
  } else {
    console.log(`\n${differences} difference(s). Run "npm run db:reset" to rebuild the tables from db/schema.sql.`);
    process.exit(1);
  }
}

main().catch((err) => {
  console.error('[db:check] Failed:', err.message || err.code);
  process.exit(1);
});
