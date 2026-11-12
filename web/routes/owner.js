'use strict';
// P4 - Portal chủ lab. Chỉ dùng proc để ghi; SELECT read-only qua queryAs (README §4/D1).
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const router = require('express').Router();
const multer = require('multer');
const { sql, queryAs } = require('../lib/db');
const { requireRole } = require('../lib/auth');
const { HttpError, mapDbError } = require('../lib/errors');
const { uploadDir } = require('../lib/config');

const ownerOnly = requireRole('LabOwner');
const scansDir = path.join(uploadDir, 'owner');
const PAGE_SIZE = 20;
const int = (value) => ({ type: sql.Int, value });
const text = (v, max = 255) => String(v == null ? '' : v).trim().slice(0, max);
const opt = (v, max = 255) => text(v, max) || null;

function positiveId(value) {
  const s = String(value ?? '');
  if (!/^[1-9]\d*$/.test(s)) throw new HttpError(400, 'Mã dữ liệu không hợp lệ.');
  const n = Number(s);
  if (!Number.isSafeInteger(n) || n > 2147483647) throw new HttpError(400, 'Mã dữ liệu không hợp lệ.');
  return n;
}
function optionalId(value) { return value ? positiveId(value) : null; }
function smallInt(value, min, max, label) {
  const n = Number(value);
  if (!/^\d+$/.test(String(value ?? '')) || !Number.isInteger(n) || n < min || n > max) {
    throw new HttpError(400, `${label} phải từ ${min} đến ${max}.`);
  }
  return n;
}
function money(value) {
  const str = String(value ?? '').trim();
  const n = Number(str);
  if (!/^\d+$/.test(str) || !Number.isSafeInteger(n) || n < 0 || n > 999999999999) {
    throw new HttpError(400, 'Đơn giá phải là số nguyên từ 0 đến 999.999.999.999.');
  }
  return n;
}
function optionalFloat(value, min, max) {
  if (value == null || String(value).trim() === '') return null;
  const s = String(value).trim();
  if (!/^-?\d+(\.\d+)?$/.test(s)) throw new HttpError(400, 'Tọa độ không hợp lệ.');
  const n = Number(s);
  if (!Number.isFinite(n) || n < min || n > max) throw new HttpError(400, 'Tọa độ ngoài phạm vi.');
  return n;
}
function jsonOrNull(raw, label) {
  const value = opt(raw, 4000);
  if (!value) return null;
  try { JSON.parse(value); } catch { throw new HttpError(400, `${label} phải là JSON hợp lệ.`); }
  return value;
}
function formError(res, err, view, data) {
  const mapped = err instanceof HttpError ? { status: err.status, message: err.message } : mapDbError(err);
  if (!mapped || mapped.status >= 500 || mapped.status === 403 || mapped.status === 404) throw err;
  res.locals.flash.push({ type: 'danger', msg: mapped.message });
  return res.status(mapped.status).render(view, data);
}
async function ownerData(req) {
  const r = await req.callProc('lab.sp_GetMyLabs', { OwnerUserId: int(req.session.user.id) });
  return { labs: r.recordsets[0] || [], services: r.recordsets[1] || [] };
}
function ownedLab(data, id) {
  const lab = data.labs.find((l) => l.LabId === id);
  if (!lab) throw new HttpError(404, 'Lab không tồn tại hoặc không thuộc tài khoản của bạn.');
  return lab;
}
function ownedService(data, labId, serviceId) {
  ownedLab(data, labId);
  const item = data.services.find((s) => s.LabId === labId && s.LabServiceId === serviceId);
  if (!item) throw new HttpError(404, 'Dịch vụ không tồn tại trong lab này.');
  return item;
}
async function refs(req) {
  const r = await req.callProc('lab.sp_GetReferenceData');
  return { formats: r.recordsets[0] || [], types: r.recordsets[1] || [], stages: r.recordsets[2] || [] };
}
function labFields(body) {
  return {
    labName: text(body.labName, 150), addressLine: text(body.addressLine, 255),
    ward: text(body.ward, 100), district: text(body.district, 100), city: text(body.city, 100),
    description: opt(body.description, 1000), phone: opt(body.phone, 20), email: opt(body.email, 255),
    openHoursJson: opt(body.openHoursJson, 4000), specialTechniques: opt(body.specialTechniques, 4000),
    dailyCapacityRolls: body.dailyCapacityRolls, latitude: body.latitude, longitude: body.longitude,
  };
}
function labFromRow(row) {
  return {
    labName: row.LabName, addressLine: row.AddressLine, ward: row.Ward,
    district: row.District, city: row.City, description: row.Description,
    phone: row.Phone, email: row.Email, openHoursJson: row.OpenHoursJson,
    specialTechniques: row.SpecialTechniques, dailyCapacityRolls: row.DailyCapacityRolls,
    latitude: row.Latitude, longitude: row.Longitude,
  };
}
function labParams(userId, labId, form) {
  for (const key of ['labName', 'addressLine', 'ward', 'district', 'city']) {
    if (!form[key]) throw new HttpError(400, 'Vui lòng nhập đủ tên lab và địa chỉ.');
  }
  const latitude = optionalFloat(form.latitude, -90, 90);
  const longitude = optionalFloat(form.longitude, -180, 180);
  if ((latitude === null) !== (longitude === null)) throw new HttpError(400, 'Vui lòng nhập cả vĩ độ và kinh độ.');
  return {
    OwnerUserId: int(userId), LabId: labId === null ? null : int(labId),
    LabName: form.labName, AddressLine: form.addressLine, Ward: form.ward,
    District: form.district, City: form.city, Description: form.description,
    Phone: form.phone, Email: form.email,
    OpenHoursJson: jsonOrNull(form.openHoursJson, 'Giờ mở cửa'),
    SpecialTechniques: jsonOrNull(form.specialTechniques, 'Kỹ thuật đặc biệt'),
    DailyCapacityRolls: { type: sql.SmallInt, value: smallInt(form.dailyCapacityRolls, 1, 32767, 'Công suất ngày') },
    Latitude: latitude, Longitude: longitude,
  };
}
function serviceFromRow(row) {
  return {
    labServiceId: row.LabServiceId || '', serviceTypeId: row.ServiceTypeId || '',
    formatId: row.FormatId || '', packageName: row.PackageName || '',
    unitPrice: row.UnitPrice ?? '', turnaroundDays: row.TurnaroundDays ?? 3,
    description: row.Description || '', processCode: row.ProcessCode || 'ANY',
    priceUnit: row.PriceUnit || 'Roll', scanQuality: row.ScanQuality || '',
    isActive: row.IsActive === undefined ? true : Boolean(row.IsActive),
  };
}
function serviceFields(body) {
  return {
    labServiceId: body.labServiceId || '', serviceTypeId: body.serviceTypeId,
    formatId: body.formatId, packageName: text(body.packageName, 150),
    unitPrice: body.unitPrice, turnaroundDays: body.turnaroundDays,
    description: opt(body.description, 500), processCode: text(body.processCode, 10) || 'ANY',
    priceUnit: text(body.priceUnit, 5) || 'Roll', scanQuality: body.scanQuality || '',
    isActive: body.isActive === '1' || body.isActive === true,
  };
}
function serviceParams(userId, labId, form, serviceId = null, isDeleted = false) {
  if (!form.packageName) throw new HttpError(400, 'Bạn cần nhập tên gói dịch vụ.');
  if (!['ANY', 'C-41', 'E-6', 'BW', 'ECN-2'].includes(form.processCode)) throw new HttpError(400, 'Quy trình xử lý không hợp lệ.');
  if (!['Roll', 'Frame'].includes(form.priceUnit)) throw new HttpError(400, 'Đơn vị tính không hợp lệ.');
  if (form.scanQuality && !['Basic', 'High', 'Ultra'].includes(form.scanQuality)) throw new HttpError(400, 'Chất lượng scan không hợp lệ.');
  return {
    OwnerUserId: int(userId), LabId: int(labId),
    LabServiceId: serviceId === null ? null : int(serviceId),
    ServiceTypeId: int(positiveId(form.serviceTypeId)), FormatId: int(positiveId(form.formatId)),
    PackageName: form.packageName,
    UnitPrice: { type: sql.Decimal(18, 0), value: money(form.unitPrice) },
    TurnaroundDays: { type: sql.TinyInt, value: smallInt(form.turnaroundDays, 1, 60, 'Thời gian xử lý') },
    ProcessCode: form.processCode, Description: form.description,
    PriceUnit: form.priceUnit, ScanQuality: form.scanQuality || null,
    IsActive: Boolean(form.isActive) && !isDeleted, IsDeleted: Boolean(isDeleted),
  };
}
function sqlInLabIds(labs) {
  if (!labs.length) return { clause: 'NULL', args: {} };
  const args = Object.fromEntries(labs.map((lab, i) => [`Lab${i}`, int(lab.LabId)]));
  return { clause: labs.map((_, i) => `@Lab${i}`).join(', '), args };
}

