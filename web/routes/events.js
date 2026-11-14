'use strict';
const express = require('express');
const router = express.Router();
const { sql, queryAs } = require('../lib/db');
const { requireLogin, requireRole } = require('../lib/auth');

router.use('/events', requireLogin, requireRole('Customer'));

// Lỗi nghiệp vụ của sp_RegisterEvent / sp_CancelEventRegistration / sp_GetMyEventRegistrations
const BUSINESS_ERRORS = [50701, 50702, 50704, 50705];
const errNumber = (e) => e && (e.number ?? (e.originalError && e.originalError.number));

function parseEventId(req) {
  const id = parseInt(req.params.id, 10);
  return Number.isInteger(id) && id > 0 ? id : null;
}

function handleBusinessError(req, res, e, next) {
  if (BUSINESS_ERRORS.includes(errNumber(e))) {
    req.flash('danger', e.message);
    return res.redirect('/events');
  }
  return next(e);
}

// GET /events - danh sách sự kiện sắp diễn ra + đăng ký của tôi
router.get('/events', async (req, res, next) => {
  try {
    const u = req.session.user;
    const events = (await queryAs(u.role, u.id,
      `SELECT EventId, EventType, Title, StartAt, EndAt, RegistrationDeadline, VenueName, City,
              HostLabName, OrganizerName, Capacity, Fee, RegisteredCount, SeatsLeft, WaitlistCount
       FROM com.vw_UpcomingEvents
       ORDER BY StartAt`)).recordset;
    const mine = (await req.callProc('com.sp_GetMyEventRegistrations', { UserId: u.id })).recordset;

    const regMap = {};
    mine.forEach((r) => { regMap[r.EventId] = r.Status; });

    res.render('events/index', { title: 'Sự kiện', events, mine, regMap, now: new Date() });
  } catch (e) {
    next(e);
  }
});

// POST /events/:id/register
router.post('/events/:id/register', async (req, res, next) => {
  try {
    const eventId = parseEventId(req);
    if (!eventId) { req.flash('danger', 'Mã sự kiện không hợp lệ.'); return res.redirect('/events'); }
    const r = await req.callProc('com.sp_RegisterEvent',
      { EventId: eventId, UserId: req.session.user.id },
      { ResultStatus: sql.NVarChar(10) });
    if (r.output.ResultStatus === 'Registered') req.flash('success', 'Đăng ký thành công, bạn đã có chỗ.');
    else req.flash('warning', 'Sự kiện đã đủ chỗ, bạn được đưa vào hàng chờ.');
    return res.redirect('/events');
  } catch (e) {
    return handleBusinessError(req, res, e, next);
  }
});

// POST /events/:id/cancel
router.post('/events/:id/cancel', async (req, res, next) => {
  try {
    const eventId = parseEventId(req);
    if (!eventId) { req.flash('danger', 'Mã sự kiện không hợp lệ.'); return res.redirect('/events'); }
    await req.callProc('com.sp_CancelEventRegistration',
      { EventId: eventId, UserId: req.session.user.id },
      { PromotedUserId: sql.Int });
    req.flash('success', 'Đã hủy đăng ký sự kiện.');
    return res.redirect('/events');
  } catch (e) {
    return handleBusinessError(req, res, e, next);
  }
});

module.exports = router;