'use strict';
const express = require('express');
const router = express.Router();
const { requireLogin, requireRole } = require('../lib/auth');
const { sql } = require('../lib/db');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const multer = require('multer');

router.use('/market', requireLogin, requireRole('Customer'));

// 50601 không tồn tại, 50602 sai trạng thái, 50603 không có quyền, 50604 đã đánh giá, 50605 tham số sai, 50606 không đủ số lượng
const BUSINESS_ERRORS = [50601, 50602, 50603, 50604, 50605, 50606];
const errNumber = (e) => e && (e.number ?? (e.originalError && e.originalError.number));

const PAGE_SIZE = 12;
const SORTS = ['Newest', 'PriceAsc', 'PriceDesc'];
const TYPES = ['Sell', 'Exchange', 'Wanted'];
const str = (v) => { const s = String(v || '').trim(); return s ? s : null; };
const posInt = (v) => { const n = parseInt(v, 10); return Number.isInteger(n) && n > 0 ? n : null; };
const price = (v) => { const n = Number(String(v || '').trim()); return String(v || '').trim() !== '' && Number.isFinite(n) && n >= 0 ? n : null; };

router.get('/market', async (req, res, next) => {
  try {
    const q = {
      keyword: str(req.query.keyword),
      categoryId: posInt(req.query.category),
      type: TYPES.includes(req.query.type) ? req.query.type : null,
      min: price(req.query.min),
      max: price(req.query.max),
      city: str(req.query.city),
      sort: SORTS.includes(req.query.sort) ? req.query.sort : 'Newest',
      page: posInt(req.query.page) || 1,
    };

    const list = await req.callProc('mkt.sp_SearchListings', {
      Keyword: q.keyword, CategoryId: q.categoryId, ListingType: q.type,
      MinPrice: q.min, MaxPrice: q.max, City: q.city,
      SortBy: q.sort, PageNo: q.page, PageSize: PAGE_SIZE,
    });
    const categories = (await req.callProc('mkt.sp_GetCategories')).recordset;

    const listings = list.recordset;
    const totalRows = listings.length ? listings[0].TotalRows : 0;
    const pageCount = Math.max(1, Math.ceil(totalRows / PAGE_SIZE));

    const params = new URLSearchParams();
    if (q.keyword) params.set('keyword', q.keyword);
    if (q.categoryId) params.set('category', q.categoryId);
    if (q.type) params.set('type', q.type);
    if (q.min !== null) params.set('min', q.min);
    if (q.max !== null) params.set('max', q.max);
    if (q.city) params.set('city', q.city);
    if (q.sort !== 'Newest') params.set('sort', q.sort);
    const base = params.toString();
    const pageUrl = (n) => '/market?' + (base ? base + '&' : '') + 'page=' + n;

    res.render('market/index', { title: 'Chợ', listings, categories, q, totalRows, pageCount, pageUrl });
  } catch (e) {
    if (BUSINESS_ERRORS.includes(errNumber(e))) {
      req.flash('danger', e.message);
      return res.redirect('/market');
    }
    return next(e);
  }
});

// ---------- Chợ lượt 2 ----------
const STATUS_ACTIONS = ['Confirmed', 'Shipped', 'Completed', 'Cancelled', 'Disputed'];
const text = (v, n) => { const s = str(v); return s ? s.slice(0, n) : null; };

function fail(req, res, e, next, back) {
  if (BUSINESS_ERRORS.includes(errNumber(e))) {
    req.flash('danger', e.message);
    return res.redirect(back);
  }
  return next(e);
}

// Mỗi dòng một URL, dòng đầu là ảnh chính; trả { json } hoặc { error }
function parseImages(raw) {
  const urls = String(raw || '').split(/\r?\n/).map((s) => s.trim()).filter(Boolean);
  if (urls.length > 8) return { error: 'Tối đa 8 ảnh.' };
  for (const u of urls) {
    if (u.length > 255) return { error: 'URL ảnh quá dài (tối đa 255 ký tự).' };
    if (!/^(https?:\/\/|\/(?!\/))/i.test(u)) return { error: 'URL ảnh phải bắt đầu bằng http://, https:// hoặc /.' };
  }
  if (!urls.length) return { json: null };
  return { json: JSON.stringify(urls.map((url, i) => ({ url, isPrimary: i === 0 }))) };
}

