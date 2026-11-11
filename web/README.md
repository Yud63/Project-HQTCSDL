# FilmLab web

Web cho đồ án HQTCSDL (database FilmLabDB, SQL Server 2022). Node.js + Express 5 + EJS + mssql, trợ lý AI dùng Gemini. Demo chạy localhost/LAN, không Docker, không hosting.

## 1. Công nghệ và điểm lệch so với đề tài

| Đề tài ghi | Nhóm dùng | Trạng thái và lý do |
|---|---|---|
| ReactJS / Next.js | EJS render phía server | Đã chốt (D4). Cùng mục tiêu giao diện web theo role; nhóm chưa ai làm web nên chọn công nghệ ít lớp nhất |
| PostgreSQL | SQL Server 2022 + T-SQL | Đã chốt (D4). Database FilmLabDB đã hoàn thành bằng SQL Server (procedure, RLS, GRANT theo role) |
| JWT | Session cookie (express-session) + bcrypt | Đã chốt (D4). Web render phía server nên session cookie đơn giản và an toàn hơn; UserId luôn lấy từ session |
| Flutter (mobile) | Không làm mobile | Đã chốt (D4). Chỉ làm web, Customer dùng web luôn |

CSS tự viết (biến `:root`), không Bootstrap. Session lưu trong bộ nhớ: restart server là mất đăng nhập.

## 2. Chạy lần đầu

Yêu cầu: Node >= 20, SQL Server đã có database FilmLabDB và 7 login (`fl_auth`, `fl_customer`, `fl_labowner`, `fl_expert`, `fl_delivery`, `fl_admin`, `fl_system`).

```powershell
npm install
```

```powershell
Copy-Item .env.example .env
```

Mở `.env`, điền `PW_AUTH`, `PW_CUSTOMER`, `PW_LABOWNER`, `PW_EXPERT`, `PW_DELIVERY`, `PW_ADMIN`, `PW_SYSTEM` (hỏi P1), `SESSION_SECRET` (chuỗi ngẫu nhiên). Tạo `SESSION_SECRET`:

```powershell
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
```

```powershell
npm run dev
```

Kết quả mong đợi: log nạp các file `routes/*.js`, dòng cuối `FilmLab web: http://localhost:3000 (development)`.

| Biến `.env` | Ý nghĩa |
|---|---|
| `NODE_ENV` | `development` bật `/dev/*` và thanh vàng DEV. Không có biến này thì mặc định `production` |
| `PORT` | Mặc định 3000 |
| `DB_SERVER`, `DB_PORT`, `DB_NAME` | Địa chỉ SQL Server (mặc định cổng 1433) |
| `DB_ENCRYPT`, `DB_TRUST_CERT` | Mặc định `true` |
| `PW_*` | Mật khẩu từng login SQL, mỗi role một pool kết nối |
| `GEMINI_API_KEY` | Chỉ P1 dùng (trợ lý AI `/chat`), để trống nếu chưa cần. Thiếu key thì `/chat` báo "Trợ lý tạm thời không phản hồi" |
| `GEMINI_MODEL` | Model Gemini chính. Mặc định `gemini-3.8-flash` (có sẵn trong `lib/config.js`, không cần điền) |
| `GEMINI_FALLBACK_MODELS` | Model dự phòng, phân tách bằng dấu phẩy, thử lần lượt khi model chính quá tải (429/5xx). Mặc định `gemini-3.5-flash-lite,gemini-3.6-flash` |
| `SESSION_SECRET` | Bắt buộc, thiếu là server không lên |

Tuyệt đối không commit `.env`, không gửi `.env` hoặc ảnh chụp `.env` lên chat, nhóm, AI.

### Lỗi hay gặp

