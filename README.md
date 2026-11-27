# FilmLabDB

**EN:** AI-powered Platform Connecting Film Photography Enthusiasts with Film Processing Labs - database project (SQL Server 2022 + T-SQL).
**VI:** Nền tảng kết nối cộng đồng nhiếp ảnh phim và các Film Lab (MiniLab) tích hợp AI - đồ án môn Hệ quản trị cơ sở dữ liệu.

## Trạng thái
| Hạng mục | Tình trạng |
|---|---|
| Database (bảng, T-SQL nghiệp vụ, bảo mật, backup) | Xong, `tests/` 00-22 |
| Demo (`demo.sql`, dữ liệu dashboard) | Xong |
| Web demo + tích hợp AI | Đã chạy được trên localhost (đăng nhập theo role, đơn hàng, chợ, AI chat). Demo qua tunnel: `backend/README.md` mục 9b. Chưa deploy lâu dài |
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
| `backend/` | Backend Node.js (Express 5 + mssql) gọi Stored Procedure, kèm trợ lý AI (Gemini) trong `backend/chatbot/`. Cài đặt và chạy: `backend/README.md` |
| `frontend/` | Giao diện EJS (`views/`) và tài nguyên tĩnh (`public/`), do Express phục vụ |
| `build.cmd`, `build.sh` | Dựng DB + chạy smoke test và schema check bằng 1 lệnh |
| `.github/` | CI (dựng SQL Server 2022 trong Docker, chạy mọi file `tests/*.sql`) + mẫu Pull Request |

## Chạy thử (cần SQL Server 2022 + sqlcmd)
| Hệ điều hành | Lệnh |
|---|---|
| Windows (Windows auth) | `build.cmd localhost 1` |
| Linux / macOS / Docker | `SA_PASSWORD='...' ./build.sh localhost 1` |
| SSMS | Mở `database/99_run_all.sql`, bật *Query > SQLCMD Mode*, bỏ comment 2 dòng `:setvar` rồi Execute |

Tham số thứ hai là `REBUILD`: `1` xóa DB cũ và dựng lại, `0` giữ DB nếu đã có. Sau khi dựng xong, chạy các test còn lại và dữ liệu demo theo `tests/README.md` và `demo/README.md`.

## Chạy web (sau khi dựng DB)
| Cần cài | Ghi chú |
|---|---|
| Node.js >= 20 | Kiểm tra bằng `node --version` |
| Package npm | Chạy `npm install` trong thư mục `web` (không cần cài gì thêm ngoài `package.json`) |
| `cloudflared` | **Tùy chọn**, chỉ khi demo qua link công khai (`winget install --id Cloudflare.cloudflared`) |

Công nghệ web: Node.js, Express 5, EJS, `mssql`, `express-session` (store tự viết trên SQL Server), `bcrypt`, `multer`, Google Gemini (trợ lý AI).

Cấu hình `.env`, chạy `npm run dev`, bảng lỗi thường gặp và demo qua tunnel: xem `backend/README.md` (mục 2 và mục 9b).

DB đã dựng từ trước khi có session store phải bổ sung bảng `iam.Sessions`, 4 procedure `iam.sp_Session*` và 4 GRANT cho `role_Auth`: xem `backend/README.md`, mục "Session và role". DB dựng mới bằng `build.cmd` / `99_run_all.sql` thì có sẵn.

## Module (schema)
`iam` - `lab` - `ord` (gồm Review, Complaint) - `dlv` - `arc` - `mkt` - `com` - `ai` - `audit`.

| Đối tượng | Số lượng |
|---|---|
| Bảng | 41 |
| Khóa ngoại | 77 |
| Procedure | 81 (61 theo kế hoạch, trong đó 16 bắt buộc; 20 bổ sung cho web) |
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
| Web (session, phân quyền) | Session cookie `httpOnly`, lưu trong bảng `iam.Sessions`; UserId luôn lấy từ session, web gọi DB bằng 7 login `fl_*` theo role (mỗi role một pool). Chi tiết: `backend/README.md` |

## Quy ước và quy trình
Đọc `docs/Conventions.md` và `docs/Git-Workflow.md` trước khi viết code.

## Thành viên
| Họ tên | Module phụ trách |
|---|---|
| | |