# Conventions (luật chung cả nhóm - đọc trước khi viết code)

## 1. Môi trường
| Hạng mục | Quy ước |
|---|---|
| SQL Server | 2022 (compatibility level 160), cả nhóm cùng phiên bản |
| Database / Collation | `FilmLabDB`, `Vietnamese_100_CI_AS` |
| File `.sql` | UTF-8, xuống dòng LF; chạy bằng `sqlcmd -f 65001` |
| Dựng lại DB | `build.cmd` / `build.sh` hoặc `database/99_run_all.sql` với `REBUILD=1` |

## 2. Schema = module
| Schema | Module | Ghi chú |
|---|---|---|
| `iam` | M1 Identity & Access | Gốc, không phụ thuộc ai |
| `lab` | M2 Lab & Catalog | |
| `ord` | M3 Order/Payment + M6 Review/Complaint | |
| `dlv` | M4 Delivery | |
| `arc` | M5 Digital Archive | |
| `mkt` | M7 Marketplace | |
| `com` | M8 Community | |
| `ai` | M9 AI Support | |
| `audit` | M10 System/Audit | **Không dùng `sys`** vì là schema hệ thống của SQL Server |

## 3. Đặt tên
| Đối tượng | Quy ước | Ví dụ |
|---|---|---|
| Bảng | PascalCase, số nhiều, có schema | `ord.Orders` |
| Cột | PascalCase | `OrderId`, `CreatedAt` |
| Khóa chính | `<Entity>Id`, `INT IDENTITY(1,1)` (riêng `arc.ScanFiles`: `UNIQUEIDENTIFIER`) | `OrderId` |
| Ràng buộc | `PK_` `FK_` `CK_` `UQ_` `DF_` + tên bảng/cột | `FK_Orders_FilmLabs` |
| Index | `IX_<Bang>_<Cot>` | `IX_Orders_LabId` |
| Procedure | `schema.sp_VerbNoun` | `ord.sp_CreateOrder` |
| Function | `schema.fn_Ten` | `ord.fn_CalcOrderTotal` |
| View | `schema.vw_Ten` | `ord.vw_LabRevenue` |
| Trigger | `schema.trg_Bang_Viec` | `ord.trg_Orders_LogStage` |
| Role | `role_<Ten>` | `role_LabOwner` |

## 4. Kiểu dữ liệu chuẩn
| Dữ liệu | Kiểu |
|---|---|
| Tiền VND | `DECIMAL(18,0)` |
| Thời gian | `DATETIME2(0)`, ghi bằng `SYSUTCDATETIME()` (không dùng `GETDATE()`) |
| Chuỗi | `NVARCHAR` (tiếng Việt có dấu) |
| Cờ đúng/sai | `BIT` |
| Metadata linh hoạt | `NVARCHAR(MAX)` + `CHECK (ISJSON(col) = 1)` |
| Vị trí | `geography` |
| Cột chuẩn mọi bảng chính | `CreatedAt`, `UpdatedAt`, `IsDeleted` (soft delete) |

## 5. Luật xóa và khóa ngoại
| Luật | Lý do |
|---|---|
| FK mặc định `NO ACTION`; xóa mềm bằng `IsDeleted` | Tránh lỗi *multiple cascade paths* của SQL Server |
| FK trong cùng module: tạo ngay trong `01_tables` | |
| FK giữa các module: tạo ở `02_foreign_keys` | Tạo bảng không phụ thuộc thứ tự giữa người làm |
| Giá trị trạng thái nằm trong bảng danh mục + FK | Không gõ tay `'Scanning'` ở nhiều nơi |

## 6. Quyền sở hữu dữ liệu
| Luật | Nội dung |
|---|---|
| Module chỉ **GHI** vào bảng của chính nó | Muốn ghi module khác -> gọi `sp_` của module đó |
| Module được **ĐỌC** bảng module khác | Qua view hoặc JOIN có chủ đích |
| Muốn đổi cột/bảng/chữ ký `sp_` đã công bố | Sửa `docs/Contracts.md` trong cùng Pull Request |

## 7. Re-run (chạy lại)
| Loại file | Cách chạy lại |
|---|---|
| Tables, FK, Index, Seed | Chạy lại bằng `REBUILD=1` (DB tạo mới). Không `DROP TABLE` thủ công trong file |
| Function, View, Procedure, Trigger | `CREATE OR ALTER`, chạy lại bao nhiêu lần cũng được |
| Seed `reference` | ID cố định được phép (danh mục dùng chung) |
| Seed `sample` | Không gắn cứng ID; tra bằng khóa tự nhiên (Email, tên lab...) |

## 8. Procedure và Trigger
| Hạng mục | Quy ước |
|---|---|
| Procedure | `SET NOCOUNT ON; SET XACT_ABORT ON;` -> `TRY` -> `BEGIN TRAN` -> logic -> `COMMIT` -> `CATCH` -> `ROLLBACK` -> `THROW;` |
| Báo lỗi nghiệp vụ | `THROW <mã>, N'<thông báo tiếng Việt>', 1;` |
| Dải mã lỗi | iam `50100` - lab `50200` - ord `50300` - dlv `50400` - arc `50500` - mkt `50600` - com `50700` - ai `50800` - audit `50900` |
| Trigger | Set-based (nhiều dòng), `IF TRIGGER_NESTLEVEL() > 1 RETURN;`, không `UPDATE` lại bảng đã kích hoạt nó |

## 9. Vai trò bảo mật
`role_Customer`, `role_LabOwner`, `role_Expert`, `role_Delivery`, `role_Admin`.
Làm bảo mật (`09_security`) **sau khi** các module chạy ổn; bật RLS xong phải chạy lại toàn bộ test.

## 10. Git
Xem `docs/Git-Workflow.md`.
