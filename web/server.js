'use strict';
const fs = require('fs');
const path = require('path');
const express = require('express');
const session = require('express-session');
const config = require('./lib/config');
const { callProc } = require('./lib/db');
const { HttpError, notFound, errorHandler } = require('./lib/errors');
const { menuFor } = require('./lib/nav');

const app = express();
app.disable('x-powered-by');
app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));

fs.mkdirSync(config.uploadDir, { recursive: true });

app.use(express.static(path.join(__dirname, 'public')));
app.use(express.urlencoded({ extended: true }));
app.use(express.json());

// Session lưu trong bộ nhớ (mất khi restart server)
app.use(session({
  name: 'fl.sid',
  secret: config.sessionSecret,
  resave: false,
  saveUninitialized: false,
  cookie: { httpOnly: true, sameSite: 'lax', maxAge: 8 * 60 * 60 * 1000 },
}));

// Flash + biến dùng chung cho view + req.callProc
app.use((req, res, next) => {
  const user = req.session.user || null;

  // Dùng req.flash(type, msg) rồi res.redirect(...). type: success | info | warning | danger
  req.flash = (type, msg) => {
    if (!req.session.flash) req.session.flash = [];
    req.session.flash.push({ type, msg });
  };
  res.locals.flash = req.session.flash || [];
  delete req.session.flash;

  res.locals.currentUser = user;
  res.locals.menu = menuFor(user && user.role);
  res.locals.currentPath = req.path;
  res.locals.isDev = config.isDev;

  // Gọi procedure bằng role và UserId của người đang đăng nhập (UserId luôn từ session)
  req.callProc = (proc, params, outputs) => {
    const u = req.session.user;
    if (!u) throw new HttpError(401, 'Bạn cần đăng nhập.');
    return callProc(u.role, u.id, proc, params, outputs);
  };
  next();
});

// Tự nạp mọi file trong routes/ (file export router; export null thì bỏ qua)
const routesDir = path.join(__dirname, 'routes');
for (const file of fs.readdirSync(routesDir).filter((f) => f.endsWith('.js')).sort()) {
  const router = require(path.join(routesDir, file));
  if (typeof router === 'function') {
    app.use(router);
    console.log(`  nạp routes/${file}`);
  }
}

app.use(notFound);
app.use(errorHandler);

app.listen(config.port, (err) => {
  if (err) {
    console.error(`Không mở được cổng ${config.port}:`, err.message);
    process.exit(1);
  }
  console.log(`FilmLab web: http://localhost:${config.port} (${config.nodeEnv})`);
});