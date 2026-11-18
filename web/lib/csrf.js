'use strict';

// Chống CSRF bằng cách kiểm header mà trình duyệt tự gửi, kẻ tấn công không giả được.
// Chỉ áp dụng cho request có thể đổi dữ liệu (POST, PUT, PATCH, DELETE).
const SAFE_METHODS = new Set(['GET', 'HEAD', 'OPTIONS']);

function block(res) {
  return res.status(403).type('text/plain').send('Yêu cầu bị từ chối (CSRF).');
}

function csrfGuard(req, res, next) {
  if (SAFE_METHODS.has(req.method)) return next();

  // Trình duyệt hiện đại luôn gửi Sec-Fetch-Site: same-origin (từ trang của mình),
  // none (người dùng tự gõ URL), cross-site / same-site (từ trang khác)
  const site = req.get('sec-fetch-site');
  if (site) {
    return site === 'same-origin' || site === 'none' ? next() : block(res);
  }

  // Trình duyệt cũ không có Sec-Fetch-Site: so host của Origin với host đang phục vụ
  const origin = req.get('origin');
  if (origin) {
    try {
      return new URL(origin).host === req.get('host') ? next() : block(res);
    } catch (e) {
      return block(res);
    }
  }

  // Không có cả hai header: chặn (chế độ nghiêm ngặt)
  return block(res);
}

module.exports = csrfGuard;