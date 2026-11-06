# FilmLabDB

**EN:** AI-powered Platform Connecting Film Photography Enthusiasts with Film Processing Labs - database project (SQL Server 2022 + T-SQL).
**VI:** Nền tảng kết nối cộng đồng nhiếp ảnh phim và các Film Lab (MiniLab) tích hợp AI - đồ án môn Hệ quản trị cơ sở dữ liệu.

## Trạng thái
| Hạng mục | Tình trạng |
|---|---|
| Database (bảng, T-SQL nghiệp vụ, bảo mật, backup) | Xong, `tests/` 00-22 |
| Demo (`demo.sql`, dữ liệu dashboard) | Xong |
| Web demo + tích hợp AI | Đang chuẩn bị (xem `web/README.md`) |
| Báo cáo cuối | Làm sau (`docs/BaoCao.docx`) |

## Cấu trúc
| Thư mục / File | Nội dung |
|---|---|
| `database/` | Toàn bộ T-SQL, chạy theo số thứ tự `00_setup` đến `09_security`, `99_run_all.sql` dựng lại tất cả. `10_backup/` chạy tay, không nằm trong `99_run_all.sql` (xem `database/10_backup/README.md`) |
| `docs/` | Requirements, DataDictionary.xlsx, Contracts, Normalization, Phan-cong, Conventions, Git-Workflow, (BaoCao làm sau) |
| `diagrams/` | ERD (Mermaid, hiển thị trực tiếp trên GitHub) |
| `tools/` | Sinh ERD, Data Dictionary, Contracts từ một nguồn dữ liệu (`schema_spec.py`) |
| `templates/` | Mẫu bảng, procedure, trigger |
| `tests/` | Script kiểm thử `00` đến `22` (xem `tests/README.md`) |
| `demo/` | Kịch bản demo (`demo.sql`) và dữ liệu mẫu cho dashboard (`seed_dashboard/`), xem `demo/README.md` |
| `web/` | Web demo gọi Stored Procedure (đang chuẩn bị) |
| `build.cmd`, `build.sh` | Dựng DB + chạy smoke test và schema check bằng 1 lệnh |
| `.github/` | CI (dựng SQL Server 2022 trong Docker, chạy mọi file `tests/*.sql`) + mẫu Pull Request |

## Chạy thử (cần SQL Server 2022 + sqlcmd)
| Hệ điều hành | Lệnh |
|---|---|
| Windows (Windows auth) | `build.cmd localhost 1` |
| Linux / macOS / Docker | `SA_PASSWORD='...' ./build.sh localhost 1` |
| SSMS | Mở `database/99_run_all.sql`, bật *Query > SQLCMD Mode*, bỏ comment 2 dòng `:setvar` rồi Execute |

Tham số thứ hai là `REBUILD`: `1` xóa DB cũ và dựng lại, `0` giữ DB nếu đã có. Sau khi dựng xong, chạy các test còn lại và dữ liệu demo theo `tests/README.md` và `demo/README.md`.

## Module (schema)
`iam` - `lab` - `ord` (gồm Review, Complaint) - `dlv` - `arc` - `mkt` - `com` - `ai` - `audit`.

| Đối tượng | Số lượng |
|---|---|
| Bảng | 41 |
| Khóa ngoại | 77 |
| Procedure | 61 (16 procedure bắt buộc) |
| Function | 16 |
| Trigger | 28 |
| View | 14 |
| Role | 7 |

Chi tiết: `docs/Contracts.md`, `diagrams/ERD.md`.

## Bảo mật
| Lớp | Nội dung |
|---|---|
| Role | 7 role: `role_Customer`, `role_LabOwner`, `role_Expert`, `role_Delivery`, `role_Admin`, `role_Auth` (đăng ký/đăng nhập), `role_System` (job hệ thống) |
| GRANT/DENY | `database/09_security/02_permissions.sql` |
| Row-Level Security | `database/09_security/03_row_level_security.sql` |
| Data Masking | `database/09_security/04_data_masking.sql` |
| SQL login cho backend | `database/09_security/05_sql_logins.sql`, chạy tay, mật khẩu truyền qua `sqlcmd -v`, không lưu trong repo |

## Quy ước và quy trình
Đọc `docs/Conventions.md` và `docs/Git-Workflow.md` trước khi viết code.

## Thành viên
| Họ tên | Module phụ trách |
|---|---|
| | |