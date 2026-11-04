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

Backend không dùng Windows Authentication. Mỗi role một SQL login và một connection pool riêng. Tạo login bằng `database/09_security/05_sql_logins.sql` (mật khẩu truyền qua `sqlcmd -v`, không lưu trong repo; lưu trong file `.env` của backend và thêm `.env` vào `.gitignore`).

| Login | Database role | Dùng cho |
|---|---|---|
| `fl_auth` | role_Auth | Đăng ký, đăng nhập (chưa có UserId) |
| `fl_customer` | role_Customer | Request của khách |
| `fl_labowner` | role_LabOwner | Request của chủ lab |
| `fl_expert` | role_Expert | Request của chuyên gia (demo qua `demo.sql`) |
| `fl_delivery` | role_Delivery | Request của đối tác giao hàng (demo qua `demo.sql`) |
| `fl_admin` | role_Admin | Request của Admin |

Yêu cầu máy chủ: bật Mixed Mode và TCP/IP (port 1433). Không cấp `sysadmin` hoặc `db_owner` cho các login này vì sẽ qua mặt RLS.