// ---------- Upload ảnh tin chợ: ảnh công khai nên lưu trong public ----------
const marketImgDir = path.join(__dirname, '..', 'public', 'img', 'market');
const IMG_EXT = { 'image/jpeg': '.jpg', 'image/png': '.png', 'image/webp': '.webp' };
const IMG_SIG = {
  'image/jpeg': (b) => b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff,
  'image/png': (b) => b.subarray(0, 8).equals(Buffer.from('89504e470d0a1a0a', 'hex')),
  'image/webp': (b) => b.subarray(0, 4).toString('ascii') === 'RIFF' && b.subarray(8, 12).toString('ascii') === 'WEBP',
};
const marketUpload = multer({
  storage: multer.diskStorage({
    destination: (req, file, cb) => fs.mkdir(marketImgDir, { recursive: true }, (err) => cb(err, marketImgDir)),
    filename: (req, file, cb) => cb(null, crypto.randomUUID() + IMG_EXT[file.mimetype]),
  }),
  limits: { fileSize: 2 * 1024 * 1024, files: 4 },
  fileFilter: (req, file, cb) => (IMG_EXT[file.mimetype] ? cb(null, true) : cb(new Error('BAD_TYPE'))),
});
function uploadImages(req, res, next) {
  marketUpload.array('photos', 4)(req, res, (err) => {
    req.uploadError = null;
    if (err) {
      req.uploadError = err.message === 'BAD_TYPE'
        ? 'Chỉ nhận ảnh JPEG, PNG hoặc WebP.'
        : 'Ảnh quá lớn (tối đa 2 MB mỗi ảnh, tối đa 4 ảnh) hoặc tải lên không hợp lệ.';
    }
    next();
  });
}
function hasValidSignature(f) {
  const buf = Buffer.alloc(12);
  const fd = fs.openSync(f.path, 'r');
  try { fs.readSync(fd, buf, 0, 12, 0); } finally { fs.closeSync(fd); }
  return IMG_SIG[f.mimetype](buf);
}

router.get('/market/new', async (req, res, next) => {
  try {
    const categories = (await req.callProc('mkt.sp_GetCategories')).recordset;
    res.render('market/new', { title: 'Đăng tin', categories, form: {}, error: null });
  } catch (e) { next(e); }
});

router.post('/market/new', uploadImages, async (req, res, next) => {
  try {
    const u = req.session.user;
    const b = req.body || {};
    const categories = (await req.callProc('mkt.sp_GetCategories')).recordset;
    const renderErr = (msg) => {
      (req.files || []).forEach((f) => fs.unlink(f.path, () => {}));
      return res.status(400).render('market/new', { title: 'Đăng tin', categories, form: b, error: msg });
    };

    if (req.uploadError) return renderErr(req.uploadError);
      const files = req.files || [];
      if (files.some((f) => !hasValidSignature(f))) return renderErr('File tải lên không phải ảnh hợp lệ.');
      const uploaded = files.map((f) => '/img/market/' + f.filename);
      const imgs = parseImages(uploaded.concat(String(b.images || '').split(/\r?\n/)).join('\n'));
     if (imgs.error) return renderErr(imgs.error);

    const qtyRaw = String(b.quantity || '').trim();
    const qty = qtyRaw === '' ? 1 : parseInt(qtyRaw, 10);

    try {
      await req.callProc('mkt.sp_CreateListing', {
        SellerId: u.id,
        CategoryId: posInt(b.category),
        ListingType: String(b.type || ''),
        Title: text(b.title, 200),
        Description: text(b.description, 2000),
        Brand: text(b.brand, 50),
        Model: text(b.model, 100),
        Condition: text(b.condition, 10),
        Price: price(b.price),
        ExchangeWanted: text(b.exchangeWanted, 255),
        Quantity: Number.isInteger(qty) ? qty : 0,
        City: text(b.city, 100),
        ImagesJson: imgs.json,
      }, { NewListingId: sql.Int });
    } catch (e) {
      if (BUSINESS_ERRORS.includes(errNumber(e))) return renderErr(e.message);
      throw e;
    }
    req.flash('success', 'Đã đăng tin.');
    return res.redirect('/market/mine');
  } catch (e) { return next(e); }
});

