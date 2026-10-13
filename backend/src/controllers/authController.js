'use strict';

const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { query } = require('../db');

const SALT_ROUNDS = 10;
const JWT_EXPIRES_IN = '7d';

/**
 * Sign a JWT for the given user payload.
 * @param {{ id: string, name: string, email: string, role: string }} user
 * @returns {string} Signed JWT token
 */
const signToken = (user) =>
  jwt.sign(
    { id: user.id, name: user.name, email: user.email, role: user.role },
    process.env.JWT_SECRET,
    { expiresIn: JWT_EXPIRES_IN }
  );

// ---------------------------------------------------------------------------
// POST /api/auth/signup
// ---------------------------------------------------------------------------
const signup = async (req, res) => {
  const { name, email, password, role = 'user' } = req.body;

  // --- Input validation ---
  if (!name || !email || !password) {
    return res.status(400).json({ message: 'name, email, and password are required.' });
  }
  if (typeof email !== 'string' || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return res.status(400).json({ message: 'Please provide a valid email address.' });
  }
  if (password.length < 6) {
    return res.status(400).json({ message: 'Password must be at least 6 characters.' });
  }

  try {
    // --- Check for existing email ---
    const existing = await query('SELECT id FROM users WHERE email = $1', [email.toLowerCase()]);
    if (existing.rowCount > 0) {
      return res.status(409).json({ message: 'An account with this email already exists.' });
    }

    // --- Hash password ---
    const password_hash = await bcrypt.hash(password, SALT_ROUNDS);

    // --- Insert user ---
    const result = await query(
      `INSERT INTO users (id, name, email, password_hash, role, created_at)
       VALUES (gen_random_uuid(), $1, $2, $3, $4, NOW())
       RETURNING id, name, email, role`,
      [name.trim(), email.toLowerCase(), password_hash, role]
    );

    const user = result.rows[0];
    const token = signToken(user);

    return res.status(201).json({ token, user });
  } catch (err) {
    console.error('[signup] Error:', err.message);
    return res.status(500).json({ message: 'Server error during signup.' });
  }
};

// ---------------------------------------------------------------------------
// POST /api/auth/login
// ---------------------------------------------------------------------------
const login = async (req, res) => {
  const { email, password } = req.body;

  if (!email || !password) {
    return res.status(400).json({ message: 'email and password are required.' });
  }

  try {
    // --- Find user ---
    const result = await query(
      'SELECT id, name, email, role, password_hash FROM users WHERE email = $1',
      [email.toLowerCase()]
    );

    if (result.rowCount === 0) {
      return res.status(401).json({ message: 'Invalid email or password.' });
    }

    const user = result.rows[0];

    // --- Compare password ---
    const isMatch = await bcrypt.compare(password, user.password_hash);
    if (!isMatch) {
      return res.status(401).json({ message: 'Invalid email or password.' });
    }

    const token = signToken(user);

    // Strip password_hash before sending
    const { password_hash, ...safeUser } = user;
    return res.status(200).json({ token, user: safeUser });
  } catch (err) {
    console.error('[login] Error:', err.message);
    return res.status(500).json({ message: 'Server error during login.' });
  }
};

// ---------------------------------------------------------------------------
// GET /api/auth/me  (protected)
// ---------------------------------------------------------------------------
const getMe = async (req, res) => {
  // req.user is set by the protect middleware
  try {
    const result = await query(
      'SELECT id, name, email, role FROM users WHERE id = $1',
      [req.user.id]
    );

    if (result.rowCount === 0) {
      return res.status(404).json({ message: 'User not found.' });
    }

    return res.status(200).json({ user: result.rows[0] });
  } catch (err) {
    console.error('[getMe] Error:', err.message);
    return res.status(500).json({ message: 'Server error fetching user.' });
  }
};

module.exports = { signup, login, getMe };