| Triệu chứng | Nguyên nhân | Cách xử lý |
|---|---|---|
| `EADDRINUSE` cổng 3000 | Còn server cũ đang chạy | Chạy `Get-NetTCPConnection -LocalPort 3000 -State Listen \| Select-Object OwningProcess`, rồi `Stop-Process -Id` kèm số PID in ra (gõ số thật, không gõ dấu `<` `>`), rồi `rs` ở terminal nodemon |
| `ERR_CONNECTION_REFUSED` | Không có server nào chạy | `npm run dev` |
| Đổi `.env` mà không có tác dụng | nodemon chỉ theo dõi `js, mjs, cjs, json`, không theo dõi `.env` | Gõ `rs` ở terminal nodemon |
| `/dev/...` ra 404 | Đang `NODE_ENV=production` | Sửa `.env`, Ctrl + S, `rs` |
| Thiếu biến `...` trong `.env` | Thiếu `SESSION_SECRET`, `DB_SERVER` hoặc `DB_NAME` | Điền theo `.env.example` |
| `rs` báo "not recognized" | Gõ nhầm vào terminal PowerShell thường | `rs` chỉ gõ ở terminal đang chạy nodemon |

Ghi chú PowerShell: terminal đang chạy `npm run dev` bị chiếm, lệnh khác phải mở terminal thứ hai (nút `+`). Xóa nhiều file dùng `Remove-Item a, b` (lệnh `del a b c` lỗi). Gọi HTTP dùng `curl.exe`, không dùng `curl`.

## 3. Cấu trúc thư mục

```
server.js            khởi động, session, flash, req.callProc, tự nạp routes/*.js
lib/config.js        đọc .env một chỗ duy nhất
lib/db.js            callProc, queryAs, getPool, sql
lib/errors.js        HttpError, map lỗi SQL -> HTTP, trang lỗi
lib/auth.js          ROLES, requireLogin, requireRole, startSession, destroySession
lib/nav.js           menu theo role (MENUS), trang đích của "/" (HOMES)
routes/*.js          mỗi file một router, server tự nạp
views/               EJS; views/partials/header.ejs, footer.ejs dùng chung
public/css/style.css CSS chung; mẫu thành phần ở /dev/ui
uploads/             file người dùng tải lên (không commit)
```

Quy tắc sở hữu:

| Đường dẫn | Ai sửa |
|---|---|
| `lib/*`, `server.js` | Chỉ P1. Cần đổi gì thì báo P1 |
| `lib/nav.js` (thêm trang vào menu, đặt `HOMES`) | Chỉ P1 |
| `public/css/style.css` | Sửa qua PR, P1 duyệt. Thành phần đã có thì chép class, không viết CSS mới |
| `routes/<module>.js`, `views/<module>/*` | Người phụ trách module đó |

`routes/*.js` tự nạp theo thứ tự tên file. File export một router thì được nạp, export `null` thì bỏ qua. Không cần sửa `server.js` để thêm route.

## 4. Gọi database

Mọi truy cập DB đi qua `lib/db.js`. Mỗi role có pool riêng (đăng nhập SQL riêng), nên quyền ở tầng SQL do GRANT quyết định, không phải do code web.

### Gọi procedure

Trong route, dùng `req.callProc` (role và UserId lấy từ session, không ai truyền tay được):

```js
const r = await req.callProc('lab.sp_GetReferenceData');
// r.recordsets[0] = formats, [1] = serviceTypes, [2] = stages
```

Chữ ký đầy đủ (dùng khi chưa có session, ví dụ đăng nhập):

```js
callProc(role, userId, 'schema.sp_Name', params, outputs)
// trả { recordset, recordsets, output, returnValue }
```

| Mục | Quy tắc |
|---|---|
| `role` | `customer`, `labowner`, `expert`, `delivery`, `admin`, `auth`, `system`; không phân biệt hoa thường (`LabOwner` cũng được) |
| `params` | Object `{ Ten: giaTri }`, tên có hoặc không có `@` |
| Kiểu tự đoán | số nguyên Int (lớn hơn 2147483647 thì BigInt), số thực Float, boolean Bit, `Date` DateTime2, `Buffer` VarBinary, chuỗi NVarChar(MAX) |
| Mảng, object | Tự `JSON.stringify` (dùng cho `@ItemsJson`, `@SourcesJson`...) |
| `null` | Gửi NULL. `undefined` thì bỏ qua tham số |
| Kiểu chỉ định | `{ type: sql.Int, value: 5 }` |
| `outputs` | `{ NewOrderId: sql.Int }`, kết quả ở `r.output.NewOrderId` |
| Tên procedure | Bắt buộc dạng `schema.ten` |

