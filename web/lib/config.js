'use strict';
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '..', '.env'), quiet: true });

function required(name) {
  const v = process.env[name];
  if (!v) throw new Error(`Thiếu biến ${name} trong .env (xem .env.example)`);
  return v;
}

const bool = (v, def) => (v === undefined || v === '' ? def : String(v).toLowerCase() === 'true');

const nodeEnv = process.env.NODE_ENV || 'production';

module.exports = {
  nodeEnv,
  isDev: nodeEnv === 'development',
  port: Number(process.env.PORT) || 3000,
  sessionSecret: required('SESSION_SECRET'),
  db: {
    server: required('DB_SERVER'),
    port: Number(process.env.DB_PORT) || 1433,
    name: required('DB_NAME'),
    encrypt: bool(process.env.DB_ENCRYPT, true),
    trustServerCertificate: bool(process.env.DB_TRUST_CERT, true),
  },
  dbPasswords: {
    auth: process.env.PW_AUTH,
    customer: process.env.PW_CUSTOMER,
    labowner: process.env.PW_LABOWNER,
    expert: process.env.PW_EXPERT,
    delivery: process.env.PW_DELIVERY,
    admin: process.env.PW_ADMIN,
    system: process.env.PW_SYSTEM,
  },
  geminiApiKey: process.env.GEMINI_API_KEY || '',
  geminiModel: process.env.GEMINI_MODEL || 'gemini-3.8-flash',
  geminiFallbackModels: (process.env.GEMINI_FALLBACK_MODELS || 'gemini-3.5-flash-lite,gemini-3.6-flash')
    .split(',').map((s) => s.trim()).filter(Boolean),
  uploadDir: path.join(__dirname, '..', 'uploads'),
};