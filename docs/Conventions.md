# Conventions (luật chung cả nhóm - đọc trước khi viết code)

> Bản v2 (Đợt 4). Thay thế bản trong khung ban đầu. Nếu `Conventions.md` và `Contracts.md` khác nhau thì theo `Contracts.md`.

## 1. Môi trường
| Hạng mục | Quy ước |
|---|---|
| SQL Server | 2022 (compatibility level 160), cả nhóm cùng phiên bản |
| Database / Collation | `FilmLabDB`, `Vietnamese_100_CI_AS` |
| File `.sql` | UTF-8, xuống dòng LF; chạy bằng `sqlcmd -f 65001` |
| Dựng lại DB | `build.cmd` / `build.sh` hoặc `database/99_run_all.sql` với `REBUILD=1` |
| Công cụ sinh tài liệu | Python 3 + `openpyxl` (chỉ cho `gen_dict.py`); xem `tools/README.md` |

## 2. Schema = module, file = unit
| Schema | Module | File ở mỗi tầng | Ghi chú |
|---|---|---|---|
| `iam` | M1 Identity & Access | `iam.sql` | Gốc, không phụ thuộc ai |
| `lab` | M2 Lab & Catalog | `lab.sql` | |
| `ord` | M3 Order, Payment, Fee | `ord.sql` | |
| `ord` | M6 Review, Complaint | `ord_feedback.sql` | **Cùng schema `ord`, file riêng**, chạy ngay sau `ord.sql`, để hai người không sửa chung file |
| `dlv` | M4 Delivery | `dlv.sql` | |
| `arc` | M5 Digital Archive | `arc.sql` | Chủ sở hữu `arc.Notifications` |
| `mkt` | M7 Marketplace | `mkt.sql` | |
| `com` | M8 Community | `com.sql` | |
| `ai` | M9 AI Support | `ai.sql` | |
| `audit` | M10 System/Audit | `audit.sql` | **Không dùng `sys`** (schema hệ thống của SQL Server) |

## 3. Đặt tên
| Đối tượng | Quy ước | Ví dụ |
|---|---|---|
| Bảng | PascalCase, số nhiều, kèm schema | `ord.Orders` |
| Cột | PascalCase | `OrderId`, `CreatedAt` |
| Khóa chính | `<Entity>Id`; ràng buộc `PK_<Bảng>` | `PK_Orders` |
| Khóa ngoại | `FK_<Bảng con>_<Bảng cha>`; trùng thì thêm `_<Cột>` (tên đã gán sẵn trong `DataDictionary.xlsx`, sheet `Relationships`) | `FK_Orders_Users`, `FK_Orders_Addresses_PickupAddressId` |
| CHECK / UNIQUE / DEFAULT | `CK_` / `UQ_` / `DF_` + `<Bảng>_<Cột>` | `CK_Orders_TotalAmount` |
| Index | `IX_` thường, `UX_` unique (kể cả filtered), `SIX_` spatial | `UX_Users_Email`, `SIX_FilmLabs_Location` |
| Procedure | `schema.sp_VerbNoun` | `ord.sp_CreateOrder` |
| Function | `schema.fn_Ten` | `ord.fn_CalcOrderTotal` |
| View | `schema.vw_Ten` | `ord.vw_LabRevenue` |
| Trigger | `schema.trg_Bang_Viec` | `ord.trg_Orders_LogStage` |
| Sequence | `schema.seq_Ten` | `ord.seq_OrderCode` |
| Role | `role_<Ten>` | `role_LabOwner` |

## 4. Kiểu dữ liệu chuẩn
| Dữ liệu | Kiểu |
|---|---|
| Khóa chính thường | `INT IDENTITY(1,1)` |
| Khóa chính bảng log tăng nhanh | `BIGINT IDENTITY` (`ai.AIChatLogs`, `ai.RecommendationLogs`, `audit.AuditLogs`) |
| Khóa chính ngoại lệ | `UNIQUEIDENTIFIER DEFAULT NEWSEQUENTIALID()` cho `arc.ScanFiles` |
| Khóa chính bảng danh mục (Lookup) | `INT` cố định, **không** IDENTITY |
| Tiền VND | `DECIMAL(18,0)` |
| Thời gian | `DATETIME2(0)`, ghi bằng `SYSUTCDATETIME()` (không dùng `GETDATE()`) |
| Chuỗi | `NVARCHAR` (tiếng Việt có dấu) |
| Cờ đúng/sai | `BIT` |
| Dữ liệu bán cấu trúc | `NVARCHAR(MAX)` + `CHECK (ISJSON(col) = 1)`, đọc bằng `OPENJSON` / `JSON_VALUE` |
| Vị trí | `geography` + spatial index |
| Cột chuẩn bảng chính | `CreatedAt`, `UpdatedAt`, `IsDeleted` (xóa mềm); bảng nào có cột nào ghi trong `DataDictionary.xlsx` |

## 5. Khóa ngoại và xóa
| Luật | Lý do |
|---|---|
| FK mặc định `NO ACTION`; xóa mềm bằng `IsDeleted` | Tránh lỗi *multiple cascade paths* của SQL Server |
| FK **trong cùng schema** tạo ngay trong `01_tables` | |
| FK **giữa các schema** tạo ở `02_foreign_keys` | Tạo bảng không phụ thuộc thứ tự giữa người làm |
| **FK ghép** để DB tự bảo đảm khớp: `ord.Reviews`/`ord.Complaints` (`OrderId`, `CustomerId`, `LabId`) -> `ord.Orders`; `mkt.MarketTransactions` (`ListingId`, `SellerId`) -> `mkt.Listings` | Đích của FK ghép cần ràng buộc UNIQUE tương ứng ở bảng cha (đã nêu trong Contracts) |
| Hai cột **không FK có chủ ý**: `ai.RecommendationLogs.ItemId`, `audit.AuditLogs.ChangedBy` | Log phải tồn tại độc lập; xem `docs/Normalization.md` DN-11 |