Lấy `sql` từ `require('../lib/db')`.

Mỗi lần gọi chạy một batch: đặt `UserId` vào session context (cho RLS), chạy procedure, reset `UserId` về NULL (kể cả khi lỗi, lỗi gốc được ném lại nguyên mã). Deadlock (1205) tự thử lại tối đa 3 lần.

### SELECT trực tiếp (quyết định D1)

Chỉ cho bảng đã GRANT SELECT và có RLS:

```js
const u = req.session.user;
const r = await queryAs(u.role, u.id, 'SELECT COUNT(*) AS Total FROM arc.Notifications WHERE ...');
```

Chỉ dùng cho SELECT. Ghi dữ liệu luôn qua procedure. Tham số trong câu SQL viết `@Ten` và truyền qua tham số thứ tư `{ Ten: giaTri }`. Không nối chuỗi vào câu SQL.

### Quy tắc cứng

1. `UserId` và `role` luôn lấy từ `req.session.user`. Không bao giờ lấy từ `req.body`, `req.query` hay URL. Tham số procedure kiểu `@CustomerId` cũng truyền `req.session.user.id`.
2. Dữ liệu người dùng in ra view bằng `<%= %>` (tự escape). `<%- %>` chỉ dùng cho `include`.
3. Mật khẩu, API key, `.env` không vào code, không vào Git.
4. Không bao giờ truyền `@CallerAuthorized` cho `ord.sp_UpdateOrderStage` và `dlv.sp_UpdateDeliveryStatus`. Đây là tham số nội bộ để procedure tự kiểm quyền.
5. Không `INSERT`, `UPDATE`, `DELETE` trực tiếp bảng. Ghi dữ liệu chỉ qua procedure (nhiều bảng bị DENY DELETE và có RLS).

## 5. Lỗi và mã trạng thái

Express 5 tự chuyển lỗi của handler `async` tới error handler. Không cần `try/catch` bao ngoài. Chỉ `catch` khi muốn xử lý riêng một mã lỗi, ví dụ lấy mã bằng `e.number`.

Ném lỗi chủ động:

```js
const { HttpError } = require('../lib/errors');
throw new HttpError(404, 'Không tìm thấy đơn hàng.');
```

| Lỗi từ SQL | HTTP |
|---|---|
| 50x01 (x bất kỳ, tính theo 2 chữ số cuối) | 404 |
| 50x02, 50x04, 50x06 | 409 |
| 50x03 (quyết định D2) | 403 |
| 50x05 | 400 |
| Mã 50000-50999 khác | 400, thông báo lấy từ SQL |
| 229, 230, 262, 33504 | 403 |
| 1205 | 503 |
| 2601, 2627 | 409 |
| 547, 515, 245, 8114, 8115, 8152 | 400 |
| Lỗi kết nối (`ELOGIN`, `ESOCKET`, `ETIMEOUT`...) | 503 |
| Còn lại | 500 (thông báo chung, chi tiết chỉ in ở terminal; `development` mới hiện stack trên trang) |

Đường `/api/*`, request `xhr` hoặc client ưu tiên JSON nhận `{ "error": "..." }`. Còn lại nhận trang `views/error.ejs`.

## 6. Đăng nhập, phân quyền, giao diện

### Session và role

`req.session.user = { id, name, roles[], role }`. Người có nhiều role chọn một role khi đăng nhập và dùng role đó cả phiên. Chưa có chức năng đổi role giữa phiên (muốn đổi: đăng xuất, đăng nhập lại).

