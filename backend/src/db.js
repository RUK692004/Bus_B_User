'use strict';

require('dotenv').config();
const { Pool } = require('pg');

const pool = new Pool({
  host: process.env.DB_HOST,
  port: parseInt(process.env.DB_PORT, 10) || 5432,
  database: process.env.DB_NAME,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
});

// The pool discards the broken client and opens a new one on the next query,
// so an idle-client error is logged rather than taking the whole server down.
pool.on('error', (err) => {
  console.error('[DB] Unexpected error on idle client:', err.message);
});

pool.on('connect', () => {
  console.log('[DB] New client connected to PostgreSQL');
});

/**
 * Execute a parameterised query.
 * @param {string} text   - SQL query string
 * @param {Array}  params - Positional parameters
 */
const query = (text, params) => pool.query(text, params);

module.exports = { pool, query };
