'use strict';

const router = require('express').Router();
const { randomUUID } = require('node:crypto');
const { requireRole } = require('../lib/auth');
const { HttpError } = require('../lib/errors');
const { sql } = require('../lib/db');

const browse = requireRole('Customer', 'Expert', 'LabOwner');
const customer = requireRole('Customer');
const sorts = { Relevance: 'Phù hợp', Price: 'Giá thấp', Rating: 'Điểm cao', Distance: 'Gần nhất', Turnaround: 'Xử lý nhanh' };
const addressFields = { RecipientName: ['Người nhận', 100], Phone: ['Số điện thoại', 15], Line1: ['Số nhà, tên đường', 255], Ward: ['Phường/xã', 100], District: ['Quận/huyện', 100], City: ['Tỉnh/thành phố', 100], Label: ['Tên gợi nhớ', 50] };

function invalid(message) { throw new HttpError(400, message); }
function field(value, label, max, required = false) {
  if (value == null || value === '') {
    if (required) invalid('Vui lòng nhập ' + label + '.');
    return undefined;
  }
  if (typeof value !== 'string' || value.trim().length > max) invalid(label + ' không hợp lệ.');
  const result = value.trim();
  if (required && !result) invalid('Vui lòng nhập ' + label + '.');
  return result || undefined;
}
function number(value, label, min, max, integer = false, required = false) {
  const raw = field(value, label, 32, required);
  if (raw === undefined) return undefined;
  const n = Number(raw);
  if (!/^-?\d+(\.\d+)?$/.test(raw) || !Number.isFinite(n) || n < min || n > max || (integer && !Number.isSafeInteger(n))) invalid(label + ' ngoài phạm vi hợp lệ.');
  return n;
}
const id = (value, label) => number(value, label, 1, 2147483647, true, true);
function choice(value, options, label) {
  if (!options.includes(value)) invalid('Vui lòng chọn ' + label + ' hợp lệ.');
  return value;
}
function recId(value) {
  return typeof value === 'string' && /^[1-9]\d{0,18}$/.test(value) && BigInt(value) <= 9223372036854775807n ? value : '';
}
function addresses(req) {
  return req.callProc('iam.sp_GetMyAddresses', { UserId: req.session.user.id }).then(r => r.recordset);
}
function labData(req, LabId) { return req.callProc('lab.sp_GetLabDetail', { LabId }); }
function url(path, params) {
  const query = new URLSearchParams(Object.entries(params).filter(([,v]) => v !== undefined && v !== '')).toString();
  return query ? path + '?' + query : path;
}

router.get('/labs', browse, async (req, res) => {
  const q = req.query;
  const params = {
    FormatId: number(q.FormatId, 'Khổ phim', 1, 2147483647, true),
    ServiceTypeId: number(q.ServiceTypeId, 'Dịch vụ', 1, 2147483647, true),
    MaxPrice: number(q.MaxPrice, 'Giá tối đa', 0, Number.MAX_SAFE_INTEGER, true),
    MaxTurnaroundDays: number(q.MaxTurnaroundDays, 'Số ngày', 0, 255, true),
    MinRating: number(q.MinRating, 'Điểm tối thiểu', 0, 5),
    Technique: field(q.Technique, 'Kỹ thuật', 50),
    Latitude: number(q.Latitude, 'Vĩ độ', -90, 90),
    Longitude: number(q.Longitude, 'Kinh độ', -180, 180),
    MaxDistanceKm: number(q.MaxDistanceKm, 'Bán kính', 0, 9999.99),
    SortBy: choice(q.SortBy ?? 'Relevance', Object.keys(sorts), 'thứ tự'),
    PageSize: number(q.PageSize, 'Số dòng', 1, 100, true) ?? 20,
    PageNo: number(q.PageNo, 'Số trang', 1, 2147483647, true) ?? 1,
  };
  if (params.PageNo * params.PageSize > 2147483647) invalid('Số trang quá lớn.');
  const [refs, result] = await Promise.all([req.callProc('lab.sp_GetReferenceData'), req.callProc('lab.sp_SearchLabs', params)]);
  let hasNext = false;
  if (result.recordset.length === params.PageSize && (params.PageNo + 1) * params.PageSize <= 2147483647) {
    const next = await req.callProc('lab.sp_SearchLabs', { ...params, PageNo: params.PageNo + 1 });
    hasNext = next.recordset.length > 0;
  }
  res.render('labs/index', { title: 'Tìm lab', labs: result.recordset, params, sorts,
    formats: refs.recordsets[0], types: refs.recordsets[1], hasNext,
    pageUrl: n => url('/labs', { ...params, PageNo: n }) });
});

