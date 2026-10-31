'use strict';

require('dotenv').config();

// Without a secret every token operation fails, so refuse to start at all.
if (!process.env.JWT_SECRET) {
  console.error('[Server] JWT_SECRET is not set. Add it to .env (see .env.example).');
  process.exit(1);
}

const http = require('http');
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const authRoutes = require('./routes/authRoutes');
const busRoutes  = require('./routes/busRoutes');
const { initWebSocketServer } = require('./websocket');
const { query } = require('./db');

const app = express();
const PORT = process.env.PORT || 5000;

// ---------------------------------------------------------------------------
// Global Middleware
// ---------------------------------------------------------------------------
app.use(helmet());
app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: false }));

// Slows down password guessing: 20 auth requests per IP per 15 minutes.
// If you deploy behind a reverse proxy, also set `app.set('trust proxy', 1)`
// so the limit applies per client rather than to the proxy's IP.
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 20,
  standardHeaders: 'draft-8',
  legacyHeaders: false,
  message: { message: 'Too many attempts. Please try again in a few minutes.' },
});

// ---------------------------------------------------------------------------
// Routes
// ---------------------------------------------------------------------------
// Also reports whether PostgreSQL answers, so a phone browser can confirm the
// whole chain (phone -> server -> database) in one request.
app.get('/api/health', async (_req, res) => {
  let database = 'connected';
  try {
    await query('SELECT 1');
  } catch (err) {
    database = 'disconnected';
    console.error('[Health] Database check failed:', err.message || err.code);
  }
  res.json({ status: 'ok', database, timestamp: new Date() });
});
app.use('/api/auth', authLimiter, authRoutes);
app.use('/api/buses', busRoutes);

// ---------------------------------------------------------------------------
// 404 handler
// ---------------------------------------------------------------------------
app.use((_req, res) => {
  res.status(404).json({ message: 'Route not found.' });
});

// ---------------------------------------------------------------------------
// Global error handler
// ---------------------------------------------------------------------------
// eslint-disable-next-line no-unused-vars
app.use((err, _req, res, _next) => {
  console.error('[Server Error]', err.message);
  res.status(err.status || 500).json({ message: err.message || 'Internal server error.' });
});

// ---------------------------------------------------------------------------
// Server & WebSocket Setup
// ---------------------------------------------------------------------------
const server = http.createServer(app);
const wss = initWebSocketServer(server);

app.server = server;
app.wss = wss;

server.listen(PORT, () => {
  console.log(`[Server] Running on http://localhost:${PORT}`);
  console.log(`[WebSocket] Live tracking ready on ws://localhost:${PORT}`);
});

module.exports = app;