router.post('/market/:id/close', async (req, res, next) => {
  try {
    const id = posInt(req.params.id);
    if (!id) { req.flash('danger', 'Tin không hợp lệ.'); return res.redirect('/market/mine'); }
    await req.callProc('mkt.sp_CloseListing', { ListingId: id, SellerId: req.session.user.id });
    req.flash('success', 'Đã đóng tin.');
    return res.redirect('/market/mine');
  } catch (e) { return fail(req, res, e, next, '/market/mine'); }
});

router.post('/market/:id/delete', async (req, res, next) => {
  try {
    const id = posInt(req.params.id);
    if (!id) { req.flash('danger', 'Tin không hợp lệ.'); return res.redirect('/market/mine'); }
    await req.callProc('mkt.sp_DeleteListing', { ListingId: id, SellerId: req.session.user.id });
    req.flash('success', 'Đã xóa tin.');
    return res.redirect('/market/mine');
  } catch (e) { return fail(req, res, e, next, '/market/mine'); }
});

router.get('/market/mine', async (req, res, next) => {
  try {
    const listings = (await req.callProc('mkt.sp_GetMyListings', { UserId: req.session.user.id })).recordset;
    res.render('market/mine', { title: 'Tin của tôi', listings });
  } catch (e) { next(e); }
});

router.get('/market/transactions', async (req, res, next) => {
  try {
    const rows = (await req.callProc('mkt.sp_GetMyTransactions', { UserId: req.session.user.id })).recordset;
    res.render('market/transactions', { title: 'Giao dịch', rows });
  } catch (e) { next(e); }
});

router.post('/market/transactions/:id/status', async (req, res, next) => {
  const back = '/market/transactions';
  try {
    const id = posInt(req.params.id);
    const b = req.body || {};
    if (!id || !STATUS_ACTIONS.includes(b.status)) { req.flash('danger', 'Yêu cầu không hợp lệ.'); return res.redirect(back); }
    await req.callProc('mkt.sp_UpdateMarketTransaction', {
      TransactionId: id, ActorUserId: req.session.user.id, NewStatus: b.status, Reason: text(b.reason, 500),
    });
    req.flash('success', 'Đã cập nhật giao dịch.');
    return res.redirect(back);
  } catch (e) { return fail(req, res, e, next, back); }
});

router.post('/market/transactions/:id/rate', async (req, res, next) => {
  const back = '/market/transactions';
  try {
    const id = posInt(req.params.id);
    const b = req.body || {};
    if (!id) { req.flash('danger', 'Yêu cầu không hợp lệ.'); return res.redirect(back); }
    const rating = parseInt(b.rating, 10);
    await req.callProc('mkt.sp_RateSeller', {
      TransactionId: id, BuyerId: req.session.user.id,
      Rating: Number.isInteger(rating) ? rating : null, Comment: text(b.comment, 500),
    });
    req.flash('success', 'Cảm ơn bạn đã đánh giá người bán.');
    return res.redirect(back);
  } catch (e) { return fail(req, res, e, next, back); }
});

router.get('/market/messages', async (req, res, next) => {
  try {
    const u = req.session.user;
    const rows = (await req.callProc('mkt.sp_GetMyMessages', { UserId: u.id })).recordset;
    const map = new Map();
    rows.forEach((m) => {
      const key = m.ListingId + '-' + m.PartnerId;
      if (!map.has(key)) {
        map.set(key, {
          ListingId: m.ListingId, ListingTitle: m.ListingTitle, PartnerId: m.PartnerId,
          PartnerName: m.PartnerName, iAmSeller: Number(m.SellerId) === Number(u.id), messages: [],
        });
      }
      map.get(key).messages.push(m);
    });
    const last = (c) => new Date(c.messages[c.messages.length - 1].SentAt).getTime();
    const convs = [...map.values()].sort((a, b) => last(b) - last(a));
    res.render('market/messages', { title: 'Tin nhắn', convs });
  } catch (e) { next(e); }
});

