'use strict';
const { rateLimit } = require('express-rate-limit');

const base = { standardHeaders: 'draft-7', legacyHeaders: false };
const byUser = (req) => `u${req.session.user.id}`;

// Login: chỉ đếm lần thất bại (status >= 400), theo IP. 10 lần / 15 phút
const loginLimiter = rateLimit({
  ...base,
  windowMs: 15 * 60 * 1000,
  limit: 10,
  skipSuccessfulRequests: true,
  handler: (req, res) => {
    res.locals.flash.push({ type: 'danger', msg: 'Bạn thử đăng nhập sai quá nhiều lần. Vui lòng thử lại sau 15 phút.' });
    res.status(429).render('login', { title: 'Đăng nhập', email: '' });
  },
});

// Đăng ký: 10 lần / giờ theo IP (mỗi lần tốn bcrypt)
// Chọn vai trò: chỉ đếm lần thất bại (status >= 400), theo IP. 10 lần / 15 phút
const roleLimiter = rateLimit({
  ...base,
  windowMs: 15 * 60 * 1000,
  limit: 10,
  skipSuccessfulRequests: true,
  handler: (req, res) => {
    req.flash('danger', 'Bạn chọn vai trò sai quá nhiều lần. Vui lòng đăng nhập lại sau 15 phút.');
    res.redirect('/login');
  },
});
const registerLimiter = rateLimit({
  ...base,
  windowMs: 60 * 60 * 1000,
  limit: 10,
  handler: (req, res) => {
    res.locals.flash.push({ type: 'danger', msg: 'Bạn đăng ký quá nhiều lần. Vui lòng thử lại sau 1 giờ.' });
    res.status(429).render('register', { title: 'Đăng ký', email: '', fullName: '', phone: '' });
  },
});

// Chat: 10 câu / phút theo user (tốn quota Gemini). Client gọi fetch nên trả JSON
const chatLimiter = rateLimit({
  ...base,
  windowMs: 60 * 1000,
  limit: 10,
  keyGenerator: byUser,
  handler: (req, res) => {
    res.status(429).json({ error: 'Bạn gửi câu hỏi quá nhanh. Vui lòng chờ một phút rồi thử lại.' });
  },
});

// Upload scan: 10 lần / 10 phút theo user. Form thường nên flash rồi quay lại đơn
const uploadLimiter = rateLimit({
  ...base,
  windowMs: 10 * 60 * 1000,
  limit: 10,
  keyGenerator: byUser,
  handler: (req, res) => {
    req.flash('danger', 'Bạn tải ảnh lên quá nhiều lần. Vui lòng thử lại sau vài phút.');
    res.redirect(`/owner/orders/${encodeURIComponent(req.params.id)}`);
  },
});

module.exports = { loginLimiter, roleLimiter, registerLimiter, chatLimiter, uploadLimiter };