// --- Danh sách lab & hồ sơ ---
router.get('/owner/labs', ownerOnly, async (req, res) => {
  const data = await ownerData(req);
  return res.render('owner/labs', { title: 'Lab của tôi', ...data });
});
router.get('/owner/labs/new', ownerOnly, (req, res) => {
  return res.render('owner/lab-form', { title: 'Tạo lab mới', labId: null, lab: labFields({}), editing: false });
});
router.post('/owner/labs/new', ownerOnly, async (req, res) => {
  const form = labFields(req.body);
  try {
    const r = await req.callProc('lab.sp_SaveLabProfile', labParams(req.session.user.id, null, form), { NewLabId: sql.Int });
    req.flash('success', 'Đã tạo lab. Hồ sơ sẽ ở trạng thái chờ Admin duyệt.');
    return res.redirect(`/owner/labs/${r.output.NewLabId}/edit`);
  } catch (e) {
    return formError(res, e, 'owner/lab-form', { title: 'Tạo lab mới', labId: null, lab: form, editing: false });
  }
});
router.get('/owner/labs/:id/edit', ownerOnly, async (req, res) => {
  const id = positiveId(req.params.id);
  const data = await ownerData(req);
  const lab = ownedLab(data, id);
  return res.render('owner/lab-form', { title: 'Sửa thông tin lab', labId: id, lab: labFromRow(lab), editing: true, approval: lab.ApprovalStatus });
});
router.post('/owner/labs/:id/edit', ownerOnly, async (req, res) => {
  const id = positiveId(req.params.id);
  const data = await ownerData(req);
  const lab = ownedLab(data, id);
  const form = labFields(req.body);
  try {
    await req.callProc('lab.sp_SaveLabProfile', labParams(req.session.user.id, id, form), { NewLabId: sql.Int });
    req.flash('success', 'Thông tin lab đã được lưu vào database.');
    return res.redirect(`/owner/labs/${id}/edit`);
  } catch (e) {
    return formError(res, e, 'owner/lab-form', { title: 'Sửa thông tin lab', labId: id, lab: form, editing: true, approval: lab.ApprovalStatus });
  }
});

