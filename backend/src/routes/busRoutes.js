'use strict';

const { Router } = require('express');
const {
  searchBus,
  searchTrips,
  nearbyBuses,
  getBusRoute,
} = require('../controllers/busController');

const router = Router();

// GET /api/buses/search?number=...
router.get('/search', searchBus);

// GET /api/buses/trips?from=...&to=...
router.get('/trips', searchTrips);

// GET /api/buses/nearby?lat=...&lng=...&radius=...
router.get('/nearby', nearbyBuses);

// GET /api/buses/:id/route
// NOTE: Keep this LAST so "/search", "/trips", "/nearby" are not matched as :id
router.get('/:id/route', getBusRoute);

module.exports = router;
