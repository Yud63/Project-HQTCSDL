# tests/

| File | Việc kiểm tra |
|---|---|
| `00_smoke_test.sql` | Đủ 9 schema, đủ 5 role |

Quy ước: mỗi test là một file `NN_<ten>.sql`, test sai thì `THROW` (để CI báo đỏ), đúng thì `PRINT N'... PASS'`.
Các test nghiệp vụ (đặt đơn, đổi trạng thái, trigger, phân quyền) thêm dần khi module xong.
| `17_security_test.sql` | GRANT/DENY, RLS, Data Masking theo role, gồm role_System (T17-T22: ma trận EXECUTE, gọi thật `mkt.sp_RunMaintenance` bọc ROLLBACK, `ord.sp_CreateOrder` bị lỗi 229) (22 PASS) |
| `18_manage_test.sql` | 9 procedure quản trị Đợt 8 (lab, event, address, user/role, fee, album) và gọi thật dưới role_Customer/LabOwner/Expert |
| `18_manage_test.sql` | 9 procedure quản trị Đợt 8 (lab, sự kiện, địa chỉ, user/role, phí, album), gọi thật dưới role_Customer/LabOwner/Expert |
| `19_read_test.sql` | 6 procedure đọc Đợt 8a (đăng nhập, địa chỉ, đơn, chi tiết lab) và role_Auth, gọi thật dưới role |
| `20_support_test.sql` | 4 procedure đọc Đợt 8a-2 (danh mục, lab chờ duyệt, danh sách user, tìm tri thức cho chatbot), gọi thật dưới role_Auth/Customer/LabOwner/Expert/Admin (38 PASS) |
| `21_role_admin_delivery_test.sql` | Quyền EXECUTE/SELECT của role_Admin và role_Delivery: HAS_PERMS_BY_NAME gộp theo schema, gọi thật bọc ROLLBACK, dữ liệu seed không đổi (23 PASS) |
| `22_search_dynamic_sql_test.sql` | Dynamic SQL không theo ownership chaining (lỗi 229) và mkt.sp_SearchListings dùng EXECUTE AS OWNER, chạy được dưới Customer/LabOwner/Expert (9 PASS khi không có Full-Text, 8 PASS + 1 INFO nếu có) |