// --- Dịch vụ: tạo / sửa / bật-tắt / xóa mềm ---
router.get('/owner/labs/:id/services', ownerOnly, async (req, res) => {
  const id = positiveId(req.params.id);
  const data = await ownerData(req);
  const lab = ownedLab(data, id);
  const reference = await refs(req);
  const editId = optionalId(req.query.edit);
  const edit = editId ? ownedService(data, id, editId) : null;
  return res.render('owner/services', {
    title: 'Dịch vụ · ' + lab.LabName, lab, services: data.services.filter((s) => s.LabId === id),
    form: edit ? serviceFromRow(edit) : serviceFromRow({}), ...reference,
  });
});
router.post('/owner/labs/:id/services', ownerOnly, async (req, res) => {
  const id = positiveId(req.params.id);
  const data = await ownerData(req);
  const lab = ownedLab(data, id);
  const form = serviceFields(req.body);
  const editId = optionalId(form.labServiceId);
  if (editId) ownedService(data, id, editId);
  try {
    const p = serviceParams(req.session.user.id, id, form, editId);
    await req.callProc('lab.sp_SaveLabService', p, { NewLabServiceId: sql.Int });
    req.flash('success', editId ? 'Đã lưu thay đổi dịch vụ.' : 'Đã thêm dịch vụ mới.');
    return res.redirect(`/owner/labs/${id}/services`);
  } catch (e) {
    const reference = await refs(req);
    return formError(res, e, 'owner/services', {
      title: 'Dịch vụ · ' + lab.LabName, lab, form,
      services: data.services.filter((s) => s.LabId === id), ...reference,
    });
  }
});
router.post('/owner/labs/:id/services/:serviceId/:action', ownerOnly, async (req, res) => {
  const labId = positiveId(req.params.id);
  const serviceId = positiveId(req.params.serviceId);
  const action = req.params.action;
  if (!['toggle', 'delete'].includes(action)) throw new HttpError(404, 'Không tìm thấy thao tác dịch vụ.');
  const data = await ownerData(req);
  const item = ownedService(data, labId, serviceId);
  const form = serviceFromRow(item);
  if (action === 'toggle') form.isActive = !form.isActive;
  if (action === 'delete') form.isActive = false;
  await req.callProc('lab.sp_SaveLabService', serviceParams(req.session.user.id, labId, form, serviceId, action === 'delete'), { NewLabServiceId: sql.Int });
  req.flash('success', action === 'delete' ? 'Đã xóa mềm gói dịch vụ.' : 'Đã đổi trạng thái dịch vụ.');
  return res.redirect(`/owner/labs/${labId}/services`);
});

