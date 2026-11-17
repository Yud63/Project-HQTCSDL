'use strict';
const session = require('express-session');
const { sql, callProc } = require('./db');

const DEFAULT_TTL_MS = 8 * 60 * 60 * 1000;

function expiresOf(sess) {
  const e = sess && sess.cookie && sess.cookie.expires;
  const t = e ? new Date(e).getTime() : Date.now() + DEFAULT_TTL_MS;
  return new Date(Number.isFinite(t) ? t : Date.now() + DEFAULT_TTL_MS);
}

class SqlSessionStore extends session.Store {
  get(sid, cb) {
    callProc('auth', null, 'iam.sp_SessionGet', { Sid: sid })
      .then((r) => {
        const row = r.recordset[0];
        cb(null, row ? JSON.parse(row.Data) : null);
      })
      .catch((e) => cb(e));
  }

  set(sid, sess, cb) {
    callProc('auth', null, 'iam.sp_SessionSet', {
      Sid: sid,
      Data: JSON.stringify(sess),
      ExpiresAt: { type: sql.DateTime2(0), value: expiresOf(sess) },
    })
      .then(() => cb && cb(null))
      .catch((e) => cb && cb(e));
  }

  touch(sid, sess, cb) {
    callProc('auth', null, 'iam.sp_SessionTouch', {
      Sid: sid,
      ExpiresAt: { type: sql.DateTime2(0), value: expiresOf(sess) },
    })
      .then(() => cb && cb(null))
      .catch((e) => cb && cb(e));
  }

  destroy(sid, cb) {
    callProc('auth', null, 'iam.sp_SessionDestroy', { Sid: sid })
      .then(() => cb && cb(null))
      .catch((e) => cb && cb(e));
  }
}

module.exports = SqlSessionStore;