'use strict';

const router = require('express').Router();
const { requireLogin, requireRole } = require('../lib/auth');
router.use('/recommend', requireLogin, requireRole('Customer'));
const { sql, queryAs } = require('../lib/db');
const gemini = require('../lib/gemini');

// Danh sách gợi ý Lab
router.get('/recommend', async (req, res, next) => {
  const user = req.session.user;

  try {
    const result = await req.callProc('ai.sp_GetLabRecommendations', {
      UserId: { type: sql.Int, value: user.id },
      TopN: { type: sql.TinyInt, value: 5 },
      Latitude: { type: sql.Float, value: null },
      Longitude: { type: sql.Float, value: null }
    });

    const labs = result.recordset || [];
    let aiAdvice = '';

    if (false && labs.length > 0) {
      try {
        const aiResult = await gemini.recommendLabs(labs);
        aiAdvice = aiResult.text;
      } catch (err) {
        console.error('[recommend] Gemini lỗi:', err.message);
        aiAdvice = 'Trợ lý Gemini tạm thời không phản hồi. Bạn vẫn có thể xem danh sách phòng Lab được đề xuất bên dưới.';
      }
    }

    const flash = [];
    if (req.query.dismissed === '1') flash.push({ type: 'success', msg: 'Đã ghi nhận thao tác Bỏ qua thành công.' });
    if (req.query.clicked === '1') flash.push({ type: 'success', msg: 'Đã ghi nhận lượt xem Lab thành công.' });

    res.render('recommend/index', {
      title: 'Gợi ý phòng Lab',
      labs,
      aiAdvice,
      flash
    });
  } catch (err) {
    next(err);
  }
});

// Trang thiết lập sở thích
router.get('/recommend/preferences', async (req, res, next) => {
  const user = req.session.user;

  try {
    const result = await queryAs(
      'Customer',
      user.id,
      `SELECT PreferredFormatId, PreferredFilmType,
              PreferredCity, MaxDistanceKm, MaxBudgetPerRoll,
              PrioritizeQuality, PrioritizeSpeed
       FROM ai.UserPreferences WHERE UserId = @UserId`,
      { UserId: { type: sql.Int, value: user.id } }
    );

    const flash = [];
    if (req.query.saved === '1') flash.push({ type: 'success', msg: 'Đã lưu sở thích.' });

    res.render('recommend/preferences', {
      title: 'Sở thích gợi ý Lab',
      p: result.recordset?.[0] || {},
      filmTypes: [
        ['ColorNegative', 'Phim màu âm bản'],
        ['BlackWhite', 'Phim đen trắng'],
        ['ColorSlide', 'Phim slide màu']
      ],
      flash
    });
  } catch (err) {
    next(err);
  }
});

// Lưu sở thích vào SQL Server
router.post('/recommend/preferences', async (req, res, next) => {
  const user = req.session.user;

  try {
    const b = req.body || {};
    const filmTypes = ['ColorNegative', 'BlackWhite', 'ColorSlide'];
    const filmType = filmTypes.includes(b.filmType) ? b.filmType : null;
    const distance = b.distance === '' || b.distance == null ? null : Number(b.distance);
    const budget = b.budget === '' || b.budget == null ? null : Number(b.budget);

    if (distance !== null && (!Number.isFinite(distance) || distance <= 0 || distance > 9999.99)) {
      return res.status(400).send('Khoảng cách không hợp lệ.');
    }
    if (budget !== null && (!Number.isSafeInteger(budget) || budget < 0)) {
      return res.status(400).send('Ngân sách không hợp lệ.');
    }

    await req.callProc('ai.sp_SaveUserPreferences', {
      UserId: { type: sql.Int, value: user.id },
      PreferredFormatId: null,
      PreferredFilmType: filmType,
      PreferredCity: String(b.city || '').trim().slice(0, 100) || null,
      MaxDistanceKm: { type: sql.Decimal(6, 2), value: distance },
      MaxBudgetPerRoll: { type: sql.Decimal(18, 0), value: budget },
      PrioritizeQuality: { type: sql.Bit, value: b.quality === 'on' },
      PrioritizeSpeed: { type: sql.Bit, value: b.speed === 'on' },
      Source: 'UserSet',
      ExtraJson: null
    });

    res.redirect('/recommend/preferences?saved=1');
  } catch (err) {
    next(err);
  }
});

// Ghi nhận thao tác Xem Lab / Bỏ qua
router.post('/recommend/action', async (req, res, next) => {
  const user = req.session.user;

  try {
    const { recLogId, labId, action } = req.body || {};

    if (!['Clicked', 'Dismissed'].includes(action)) {
      return res.status(400).send('Thao tác không hợp lệ.');
    }

    if (!/^\d+$/.test(String(recLogId || '')) ||
        BigInt(recLogId) <= 0n) {
      return res.status(400).send('Mã gợi ý không hợp lệ.');
    }

    await req.callProc('ai.sp_RecordRecommendationAction', {
      RecLogId: { type: sql.BigInt, value: recLogId },
      UserId: { type: sql.Int, value: user.id },
      Action: { type: sql.NVarChar(9), value: action }
    });

    if (action === 'Clicked') {
      if (!/^\d+$/.test(String(labId || '')) ||
          Number(labId) <= 0 ||
          !Number.isSafeInteger(Number(labId))) {
        return res.status(400).send('Mã Lab không hợp lệ.');
      }
      return res.redirect('/recommend?clicked=1');
    }

    res.redirect('/recommend?dismissed=1');
  } catch (err) {
    next(err);
  }
});

module.exports = router;