router.post('/market/:id/order', async (req, res, next) => {
  try {
    const id = posInt(req.params.id);
    if (!id) { req.flash('danger', 'Mã tin không hợp lệ.'); return res.redirect('/market'); }
    const back = '/market/' + id;
    const b = req.body || {};
    const qty = posInt(b.quantity);
    if (!qty) { req.flash('danger', 'Số lượng đặt phải từ 1 trở lên.'); return res.redirect(back); }
    try {
      await req.callProc('mkt.sp_PlaceMarketOrder', {
        ListingId: id, BuyerId: req.session.user.id, Quantity: qty, Note: text(b.note, 500),
      }, { NewTransactionId: sql.Int });
    } catch (e) { return fail(req, res, e, next, back); }
    req.flash('success', 'Đã gửi đơn đặt mua, chờ người bán xác nhận.');
    return res.redirect('/market/transactions');
  } catch (e) { return next(e); }
});

// Người nhận: nếu (tin, đối tác) đã có hội thoại của tôi thì trả lời đối tác đó; nếu không thì gửi cho chủ tin (tin phải Active)
router.post('/market/:id/message', async (req, res, next) => {
  try {
    const u = req.session.user;
    const b = req.body || {};
    const id = posInt(req.params.id);
    if (!id) { req.flash('danger', 'Mã tin không hợp lệ.'); return res.redirect('/market'); }
    const back = b.from === 'messages' ? '/market/messages' : '/market/' + id;
    const body = text(b.body, 1000);
    if (!body) { req.flash('danger', 'Nội dung tin nhắn không được rỗng.'); return res.redirect(back); }
    try {
      let receiverId = null;
      const partnerId = posInt(b.to);
      if (partnerId) {
        const msgs = (await req.callProc('mkt.sp_GetMyMessages', { UserId: u.id })).recordset;
        if (msgs.some((m) => Number(m.ListingId) === id && Number(m.PartnerId) === partnerId)) receiverId = partnerId;
      }
      if (!receiverId) {
        const r = await req.callProc('mkt.sp_GetListingDetail', { ListingId: id });
        const listing = r.recordsets[0] && r.recordsets[0][0];
        if (!listing) { req.flash('danger', 'Tin không tồn tại hoặc đã đóng.'); return res.redirect('/market'); }
        if (Number(listing.SellerId) === Number(u.id)) {
          req.flash('danger', 'Đây là tin của bạn. Hãy trả lời trong mục Tin nhắn.');
          return res.redirect(back);
        }
        receiverId = listing.SellerId;
      }
      await req.callProc('mkt.sp_SendMessage', {
        ListingId: id, SenderId: u.id, ReceiverId: receiverId, Body: body,
      }, { NewMessageId: sql.Int });
    } catch (e) { return fail(req, res, e, next, back); }
    req.flash('success', 'Đã gửi tin nhắn.');
    return res.redirect(back);
  } catch (e) { return next(e); }
});
// ---------- hết Chợ lượt 2 ----------

router.get('/market/:id', async (req, res, next) => {
  try {
    const id = posInt(req.params.id);
    if (!id) { req.flash('danger', 'Mã tin không hợp lệ.'); return res.redirect('/market'); }
    const r = await req.callProc('mkt.sp_GetListingDetail', { ListingId: id });
    const listing = r.recordsets[0] && r.recordsets[0][0];
    if (!listing) { req.flash('danger', 'Tin không tồn tại hoặc đã đóng.'); return res.redirect('/market'); }
    return res.render('market/detail', { title: listing.Title, listing, images: r.recordsets[1] || [], isOwner: Number(listing.SellerId) === Number(req.session.user.id) });
  } catch (e) {
    if (BUSINESS_ERRORS.includes(errNumber(e))) {
      req.flash('danger', e.message);
      return res.redirect('/market');
    }
    return next(e);
  }
});

module.exports = router;