| Hàm (`lib/auth.js`) | Dùng |
|---|---|
| `requireLogin` | Chưa đăng nhập thì chuyển `/login` kèm cảnh báo, sau khi đăng nhập quay lại đúng trang cũ |
| `requireRole('Customer', ...)` | Sai role thì lỗi 403 |
| Các role hợp lệ | `Customer`, `LabOwner`, `Expert`, `Delivery`, `Admin` |

### Mẫu route (chép rồi đổi tên)

`routes/labs.js`:

```js
'use strict';
const router = require('express').Router();
const { requireRole } = require('../lib/auth');

router.get('/labs', requireRole('Customer'), async (req, res) => {
  const r = await req.callProc('lab.sp_GetReferenceData');
  res.render('labs/index', { title: 'Tìm lab', formats: r.recordsets[0] });
});

module.exports = router;
```

`views/labs/index.ejs`:

```html
<%- include('../partials/header') %>
<h1>Tìm lab</h1>
<div class="grid">
  <% formats.forEach(function (f) { %><div class="card"><%= JSON.stringify(f) %></div><% }) %>
</div>
<%- include('../partials/footer') %>
```

### Thông báo (flash)

| Cách | Khi nào |
|---|---|
| `req.flash('success', 'Đã lưu.'); res.redirect('/orders');` | Sau POST rồi chuyển trang |
| `res.locals.flash.push({ type: 'danger', msg: '...' }); res.render(...)` | Hiện lỗi ngay trên trang đang render, không chuyển trang |

`type`: `success`, `info`, `warning`, `danger`.

### View và CSS

| Mục | Quy tắc |
|---|---|
| Đầu và cuối view | `include('../partials/header')` và `include('../partials/footer')` (đường dẫn tương đối theo vị trí view) |
| Tiêu đề tab | Truyền `title` khi `res.render` |
| CSS riêng cho một trang | Tạo `public/css/<tên>.css`, truyền `styles: ['<tên>']` khi render |
| Biến có sẵn trong mọi view | `currentUser`, `menu`, `currentPath`, `flash`, `isDev` |
| Thành phần dựng sẵn | `btn` (`btn-outline`, `btn-danger`, `btn-sm`), `badge` (`-success`, `-warning`, `-danger`), `alert-*`, `card`, `card-link`, `grid`, `form`, `table` (bọc `table-wrap`, cột số dùng `num`), `pagination`, `empty`. Xem mẫu thật ở `/dev/ui` |

### Menu theo role (`lib/nav.js`)

Menu đã khai báo trước các URL dưới đây. Trang nào chưa có route thì bấm ra 404 (bình thường). Người làm module chỉ cần tạo đúng URL trong cột `href`.

| Role | Menu (nhãn: URL) |
|---|---|
| Customer | Tìm lab: `/labs`; Đơn của tôi: `/orders`; Thông báo: `/notifications`; Kho ảnh: `/archive`; Gợi ý: `/recommend`; Trợ lý AI: `/chat`; Chợ: `/market`; Sự kiện: `/events` |
| LabOwner | Lab của tôi: `/owner/labs`; Đơn hàng: `/owner/orders`; Đánh giá: `/owner/reviews`; Doanh thu: `/owner/revenue`; Trợ lý AI: `/chat` |
| Expert | Trợ lý AI: `/chat` |
| Delivery | Giao nhận: `/delivery` |
| Admin | Tổng quan: `/admin`; Lab: `/admin/labs`; Người dùng: `/admin/users`; Khiếu nại: `/admin/complaints` |

`/` chuyển người dùng tới trang đích theo role nếu `HOMES[role]` có giá trị, không thì hiện trang chào. P1 đặt `HOMES` khi trang đã chạy.

### Upload (quyết định D3)

File tải lên lưu ở `web/uploads/` (thư viện `multer` đã cài, đường dẫn lấy từ `config.uploadDir`). Thư mục này nằm trong `.gitignore`, không commit.

## 7. Phân công màn hình

