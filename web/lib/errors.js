'use strict';
const config = require('./config');

class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.name = 'HttpError';
    this.status = status;
  }
}

// Hậu tố mã lỗi 50x0N của procedure
const SUFFIX_STATUS = { 1: 404, 2: 409, 3: 403, 4: 409, 5: 400, 6: 409 };

// Lỗi hệ thống SQL Server thường gặp
const SQL_STATUS = {
  229: [403, 'Bạn không có quyền thực hiện thao tác này.'],
  230: [403, 'Bạn không có quyền thực hiện thao tác này.'],
  262: [403, 'Bạn không có quyền thực hiện thao tác này.'],
  33504: [403, 'Thao tác không được phép với dữ liệu này.'],
  1205: [503, 'Hệ thống đang bận, vui lòng thử lại.'],
  2601: [409, 'Dữ liệu đã tồn tại.'],
  2627: [409, 'Dữ liệu đã tồn tại.'],
  547: [400, 'Dữ liệu không hợp lệ.'],
  515: [400, 'Thiếu dữ liệu bắt buộc.'],
  245: [400, 'Dữ liệu không hợp lệ.'],
  8114: [400, 'Dữ liệu không hợp lệ.'],
  8115: [400, 'Dữ liệu không hợp lệ.'],
  8152: [400, 'Dữ liệu quá dài.'],
};

const CONN_CODES = new Set(['ELOGIN', 'ESOCKET', 'ETIMEOUT', 'ECONNCLOSED', 'ENOTOPEN', 'EALREADYCONNECTING', 'ECONNRESET']);

function errNumber(e) {
  return e.number ?? (e.originalError && (e.originalError.number ?? (e.originalError.info && e.originalError.info.number)));
}

function mapDbError(err) {
  const n = errNumber(err);
  if (typeof n === 'number') {
    if (n >= 50000 && n <= 50999) return { status: SUFFIX_STATUS[n % 100] || 400, message: err.message };
    if (SQL_STATUS[n]) return { status: SQL_STATUS[n][0], message: SQL_STATUS[n][1] };
  }
  const code = err.code || (err.originalError && err.originalError.code);
  if (CONN_CODES.has(code)) return { status: 503, message: 'Không kết nối được cơ sở dữ liệu.' };
  return null;
}

function toHttp(err) {
  if (err instanceof HttpError) return { status: err.status, message: err.message };
  return mapDbError(err) || { status: 500, message: 'Lỗi hệ thống. Vui lòng thử lại sau.' };
}

function wantsJson(req) {
  return req.originalUrl.startsWith('/api/') || req.xhr || req.accepts(['html', 'json']) === 'json';
}

function notFound(req, res, next) {
  next(new HttpError(404, 'Không tìm thấy trang.'));
}

// eslint-disable-next-line no-unused-vars
function errorHandler(err, req, res, next) {
  if (res.headersSent) return next(err);
  const { status, message } = toHttp(err);
  if (status >= 500) console.error(err);
  if (wantsJson(req)) return res.status(status).json({ error: message });
  const detail = config.isDev && status >= 500 ? err.stack : undefined;
  return res.status(status).render('error', { title: 'Lỗi', status, message, detail }, (e, html) => {
    if (e) return res.status(status).type('text').send(`${status} ${message}`);
    return res.send(html);
  });
}

module.exports = { HttpError, mapDbError, notFound, errorHandler, wantsJson };