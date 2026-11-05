# demo/

Kịch bản demo trên SSMS (`demo.sql`) và web, cùng dữ liệu mẫu cho dashboard (`seed_dashboard/`). Soạn theo thứ tự trình bày, chạy thử 2-3 lần trước buổi demo.

| File / thư mục | Việc |
|---|---|
| `demo.sql` | Luồng chính dưới role thật, 13 kiểm tra |
| `seed_dashboard/` | Dữ liệu mẫu cho dashboard: khách, lab, đơn nhiều stage, tri thức cho chatbot |


## demo.sql

Chạy luồng chính dưới role thật bằng `EXECUTE AS USER` (user không login), gồm 13 kiểm tra:

| Nhóm | Kiểm tra |
|---|---|
| role_Auth | Đăng ký, lấy thông tin đăng nhập, không SELECT trực tiếp `iam.Users` |
| role_Customer | Đặt đơn (ownership chaining qua `sp_RequestDelivery`, `sp_CreateNotification` đang DENY), thanh toán, review, bị chặn gọi trực tiếp procedure nội bộ |
| RLS | Customer 7 không thấy đơn của Customer 6 |
| role_LabOwner | Xác nhận đơn, đổi stage, upload scan, hoàn tất |
| role_Admin | Duyệt lab, khóa/mở user, không SELECT trực tiếp `iam.Users` |

Lưu ý: role_System (login `fl_system`) là job bảo trì marketplace, chỉ EXECUTE `mkt.sp_RunMaintenance`. Phần này kiểm ở `tests/17_security_test.sql` (T17-T22), `demo.sql` không chạy.

Cách chạy (từ thư mục gốc repo, mặc định `@Commit = 0` — ROLLBACK, chạy lại thoải mái):

```
sqlcmd -S localhost -E -C -f 65001 -d FilmLabDB -i demo\demo.sql | find /c "PASS:"
```

Mong đợi: `13`. Bỏ phần `| find /c "PASS:"` để xem từng dòng PASS/FAIL. Đổi `@Commit = 1` trong file nếu muốn giữ dữ liệu demo (đơn, user demo, lab được duyệt).


## seed_dashboard/

Dữ liệu mẫu để dashboard có số liệu: thêm khách, lab, đơn ở nhiều stage và tri thức cho chatbot. Chạy **sau** khi build + seed mẫu xong. Không nằm trong `99_run_all.sql` / `build.cmd`, nên không đổi số PASS chuẩn của `tests/` (đã chạy lại test 02-20 và `demo.sql` trên DB có seed: đều đúng số PASS).

| File | Nội dung |
|---|---|
| `00_run_all.sql` | Chạy lần lượt 01 → 04, dừng khi có lỗi |
| `01_customers.sql` | 3 Customer + 2 LabOwner mới, địa chỉ cho 3 Customer |
| `02_labs.sql` | Cần Thơ Film Lab (Approved, 7 gói), Đà Lạt Retro Lab (Approved rồi Suspended, 3 gói) |
| `03_orders.sql` | 12 đơn của Cần Thơ Film Lab, đi qua procedure thật (tạo đơn, đổi stage, thanh toán, hủy) |
| `04_knowledge.sql` | 24 chunk tri thức tiếng Việt cho `ai.KnowledgeDocs` (21 đã duyệt, 3 chưa duyệt) |
| `99_verify.sql` | 20 kiểm tra PASS/FAIL |

Cách chạy (từ thư mục gốc repo, mỗi script chạy lại được):

```
sqlcmd -S localhost -E -C -f 65001 -d FilmLabDB -W -i demo\seed_dashboard\00_run_all.sql
```
```
sqlcmd -S localhost -E -C -f 65001 -d FilmLabDB -i demo\seed_dashboard\99_verify.sql | find /c "PASS:"
```

Mong đợi: `20`.

Dữ liệu sau khi seed (cộng với seed mẫu):

| Thứ | Số lượng |
|---|---|
| User | 13 (8 mẫu + 5 mới) |
| Lab | 5: 3 Approved, 1 Pending (Đà Nẵng, không đụng), 1 Suspended |
| Đơn | 18 (6 mẫu + 12 mới), có ít nhất 1 đơn ở mỗi stage trong 13 stage |
| Thanh toán | 11 Paid, 1 Refunded, 6 Unpaid |
| Tri thức | 28 chunk (24 đã duyệt, 4 chưa duyệt) |

Sửa hoặc thêm dữ liệu:

| Muốn | Cách làm |
|---|---|
| Thêm đơn | Thêm 1 dòng vào bảng kế hoạch `@plan` (và dòng gói tương ứng trong `@items`) của `03_orders.sql`, chạy lại: chỉ đơn mới được tạo. Sửa `Target` lớn hơn thì đơn cũ được đẩy tiếp |
| Đổi hoặc xóa đơn đã tạo | Không sửa được (đơn là bản ghi thật có log, thông báo, giao nhận). Dựng lại DB (`REBUILD=1`) rồi chạy `00_run_all.sql` |
| Sửa chunk tri thức | Sửa `Content` hoặc `Topic` của dòng trong `04_knowledge.sql` rồi chạy lại: script cập nhật tại chỗ theo `Title` |
| Thêm chunk | Thêm dòng vào danh sách của `04_knowledge.sql`, chạy lại |
| Đổi `Title` hoặc bỏ chunk | Chunk cũ ẩn bằng `UPDATE ai.KnowledgeDocs SET IsDeleted = 1 WHERE Title = N'<tiêu đề cũ>';` |
| Đổi trạng thái duyệt chunk | Dùng `ai.sp_ApproveKnowledgeDoc`, không đổi qua file seed |

Lưu ý:

- Nội dung chunk về nhiếp ảnh phim (nhiệt độ, thời gian, đặc điểm phim) là **tham khảo**, viết cho demo từ kiến thức chung. Cần đối chiếu datasheet của hãng (Kodak, Ilford, Fujifilm) nếu dùng cho báo cáo chính thức. Hai chunk "Đặt đơn FilmLab" mô tả đúng hành vi hiện tại của hệ thống.
- Tên, email, số điện thoại, địa chỉ trong seed là dữ liệu giả. 5 tài khoản mới dùng hash giả `SEED-ONLY-NOT-A-REAL-HASH` nên **không đăng nhập web được**.
- Lab Suspended không nhận đơn mới (lỗi 50302), dùng để demo chặn đặt đơn.
- Backup trước khi chạy test: xem `database/10_backup/`. Bản sao lưu dùng khi chạy lại test nên đặt ngoài repo (`*.bak` đã được `.gitignore` bỏ qua).