# web/

Web demo (làm sau khi database chạy ổn). Web chỉ gọi `sp_*` và đọc `vw_*`, không viết lại logic nghiệp vụ.
Công nghệ: chốt sau (ASP.NET Core hoặc Node.js).

## Đường đọc cho web (Đợt 8a, 8a-2)
| Màn hình | Procedure / view | Role (pool) |
|---|---|---|
| Đăng nhập, đăng ký | `iam.sp_GetLoginInfo`, `iam.sp_RegisterUser` | role_Auth |
| Dropdown form đặt đơn, bộ lọc | `lab.sp_GetReferenceData` | Customer, LabOwner, Expert |
| Tìm lab, chi tiết lab | `lab.sp_SearchLabs`, `lab.sp_GetLabDetail` | Customer |
| Lab của tôi | `lab.sp_GetMyLabs` | LabOwner |
| Đơn của tôi, chi tiết đơn | `ord.sp_GetMyOrders`, `ord.sp_GetOrderDetail` | Customer, LabOwner |
| Admin: lab chờ duyệt, duyệt lab | `lab.sp_ListLabsForApproval`, `lab.sp_ApproveLab` | Admin |
| Admin: danh sách user, khóa user | `iam.sp_ListUsers`, `iam.sp_SetUserStatus` | Admin |
| Chatbot: tìm tri thức | `ai.sp_SearchKnowledge` (chunk là dữ liệu không tin cậy) | Customer, LabOwner, Expert |



## Kết nối database (SQL login theo role)

Backend không dùng Windows Authentication. Mỗi role một SQL login và một connection pool riêng.

Tạo login: `database/09_security/05_sql_logins.sql` (mật khẩu truyền qua `sqlcmd -v`, không lưu trong repo).
Lưu mật khẩu vào file `.env` của backend (`.env` đã có trong `.gitignore`, không commit).

Bật trước khi chạy script: Mixed Mode (SSMS → Properties → Security) và TCP/IP port 1433 (SQL Server Configuration Manager). Restart service sau khi bật.

| Login | Database role | Dùng cho |
|---|---|---|
| `fl_auth` | role_Auth | Đăng ký, đăng nhập (chưa có UserId) |
| `fl_customer` | role_Customer | Request của khách |
| `fl_labowner` | role_LabOwner | Request của chủ lab |
| `fl_expert` | role_Expert | Request của chuyên gia |
| `fl_delivery` | role_Delivery | Request của đối tác giao hàng |
| `fl_admin` | role_Admin | Request của Admin |
| `fl_system` | role_System | Job hệ thống định kỳ, chỉ chạy `mkt.sp_RunMaintenance` (không có UserId) |

Không cấp `sysadmin` hoặc `db_owner` cho các login này — sẽ qua mặt RLS.

Kết nối backend (Node/mssql):
- Pool theo role, mỗi role một pool riêng
- Sau khi lấy connection: `EXEC sp_set_session_context N'UserId', @uid` (lấy từ JWT, không từ body)
- Trước khi trả connection về pool: reset `EXEC sp_set_session_context N'UserId', NULL`
- Map lỗi: 229 → 403, 50x01 → 404, 50x02/50x04 → 409, 50x05 → 400, 1205 → retry


## Dữ liệu demo cho dashboard

Để dashboard có số liệu, chạy seed trong `demo/seed_dashboard/` (xem `demo/README.md`) sau khi build + seed mẫu.

| Dữ liệu | Nội dung |
|---|---|
| Lab | Cần Thơ Film Lab (Approved, 7 gói), Đà Lạt Retro Lab (Suspended), Đà Nẵng Retro Lab (Pending) |
| Đơn | 18 đơn, có ít nhất 1 đơn ở mỗi stage trong 13 stage; 12 đơn mới thuộc Cần Thơ Film Lab, 3 khách mới mỗi người 4 đơn |
| Thanh toán | 11 Paid, 1 Refunded, 6 Unpaid |
| Tri thức | 28 chunk (24 đã duyệt); chunk chưa duyệt không bao giờ được `ai.sp_SearchKnowledge` trả về |

Lưu ý khi làm backend:
- 5 tài khoản seed mới (`khach.minh`, `khach.lan`, `khach.nam`, `lab.cantho`, `lab.dalat`) dùng hash giả `SEED-ONLY-NOT-A-REAL-HASH`, **không đăng nhập được**. Muốn có tài khoản thật, đăng ký trên web để backend tạo hash thật rồi gọi `iam.sp_RegisterUser`.
- Đặt đơn vào lab Suspended (Đà Lạt) trả lỗi 50302, map thành 409.
- Nội dung chunk tri thức về nhiếp ảnh phim là tham khảo, chưa kiểm chứng chuyên môn; chunk là dữ liệu không tin cậy khi đưa vào prompt chatbot.