router.get('/labs/:id', browse, async (req, res) => {
  const LabId = id(req.params.id, 'Mã lab');
  const r = await labData(req, LabId);
  const lab = r.recordsets[0][0];
  let reviews = null;
  if (req.session.user.role !== 'Expert' && Number(lab.ReviewCount) > 0) {
    try { reviews = (await req.callProc('ord.sp_GetPublicLabReviews', { LabId })).recordset; }
    catch (e) { if (e.number !== 2812) throw e; } // Database P1 trước khi có procedure đọc review.
  } else if (!Number(lab.ReviewCount)) reviews = [];
  res.render('labs/detail', { title: lab.LabName, lab, services: r.recordsets[1], reviews,
    orderUrl: url('/orders/new', { labId: LabId, rec: recId(req.query.rec) }) });
});

router.get('/orders/new', customer, async (req, res) => {
  if (!req.query.labId) return res.redirect('/labs');
  const LabId = id(req.query.labId, 'Mã lab');
  const [r, refs, list] = await Promise.all([labData(req, LabId), req.callProc('lab.sp_GetReferenceData'), addresses(req)]);
  res.render('checkout/new', { title: 'Đặt dịch vụ', lab: r.recordsets[0][0], services: r.recordsets[1],
    formats: refs.recordsets[0], list, rec: recId(req.query.rec), addressUrl: url('/account/addresses', { labId: LabId, rec: recId(req.query.rec) }) });
});

router.post('/orders/new', customer, async (req, res) => {
  const b = req.body || {};
  const LabId = id(b.labId, 'Mã lab');
  const FulfillmentMethod = choice(b.fulfillment, ['DropOff','Pickup'], 'cách gửi phim');
  const ReturnMethod = choice(b.returnMethod, ['SelfCollect','Delivery'], 'cách nhận lại');
  const items = [];
  for (const [key, value] of Object.entries(b.quantity || {})) {
    if (!/^s[1-9]\d*$/.test(key)) invalid('Mã gói không hợp lệ.');
    const quantity = number(value, 'Số lượng', 0, 2147483647, true);
    if (!quantity) continue;
    items.push({ labServiceId: id(key.slice(1), 'Mã gói'), quantity,
      filmStockId: number(b.stock?.[key], 'Mã loại phim', 1, 2147483647, true) ?? null,
      note: field(b.note?.[key], 'Ghi chú dịch vụ', 255) ?? null });
  }
  if (!items.length) invalid('Chọn ít nhất một gói với số lượng lớn hơn 0.');
  const UserId = req.session.user.id;
  const r = await req.callProc('ord.sp_CreateOrder', {
    CustomerId: UserId, LabId, FulfillmentMethod, ReturnMethod,
    PickupAddressId: FulfillmentMethod === 'Pickup' ? id(b.pickupAddress, 'Địa chỉ lấy phim') : undefined,
    ReturnAddressId: ReturnMethod === 'Delivery' ? id(b.returnAddress, 'Địa chỉ trả phim') : undefined,
    ItemsJson: items, CustomerNote: field(b.customerNote, 'Ghi chú đơn', 500),
  }, { NewOrderId: sql.Int });
  const rec = recId(b.rec);
  if (rec) {
    try {
      await req.callProc('ai.sp_RecordOrderedLab', { RecLogId: rec, UserId, LabId });
    } catch (e) {
      console.warn('P2: chưa ghi được Ordered cho đơn', r.output.NewOrderId, e.number || e.code);
    }
  }
  req.flash('success', 'Đã tạo đơn. Bạn có thể thanh toán sau khi lab xác nhận.');
  res.redirect(303, '/orders/' + r.output.NewOrderId + '/pay');
});

