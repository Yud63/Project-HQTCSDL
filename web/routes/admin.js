
'use strict';

const router = require('express').Router();
const { requireLogin, requireRole } = require('../lib/auth');
router.use('/admin', requireLogin, requireRole('Admin'));
const { sql, queryAs } = require('../lib/db');

// Bảo vệ nội dung hiển thị trên HTML
function esc(value) {
  return String(value ?? '').replace(/[&<>"']/g, c => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#39;'
  })[c]);
}

// Trang quản lý người dùng
router.get('/admin/users', async (req, res, next) => {
  const user = req.session.user;

  if (!user) {
    return res.redirect('/login');
  }

  if (user.role !== 'Admin') {
    return res.status(403).send('Bạn không có quyền truy cập.');
  }

  try {
    const keyword = String(req.query.keyword || '').trim().slice(0, 100);
    const roleCode = String(req.query.role || '').trim();
const allowedRoles = ['Admin', 'Customer', 'LabOwner', 'Expert', 'Delivery'];
const selectedRole = allowedRoles.includes(roleCode) ? roleCode : '';
const status = String(req.query.status || '');
    const result = await req.callProc('iam.sp_ListUsers', {
      AdminUserId: { type: sql.Int, value: user.id },
      RoleCode: selectedRole || null,
      IsActive: status === '1' ? true : status === '0' ? false : null,
      
      Keyword: keyword || null,
      PageNo: { type: sql.Int, value: 1 },
      PageSize: { type: sql.Int, value: 20 }
    });

    const users = result.recordset || [];
    const total = users[0]?.TotalRows ?? 0;

    const rows = users.map(u => `
      <tr>
        <td>${esc(u.UserId)}</td>
        <td>${esc(u.FullName)}</td>
        <td>${esc(u.Email)}</td>
        <td>${esc(u.Roles)}</td>
        <td>${u.IsActive ? 'Hoạt động' : 'Đã khóa'}</td>

<td>
  ${Number(u.UserId) === Number(user.id) ? 'Tài khoản của bạn' : `
    <form method="POST" action="/admin/users/${u.UserId}/status">
      <input type="hidden" name="isActive" value="${u.IsActive ? '0' : '1'}">
      <button type="submit" onclick="return confirm('Bạn chắc chắn muốn thay đổi trạng thái tài khoản này?')">
        ${u.IsActive ? 'Khóa' : 'Mở khóa'}
      </button>
    </form>
  `}
</td>

      </tr>
    `).join('');

    return res.send(`
      <!DOCTYPE html>
      <html lang="vi">
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Quản lý người dùng - FilmLab</title>
        <style>
          body {
            font-family: Arial, sans-serif;
            background: #f7f7f7;
            padding: 30px;
          }
          main {
            max-width: 1100px;
            margin: auto;
          }
          table {
            width: 100%;
            border-collapse: collapse;
            background: white;
          }
          th, td {
            padding: 12px;
            border: 1px solid #ddd;
            text-align: left;
          }
          th {
            background: #b54f07;
            color: white;
          }
          a {
            color: #b54f07;
          }
        </style>
      </head>
      <body>
        <main>
          <a href="/">← Về trang chủ</a>
          <h1>Quản lý người dùng - FilmLab</h1>
          <p>Tổng số tài khoản: ${total}</p>

<form method="GET" action="/admin/users" style="margin: 16px 0;">
  <input
    type="text"
    name="keyword"
    placeholder="Nhập tên hoặc email cần tìm..."
    value="${esc(keyword)}"
    style="padding: 10px; width: 300px;"
  >
  <select name="role" style="padding: 10px; margin-left: 8px;">
  <option value="">Tất cả vai trò</option>
  <option value="Admin" ${selectedRole === 'Admin' ? 'selected' : ''}>Admin</option>
  <option value="Customer" ${selectedRole === 'Customer' ? 'selected' : ''}>Customer</option>
  <option value="LabOwner" ${selectedRole === 'LabOwner' ? 'selected' : ''}>LabOwner</option>
  <option value="Expert" ${selectedRole === 'Expert' ? 'selected' : ''}>Expert</option>
  <option value="Delivery" ${selectedRole === 'Delivery' ? 'selected' : ''}>Delivery</option>
</select>
<select name="status" style="padding: 10px; margin-left: 8px;">
  <option value="">Tất cả trạng thái</option>
  <option value="1" ${status === '1' ? 'selected' : ''}>Hoạt động</option>
  <option value="0" ${status === '0' ? 'selected' : ''}>Bị khóa</option>
</select>
  <button type="submit" style="padding: 10px 20px; cursor: pointer;">
    Tìm kiếm
  </button>
  <a href="/admin/users" style="margin-left: 10px;">Xóa lọc</a>
</form>

          <table>
            <thead>
              <tr>
                <th>ID</th>
                <th>Họ tên</th>
                <th>Email</th>
                <th>Vai trò</th>
                <th>Trạng thái</th>
                <th>Thao tác</th>
              </tr>
            </thead>
            <tbody>
              ${rows || '<tr><td colspan="6">Chưa có dữ liệu</td></tr>'}
            </tbody>
          </table>
        </main>
      </body>
      </html>
    `);
  } catch (err) {
    next(err);
  }
});

