
'use strict';

const router = require('express').Router();
const crypto = require('node:crypto');
const { requireRole } = require('../lib/auth');
const { sql, queryAs } = require('../lib/db');

function csrfValid(req) {
  const expected = req.session.sellerCsrfToken;
  const received = req.body._csrf;

  return typeof expected === 'string' &&
    typeof received === 'string' &&
    /^[a-f0-9]{64}$/.test(expected) &&
    /^[a-f0-9]{64}$/.test(received) &&
    crypto.timingSafeEqual(
      Buffer.from(expected, 'hex'),
      Buffer.from(received, 'hex')
    );
}

router.get('/seller', requireRole('Customer'), async (req, res, next) => {
  try {
    if (!req.session.sellerCsrfToken) {
      req.session.sellerCsrfToken =
        crypto.randomBytes(32).toString('hex');
    }
const userId = Number(req.session.user.id);

const result = await queryAs('customer', userId, `
  SELECT ListingId, Title, Price, Quantity,
         CategoryName, CreatedAt
  FROM mkt.vw_MarketActive
  WHERE SellerId = @SellerId
  ORDER BY CreatedAt DESC
`, {
  SellerId: userId
});

const products = result.recordset;
    res.render('seller/index', {
  title: 'Đăng tin sản phẩm',
  csrfToken: req.session.sellerCsrfToken,
  products: products,
  query: {
    created: /^\d+$/.test(String(req.query.created || ''))
      ? req.query.created
      : null
  }
});
  } catch (err) {
    next(err);
  }
});

router.post('/seller/create', requireRole('Customer'), async (req, res, next) => {
  try {
    if (!csrfValid(req)) {
      return res.status(403).send('CSRF token khong hop le');
    }

    const userId = Number(req.session.user.id);
    const body = req.body;

    const title = String(body.title || '').trim();
    const city = String(body.city || '').trim();
    const description = String(body.description || '').trim();
    const categoryId = Number(body.categoryId);
    const quantity = Number(body.quantity);
    const listingType = String(body.listingType || '');
    const condition = String(body.condition || '');
    const priceText = String(body.price ?? '').trim();
    const price = priceText === '' ? null : Number(priceText);

    if (!Number.isSafeInteger(userId) || userId <= 0 ||
        !Number.isSafeInteger(categoryId) || categoryId <= 0 ||
        !Number.isSafeInteger(quantity) || quantity < 1 ||
        !['Sell', 'Exchange', 'Wanted'].includes(listingType) ||
        !title || title.length > 200 ||
        !city || city.length > 100 ||
        description.length > 2000 ||
        (listingType !== 'Wanted' &&
          !['New', 'LikeNew', 'Good', 'Fair', 'ForParts'].includes(condition)) ||
        (listingType === 'Wanted' &&
          condition !== '' &&
          !['New', 'LikeNew', 'Good', 'Fair', 'ForParts'].includes(condition)) ||
        (price !== null &&
          (!Number.isSafeInteger(price) || price < 0 || price > 999999999999999999)) ||
        (listingType === 'Sell' && price === null)) {
      return res.status(400).send('Du lieu tin dang khong hop le');
    }

    const exchangeWanted =
      String(body.exchangeWanted || '').trim();

    if (exchangeWanted.length > 255 ||
        (listingType === 'Exchange' && !exchangeWanted)) {
      return res.status(400).send('Thong tin trao doi khong hop le');
    }

    const result = await req.callProc(
      'mkt.sp_CreateListing',
      {
        SellerId: userId,
        CategoryId: categoryId,
        ListingType: listingType,
        Title: title,
        Description: description || null,
        Brand: null,
        Model: null,
        Condition: condition || null,
        Price: price === null ? null : {
          type: sql.Decimal(18, 0),
          value: price
        },
        ExchangeWanted: exchangeWanted || null,
        Quantity: quantity,
        City: city,
        ImagesJson: null
      },
      { NewListingId: sql.Int }
    );

    return res.redirect(
      '/seller?created=' + encodeURIComponent(result.output.NewListingId)
    );
  } catch (err) {
    next(err);
  }
});

module.exports = router;
