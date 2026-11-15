'use strict';
const express = require('express');
const router = express.Router();
const { requireLogin, requireRole } = require('../lib/auth');
const { queryAs } = require('../lib/db');

router.use('/delivery', requireLogin, requireRole('Delivery'));

// 50401 không tồn tại, 50402 chuyển trạng thái không hợp lệ, 50403 không có quyền, 50405 dữ liệu sai
const BUSINESS_ERRORS = [50401, 50402, 50403, 50405];
const errNumber = (e) => e && (e.number ?? (e.originalError && e.originalError.number));

const ACTIONS = ['PickedUp', 'Delivered', 'Failed'];
const DEFAULT_NOTE = {
  PickedUp: 'Đối tác đã lấy phim.',
  Delivered: 'Đối tác đã giao phim.',
  Failed: 'Chặng giao thất bại.',
};
const posInt = (v) => { const n = parseInt(v, 10); return Number.isInteger(n) && n > 0 ? n : null; };
const text = (v, n) => { const s = String(v || '').trim(); return s ? s.slice(0, n) : null; };

router.get('/delivery', async (req, res, next) => {
  try {
    const r = await queryAs('delivery', req.session.user.id,
      'SELECT * FROM dlv.vw_DeliveryBoard ORDER BY ScheduledAt, CreatedAt');
    res.render('delivery/index', { title: 'Giao nhận', rows: r.recordset });
  } catch (e) { next(e); }
});

router.post('/delivery/:id/status', async (req, res, next) => {
  const back = '/delivery';
  try {
    const id = posInt(req.params.id);
    const b = req.body || {};
    if (!id || !ACTIONS.includes(b.status)) {
      req.flash('danger', 'Yêu cầu không hợp lệ.');
      return res.redirect(back);
    }
    const reason = text(b.reason, 255);
    if (b.status === 'Failed' && !reason) {
      req.flash('danger', 'Chặng giao thất bại phải có lý do.');
      return res.redirect(back);
    }
    await req.callProc('dlv.sp_UpdateDeliveryStatus', {
      DeliveryRequestId: id,
      ActorUserId: req.session.user.id,
      NewStatus: b.status,
      Note: b.status === 'Failed' ? reason : DEFAULT_NOTE[b.status],
      FailureReason: b.status === 'Failed' ? reason : null,
    });
    req.flash('success', 'Đã cập nhật chặng giao.');
    return res.redirect(back);
  } catch (e) {
    if (BUSINESS_ERRORS.includes(errNumber(e))) {
      req.flash('danger', e.message);
      return res.redirect(back);
    }
    return next(e);
  }
});

module.exports = router;