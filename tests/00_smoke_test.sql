/* ============================================================
   File    : tests/00_smoke_test.sql
   Purpose : Kiểm tra khung đã dựng đúng (schema, role). CI chạy file này sau 99_run_all.sql.
   Thêm test mới: tạo file tests/NN_<ten>.sql, dùng THROW khi sai.
   ============================================================ */
USE FilmLabDB;
GO
SET NOCOUNT ON;

DECLARE @missing NVARCHAR(400) = N'';

-- 1) Đủ 9 schema
SELECT @missing += s.Name + N' '
FROM (VALUES (N'iam'),(N'lab'),(N'ord'),(N'dlv'),(N'arc'),(N'mkt'),(N'com'),(N'ai'),(N'audit')) AS s(Name)
WHERE SCHEMA_ID(s.Name) IS NULL;

IF @missing <> N''
BEGIN
    DECLARE @m1 NVARCHAR(2048) = N'Thiếu schema: ' + @missing;
    THROW 50001, @m1, 1;
END

-- 2) Đủ 5 role
SET @missing = N'';
SELECT @missing += r.Name + N' '
FROM (VALUES (N'role_Customer'),(N'role_LabOwner'),(N'role_Expert'),(N'role_Delivery'),(N'role_Admin')) AS r(Name)
WHERE DATABASE_PRINCIPAL_ID(r.Name) IS NULL;

IF @missing <> N''
BEGIN
    DECLARE @m2 NVARCHAR(2048) = N'Thiếu role: ' + @missing;
    THROW 50002, @m2, 1;
END

PRINT N'SMOKE TEST: PASS';
GO
