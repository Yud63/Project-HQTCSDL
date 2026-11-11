'use strict';
const router = require('express').Router();
const bcrypt = require('bcrypt');
const { sql, callProc } = require('../lib/db');
const { ROLES, startSession, destroySession } = require('../lib/auth');

const BCRYPT_COST = 10;
const PENDING_MS = 5 * 60 * 1000;
const DUMMY_HASH = bcrypt.hashSync('dummy-password-for-timing', BCRYPT_COST);
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const PHONE_RE = /^[0-9+\s().-]{8,20}$/;

const dbCode = (e) => e && (e.number ?? (e.originalError && (e.originalError.number ?? (e.originalError.info && e.originalError.info.number))));

function loginPage(res, status, extra) {
  return res.status(status).render('login', { title: 'Đăng nhập', email: '', ...extra });
}
function rolePage(res, status, roles) {
  return res.status(status).render('login-role', { title: 'Chọn vai trò', roles });
}
function registerPage(res, status, extra) {
  return res.status(status).render('register', { title: 'Đăng ký', email: '', fullName: '', phone: '', ...extra });
}
function fail(res, type, msg) {
  res.locals.flash.push({ type, msg });
}

async function finish(req, res, user, role) {
  const returnTo = await startSession(req, { ...user, role });
  return res.redirect(returnTo || '/');
}

router.get('/login', (req, res) => {
  if (req.session.user) return res.redirect('/');
  delete req.session.pendingLogin;
  return loginPage(res, 200, {});
});

router.post('/login', async (req, res) => {
  const body = req.body || {};
  const email = String(body.email || '').trim();
  const password = String(body.password || '');
  if (!email || !password) {
    fail(res, 'danger', 'Vui lòng nhập email và mật khẩu.');
    return loginPage(res, 400, { email });
  }

  const { recordset } = await callProc('auth', null, 'iam.sp_GetLoginInfo', { Email: email });
  const row = recordset[0];
  const generic = () => {
    fail(res, 'danger', 'Email hoặc mật khẩu không đúng.');
    return loginPage(res, 401, { email });
  };

  if (!row) {
    await bcrypt.compare(password, DUMMY_HASH);
    return generic();
  }
  if (row.AuthProvider !== 'Local' || !row.PasswordHash) {
    fail(res, 'warning', 'Tài khoản này đăng nhập bằng Google, chưa hỗ trợ đăng nhập bằng mật khẩu.');
    return loginPage(res, 400, { email });
  }

  let ok = false;
  try { ok = await bcrypt.compare(password, row.PasswordHash); } catch (e) { ok = false; }
  if (!ok) return generic();

  if (!row.IsActive) {
    fail(res, 'danger', 'Tài khoản đã bị khóa.');
    return loginPage(res, 403, { email });
  }
  const roles = row.Roles ? row.Roles.split(',').map((r) => r.trim()).filter((r) => ROLES.includes(r)) : [];
  if (roles.length === 0) {
    fail(res, 'danger', 'Tài khoản chưa được cấp vai trò nào.');
    return loginPage(res, 403, { email });
  }

  const user = { id: row.UserId, name: row.FullName, roles };
  if (roles.length === 1) return finish(req, res, user, roles[0]);

  req.session.pendingLogin = { ...user, at: Date.now() };
  return rolePage(res, 200, roles);
});

router.post('/login/role', async (req, res) => {
  const p = req.session.pendingLogin;
  if (!p || Date.now() - p.at > PENDING_MS) {
    delete req.session.pendingLogin;
    req.flash('warning', 'Phiên chọn vai trò đã hết hạn, vui lòng đăng nhập lại.');
    return res.redirect('/login');
  }
  const role = String((req.body || {}).role || '');
  if (!p.roles.includes(role)) {
    fail(res, 'danger', 'Vai trò không hợp lệ.');
    return rolePage(res, 400, p.roles);
  }
  return finish(req, res, { id: p.id, name: p.name, roles: p.roles }, role);
});

router.get('/register', (req, res) => {
  if (req.session.user) return res.redirect('/');
  return registerPage(res, 200, {});
});

router.post('/register', async (req, res) => {
  const b = req.body || {};
  const email = String(b.email || '').trim();
  const fullName = String(b.fullName || '').trim();
  const phone = String(b.phone || '').trim();
  const password = String(b.password || '');
  const confirm = String(b.confirm || '');
  const keep = { email, fullName, phone };

  let error = null;
  if (!EMAIL_RE.test(email)) error = 'Email không hợp lệ.';
  else if (fullName.length < 2) error = 'Vui lòng nhập họ tên.';
  else if (phone && !PHONE_RE.test(phone)) error = 'Số điện thoại không hợp lệ.';
  else if (password.length < 8) error = 'Mật khẩu tối thiểu 8 ký tự.';
  else if (Buffer.byteLength(password) > 72) error = 'Mật khẩu tối đa 72 byte.';
  else if (password !== confirm) error = 'Mật khẩu nhập lại không khớp.';
  if (error) {
    fail(res, 'danger', error);
    return registerPage(res, 400, keep);
  }

  const hash = await bcrypt.hash(password, BCRYPT_COST);
  try {
    await callProc('auth', null, 'iam.sp_RegisterUser', {
      Email: email,
      FullName: fullName,
      PasswordHash: hash,
      AuthProvider: 'Local',
      Phone: phone || null,
    }, { NewUserId: sql.Int });
  } catch (e) {
    const n = dbCode(e);
    if (n === 50104) {
      fail(res, 'danger', 'Email này đã được đăng ký.');
      return registerPage(res, 409, keep);
    }
    if (n === 50105) {
      fail(res, 'danger', 'Thông tin đăng ký không hợp lệ.');
      return registerPage(res, 400, keep);
    }
    throw e;
  }

  req.flash('success', 'Đăng ký thành công, hãy đăng nhập.');
  return res.redirect('/login');
});

router.post('/logout', async (req, res) => {
  await destroySession(req);
  res.redirect('/login');
});

module.exports = router;