'use strict';
const router = require('express').Router();
const { homeFor } = require('../lib/nav');

router.get('/', (req, res) => {
  const user = req.session.user;
  if (!user) return res.redirect('/login');
  const home = homeFor(user.role);
  if (home) return res.redirect(home);
  return res.render('home', { title: 'Trang chủ' });
});

module.exports = router;