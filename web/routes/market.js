'use strict';
const express = require('express');
const router = express.Router();
const { requireLogin, requireRole } = require('../lib/auth');

router.use('/market', requireLogin, requireRole('Customer'));

// 50601 không tồn tại/đã đóng, 50605 tham số sai
const BUSINESS_ERRORS = [50601, 50605];
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

router.get('/market/:id', async (req, res, next) => {
  try {
    const id = posInt(req.params.id);
    if (!id) { req.flash('danger', 'Mã tin không hợp lệ.'); return res.redirect('/market'); }
    const r = await req.callProc('mkt.sp_GetListingDetail', { ListingId: id });
    const listing = r.recordsets[0] && r.recordsets[0][0];
    if (!listing) { req.flash('danger', 'Tin không tồn tại hoặc đã đóng.'); return res.redirect('/market'); }
    return res.render('market/detail', { title: listing.Title, listing, images: r.recordsets[1] || [] });
  } catch (e) {
    if (BUSINESS_ERRORS.includes(errNumber(e))) {
      req.flash('danger', e.message);
      return res.redirect('/market');
    }
    return next(e);
  }
});

module.exports = router;