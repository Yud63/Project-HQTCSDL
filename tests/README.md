# tests/

Mỗi test là một file `NN_<ten>.sql`. Test sai thì `THROW` (để CI báo đỏ), đúng thì `PRINT N'... PASS'`. CI (`.github/workflows/db-build.yml`) chạy lần lượt mọi file `tests/*.sql` sau khi dựng DB bằng `99_run_all.sql`.

| File | Việc kiểm tra |
|---|---|
| `00_smoke_test.sql` | Đủ 9 schema, đủ 7 role (Customer, LabOwner, Expert, Delivery, Admin, Auth, System) |
| `01_schema_check.sql` | Schema dựng đúng: số bảng, FK, index, seed danh mục, bảng temporal, các ràng buộc chặn dữ liệu sai (sinh bởi tools) |
| `02_audit_notification_test.sql` | `audit.sp_WriteAudit` và `arc.sp_CreateNotification` |
| `03_register_user_test.sql` | `iam.sp_RegisterUser`: đăng ký đúng, tạo user và gán role Customer |
| `04_order_stage_test.sql` | `ord.sp_UpdateOrderStage`, `ord.fn_NextStage`, `ord.fn_IsValidTransition`: chuyển stage đúng, nhảy cóc và hủy sai bị lỗi 50302 |
| `05_create_order_test.sql` | `ord.sp_CreateOrder`: tiền, phí, năng lực lab, đơn DropOff/Pickup và các chặng giao |
| `06_payment_cancel_test.sql` | Thanh toán (`ord.sp_ProcessPayment`), hủy đơn (`ord.sp_CancelOrder`), giao nhận (`dlv.sp_AssignPartner`, `dlv.sp_UpdateDeliveryStatus`) |
| `07_review_complaint_test.sql` | Đánh giá (`ord.sp_AddReview`) và khiếu nại (`ord.sp_FileComplaint`, `ord.sp_ResolveComplaint`) |
| `08_lab_test.sql` | `lab.sp_SearchLabs` (các bộ lọc, lab bị đình chỉ không xuất hiện) và `lab.sp_ApproveLab` |
| `09_archive_test.sql` | `arc.sp_UploadScan`, `arc.sp_SetScanQuality`, thông báo, album, quyền upload |
| `10_market_test.sql` | Marketplace cơ bản: `mkt.sp_CreateListing`, `mkt.sp_PlaceMarketOrder`, function, tin Exchange và Wanted |
| `11_market_test.sql` | Marketplace mở rộng (bổ sung cho test 10): `mkt.sp_UpdateMarketTransaction`, `mkt.sp_SearchListings`, `mkt.sp_RateSeller`, `mkt.sp_ResolveDispute` |
| `12_community_test.sql` | Community: bài viết, bình luận, sự kiện (đăng ký, hàng chờ, hủy), kiểm duyệt |
| `13_ai_test.sql` | AI: `ai.sp_GetLabRecommendations`, sở thích, log chat, log gợi ý, duyệt tri thức, dọn log |
| `14_feedback_audit_test.sql` | Phản hồi và audit: `ord.sp_ReplyReview`, `ord.sp_ModerateReview`, `ord.fn_LabAvgRating`, khiếu nại |
| `15_inventory_check.sql` | Đối chiếu danh mục T-SQL thực tế (procedure, function, trigger, view, sequence) với danh mục chuẩn |
| `16_integration_test.sql` | Tích hợp xuyên module: đặt đơn, lab xử lý, thanh toán, upload scan, hoàn tất, review, khiếu nại, hoàn tiền |
| `17_security_test.sql` | GRANT/DENY, RLS, Data Masking theo role, gồm role_System (T17-T23: ma trận EXECUTE, gọi thật `mkt.sp_RunMaintenance` và `ai.sp_PurgeOldLogs` bọc ROLLBACK, `ord.sp_CreateOrder` bị lỗi 229) và BLOCK predicate 9 bảng (T24-T75: user test có GRANT ghi trực tiếp, ghi dòng người khác bị lỗi 33504; `arc.sp_UploadScan`, `lab.sp_GetMyLabs`, `mkt.sp_PlaceMarketOrder`, `mkt.sp_SendMessage`, `mkt.sp_UpdateMarketTransaction`, `mkt.sp_RunMaintenance` chạy được dưới BLOCK/role_System; `mkt.fn_SellerRating` đúng dưới RLS) (75 PASS) |
| `18_manage_test.sql` | 9 procedure quản trị Đợt 8 (lab, sự kiện, địa chỉ, user/role, phí, album), gọi thật dưới role_Customer/LabOwner/Expert |
| `19_read_test.sql` | 6 procedure đọc Đợt 8a (đăng nhập, địa chỉ, đơn, chi tiết lab) và role_Auth, gọi thật dưới role |
| `20_support_test.sql` | 4 procedure đọc Đợt 8a-2 (danh mục, lab chờ duyệt, danh sách user, tìm tri thức cho chatbot), gọi thật dưới role_Auth/Customer/LabOwner/Expert/Admin (38 PASS) |
| `21_role_admin_delivery_test.sql` | Quyền EXECUTE/SELECT của role_Admin và role_Delivery: HAS_PERMS_BY_NAME gộp theo schema, gọi thật bọc ROLLBACK, dữ liệu seed không đổi (23 PASS) |
| `22_search_dynamic_sql_test.sql` | Dynamic SQL không theo ownership chaining (lỗi 229) và `mkt.sp_SearchListings` dùng EXECUTE AS OWNER, chạy được dưới Customer/LabOwner/Expert (9 PASS khi không có Full-Text, 8 PASS + 1 INFO nếu có) |