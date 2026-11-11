'use strict';
const config = require('../lib/config');

if (!config.isDev) {
  module.exports = null;
} else {
  const router = require('express').Router();
  const { callProc, queryAs } = require('../lib/db');
  const { ROLES, requireLogin, startSession } = require('../lib/auth');

  const SEED_EMAILS = [
    'admin@filmlab.vn',
    'lab.saigon@filmlab.vn',
    'lab.hanoi@filmlab.vn',
    'lab.cantho@filmlab.vn',
    'lab.dalat@filmlab.vn',
    'expert@filmlab.vn',
    'shipper@filmlab.vn',
    'an.nguyen@example.com',
    'binh.tran@example.com',
    'chi.le@example.com',
    'khach.minh@example.com',
    'khach.lan@example.com',
    'khach.nam@example.com',
  ];

  const page = (res, extra) => res.render('dev/login', { title: 'Đăng nhập thử', emails: SEED_EMAILS, email: '', roles: null, ...extra });

  router.get('/dev/login', (req, res) => page(res, {}));

  router.post('/dev/login', async (req, res) => {
    const email = String(req.body.email || '').trim();
    const { recordset } = await callProc('auth', null, 'iam.sp_GetLoginInfo', { Email: email });
    const row = recordset[0];
    const roles = row && row.Roles ? row.Roles.split(',').filter((r) => ROLES.includes(r)) : [];

    if (!row || !row.IsActive || roles.length === 0) {
      res.locals.flash.push({ type: 'danger', msg: 'Không tìm thấy tài khoản, tài khoản bị khóa hoặc chưa có role.' });
      return page(res, { email });
    }

    let role = req.body.role;
    if (!role && roles.length === 1) role = roles[0];
    if (!role || !roles.includes(role)) return page(res, { email, roles }); // nhiều role: hỏi chọn

    const returnTo = await startSession(req, { id: row.UserId, name: row.FullName, roles, role });
    return res.redirect(returnTo || '/');
  });

  // Gọi một procedure bằng role + UserId của người đang đăng nhập
  router.get('/dev/ping', requireLogin, async (req, res) => {
    const t0 = Date.now();
    const r = await req.callProc('lab.sp_GetReferenceData');
    res.json({
      user: req.session.user,
      ms: Date.now() - t0,
      formats: r.recordsets[0].length,
      serviceTypes: r.recordsets[1].length,
      stages: r.recordsets[2].length,
    });
  });

  // SELECT trực tiếp qua RLS: Customer chỉ thấy thông báo của mình, Admin thấy tất cả
  router.get('/dev/notifications', requireLogin, async (req, res) => {
    const u = req.session.user;
    const r = await queryAs(u.role, u.id, 'SELECT COUNT(*) AS Total FROM arc.Notifications');
    res.json({ user: u, total: r.recordset[0].Total });
  });

  router.get('/dev/ui', (req, res) => res.render('dev/ui', { title: 'Mẫu giao diện' }));

  module.exports = router;
}