Phạm vi: kế hoạch URL P1-P5 + 4 trang mỏng (`/delivery`, `/admin/complaints`, `/market`, `/events`) để phủ đủ 16 procedure ★ (docs/Requirements.md mục E.6). Phần còn lại của Marketplace, Community, Admin moderation làm sau nếu còn thời gian.

Tham số, result set, mã lỗi chi tiết: `docs/Contracts.md` và `database/07_procedures/*.sql`. Không đoán tên tham số, mở file procedure ra đọc.

Role viết tắt: C = Customer, L = LabOwner, E = Expert, D = Delivery, A = Admin.

| URL | Role | Người | Procedure / view | Lưu ý |
|---|---|---|---|---|
| `/register`, `/login`, `/logout` | tất cả | P1 | `iam.sp_RegisterUser`, `iam.sp_GetLoginInfo` | Xong. Đăng ký chỉ gán role Customer |
| `/chat` | C, E, L | P1 | `ai.sp_SearchKnowledge`, `ai.sp_LogChatMessage` | Delivery không dùng. Không gửi thông tin cá nhân hay đơn hàng cho Gemini |
| `/labs` | C, E, L | P2 | `lab.sp_SearchLabs`, `lab.sp_GetReferenceData` | |
| `/labs/:id` | C, E, L | P2 | `lab.sp_GetLabDetail` | |
| `/orders/new` | C | P2 | `lab.sp_GetReferenceData`, `ord.sp_CreateOrder` | `@ItemsJson` = mảng `{labServiceId, filmStockId, quantity, note}`, truyền mảng JS, `callProc` tự stringify |
| `/orders/:id/pay` | C | P2 | `ord.sp_ProcessPayment` | |
| `/account/addresses` | C | P2 | `iam.sp_GetMyAddresses`, `iam.sp_SaveAddress` | |
| `/orders` | C | P3 | `ord.sp_GetMyOrders` (`@AsRole='Customer'`) | Có `TotalRows` để phân trang |
| `/orders/:id` | C | P3 | `ord.sp_GetOrderDetail`, `ord.sp_CancelOrder` | Nút hủy đặt ở trang này. Detail trả 5 result set |
| `/orders/:id/review` | C | P3 | `ord.sp_AddReview` | |
| `/orders/:id/complaint` | C | P3 | `ord.sp_FileComplaint` | |
| `/notifications` | C, D, E, L | P3 | SELECT `arc.Notifications` (RLS), `arc.sp_MarkNotificationRead` | |
| `/archive` | C | P3 | SELECT `arc.vw_CustomerArchive`, `arc.sp_SaveAlbum`, `arc.sp_SetAlbumPhoto` | |
| `/owner/labs` | L | P4 | `lab.sp_GetMyLabs` | |
| `/owner/labs/:id/edit` | L | P4 | `lab.sp_SaveLabProfile` | |
| `/owner/labs/:id/services` | L | P4 | `lab.sp_SaveLabService` | |
| `/owner/orders` | L | P4 | `ord.sp_GetMyOrders` (`@AsRole='LabOwner'`), SELECT `ord.vw_OrdersInProgress` | |
| `/owner/orders/:id` | L | P4 | `ord.sp_GetOrderDetail`, `ord.sp_UpdateOrderStage`, `arc.sp_UploadScan` | Không truyền `@CallerAuthorized` |
| `/owner/reviews` | L | P4 | SELECT `ord.vw_LabReviews`, `ord.sp_ReplyReview` | |
| `/owner/revenue` | L | P4 | SELECT `ord.vw_LabRevenue` | |
| `/admin` | A | P5 | SELECT `audit.vw_AdminDashboard`, `audit.vw_RecentChanges` | |
| `/admin/labs` | A | P5 | `lab.sp_ListLabsForApproval`, `lab.sp_ApproveLab` | |
| `/admin/users` | A | P5 | `iam.sp_ListUsers`, `iam.sp_SetUserStatus`, `iam.sp_AssignRole` | Danh sách không trả PasswordHash, Phone |
| `/recommend` | C | P5 | `ai.sp_GetLabRecommendations`, `ai.sp_RecordRecommendationAction` | `sp_GetLabRecommendations` không trả `RecLogId`. Muốn ghi hành động phải SELECT `ai.RecommendationLogs` (RLS tự lọc theo user) lấy `RecLogId` mới nhất |
| `/recommend/preferences` | C | P5 | `ai.sp_SaveUserPreferences`, SELECT `ai.UserPreferences` | |
| `/delivery` | D | (chưa phân) | SELECT `dlv.vw_DeliveryBoard`, `dlv.sp_UpdateDeliveryStatus` | Flow 2. Không truyền `@CallerAuthorized` |
| `/admin/complaints` | A | (chưa phân) | SELECT `ord.vw_OpenComplaints`, `ord.sp_ResolveComplaint` | |
| `/market` | C | (chưa phân) | `mkt.sp_SearchListings`, `mkt.sp_CreateListing`, `mkt.sp_PlaceMarketOrder` | Flow 5 |
| `/events` | C | (chưa phân) | SELECT `com.vw_UpcomingEvents`, `com.sp_RegisterEvent` | Flow 6. Community không có procedure đọc bài viết nên không làm `/articles` |