// --- Đơn hàng: tất cả hoặc lọc theo chi nhánh; đọc là SELECT/procedure, không ghi thẳng ---
router.get('/owner/orders', ownerOnly, async (req, res) => {
  const data = await ownerData(req);
  const reference = await refs(req);
  const stageCode = opt(req.query.stage, 20);
  const stage = stageCode ? reference.stages.find((s) => s.StageCode === stageCode) : null;
  if (stageCode && !stage) throw new HttpError(400, 'Trạng thái đơn không hợp lệ.');
  const labId = optionalId(req.query.lab);
  if (labId) ownedLab(data, labId);
  const page = req.query.page ? smallInt(req.query.page, 1, 100000, 'Trang') : 1;
  let orders = [], totalRows = 0;
  if (labId) {
    // SELECT bảng đã GRANT, RLS; LabId phải có trong sp_GetMyLabs (không đọc dữ liệu lab khác).
    const r = await queryAs(req.session.user.role, req.session.user.id,
      `SELECT OrderId, OrderCode, CustomerId, LabId, StageId, PaymentStatus,
              TotalAmount, FulfillmentMethod, ReturnMethod, EstimatedReadyDate, CreatedAt,
              COUNT_BIG(*) OVER() AS TotalRows
       FROM ord.Orders
       WHERE IsDeleted = 0 AND LabId = @LabId AND (@StageId IS NULL OR StageId = @StageId)
       ORDER BY CreatedAt DESC, OrderId DESC
       OFFSET @Offset ROWS FETCH NEXT @Limit ROWS ONLY`,
      { LabId: int(labId), StageId: stage ? int(stage.StageId) : null, Offset: int((page - 1) * PAGE_SIZE), Limit: int(PAGE_SIZE) });
    orders = r.recordset.map((o) => ({ ...o,
      LabName: data.labs.find((l) => l.LabId === o.LabId)?.LabName,
      StageName: reference.stages.find((s) => s.StageId === o.StageId)?.StageName,
    }));
  } else {
    const r = await req.callProc('ord.sp_GetMyOrders', {
      UserId: int(req.session.user.id), AsRole: 'LabOwner', StageCode: stageCode,
      PageNo: int(page), PageSize: int(PAGE_SIZE),
    });
    orders = r.recordset;
  }
  if (orders.length) totalRows = Number(orders[0].TotalRows);
  const { clause, args } = sqlInLabIds(data.labs);
  const active = data.labs.length ? (await queryAs(req.session.user.role, req.session.user.id,
    `SELECT TOP (100) OrderId, OrderCode, LabId, StageName, DaysInProgress, PaymentStatus, EstimatedReadyDate
     FROM ord.vw_OrdersInProgress WHERE LabId IN (${clause}) ORDER BY DaysInProgress DESC, CreatedAt DESC`, args)).recordset : [];
  return res.render('owner/orders', {
    title: 'Đơn hàng', labs: data.labs, orders, active, stages: reference.stages,
    labId, stageCode, page, totalRows, pageCount: Math.ceil(totalRows / PAGE_SIZE),
  });
});
router.get('/owner/orders/:id', ownerOnly, async (req, res) => {
  const id = positiveId(req.params.id);
  const r = await req.callProc('ord.sp_GetOrderDetail', { OrderId: int(id), UserId: int(req.session.user.id) });
  if (!r.recordsets[0]?.[0]) throw new HttpError(404, 'Không tìm thấy đơn hàng.');
  const detail = {
    order: r.recordsets[0][0], items: r.recordsets[1] || [], timeline: r.recordsets[2] || [],
    payments: r.recordsets[3] || [], deliveries: r.recordsets[4] || [],
  };
  const reference = await refs(req);
  return res.render('owner/order-detail', { title: 'Đơn ' + detail.order.OrderCode, ...detail, stages: reference.stages });
});
router.post('/owner/orders/:id/stage', ownerOnly, async (req, res) => {
  const id = positiveId(req.params.id);
  const stage = positiveId(req.body.stageId);
  const note = opt(req.body.note, 255);
  try {
    await req.callProc('ord.sp_UpdateOrderStage', {
      OrderId: int(id), ActorUserId: int(req.session.user.id), NewStageId: int(stage), Note: note,
      // KHÔNG truyền CallerAuthorized: procedure tự kiểm quyền.
    });
    req.flash('success', 'Đã cập nhật tiến độ đơn hàng.');
  } catch (e) {
    const mapped = mapDbError(e);
    if (!mapped || mapped.status >= 500) throw e;
    req.flash('danger', mapped.message);
  }
  return res.redirect(`/owner/orders/${id}`);
});

