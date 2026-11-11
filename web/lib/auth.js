'use strict';
const { HttpError, wantsJson } = require('./errors');

const ROLES = ['Customer', 'LabOwner', 'Expert', 'Delivery', 'Admin'];

function safeReturn(url) {
  if (typeof url !== 'string' || !url.startsWith('/') || url.startsWith('//') || url.startsWith('/\\')) return null;
  return url;
}

function requireLogin(req, res, next) {
  if (req.session && req.session.user) return next();
  if (wantsJson(req)) return next(new HttpError(401, 'Bạn cần đăng nhập.'));
  if (req.method === 'GET') req.session.returnTo = req.originalUrl;
  req.flash('warning', 'Vui lòng đăng nhập để tiếp tục.');
  return res.redirect('/login');
}

function requireRole(...roles) {
  for (const r of roles) {
    if (!ROLES.includes(r)) throw new Error(`requireRole: role không hợp lệ "${r}"`);
  }
  return (req, res, next) => requireLogin(req, res, (err) => {
    if (err) return next(err);
    if (!roles.includes(req.session.user.role)) {
      return next(new HttpError(403, 'Bạn không có quyền truy cập trang này.'));
    }
    return next();
  });
}

/** Tạo session mới (chống session fixation). Trả URL cần quay lại (hoặc null). */
function startSession(req, user) {
  if (!ROLES.includes(user.role) || !user.roles.includes(user.role)) throw new Error('Role không hợp lệ');
  const returnTo = safeReturn(req.session.returnTo);
  return new Promise((resolve, reject) => {
    req.session.regenerate((err) => {
      if (err) return reject(err);
      req.session.user = { id: user.id, name: user.name, roles: user.roles, role: user.role };
      return req.session.save((err2) => (err2 ? reject(err2) : resolve(returnTo)));
    });
  });
}

function destroySession(req) {
  return new Promise((resolve) => req.session.destroy(() => resolve()));
}

module.exports = { ROLES, requireLogin, requireRole, startSession, destroySession };