Quyền theo role (tra trước khi viết route):

| Role | EXECUTE |
|---|---|
| Delivery | Chỉ `arc.sp_MarkNotificationRead`, `dlv.sp_UpdateDeliveryStatus` + SELECT `dlv.*`, `arc.Notifications`. Không tra cứu lab, không dùng trợ lý |
| Admin | Mọi procedure trong 8 schema `ai`, `arc`, `com`, `dlv`, `iam`, `lab`, `mkt`, `ord` |
| Procedure nội bộ (mọi role đều bị DENY) | `arc.sp_CreateNotification`, `audit.sp_WriteAudit`, `dlv.sp_RequestDelivery`, `lab.sp_RecalcLabRating` |

Role Expert chỉ có `/chat` trong menu. Menu đã khai báo sẵn `/delivery`, `/admin/complaints`, `/market`, `/events` trong `lib/nav.js`; trang nào chưa có route thì bấm ra 404.

## 8. Làm việc nhóm với Git

| Quy tắc | Nội dung |
|---|---|
| Nhánh | Mỗi người một nhánh riêng cho module của mình, không commit thẳng vào nhánh chính |
| Merge | Qua Pull Request, P1 duyệt trước khi merge |
| Phạm vi PR | Chỉ sửa file của module mình. Cần sửa `lib/*`, `server.js`, `lib/nav.js` thì nhờ P1 |
| Không commit | `.env`, `node_modules/`, `uploads/` (đã có trong `.gitignore`) |

## 9. Test trước khi mở PR

Đăng nhập thử (chỉ có khi `NODE_ENV=development`, bỏ vào ngày 13): `http://localhost:3000/dev/login`, chọn tài khoản trong danh sách, không cần mật khẩu. Người có nhiều role sẽ hiện ô chọn vai trò.

| Tài khoản seed | Role |
|---|---|
| `admin@filmlab.vn` | Admin |
| `lab.saigon@filmlab.vn` | Customer + LabOwner |
| `lab.hanoi@`, `lab.cantho@`, `lab.dalat@filmlab.vn` | LabOwner |
| `expert@filmlab.vn` | Expert + Customer |
| `shipper@filmlab.vn` | Delivery |
| `an.nguyen@`, `binh.tran@`, `chi.le@`, `khach.minh@`, `khach.lan@`, `khach.nam@example.com` | Customer |

Ghi chú tài khoản:

- Không phải tài khoản seed nào cũng có mật khẩu dùng được ở `/login` (ví dụ `shipper@` và `expert@` đăng nhập được, hỏi P1 mật khẩu). Tài khoản nào không đăng nhập được thì dùng `/dev/login`.
- `chi.le@example.com` là tài khoản Google (không có mật khẩu).
- Muốn thử đăng nhập mật khẩu thật: đăng ký tài khoản mới ở `/register` (tự có role Customer).

