# FilmLabDB

**EN:** AI-powered Platform Connecting Film Photography Enthusiasts with Film Processing Labs - database project (SQL Server 2022 + T-SQL).
**VI:** Nền tảng kết nối cộng đồng nhiếp ảnh phim và các Film Lab (MiniLab) tích hợp AI - đồ án môn Hệ quản trị cơ sở dữ liệu.

## Cấu trúc
| Thư mục / File | Nội dung |
|---|---|
| `database/` | Toàn bộ T-SQL, chạy theo số thứ tự, `99_run_all.sql` dựng lại tất cả |
| `docs/` | Conventions, Contracts, Git-Workflow, (Requirements, DataDictionary, BaoCao) |
| `diagrams/` | ERD |
| `templates/` | Mẫu bảng, procedure, trigger |
| `tests/` | Script kiểm thử |
| `demo/` | Kịch bản demo (`demo.sql`) |
| `web/` | Web demo gọi Stored Procedure (làm sau) |
| `build.cmd`, `build.sh` | Dựng DB + chạy smoke test bằng 1 lệnh |
| `.github/` | CI (dựng SQL Server 2022 trong Docker) + mẫu Pull Request |

## Chạy thử (cần SQL Server 2022 + sqlcmd)
| Hệ điều hành | Lệnh |
|---|---|
| Windows (Windows auth) | `build.cmd localhost 1` |
| Linux / macOS / Docker | `SA_PASSWORD='...' ./build.sh localhost 1` |
| SSMS | Mở `database/99_run_all.sql`, bật *Query > SQLCMD Mode*, bỏ comment 2 dòng `:setvar` rồi Execute |

## Module (schema)
`iam` - `lab` - `ord` - `dlv` - `arc` - `mkt` - `com` - `ai` - `audit` (chi tiết: `docs/Contracts.md`).

## Quy ước và quy trình
Đọc `docs/Conventions.md` và `docs/Git-Workflow.md` trước khi viết code.

## Thành viên
| Họ tên | Module phụ trách |
|---|---|
| | |