// Khóa hoặc mở khóa tài khoản người dùng
router.post('/admin/users/:id/status', async (req, res, next) => {
  const admin = req.session.user;

  if (!admin) {
    return res.redirect('/login');
  }

  if (admin.role !== 'Admin') {
    return res.status(403).send('Bạn không có quyền truy cập.');
  }

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
      IsActive: {
        type: sql.Bit,
        value: isActive === '1'
      }
    });

    return res.redirect('/admin/users');
  } catch (err) {
    next(err);
  }
});
// Trang quản lý và duyệt phòng Lab
router.get('/admin/labs', async (req, res, next) => {
  const admin = req.session.user;

  if (!admin) return res.redirect('/login');

  if (admin.role !== 'Admin') {
    return res.status(403).send('Bạn không có quyền truy cập.');
  }

  try {
    const result = await req.callProc('lab.sp_ListLabsForApproval', {
      AdminUserId: { type: sql.Int, value: admin.id },
      Status: null,
      PageNo: { type: sql.Int, value: 1 },
      PageSize: { type: sql.Int, value: 20 }
    });

    const labs = result.recordset || [];

    
const rows = labs.map(lab => `
  <tr>
    <td>${esc(lab.LabId)}</td>
    <td>${esc(lab.LabName)}</td>
    <td>${esc(lab.OwnerName)}</td>
    <td>${esc(lab.City)}</td>
    <td>${esc(lab.ApprovalStatus)}</td>
    <td>
      ${lab.ApprovalStatus === 'Pending' ? `
        <form method="POST" action="/admin/labs/${lab.LabId}/approve" style="display:inline;">
          <input type="hidden" name="decision" value="Approved">
          <button type="submit">Duyệt</button>
        </form>
        <form method="POST" action="/admin/labs/${lab.LabId}/approve" style="display:inline;">
          <input type="hidden" name="decision" value="Rejected">
          <button type="submit">Từ chối</button>
        </form>
      ` : 'Đã xử lý'}
    </td>
  </tr>
`).join('');


    res.send(`
      <!DOCTYPE html>
      <html lang="vi">
      <head>
        <meta charset="UTF-8">
        <title>Quản lý Lab - FilmLab</title>
        <style>
          body { font-family: Arial; margin: 40px; }
          table { border-collapse: collapse; width: 100%; }
          th, td { border: 1px solid #ddd; padding: 12px; }
          th { background: #b54f07; color: white; text-align: left; }
        </style>
      </head>
      <body>
        <a href="/">← Về trang chủ</a>
        <h1>Quản lý phòng Lab - FilmLab</h1>
        <p>Tổng số phòng Lab: ${labs[0]?.TotalRows ?? 0}</p>

        <table>
          <thead>
            <tr>
              <th>ID</th>
              <th>Tên Lab</th>
              <th>Chủ Lab</th>
              <th>Thành phố</th>
              <th>Trạng thái</th>
              <th>Thao tác</th>
            </tr>
          </thead>
          <tbody>
            ${rows || '<tr><td colspan="6">Chưa có dữ liệu</td></tr>'}
          </tbody>
        </table>
      </body>
      </html>
    `);
  } catch (err) {
    next(err);
  }
});




