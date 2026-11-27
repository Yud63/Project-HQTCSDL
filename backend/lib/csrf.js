'use strict';
const crypto = require('crypto');

// Chống CSRF 2 lớp: (1) kiểm header trình duyệt tự gửi, (2) token trong session cho người đã đăng nhập.
// Chỉ áp dụng cho request có thể đổi dữ liệu (POST, PUT, PATCH, DELETE).
const SAFE_METHODS = new Set(['GET', 'HEAD', 'OPTIONS']);
// Form chạy khi chưa có session đăng nhập: miễn token, vẫn bị kiểm header
const TOKEN_EXEMPT = new Set(['/login', '/login/role', '/register', '/dev/login']);

function block(res) {
  return res.status(403).type('text/plain').send('Yêu cầu bị từ chối (CSRF).');
}

function headerOk(req) {
  // Sec-Fetch-Site: same-origin (từ trang của mình), none (người dùng tự gõ URL),
  // cross-site / same-site (từ trang khác)
  const site = req.get('sec-fetch-site');
  if (site) return site === 'same-origin' || site === 'none';

  // Trình duyệt cũ không có Sec-Fetch-Site: so host của Origin với host đang phục vụ
  const origin = req.get('origin');
  if (origin) {
    try {
      return new URL(origin).host === req.get('host');
    } catch (e) {
      return false;
    }
  }
  // Không có cả hai header: chặn (chế độ nghiêm ngặt)
  return false;
}

function tokenOk(req) {
  const expected = req.session && req.session.csrfToken;
  const sent = (req.body && req.body._csrf) || (req.query && req.query._csrf) || req.get('x-csrf-token');
  if (!expected || typeof sent !== 'string') return false;
  const a = Buffer.from(expected);
  const b = Buffer.from(sent);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

function csrfGuard(req, res, next) {
  // Người đã đăng nhập luôn có token trong session, view lấy qua res.locals.csrfToken
  if (req.session && req.session.user) {
    if (!req.session.csrfToken) req.session.csrfToken = crypto.randomBytes(32).toString('hex');
    res.locals.csrfToken = req.session.csrfToken;
  } else {
    res.locals.csrfToken = '';
  }

  if (SAFE_METHODS.has(req.method)) return next();
  if (!headerOk(req)) return block(res);

  const needToken = req.session && req.session.user && !TOKEN_EXEMPT.has(req.path);
  if (needToken && !tokenOk(req)) return block(res);
  return next();
}

module.exports = csrfGuard;