Checklist mỗi màn hình:

| # | Kiểm tra | Mong đợi |
|---|---|---|
| 1 | Chưa đăng nhập, vào URL của màn hình | Chuyển `/login` kèm thanh vàng, đăng nhập xong quay lại đúng URL |
| 2 | Đăng nhập bằng role đúng | Trang chạy, dữ liệu hiển thị |
| 3 | Đăng nhập bằng role khác (ví dụ Delivery) | Trang 403 |
| 4 | Hai tài khoản cùng role | Mỗi người chỉ thấy dữ liệu của mình (RLS) |
| 5 | Nhập dữ liệu sai, thiếu, trùng | Hiện thông báo lỗi hợp lý, không trang trắng, không 500 |
| 6 | Mở view ở cả 2 trạng thái | Không lỗi khi danh sách rỗng (`class="empty"`) |


## 10. Dựng database (làm một lần trên máy mới)

Web không tự tạo database. Mỗi người tự dựng FilmLabDB trên SQL Server của máy mình, rồi điền `.env` cho khớp.

| Bước | Việc |
|---|---|
| 1 | Bật Mixed Mode (SSMS, chuột phải server, Properties, Security) và TCP/IP cổng 1433 (SQL Server Configuration Manager). Restart service SQL Server sau khi bật |
| 2 | Build database (từ thư mục gốc repo) |
| 3 | Tạo 7 login `fl_*` |
| 4 | Seed dashboard (có thêm đơn, lab, kho tri thức cho trợ lý AI) |
| 5 | Điền `.env` (mục 2): 7 biến `PW_*` phải đúng bằng mật khẩu đã đặt ở bước 3 |

Bước 2. Cảnh báo: mặc định `build.cmd` **dựng lại từ đầu và xóa dữ liệu hiện có** của FilmLabDB. Cú pháp `build.cmd [server] [rebuild 0|1]`:

```powershell
.\build.cmd localhost 1
```

Kết quả mong đợi: chạy hết `database\99_run_all.sql`, rồi smoke test và schema check, không in `BUILD FAILED` hay `SMOKE FAILED`.

Bước 3. Một dòng duy nhất, thay `...` bằng mật khẩu bạn tự đặt cho từng login (mật khẩu mạnh, không dùng ký tự `^ & % "`):

```powershell
sqlcmd -S localhost -E -C -f 65001 -d FilmLabDB -v PwAuth="..." PwCustomer="..." PwLabOwner="..." PwExpert="..." PwDelivery="..." PwAdmin="..." PwSystem="..." -i database\09_security\05_sql_logins.sql
```

Không đưa mật khẩu vào file nào trong repo. Không cấp `sysadmin` hay `db_owner` cho các login này (sẽ qua mặt RLS).

Bước 4. Seed dashboard (chạy lại được nhiều lần):

```powershell
sqlcmd -S localhost -E -C -f 65001 -d FilmLabDB -W -i demo\seed_dashboard\00_run_all.sql
```

Kiểm tra seed:

```powershell
sqlcmd -S localhost -E -C -f 65001 -d FilmLabDB -i demo\seed_dashboard\99_verify.sql | find /c "PASS:"
```

Kết quả mong đợi: `20`. Sau seed, kho tri thức có 24 chunk (21 đã duyệt), trợ lý AI `/chat` trả lời được nhiều chủ đề hơn.

Lưu ý:

- 5 tài khoản seed mới (`khach.minh`, `khach.lan`, `khach.nam`, `lab.cantho`, `lab.dalat`) dùng hash giả, không đăng nhập được ở `/login`. Dùng `/dev/login`, hoặc đăng ký tài khoản mới ở `/register`.
- Ai sửa procedure hay bảng thì phải sửa file `.sql` trong repo **và** chạy lên SQL Server của mình, rồi báo cả nhóm chạy lại build. Nếu không, máy các bạn sẽ lệch nhau.
- Nội dung chunk tri thức là tham khảo, chưa kiểm chứng chuyên môn.