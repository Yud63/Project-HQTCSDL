'use strict';
const sql = require('mssql');
const config = require('./config');

const LOGINS = {
  auth: 'fl_auth',
  customer: 'fl_customer',
  labowner: 'fl_labowner',
  expert: 'fl_expert',
  delivery: 'fl_delivery',
  admin: 'fl_admin',
  system: 'fl_system',
};

const MAX_ATTEMPTS = 3; // thử lại khi deadlock (1205)
const NAME_RE = /^[A-Za-z_][A-Za-z0-9_]*$/;
const PROC_RE = /^[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*$/;
const pools = new Map();
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function poolKey(role) {
  const key = String(role || '').toLowerCase();
  if (!LOGINS[key]) throw new Error(`Role không hợp lệ: ${role}`);
  return key;
}

function getPool(role) {
  const key = poolKey(role);
  if (!pools.has(key)) {
    const password = config.dbPasswords[key];
    if (!password) throw new Error(`Thiếu mật khẩu của ${LOGINS[key]} trong .env (PW_${key.toUpperCase()})`);
    const pool = new sql.ConnectionPool({
      server: config.db.server,
      port: config.db.port,
      database: config.db.name,
      user: LOGINS[key],
      password,
      options: { encrypt: config.db.encrypt, trustServerCertificate: config.db.trustServerCertificate },
      pool: { max: 10, min: 0, idleTimeoutMillis: 30000 },
      requestTimeout: 30000,
    });
    pool.on('error', (e) => {
      console.error(`[db:${key}]`, e.message);
      pools.delete(key);
    });
    // Kết nối lỗi thì bỏ khỏi cache để lần gọi sau thử lại
    pools.set(key, pool.connect().catch((e) => { pools.delete(key); throw e; }));
  }
  return pools.get(key);
}

function cleanName(raw) {
  const n = String(raw).replace(/^@/, '');
  if (!NAME_RE.test(n) || n.startsWith('__')) throw new Error(`Tên tham số không hợp lệ: ${raw}`);
  return n;
}

function isTyped(v) {
  return v !== null && typeof v === 'object' && !(v instanceof Date) && !Buffer.isBuffer(v) && 'type' in v && 'value' in v;
}

// Tham số: giá trị thường (tự đoán kiểu), hoặc { type: sql.Xxx, value }.
// Mảng / object thường tự JSON.stringify (cho @ItemsJson, @SourcesJson...). null gửi NULL.
function bind(request, name, raw) {
  let type;
  let value = raw;
  if (isTyped(raw)) { type = raw.type; value = raw.value; }
  else if (raw === null) type = sql.NVarChar(sql.MAX);
  else if (typeof raw === 'boolean') type = sql.Bit;
  else if (typeof raw === 'bigint') type = sql.BigInt;
  else if (typeof raw === 'number') type = Number.isInteger(raw) ? (Math.abs(raw) > 2147483647 ? sql.BigInt : sql.Int) : sql.Float;
  else if (raw instanceof Date) type = sql.DateTime2;
  else if (Buffer.isBuffer(raw)) type = sql.VarBinary(sql.MAX);
  else if (typeof raw === 'object') { value = JSON.stringify(raw); type = sql.NVarChar(sql.MAX); }
  else { value = String(raw); type = sql.NVarChar(sql.MAX); }
  request.input(name, type, value);
}

function errNumber(e) {
  return e && (e.number ?? (e.originalError && (e.originalError.number ?? (e.originalError.info && e.originalError.info.number))));
}

// Đặt UserId (RLS) -> chạy body -> luôn reset UserId về NULL trước khi trả connection về pool
const wrap = (body) => `BEGIN TRY
EXEC sp_set_session_context @key=N'UserId', @value=@__uid;
${body};
EXEC sp_set_session_context @key=N'UserId', @value=NULL;
END TRY
BEGIN CATCH
EXEC sp_set_session_context @key=N'UserId', @value=NULL;
THROW;
END CATCH`;

async function execute(role, userId, body, params, outputs) {
  if (userId !== null && userId !== undefined && !Number.isInteger(userId)) {
    throw new Error('userId phải là số nguyên hoặc null');
  }
  const pool = await getPool(role);
  const text = wrap(body);
  for (let attempt = 1; ; attempt++) {
    const request = pool.request();
    request.input('__uid', sql.Int, userId ?? null);
    request.output('__rc', sql.Int);
    for (const [k, v] of Object.entries(params)) {
      if (v !== undefined) bind(request, cleanName(k), v);
    }
    for (const [k, t] of Object.entries(outputs)) request.output(cleanName(k), t);
    try {
      const result = await request.query(text);
      const output = { ...result.output };
      const returnValue = output.__rc ?? null;
      delete output.__rc;
      return { recordset: result.recordset || [], recordsets: result.recordsets || [], output, returnValue };
    } catch (e) {
      if (errNumber(e) === 1205 && attempt < MAX_ATTEMPTS) { await sleep(100 * attempt); continue; }
      throw e;
    }
  }
}

/**
 * Gọi stored procedure.
 *   callProc('customer', userId, 'ord.sp_CreateOrder', { CustomerId: userId, ... }, { NewOrderId: sql.Int })
 * Trả { recordset, recordsets, output, returnValue }.
 */
function callProc(role, userId, proc, params = {}, outputs = {}) {
  if (!PROC_RE.test(proc)) throw new Error(`Tên procedure không hợp lệ: ${proc}`);
  const names = Object.keys(params).filter((k) => params[k] !== undefined).map(cleanName);
  const args = names.map((n) => `@${n}=@${n}`)
    .concat(Object.keys(outputs).map((k) => { const n = cleanName(k); return `@${n}=@${n} OUTPUT`; }))
    .join(', ');
  return execute(role, userId, `EXEC @__rc = ${proc} ${args}`, params, outputs);
}

/** SELECT trực tiếp bảng đã GRANT + RLS (quyết định D1). Chỉ dùng cho SELECT. */
function queryAs(role, userId, text, params = {}) {
  return execute(role, userId, text, params, {});
}

module.exports = { sql, callProc, queryAs, getPool };