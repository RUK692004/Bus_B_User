'use strict';

const { Router } = require('express');
const { signup, login, getMe } = require('../controllers/authController');
const { protect } = require('../middleware/auth');

const router = Router();

// Public routes
router.post('/signup', signup);
router.post('/login', login);

// Protected routes
router.get('/me', protect, getMe);

module.exports = router;