router.post('/admin/labs/:id/approve', async (req, res, next) => {
  const admin = req.session.user;

  if (!admin) return res.redirect('/login');

  if (admin.role !== 'Admin') {
    return res.status(403).send('Bạn không có quyền truy cập.');
  }

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


// Danh sách khiếu nại đang mở
router.get('/admin/complaints', async (req, res, next) => {
  const admin = req.session.user;

  if (!admin) return res.redirect('/login');

  if (admin.role !== 'Admin') {
    return res.status(403).send('Bạn không có quyền truy cập.');
  }

  try {
    const result = await queryAs(
      'admin',
      admin.id,
      `SELECT TOP 200 ComplaintId, OrderCode, CustomerName, LabName, Category, Title,
              Status, AssignedAdminName, CreatedAt, AgeDays
       FROM ord.vw_OpenComplaints
       ORDER BY CreatedAt, ComplaintId`
    );

    const complaints = result.recordset || [];

    const rows = complaints.map(c => `
      <tr>
        <td>${esc(c.ComplaintId)}</td>
        <td>${esc(c.OrderCode)}</td>
        <td>${esc(c.CustomerName)}</td>
        <td>${esc(c.LabName)}</td>
        <td>${esc(c.Category)}</td>
        <td>${esc(c.Title)}</td>
        <td>${esc(c.Status)}</td>
        <td>${esc(c.AssignedAdminName ?? 'Chưa phân công')}</td>
        <td>${c.CreatedAt ? esc(new Date(c.CreatedAt).toLocaleString('vi-VN')) : ''}</td>
        <td>${esc(c.AgeDays ?? 0)}</td>
      </tr>
    `).join('');

    res.send(`
      <!DOCTYPE html>
      <html lang="vi">
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Khiếu nại - FilmLab</title>
        <style>
          body { font-family: Arial, sans-serif; margin: 40px; }
          table { border-collapse: collapse; width: 100%; }
          th, td { border: 1px solid #ddd; padding: 12px; text-align: left; }
          th { background: #b54f07; color: white; }
          a { color: #b54f07; }
        </style>
      </head>
      <body>
        <a href="/admin">← Về tổng quan Admin</a>
        <h1>Khiếu nại đang mở - FilmLab</h1>
        <p>Tổng số khiếu nại: ${complaints.length}</p>

        <table>
          <thead>
            <tr>
              <th>ID</th>
              <th>Mã đơn</th>
              <th>Khách hàng</th>
              <th>Phòng Lab</th>
              <th>Loại</th>
              <th>Tiêu đề</th>
              <th>Trạng thái</th>
              <th>Admin phụ trách</th>
              <th>Ngày tạo</th>
              <th>Số ngày</th>
            </tr>
          </thead>
          <tbody>
            ${rows || '<tr><td colspan="10">Chưa có khiếu nại đang mở</td></tr>'}
          </tbody>
        </table>
      </body>
      </html>
    `);
  } catch (err) {
    next(err);
  }
});

// Trang tổng quan Admin
router.get('/admin', async (req, res, next) => {
  const admin = req.session.user;

  if (!admin) {
    return res.redirect('/login');
  }

  if (admin.role !== 'Admin') {
    return res.status(403).send('Bạn không có quyền truy cập.');
  }

  try {
  const dashboardResult = await queryAs(
  'admin',
  admin.id,
  'SELECT * FROM audit.vw_AdminDashboard'
);

const dashboard = dashboardResult.recordset?.[0] || {};
const complaintsResult = await queryAs(
  'admin',
  admin.id,
  'SELECT * FROM ord.vw_OpenComplaints'
);

const complaints = complaintsResult.recordset || [];  
const auditResult = await queryAs(
  'admin',
  admin.id,
  'SELECT TOP 20 * FROM audit.vw_RecentChanges'
);

const auditLogs = auditResult.recordset || [];
const aiResult = await queryAs(
  'admin',
  admin.id,
  'SELECT * FROM ai.vw_RecommendationMetrics'
);

const aiMetrics = aiResult.recordset || [];
    res.send(`
      <!DOCTYPE html>
      <html lang="vi">
      <head>
        <meta charset="UTF-8">
        <title>Tổng quan Admin - FilmLab</title>
        <style>
  body {
    font-family: Arial, sans-serif;
    background: #f5f6fa;
    margin: 40px;
    color: #1e293b;
  }

  h1 {
    color: #b54f07;
  }

  h2 {
    margin-top: 30px;
  }

  table {
    width: 100%;
    border-collapse: collapse;
    background: white;
    border-radius: 12px;
    overflow: hidden;
    box-shadow: 0 4px 15px rgba(0,0,0,0.08);
  }

  th {
    background: #b54f07;
    color: white;
    padding: 15px;
    text-align: left;
  }

  td {
    padding: 14px;
    border-bottom: 1px solid #eee;
  }

  tr:hover {
    background: #fff7ed;
  }

  a {
    color: #b54f07;
    font-weight: bold;
  }
</style>
      </head>
      <body style="font-family:Arial; margin:40px;">
        <h1>Tổng quan Admin - FilmLab</h1>
        <p>Chào mừng đến trang quản trị hệ thống.</p>
        <h2>Thống kê hệ thống</h2>

<table border="1" cellpadding="12" cellspacing="0">
  <tr>
    <th>Chỉ số</th>
    <th>Giá trị</th>
  </tr>
  <tr>
    <td>Tổng người dùng</td>
    <td>${esc(dashboard.TotalUsers ?? 0)}</td>
  </tr>
  <tr>
    <td>Lab đã duyệt</td>
    <td>${esc(dashboard.ApprovedLabs ?? 0)}</td>
  </tr>
  <tr>
    <td>Lab chờ duyệt</td>
    <td>${esc(dashboard.PendingLabs ?? 0)}</td>
  </tr>
  <tr>
    <td>Đơn hàng đang xử lý</td>
    <td>${esc(dashboard.OrdersInProgress ?? 0)}</td>
  </tr>
  <tr>
    <td>Đơn hàng tháng này</td>
    <td>${esc(dashboard.OrdersThisMonth ?? 0)}</td>
  </tr>
  <tr>
    <td>Doanh thu tháng này</td>
    <td>${esc(dashboard.RevenueThisMonth ?? 0)} VNĐ</td>
  </tr>
  <tr>
    <td>Khiếu nại đang mở</td>
    <td>${esc(dashboard.OpenComplaints ?? 0)}</td>
  </tr>
</table>
<h2>Nhật ký hoạt động hệ thống</h2>

<table>
  <tr>
    <th>Mã nhật ký</th>
    <th>Bảng dữ liệu</th>
    <th>Hành động</th>
    <th>Người thực hiện</th>
    <th>Thời gian</th>
  </tr>

  ${auditLogs.map(log => `
    <tr>
      <td>${esc(log.AuditLogId ?? '')}</td>
      <td>${esc(log.TableSchema ?? '')}.${esc(log.TableName ?? '')}</td>
      <td>${esc(log.Action ?? '')}</td>
      <td>${esc(log.ChangedByName ?? 'Hệ thống')}</td>
      <td>${log.ChangedAt ? esc(new Date(log.ChangedAt).toLocaleString('vi-VN')) : ''}</td>
    </tr>
  `).join('')}
</table>
<h2>Thống kê AI Recommendation</h2>

<table>
  <tr>
    <th>Phiên bản AI</th>
    <th>Loại đề xuất</th>
    <th>Lượt hiển thị</th>
    <th>Lượt nhấp</th>
    <th>Lượt đặt hàng</th>
    <th>Lượt bỏ qua</th>
    <th>CTR</th>
    <th>Tỷ lệ đặt hàng</th>
    <th>Điểm trung bình</th>
  </tr>

  ${aiMetrics.map(ai => `
    <tr>
      <td>${esc(ai.ModelVersion ?? '')}</td>
      <td>${esc(ai.RecommendationType ?? '')}</td>
      <td>${esc(ai.Impressions ?? 0)}</td>
      <td>${esc(ai.Clicked ?? 0)}</td>
      <td>${esc(ai.Ordered ?? 0)}</td>
      <td>${esc(ai.Dismissed ?? 0)}</td>
      <td>${esc(ai.CtrRate ?? 0)}</td>
      <td>${esc(ai.OrderRate ?? 0)}</td>
      <td>${esc(ai.AvgScore ?? 0)}</td>
    </tr>
  `).join('')}
</table>
<h2>Danh sách khiếu nại đang xử lý</h2>

<table>
  <tr>
    <th>STT</th>
    <th>Khách hàng</th>
    <th>Phòng Lab</th>
    <th>Lý do</th>
    <th>Trạng thái</th>
  </tr>

  ${complaints.map((c, i) => `
    <tr>
      <td>${i + 1}</td>
      <td>${esc(c.CustomerName ?? '')}</td>
      <td>${esc(c.LabName ?? '')}</td>
      <td>${esc(c.Reason ?? '')}</td>
      <td>${esc(c.Status ?? '')}</td>
    </tr>
  `).join('')}
</table>

        <ul>
          <li><a href="/admin/users">Quản lý người dùng</a></li>
          <li><a href="/admin/labs">Quản lý phòng Lab</a></li>
          <li><a href="/admin/complaints">Khiếu nại đang mở</a></li>
        </ul>
      </body>
      </html>
    `);
  } catch (err) {
    next(err);
  }
});
module.exports = router;