// --- Upload ảnh scan: file lưu riêng; tải về phải qua RLS, không public static. ---
const MIME_EXT = { 'image/jpeg': '.jpg', 'image/png': '.png', 'image/tiff': '.tiff' };
const MIME_SIGNATURE = {
  'image/jpeg': (b) => b.length >= 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff,
  'image/png': (b) => b.length >= 8 && b.subarray(0, 8).equals(Buffer.from('89504e470d0a1a0a', 'hex')),
  'image/tiff': (b) => b.length >= 4 && (b.subarray(0, 4).equals(Buffer.from('49492a00', 'hex')) || b.subarray(0, 4).equals(Buffer.from('4d4d002a', 'hex'))),
};
const scanUpload = multer({
  storage: multer.diskStorage({
    destination: (req, file, cb) => {
      fs.mkdir(scansDir, { recursive: true }, (err) => cb(err, scansDir));
    },
    filename: (req, file, cb) => cb(null, crypto.randomUUID() + MIME_EXT[file.mimetype]),
  }),
  limits: { fileSize: 200 * 1024 * 1024, files: 1 },
  fileFilter: (req, file, cb) => MIME_EXT[file.mimetype] ? cb(null, true) : cb(new HttpError(400, 'Chỉ nhận JPEG, PNG hoặc TIFF.')),
});
function uploadOne(req, res, next) {
  scanUpload.single('scan')(req, res, (err) => {
    if (!err) return next();
    if (err instanceof multer.MulterError) return next(new HttpError(400, 'Ảnh quá lớn (tối đa 200 MB) hoặc tải lên không hợp lệ.'));
    return next(err);
  });
}
async function checkOwnOrder(req, res, next) {
  const id = positiveId(req.params.id);
  const r = await req.callProc('ord.sp_GetOrderDetail', { OrderId: int(id), UserId: int(req.session.user.id) });
  const order = r.recordsets[0]?.[0];
  if (!order) throw new HttpError(404, 'Đơn hàng không tồn tại.');
  const data = await ownerData(req);
  ownedLab(data, order.LabId);
  next();
}
router.post('/owner/orders/:id/scans', ownerOnly, checkOwnOrder, uploadOne, async (req, res) => {
  const id = positiveId(req.params.id);
  const file = req.file;
  if (!file) throw new HttpError(400, 'Vui lòng chọn ảnh scan.');
  try {
    const fd = await fs.promises.open(file.path, 'r');
    const header = Buffer.alloc(12);
    try { await fd.read(header, 0, 12, 0); } finally { await fd.close(); }
    if (!MIME_SIGNATURE[file.mimetype](header)) throw new HttpError(400, 'Nội dung file không đúng định dạng ảnh được hỗ trợ.');
    const hash = crypto.createHash('sha256');
    for await (const chunk of fs.createReadStream(file.path)) hash.update(chunk);
    const frame = req.body.frameNumber ? smallInt(req.body.frameNumber, 1, 32767, 'Số khung') : null;
    const itemId = optionalId(req.body.orderItemId);
    await req.callProc('arc.sp_UploadScan', {
      OrderId: int(id), ActorUserId: int(req.session.user.id),
      FileName: text(file.originalname, 255), StorageUrl: `/owner/scans/${file.filename}`,
      ContentType: file.mimetype, FileSizeBytes: { type: sql.BigInt, value: file.size },
      FrameNumber: frame === null ? null : { type: sql.SmallInt, value: frame },
      OrderItemId: itemId === null ? null : int(itemId), ChecksumSha256: hash.digest('hex'),
    }, { NewScanFileId: sql.UniqueIdentifier });
    req.flash('success', 'Đã tải ảnh scan và lưu metadata vào database.');
  } catch (e) {
    await fs.promises.unlink(file.path).catch(() => {});
    const mapped = e instanceof HttpError ? { status: e.status, message: e.message } : mapDbError(e);
    if (!mapped || mapped.status >= 500) throw e;
    req.flash('danger', mapped.message);
  }
  return res.redirect(`/owner/orders/${id}`);
});
router.get('/owner/scans/:fileName', requireRole('Customer', 'LabOwner', 'Admin'), async (req, res, next) => {
  const fileName = String(req.params.fileName || '');
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|png|tiff)$/.test(fileName)) {
    throw new HttpError(404, 'Không tìm thấy ảnh.');
  }
  const url = `/owner/scans/${fileName}`;
  const r = await queryAs(req.session.user.role, req.session.user.id,
    'SELECT TOP (1) ScanFileId, FileName FROM arc.ScanFiles WHERE StorageUrl = @StorageUrl AND IsDeleted = 0',
    { StorageUrl: url });
  if (!r.recordset.length) throw new HttpError(404, 'Ảnh không tồn tại hoặc không thuộc quyền truy cập của bạn.');
  res.set('Cache-Control', 'private, no-store');
  return res.sendFile(fileName, { root: scansDir, dotfiles: 'deny' }, (err) => {
    if (err && !res.headersSent) next(new HttpError(err.status || 404, 'Không đọc được file ảnh.'));
  });
});

