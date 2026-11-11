'use strict';
const router = require('express').Router();
const { queryAs } = require('../lib/db');

router.get('/health', async (req, res) => {
  try {
    await queryAs('auth', null, 'SELECT 1 AS ok');
    res.json({ status: 'ok', db: 'ok' });
  } catch (e) {
    console.error('[health]', e.message);
    res.status(503).json({ status: 'degraded', db: 'error' });
  }
});

module.exports = router;