router.get('/account/addresses', customer, async (req, res) => {
  const list = await addresses(req);
  const editId = number(req.query.edit, 'Mã địa chỉ', 1, 2147483647, true);
  const edit = editId && list.find(a => a.AddressId === editId);
  if (editId && !edit) throw new HttpError(404, 'Không tìm thấy địa chỉ của bạn.');
  const labId = number(req.query.labId, 'Mã lab', 1, 2147483647, true);
  const context = { labId, rec: recId(req.query.rec) };
  res.render('checkout/addresses', { title: 'Địa chỉ của tôi', list, edit: edit || {}, addressFields,
    addressUrl: edit => url('/account/addresses', { ...context, edit }), orderUrl: labId && url('/orders/new', context) });
});

router.post('/account/addresses', customer, async (req, res) => {
  const b = req.body || {};
  const AddressId = number(b.addressId, 'Mã địa chỉ', 1, 2147483647, true);
  const remove = choice(b.action, ['save','delete'], 'thao tác') === 'delete';
  let src = b;
  if (remove) {
    src = (await addresses(req)).find(a => a.AddressId === AddressId);
    if (!src) throw new HttpError(404, 'Không tìm thấy địa chỉ của bạn.');
  }
  const data = {};
  for (const [key, [label, max]] of Object.entries(addressFields)) data[key] = field(src[key], label, max, key !== 'Label');
  const labId = number(req.query.labId, 'Mã lab', 1, 2147483647, true);
  const Latitude = number(b.Latitude, 'Vĩ độ', -90, 90);
  const Longitude = number(b.Longitude, 'Kinh độ', -180, 180);
  if (!remove && AddressId && Latitude === undefined && Longitude === undefined && b.clearCoordinates !== 'yes') {
    invalid('Khi sửa địa chỉ, hãy nhập tọa độ hoặc xác nhận lưu không có tọa độ.');
  }
  await req.callProc('iam.sp_SaveAddress', { ...data, AddressId, UserId: req.session.user.id,
    Latitude, Longitude, IsDefault: b.isDefault === 'yes', IsDeleted: remove }, { NewAddressId: sql.Int });
  req.flash('success', remove ? 'Đã xóa địa chỉ.' : 'Đã lưu địa chỉ.');
  res.redirect(303, url('/account/addresses', { labId, rec: recId(req.query.rec) }));
});

async function myOrder(req) {
  const UserId = req.session.user.id;
  const r = await req.callProc('ord.sp_GetOrderDetail', { OrderId: id(req.params.id, 'Mã đơn'), UserId });
  const order = r.recordsets[0][0];
  if (!order || order.CustomerId !== UserId) throw new HttpError(404, 'Không tìm thấy đơn của bạn.');
  return order;
}
router.get('/orders/:id/pay', customer, async (req, res) => {
  res.render('checkout/pay', { title: 'Thanh toán giả lập', order: await myOrder(req) });
});
router.post('/orders/:id/pay', customer, async (req, res) => {
  const order = await myOrder(req);
  const b = req.body || {};
  const Method = choice(b.method, ['Card','EWallet','BankTransfer'], 'phương thức thanh toán');
  const Succeeded = choice(b.outcome, ['success','failure'], 'kết quả giả lập') === 'success';
  const FailureReason = Succeeded ? undefined : field(b.reason, 'lý do thất bại', 255, true);
  if (!Number.isSafeInteger(order.TotalAmount)) throw new HttpError(409, 'Số tiền ngoài phạm vi thanh toán của web.');
  await req.callProc('ord.sp_ProcessPayment', { OrderId: order.OrderId, ActorUserId: req.session.user.id,
    Method, Amount: order.TotalAmount, Provider: 'FilmLabDemo', ProviderTxnId: randomUUID(), Succeeded, FailureReason }, { NewPaymentId: sql.Int });
  req.flash(Succeeded ? 'success' : 'warning', Succeeded ? 'Đã thanh toán giả lập thành công.' : 'Đã ghi nhận lần thanh toán thất bại. Bạn có thể thử lại.');
  res.redirect(303, '/orders/' + order.OrderId + '/pay');
});
module.exports = router;
