/* ============================================================
   Purpose : Bước 4/4. Dọn bảng sao dbo.OrdersPlan (bắt buộc sau demo,
             tránh để sót bảng trong dbo).
   ============================================================ */
USE FilmLabDB;
GO
DROP TABLE IF EXISTS dbo.OrdersPlan;
GO
SELECT OBJECT_ID(N'dbo.OrdersPlan') AS Gone;
GO