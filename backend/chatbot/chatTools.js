'use strict';
const { sql } = require('../lib/db');

const ORDER_CODE_RE = /FL-\d{4}-\d{6}/i;
const STATUS_WORDS = ['đến đâu', 'trạng thái', 'tình trạng', 'tiến độ', 'bao giờ xong'];
const REC_WORDS = ['gợi ý', 'đề xuất', 'nên chọn', 'nên dùng', 'tốt nhất'];
const ASK_CODE = 'Bạn cho mình mã đơn (dạng FL-2026-000001) để mình tra tiến độ giúp bạn nhé.';

// DB lưu UTC, hiển thị giờ Việt Nam
const fmt = (d) => (d ? new Date(d).toLocaleString('vi-VN', { timeZone: 'Asia/Ho_Chi_Minh', hour12: false }) : 'chưa có');
const fmtDate = (d) => (d ? new Date(d).toLocaleDateString('vi-VN', { timeZone: 'UTC' }) : 'chưa có');
const money = (v) => `${Number(v).toLocaleString('vi-VN')} đ`;
const has = (text, words) => words.some((w) => text.includes(w));

async function orderStatus(req, code) {
  const userId = req.session.user.id;
  const found = await req.callProc('ord.sp_FindMyOrderByCode', { OrderCode: code, UserId: userId });
  const row = found.recordset[0];
  if (!row) {
    return {
      intent: 'order_not_found',
      reply: `Không tìm thấy đơn ${code} trong tài khoản của bạn. Bạn kiểm tra lại mã đơn nhé.`,
    };
  }

  const d = await req.callProc('ord.sp_GetOrderDetail', { OrderId: row.OrderId, UserId: userId });
  const [orders, items, timeline, , delivery] = d.recordsets;
  const o = orders[0];

  const lines = [
    `Mã đơn: ${o.OrderCode}`,
    `Lab: ${o.LabName}`,
    `Trạng thái hiện tại: ${o.StageName} (${o.StageCode})`,
    `Hình thức gửi phim: ${o.FulfillmentMethod}; hình thức nhận lại: ${o.ReturnMethod}`,
    `Thanh toán: ${o.PaymentStatus}`,
    `Tổng tiền: ${money(o.TotalAmount)}`,
    `Ngày tạo: ${fmt(o.CreatedAt)}`,
    `Dự kiến xong: ${fmtDate(o.EstimatedReadyDate)}`,
    `Hoàn tất lúc: ${fmt(o.CompletedAt)}`,
  ];
  if (o.CancelReason) lines.push(`Lý do hủy: ${o.CancelReason}`);

  lines.push('Dịch vụ trong đơn:');
  items.forEach((i) => {
    lines.push(`- ${i.PackageName}, ${i.FormatName || 'không ghi khổ phim'}, phim ${i.FilmStock || 'không ghi'}, số lượng ${i.Quantity}`);
  });

  lines.push('Các bước gần nhất:');
  timeline.slice(-3).forEach((t) => lines.push(`- ${t.ToStageName}: ${fmt(t.ChangedAt)}`));

  lines.push('Giao nhận:');
  if (delivery.length === 0) lines.push('- Chưa có yêu cầu giao nhận');
  delivery.forEach((x) => lines.push(`- ${x.Direction}: ${x.Status}, hẹn ${fmt(x.ScheduledAt)}`));

  return { intent: 'order_status', dataText: lines.join('\n'), sourceLabel: 'Dữ liệu đơn hàng của bạn' };
}

async function recommend(req) {
  const r = await req.callProc('ai.sp_GetLabRecommendations', {
    UserId: req.session.user.id,
    TopN: { type: sql.TinyInt, value: 3 },
  });
  const rows = r.recordset;
  if (rows.length === 0) {
    return {
      intent: 'lab_recommend',
      reply: 'Hiện chưa có lab phù hợp để gợi ý. Bạn thử đặt tùy chọn ở trang Gợi ý lab (/recommend) nhé.',
    };
  }
  const lines = ['Danh sách lab gợi ý cho bạn (đã xếp hạng):'];
  rows.forEach((x) => {
    const dist = x.DistanceKm == null ? 'chưa có vị trí' : `${x.DistanceKm} km`;
    lines.push(`${x.Rank}. ${x.LabName}: điểm phù hợp ${x.Score}, đánh giá trung bình ${x.AvgRating}/5, khoảng cách ${dist}`);
  });
  return { intent: 'lab_recommend', dataText: lines.join('\n'), sourceLabel: 'Gợi ý lab từ hệ thống' };
}

/**
 * Định tuyến theo ý định bằng quy tắc. Trả null nếu không khớp hoặc SP lỗi
 * (ví dụ role không có EXECUTE) để route chạy RAG như cũ.
 * Trả { intent, reply } (câu cố định) hoặc { intent, dataText, sourceLabel } (đưa Gemini diễn đạt).
 */
async function route(req, question) {
  const text = question.normalize('NFC');
  const lower = text.toLowerCase();
  try {
    const m = text.match(ORDER_CODE_RE);
    if (m) return await orderStatus(req, m[0].toUpperCase());
    if (lower.includes('đơn') && has(lower, STATUS_WORDS)) return { intent: 'order_ask_code', reply: ASK_CODE };
    if (lower.includes('lab') && has(lower, REC_WORDS)) return await recommend(req);
  } catch (e) {
    console.error(`[chatTools] ${e.message}`);
  }
  return null;
}

module.exports = { route };