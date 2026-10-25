/* ============================================================
   File    : database/99_run_all.sql
   Purpose : Dựng lại TOÀN BỘ FilmLabDB bằng một lệnh (cần SQLCMD mode)

   Cách 1 (khuyên dùng) - dòng lệnh, chạy từ thư mục database/:
       sqlcmd -S localhost -E -b -C -f 65001 -v ROOT="." REBUILD=1 -i 99_run_all.sql
     hoặc chạy build.cmd (Windows) / build.sh (Linux, macOS) ở thư mục gốc repo.

   Cách 2 - SSMS: menu Query > SQLCMD Mode, bỏ comment 2 dòng :setvar bên dưới
            (đặt ROOT = đường dẫn tuyệt đối tới thư mục database), rồi Execute.

   REBUILD=1 : xoá DB cũ và tạo lại   |   REBUILD=0 : giữ DB nếu đã có
   Thứ tự = thứ tự phụ thuộc: Schema > Tables > FK > Index > Seed > Function > View > Procedure > Trigger > Security
   Trong mỗi tầng: iam, lab, ord, ord_feedback (sau ord), dlv, arc, mkt, com, ai, audit
   ============================================================ */
-- :setvar ROOT "C:\path\to\FilmLabDB\database"
-- :setvar REBUILD "1"
:on error exit

-- 00 Setup
:r $(ROOT)/00_setup/01_create_database.sql
:r $(ROOT)/00_setup/02_create_schemas.sql

-- 01 Tables (PK, CHECK, UNIQUE, DEFAULT, FK trong schema)
:r $(ROOT)/01_tables/iam.sql
:r $(ROOT)/01_tables/lab.sql
:r $(ROOT)/01_tables/ord.sql
:r $(ROOT)/01_tables/ord_feedback.sql
:r $(ROOT)/01_tables/dlv.sql
:r $(ROOT)/01_tables/arc.sql
:r $(ROOT)/01_tables/mkt.sql
:r $(ROOT)/01_tables/com.sql
:r $(ROOT)/01_tables/ai.sql
:r $(ROOT)/01_tables/audit.sql

-- 02 Foreign keys liên module
:r $(ROOT)/02_foreign_keys/iam.sql
:r $(ROOT)/02_foreign_keys/lab.sql
:r $(ROOT)/02_foreign_keys/ord.sql
:r $(ROOT)/02_foreign_keys/ord_feedback.sql
:r $(ROOT)/02_foreign_keys/dlv.sql
:r $(ROOT)/02_foreign_keys/arc.sql
:r $(ROOT)/02_foreign_keys/mkt.sql
:r $(ROOT)/02_foreign_keys/com.sql
:r $(ROOT)/02_foreign_keys/ai.sql
:r $(ROOT)/02_foreign_keys/audit.sql

-- 03 Indexes
:r $(ROOT)/03_indexes/iam.sql
:r $(ROOT)/03_indexes/lab.sql
:r $(ROOT)/03_indexes/ord.sql
:r $(ROOT)/03_indexes/ord_feedback.sql
:r $(ROOT)/03_indexes/dlv.sql
:r $(ROOT)/03_indexes/arc.sql
:r $(ROOT)/03_indexes/mkt.sql
:r $(ROOT)/03_indexes/com.sql
:r $(ROOT)/03_indexes/ai.sql
:r $(ROOT)/03_indexes/audit.sql

-- 04a Seed - reference (danh mục cố định)
:r $(ROOT)/04_seed/reference/iam.sql
:r $(ROOT)/04_seed/reference/lab.sql
:r $(ROOT)/04_seed/reference/ord.sql
:r $(ROOT)/04_seed/reference/ord_feedback.sql
:r $(ROOT)/04_seed/reference/dlv.sql
:r $(ROOT)/04_seed/reference/arc.sql
:r $(ROOT)/04_seed/reference/mkt.sql
:r $(ROOT)/04_seed/reference/com.sql
:r $(ROOT)/04_seed/reference/ai.sql
:r $(ROOT)/04_seed/reference/audit.sql

-- 04b Seed - sample (dữ liệu mẫu)
:r $(ROOT)/04_seed/sample/iam.sql
:r $(ROOT)/04_seed/sample/lab.sql
:r $(ROOT)/04_seed/sample/ord.sql
:r $(ROOT)/04_seed/sample/ord_feedback.sql
:r $(ROOT)/04_seed/sample/dlv.sql
:r $(ROOT)/04_seed/sample/arc.sql
:r $(ROOT)/04_seed/sample/mkt.sql
:r $(ROOT)/04_seed/sample/com.sql
:r $(ROOT)/04_seed/sample/ai.sql
:r $(ROOT)/04_seed/sample/audit.sql

-- 05 Functions
:r $(ROOT)/05_functions/iam.sql
:r $(ROOT)/05_functions/lab.sql
:r $(ROOT)/05_functions/ord.sql
:r $(ROOT)/05_functions/ord_feedback.sql
:r $(ROOT)/05_functions/dlv.sql
:r $(ROOT)/05_functions/arc.sql
:r $(ROOT)/05_functions/mkt.sql
:r $(ROOT)/05_functions/com.sql
:r $(ROOT)/05_functions/ai.sql
:r $(ROOT)/05_functions/audit.sql

-- 06 Views
:r $(ROOT)/06_views/iam.sql
:r $(ROOT)/06_views/lab.sql
:r $(ROOT)/06_views/ord.sql
:r $(ROOT)/06_views/ord_feedback.sql
:r $(ROOT)/06_views/dlv.sql
:r $(ROOT)/06_views/arc.sql
:r $(ROOT)/06_views/mkt.sql
:r $(ROOT)/06_views/com.sql
:r $(ROOT)/06_views/ai.sql
:r $(ROOT)/06_views/audit.sql

-- 07 Procedures
:r $(ROOT)/07_procedures/iam.sql
:r $(ROOT)/07_procedures/lab.sql
:r $(ROOT)/07_procedures/ord.sql
:r $(ROOT)/07_procedures/ord_feedback.sql
:r $(ROOT)/07_procedures/dlv.sql
:r $(ROOT)/07_procedures/arc.sql
:r $(ROOT)/07_procedures/mkt.sql
:r $(ROOT)/07_procedures/com.sql
:r $(ROOT)/07_procedures/ai.sql
:r $(ROOT)/07_procedures/audit.sql

-- 08 Triggers
:r $(ROOT)/08_triggers/iam.sql
:r $(ROOT)/08_triggers/lab.sql
:r $(ROOT)/08_triggers/ord.sql
:r $(ROOT)/08_triggers/ord_feedback.sql
:r $(ROOT)/08_triggers/dlv.sql
:r $(ROOT)/08_triggers/arc.sql
:r $(ROOT)/08_triggers/mkt.sql
:r $(ROOT)/08_triggers/com.sql
:r $(ROOT)/08_triggers/ai.sql
:r $(ROOT)/08_triggers/audit.sql

-- 09 Security
:r $(ROOT)/09_security/01_roles.sql
:r $(ROOT)/09_security/02_permissions.sql
:r $(ROOT)/09_security/03_row_level_security.sql
:r $(ROOT)/09_security/04_data_masking.sql

-- 10_backup: chạy tay, không nằm trong run_all

PRINT N'=== FilmLabDB build xong ===';
GO