## 6. Trạng thái và enum
| Loại | Cách làm |
|---|---|
| Enum nhỏ, ít đổi, không kèm thuộc tính | `CHECK (col IN (...))` (danh sách ở sheet `Enums` của Data Dictionary) |
| Trạng thái có thứ tự/thuộc tính | Bảng danh mục + FK: chỉ `ord.ProcessingStages` |
| Quy tắc chuyển trạng thái | Viết bằng function `fn_Is...Transition` + trigger `..._Guard`, không rải `IF` ở nhiều nơi |
| Không bao giờ | Gõ tay chuỗi trạng thái ở nhiều procedure khác nhau: dùng đúng giá trị trong CHECK |

## 7. Quyền sở hữu dữ liệu và gọi giữa module
| Luật | Nội dung |
|---|---|
| Chỉ **GHI** bảng của module mình | Muốn ghi module khác thì gọi procedure của module đó |
| Được **ĐỌC** bảng module khác | Qua view hoặc JOIN có chủ đích |
| Thông báo | Mọi module tạo thông báo qua `arc.sp_CreateNotification` |
| Nhật ký | Mọi trigger audit ghi qua `audit.sp_WriteAudit` |
| Đổi cột/bảng/chữ ký đã công bố | Sửa `tools/schema_spec.py` / `plan_spec.py`, chạy lại script sinh tài liệu, ghi nhật ký ở `Contracts.md` mục 10, trong **cùng** Pull Request |

## 8. Chạy lại (re-run)
| Loại file | Cách chạy lại |
|---|---|
| Tables, FK, Index, Seed | Chạy lại bằng `REBUILD=1` (DB tạo mới). Không `DROP TABLE` thủ công trong file |
| Function, View, Procedure, Trigger | `CREATE OR ALTER`, chạy bao nhiêu lần cũng được |
| Seed `reference` | ID cố định được phép (danh mục dùng chung) |
| Seed `sample` | Không gắn cứng ID của bảng IDENTITY; tra bằng khóa tự nhiên (Email, tên lab...) |

## 9. Procedure và Trigger
| Hạng mục | Quy ước |
|---|---|
| Khung procedure | `templates/procedure_template.sql`: `SET NOCOUNT ON; SET XACT_ABORT ON;` -> `TRY` -> `BEGIN TRAN` -> logic -> `COMMIT` -> `CATCH` -> `ROLLBACK` -> `THROW;` |
| Người thực hiện | Procedure ghi dữ liệu nhận `@ActorUserId` (hoặc `@CustomerId`, `@SellerId`...) và gọi `EXEC sp_set_session_context @key = N'UserId', @value = @ActorUserId;` ở đầu; trigger và RLS đọc `SESSION_CONTEXT(N'UserId')` |
| Mã lỗi | `THROW <dải module + hậu tố>, N'<thông báo tiếng Việt>', 1;` Bảng mã ở `Contracts.md` mục 6 (hậu tố 01 NotFound, 02 sai trạng thái, 03 không quyền, 04 trùng, 05 dữ liệu sai, 06 hết năng lực) |
| Chữ ký | Đúng như `Contracts.md` mục 7 (16 procedure bắt buộc); web và test chỉ phụ thuộc vào đây |
| Trigger | Set-based (xử lý nhiều dòng, không dùng biến scalar từ `inserted`); `IF TRIGGER_NESTLEVEL() > 1 RETURN;`; không `UPDATE` lại bảng đã kích hoạt nó |
| Tách trách nhiệm | Quy tắc "luôn đúng" -> CHECK/UNIQUE/FK; quy tắc cần tra bảng khác -> trigger; quy trình nhiều bước -> procedure có Transaction |

## 10. Tính năng SQL Server 2022 sử dụng
| Tính năng | Dùng ở |
|---|---|
| Temporal Table | `lab.LabServices` (lịch sử đổi giá) |
| JSON | Metadata ảnh, giờ mở cửa, tags, danh sách dòng đơn (`@ItemsJson`) |
| `geography` | Tìm lab gần khách, địa điểm sự kiện |
| Row-Level Security | Multi-tenant: lab chỉ thấy đơn của lab mình; user chỉ thấy dữ liệu của mình |
| Dynamic Data Masking | Che SĐT, email với role không đủ quyền |
| Full-Text Search | Tin Marketplace, bài viết, kho tri thức. **Bọc trong** `IF SERVERPROPERTY('IsFullTextInstalled') = 1` vì image Linux của CI không có Full-Text |
| `SEQUENCE` | `ord.seq_OrderCode`, `mkt.seq_TransactionCode` |

## 11. Vai trò bảo mật
`role_Customer`, `role_LabOwner`, `role_Expert`, `role_Delivery`, `role_Admin`. Làm bảo mật (`09_security`) **sau khi** các module chạy ổn; bật RLS xong phải chạy lại toàn bộ test.

## 12. Git
Xem `docs/Git-Workflow.md`. Mỗi người chỉ sửa file của module mình (bảng sở hữu file ở `docs/Phan-cong.md` mục 8).
