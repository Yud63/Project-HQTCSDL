# demo/

Kịch bản demo trên SSMS (`demo.sql`) và web. Soạn theo thứ tự trình bày, chạy thử 2-3 lần trước buổi demo.


## demo.sql

Chạy luồng chính dưới role thật bằng `EXECUTE AS USER` (user không login), gồm 13 kiểm tra:

| Nhóm | Kiểm tra |
|---|---|
| role_Auth | Đăng ký, lấy thông tin đăng nhập, không SELECT trực tiếp `iam.Users` |
| role_Customer | Đặt đơn (ownership chaining qua `sp_RequestDelivery`, `sp_CreateNotification` đang DENY), thanh toán, review, bị chặn gọi trực tiếp procedure nội bộ |
| RLS | Customer 7 không thấy đơn của Customer 6 |
| role_LabOwner | Xác nhận đơn, đổi stage, upload scan, hoàn tất |
| role_Admin | Duyệt lab, khóa/mở user, không SELECT trực tiếp `iam.Users` |

Cách chạy (từ thư mục gốc repo): `sqlcmd -S localhost -E -C -f 65001 -d FilmLabDB -i demo\demo.sql`. Mặc định `@Commit = 0` (ROLLBACK, chạy lại thoải mái). Đặt `@Commit = 1` để giữ dữ liệu cho buổi demo.