// --- Đánh giá: chỉ lab sở hữu, view đọc theo danh sách lab hợp lệ ---
router.get('/owner/reviews', ownerOnly, async (req, res) => {
  const data = await ownerData(req);
  const labId = optionalId(req.query.lab);
  if (labId) ownedLab(data, labId);
  const picked = labId ? data.labs.filter((l) => l.LabId === labId) : data.labs;
  const { clause, args } = sqlInLabIds(picked);
  const reviews = picked.length ? (await queryAs(req.session.user.role, req.session.user.id,
    `SELECT TOP (100) ReviewId, OrderId, OrderCode, LabId, LabName, CustomerName, RatingOverall,
            RatingScanQuality, RatingSpeed, Comment, LabReply, LabRepliedAt, IsVisible, ModerationReason, CreatedAt
     FROM ord.vw_LabReviews WHERE LabId IN (${clause}) ORDER BY CreatedAt DESC, ReviewId DESC`, args)).recordset : [];
  return res.render('owner/reviews', { title: 'Đánh giá khách hàng', labs: data.labs, labId, reviews });
});
router.post('/owner/reviews/:id/reply', ownerOnly, async (req, res) => {
  const id = positiveId(req.params.id);
  const reply = text(req.body.reply, 1000);
  if (!reply) throw new HttpError(400, 'Vui lòng nhập nội dung phản hồi.');
  try {
    await req.callProc('ord.sp_ReplyReview', { ReviewId: int(id), LabOwnerId: int(req.session.user.id), Reply: reply });
    req.flash('success', 'Đã gửi phản hồi đánh giá.');
  } catch (e) {
    const mapped = mapDbError(e);
    if (!mapped || mapped.status >= 500) throw e;
    req.flash('danger', mapped.message);
  }
  return res.redirect('/owner/reviews');
});

// --- Doanh thu: view chỉ tính doanh thu từ đơn Completed + Paid ---
router.get('/owner/revenue', ownerOnly, async (req, res) => {
  const data = await ownerData(req);
  const r = await queryAs(req.session.user.role, req.session.user.id,
    `SELECT LabId, LabName, TotalOrders, CompletedOrders, CancelledOrders, GrossRevenue,
            PlatformFeeTotal, NetRevenue, DeliveryFeeTotal
     FROM ord.vw_LabRevenue WHERE OwnerUserId = @OwnerUserId ORDER BY LabName`,
    { OwnerUserId: int(req.session.user.id) });
  const rows = r.recordset;
  const totals = rows.reduce((acc, row) => {
    for (const k of ['TotalOrders', 'CompletedOrders', 'CancelledOrders', 'GrossRevenue', 'PlatformFeeTotal', 'NetRevenue', 'DeliveryFeeTotal']) {
      acc[k] += Number(row[k] || 0);
    }
    return acc;
  }, { TotalOrders: 0, CompletedOrders: 0, CancelledOrders: 0, GrossRevenue: 0, PlatformFeeTotal: 0, NetRevenue: 0, DeliveryFeeTotal: 0 });
  return res.render('owner/revenue', { title: 'Doanh thu lab', labs: data.labs, rows, totals });
});

module.exports = router;
