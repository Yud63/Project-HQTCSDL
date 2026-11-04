/* ============================================================
   File    : demo/seed_dashboard/00_run_all.sql
   Purpose : Chạy lần lượt 4 script seed dashboard (C1-C4) bằng một lệnh. Dừng ngay khi có lỗi.
   Chạy    : (từ thư mục gốc repo, vì :r dùng đường dẫn tương đối)
             sqlcmd -S localhost -E -C -f 65001 -d FilmLabDB -W -i demo\seed_dashboard\00_run_all.sql
   Re-run  : Chạy lại được (mỗi script đều idempotent).
   Kiểm tra: sqlcmd -S localhost -E -C -f 65001 -d FilmLabDB -i demo\seed_dashboard\99_verify.sql
   Lưu ý   : KHÔNG đưa vào 99_run_all.sql / build.cmd của database. Chạy SAU khi build + seed mẫu xong.
   ============================================================ */
:on error exit
PRINT N'=== C1: Customer + LabOwner + địa chỉ ===';
GO
:r demo\seed_dashboard\01_customers.sql
PRINT N'=== C2: Lab mới (Cần Thơ Approved, Đà Lạt Suspended) ===';
GO
:r demo\seed_dashboard\02_labs.sql
PRINT N'=== C3: 12 đơn nhiều stage (Cần Thơ Film Lab) ===';
GO
:r demo\seed_dashboard\03_orders.sql
PRINT N'=== C4: 24 chunk tri thức tiếng Việt ===';
GO
:r demo\seed_dashboard\04_knowledge.sql
PRINT N'=== XONG: chạy 99_verify.sql để kiểm tra (mong đợi 20 PASS) ===';
GO