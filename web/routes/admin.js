'use strict';

const router = require('express').Router();
const { requireLogin, requireRole } = require('../lib/auth');
router.use('/admin', requireLogin, requireRole('Admin'));
const { sql, queryAs } = require('../lib/db');

const ALLOWED_ROLES = ['Admin', 'Customer', 'LabOwner', 'Expert', 'Delivery'];

// Tổng quan Admin
router.get('/admin', async (req, res, next) => {
  const admin = req.session.user;
  try {
    const dashboardResult = await queryAs('admin', admin.id, 'SELECT * FROM audit.vw_AdminDashboard');
    const complaintsResult = await queryAs('admin', admin.id, 'SELECT * FROM ord.vw_OpenComplaints');
    const auditResult = await queryAs('admin', admin.id, 'SELECT TOP 20 * FROM audit.vw_RecentChanges');
    const aiResult = await queryAs('admin', admin.id, 'SELECT * FROM ai.vw_RecommendationMetrics');

    res.render('admin/index', {
      title: 'Tổng quan Admin',
      dashboard: dashboardResult.recordset?.[0] || {},
      complaints: complaintsResult.recordset || [],
      auditLogs: auditResult.recordset || [],
      aiMetrics: aiResult.recordset || []
    });
  } catch (err) {
    next(err);
  }
});

// Quản lý người dùng
router.get('/admin/users', async (req, res, next) => {
  const admin = req.session.user;
  try {
    const keyword = String(req.query.keyword || '').trim().slice(0, 100);
    const roleCode = String(req.query.role || '').trim();
    const selectedRole = ALLOWED_ROLES.includes(roleCode) ? roleCode : '';
    const status = String(req.query.status || '');

    const result = await req.callProc('iam.sp_ListUsers', {
      AdminUserId: { type: sql.Int, value: admin.id },
      RoleCode: selectedRole || null,
      IsActive: status === '1' ? true : status === '0' ? false : null,
      Keyword: keyword || null,
      PageNo: { type: sql.Int, value: 1 },
      PageSize: { type: sql.Int, value: 20 }
    });

    const users = result.recordset || [];
    res.render('admin/users', {
      title: 'Quản lý người dùng',
      users,
      total: users[0]?.TotalRows ?? 0,
      keyword,
      selectedRole,
      status,
      roles: ALLOWED_ROLES,
      selfId: admin.id
    });
  } catch (err) {
    next(err);
  }
});

// Khóa hoặc mở khóa tài khoản
router.post('/admin/users/:id/status', async (req, res, next) => {
  const admin = req.session.user;
  const userId = Number(req.params.id);
  const isActive = String(req.body.isActive);

  if (!Number.isSafeInteger(userId) || userId <= 0 ||
      !['0', '1'].includes(isActive)) {
    return res.status(400).send('Dữ liệu không hợp lệ.');
  }

  if (userId === admin.id && isActive === '0') {
    return res.status(400).send('Không thể tự khóa tài khoản Admin.');
  }

  try {
    await req.callProc('iam.sp_SetUserStatus', {
      AdminUserId: { type: sql.Int, value: admin.id },
      UserId: { type: sql.Int, value: userId },
      IsActive: { type: sql.Bit, value: isActive === '1' }
    });

    return res.redirect('/admin/users');
  } catch (err) {
    next(err);
  }
});

// Quản lý và duyệt phòng Lab
router.get('/admin/labs', async (req, res, next) => {
  const admin = req.session.user;
  try {
    const result = await req.callProc('lab.sp_ListLabsForApproval', {
      AdminUserId: { type: sql.Int, value: admin.id },
      Status: null,
      PageNo: { type: sql.Int, value: 1 },
      PageSize: { type: sql.Int, value: 20 }
    });

    const labs = result.recordset || [];
    res.render('admin/labs', {
      title: 'Quản lý phòng Lab',
      labs,
      total: labs[0]?.TotalRows ?? 0
    });
  } catch (err) {
    next(err);
  }
});

router.post('/admin/labs/:id/approve', async (req, res, next) => {
  const admin = req.session.user;
  const labId = Number(req.params.id);
  const decision = String(req.body.decision || '');

  if (!Number.isSafeInteger(labId) || labId <= 0 ||
      !['Approved', 'Rejected'].includes(decision)) {
    return res.status(400).send('Dữ liệu không hợp lệ.');
  }

  try {
    await req.callProc('lab.sp_ApproveLab', {
      LabId: { type: sql.Int, value: labId },
      AdminUserId: { type: sql.Int, value: admin.id },
      Decision: { type: sql.NVarChar(20), value: decision },
      Reason: {
        type: sql.NVarChar(500),
        value: decision === 'Rejected' ? 'Không được phê duyệt' : null
      }
    });

    return res.redirect('/admin/labs');
  } catch (err) {
    next(err);
  }
});

// Khiếu nại đang mở
router.get('/admin/complaints', async (req, res, next) => {
  const admin = req.session.user;
  try {
    const result = await queryAs(
      'admin',
      admin.id,
      `SELECT TOP 200 ComplaintId, OrderCode, CustomerName, LabName, Category, Title,
              Status, AssignedAdminName, CreatedAt, AgeDays
       FROM ord.vw_OpenComplaints
       ORDER BY CreatedAt, ComplaintId`
    );

    res.render('admin/complaints', {
      title: 'Khiếu nại đang mở',
      complaints: result.recordset || []
    });
  } catch (err) {
    next(err);
  }
});

module.exports = router;