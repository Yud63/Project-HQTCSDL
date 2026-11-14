
'use strict';

const router = require('express').Router();
const { requireLogin, requireRole } = require('../lib/auth');
router.use('/recommend', requireLogin, requireRole('Customer'));
const { sql } = require('../lib/db');
const gemini = require('../lib/gemini');
function esc(value) {
  return String(value ?? '').replace(/[&<>"']/g, c => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#39;'
  })[c]);
}

router.get('/recommend', async (req, res, next) => {
  const user = req.session.user;

  if (!user) {
    return res.redirect('/login');
  }

  if (user.role !== 'Customer') {
    return res.status(403).send('Chỉ khách hàng mới được sử dụng chức năng gợi ý Lab.');
  }

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

    const rows = labs.map(lab => `
      <tr>
  <td>${esc(lab.Rank)}</td>
  <td>${esc(lab.LabName)}</td>
  <td>${esc(lab.Score)}</td>
  <td>${esc(lab.AvgRating)}</td>
  <td>${esc(lab.DistanceKm ?? 'Chưa có')}</td>
  <td>
    <form method="POST" action="/recommend/action" style="display:inline">
      <input type="hidden" name="recLogId" value="${esc(lab.RecLogId)}">
      <input type="hidden" name="labId" value="${esc(lab.LabId)}">
      <button name="action" value="Clicked">Xem Lab</button>
      <button name="action" value="Dismissed">Bỏ qua</button>
    </form>
  </td>
</tr>
    `).join('');

    res.send(`
      <!DOCTYPE html>
      <html lang="vi">
      <head>
        <meta charset="UTF-8">
        <title>Gợi ý phòng Lab - FilmLab</title>
        <style>
          body {
            font-family: Arial, sans-serif;
            padding: 30px;
            background: #f5f6fa;
          }
          table {
            width: 100%;
            border-collapse: collapse;
            background: white;
          }
          th, td {
            border: 1px solid #ddd;
            padding: 12px;
            text-align: left;
          }
          th {
            background: #263b60;
            color: white;
          }
        </style>
      </head>
      <body>
        <h1>Gợi ý phòng Lab bằng AI</h1>
        <p>
  <a href="/recommend/preferences">
    ⚙ Thiết lập sở thích gợi ý Lab
  </a>
</p>
        ${req.query.dismissed === '1' ? `
  <p style="color:green; font-weight:bold;">
    ✓ Đã ghi nhận thao tác Bỏ qua thành công!
  </p>
` : ''}
        ${req.query.clicked === '1' ? `
  <p style="color:green; font-weight:bold;">
    ✓ Đã ghi nhận lượt xem Lab thành công!
  </p>
` : ''}
        ${aiAdvice ? `
  <section style="background:white; padding:20px; margin:20px 0; border-radius:8px;">
    <h2>Tư vấn từ Google Gemini AI</h2>
    <p style="white-space:pre-line;">${esc(aiAdvice)}</p>
  </section>
` : ''}
        <p>Xin chào, ${esc(user.name || 'Khách hàng')}!</p>

        ${labs.length ? `
          <table>
            <tr>
              <th>Hạng</th>
              <th>Tên phòng Lab</th>
              <th>Điểm gợi ý</th>
              <th>Đánh giá</th>
              <th>Khoảng cách (km)</th>
              <th>Thao tác</th>
            </tr>
            ${rows}
          </table>
        ` : '<p>Hiện chưa có phòng Lab phù hợp để gợi ý.</p>'}

        <p><a href="/">Về trang chủ</a></p>
      </body>
      </html>
    `);
  } catch (err) {
    next(err);
  }
});

const { queryAs } = require('../lib/db');

// Trang thiết lập sở thích khách hàng
router.get('/recommend/preferences', async (req, res, next) => {
  const user = req.session.user;
  if (!user) return res.redirect('/login');
  if (user.role !== 'Customer') {
    return res.status(403).send('Chỉ khách hàng được sử dụng.');
  }

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

    const p = result.recordset?.[0] || {};

    res.send(`
      <!DOCTYPE html>
      <html lang="vi">
      <head>
        <meta charset="UTF-8">
        <title>Sở thích khách hàng - FilmLab</title>
        <style>
          body {font-family:Arial; background:#f5f6fa; padding:30px}
          form {max-width:550px; background:white; padding:25px; border-radius:10px}
          label {display:block; margin-top:15px}
          input,select {padding:10px; width:100%; box-sizing:border-box}
          input[type=checkbox] {width:auto}
          button {margin-top:20px; padding:12px 20px; background:#263b60; color:white; border:0; cursor:pointer}
        </style>
      </head>
      <body>
        <h1>Thiết lập sở thích gợi ý Lab</h1>
        <form method="POST" action="/recommend/preferences">
          <label>Loại phim yêu thích</label>
          <select name="filmType">
            <option value="">Không chọn</option>
            ${[
              ['ColorNegative', 'Phim màu âm bản'],
              ['BlackWhite', 'Phim đen trắng'],
              ['ColorSlide', 'Phim slide màu']
            ].map(([v, label]) => `
              <option value="${v}" ${p.PreferredFilmType === v ? 'selected' : ''}>${label}</option>
            `).join('')}
          </select>

          <label>Thành phố ưu tiên</label>
          <input name="city" maxlength="100" value="${esc(p.PreferredCity || '')}">

          <label>Khoảng cách tối đa (km)</label>
          <input type="number" name="distance" min="0.01" max="9999.99" step="0.01"
                 value="${esc(p.MaxDistanceKm ?? '')}">

          <label>Ngân sách tối đa mỗi cuộn (VNĐ)</label>
          <input type="number" name="budget" min="0" step="1"
                 value="${esc(p.MaxBudgetPerRoll ?? '')}">

          <label><input type="checkbox" name="quality" ${p.PrioritizeQuality ? 'checked' : ''}> Ưu tiên chất lượng</label>
          <label><input type="checkbox" name="speed" ${p.PrioritizeSpeed ? 'checked' : ''}> Ưu tiên tốc độ</label>

          <button type="submit">Lưu sở thích</button>
        </form>
        <p><a href="/recommend">Quay lại trang gợi ý Lab</a></p>
      </body>
      </html>
    `);
  } catch (err) {
    next(err);
  }
});

// Lưu sở thích vào SQL Server
router.post('/recommend/preferences', async (req, res, next) => {
  const user = req.session.user;
  if (!user) return res.redirect('/login');
  if (user.role !== 'Customer') {
    return res.status(403).send('Không có quyền.');
  }

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

router.post('/recommend/action', async (req, res, next) => {
  const user = req.session.user;

  if (!user) return res.redirect('/login');
  if (user.role !== 'Customer') {
    return res.status(403).send('Không có quyền.');
  }

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
