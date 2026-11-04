/* ============================================================
   File    : tests/22_search_dynamic_sql_test.sql
   Purpose : Việc 2A. Xác nhận gốc lỗi 229 nghi ngờ ở mkt.sp_SearchListings:
             SQL động (sp_executesql) chạy bằng quyền người gọi, không theo ownership chaining.
             Mong đợi: 9 PASS nếu mkt.Listings CHƯA có Full-Text index, 8 PASS + 1 dòng INFO nếu có.
   Cách chạy (trong thư mục tests, KHÔNG dùng -b):
     sqlcmd -S localhost -E -C -f 65001 -d FilmLabDB -i 22_search_dynamic_sql_test.sql | find /c "PASS:"
   ============================================================ */
USE FilmLabDB;
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
SET NOCOUNT ON;

-- Dựng 3 user không login, mỗi user đúng 1 role có quyền gọi sp_SearchListings
IF USER_ID(N'u_cus22') IS NOT NULL DROP USER u_cus22;
IF USER_ID(N'u_lab22') IS NOT NULL DROP USER u_lab22;
IF USER_ID(N'u_exp22') IS NOT NULL DROP USER u_exp22;
CREATE USER u_cus22 WITHOUT LOGIN;  ALTER ROLE role_Customer ADD MEMBER u_cus22;
CREATE USER u_lab22 WITHOUT LOGIN;  ALTER ROLE role_LabOwner ADD MEMBER u_lab22;
CREATE USER u_exp22 WITHOUT LOGIN;  ALTER ROLE role_Expert   ADD MEMBER u_exp22;

DECLARE @u TABLE (Id INT IDENTITY(1,1), UserName SYSNAME);
INSERT @u (UserName) VALUES (N'u_cus22'), (N'u_lab22'), (N'u_exp22');

DECLARE @res TABLE (UserName SYSNAME, HasSel INT, ErrProbe INT, ErrStatic INT, ErrKw INT);
DECLARE @sl TABLE (ListingId INT, SellerId INT, SellerName NVARCHAR(MAX), SellerRating FLOAT, CategoryId INT,
                   CategoryName NVARCHAR(MAX), ListingType NVARCHAR(MAX), Title NVARCHAR(MAX), Brand NVARCHAR(MAX),
                   Model NVARCHAR(MAX), Condition NVARCHAR(MAX), Price FLOAT, ExchangeWanted NVARCHAR(MAX),
                   Quantity INT, City NVARCHAR(MAX), PrimaryImageUrl NVARCHAR(MAX), ExpiresAt DATETIME2,
                   CreatedAt DATETIME2, TotalRows INT);

DECLARE @i INT = 1, @un SYSNAME, @hs INT, @e1 INT, @e2 INT, @e3 INT, @c INT, @n INT, @list NVARCHAR(MAX);
DECLARE @ft BIT = CASE WHEN EXISTS (SELECT 1 FROM sys.fulltext_indexes WHERE object_id = OBJECT_ID(N'mkt.Listings'))
                       THEN 1 ELSE 0 END;

-- T1: mỗi user đúng 1 role, không db_owner
SET @n = (SELECT COUNT(*) FROM @u x
          WHERE (SELECT COUNT(*) FROM sys.database_role_members WHERE member_principal_id = USER_ID(x.UserName)) = 1
            AND IS_ROLEMEMBER(N'db_owner', x.UserName) = 0);
IF @n = 3 PRINT N'PASS: T1 3 user test mỗi user đúng 1 role, không db_owner';
ELSE PRINT N'FAIL: T1 3 user test, chỉ ' + CAST(@n AS NVARCHAR(5)) + N'/3 đạt';

-- Chạy 3 lệnh cho từng user
WHILE @i <= 3
BEGIN
    SET @un = (SELECT UserName FROM @u WHERE Id = @i);
    SET @e1 = 0; SET @e2 = 0; SET @e3 = 0; SET @c = NULL;

    EXECUTE AS USER = @un;
    SET @hs = HAS_PERMS_BY_NAME(N'mkt.Listings', N'OBJECT', N'SELECT');

    -- Probe: SQL động đọc thẳng bảng, y hệt nhánh Full-Text của procedure
    BEGIN TRY
        EXEC sp_executesql N'SELECT @c = COUNT(*) FROM mkt.Listings', N'@c INT OUTPUT', @c = @c OUTPUT;
    END TRY
    BEGIN CATCH
        SET @e1 = ERROR_NUMBER();
    END CATCH

    -- Đối chứng: procedure không Keyword (SQL tĩnh, ownership chaining)
    DELETE FROM @sl;
    BEGIN TRY
        INSERT @sl EXEC mkt.sp_SearchListings @PageNo = 1, @PageSize = 20;
    END TRY
    BEGIN CATCH
        SET @e2 = ERROR_NUMBER();
    END CATCH

    -- Có Keyword (nhánh Like, hoặc nhánh Full-Text nếu có FT index)
    DELETE FROM @sl;
    BEGIN TRY
        INSERT @sl EXEC mkt.sp_SearchListings @Keyword = N'canon', @PageNo = 1, @PageSize = 20;
    END TRY
    BEGIN CATCH
        SET @e3 = ERROR_NUMBER();
    END CATCH

    IF USER_NAME() <> N'dbo' REVERT;
    INSERT @res VALUES (@un, @hs, @e1, @e2, @e3);
    SET @i += 1;
END;

-- T2: không role nào có SELECT trực tiếp trên mkt.Listings
SET @n = (SELECT COUNT(*) FROM @res WHERE HasSel = 0);
IF @n = 3 PRINT N'PASS: T2 Customer, LabOwner, Expert đều không có SELECT trên mkt.Listings';
ELSE PRINT N'FAIL: T2 có role có SELECT trên mkt.Listings (' + CAST(3 - @n AS NVARCHAR(5)) + N'/3)';

-- T3: SQL động đọc mkt.Listings dưới 3 role đều lỗi 229 (bằng chứng gốc lỗi)
SET @n    = (SELECT COUNT(*) FROM @res WHERE ErrProbe = 229);
SET @list = (SELECT STRING_AGG(UserName + N'=' + CAST(ErrProbe AS NVARCHAR(10)), N', ') FROM @res WHERE ErrProbe <> 229);
IF @n = 3 PRINT N'PASS: T3 SQL động đọc mkt.Listings bị 229 ở cả 3 role (không theo ownership chaining)';
ELSE PRINT N'FAIL: T3 mong đợi 229 ở 3 role, lệch: ' + ISNULL(@list, N'');

-- T4: đối chứng, sp_SearchListings không Keyword chạy được dưới 3 role
SET @n    = (SELECT COUNT(*) FROM @res WHERE ErrStatic = 0);
SET @list = (SELECT STRING_AGG(UserName + N'=' + CAST(ErrStatic AS NVARCHAR(10)), N', ') FROM @res WHERE ErrStatic <> 0);
IF @n = 3 PRINT N'PASS: T4 sp_SearchListings không Keyword chạy được dưới 3 role (SQL tĩnh theo ownership chaining)';
ELSE PRINT N'FAIL: T4 sp_SearchListings không Keyword, lỗi: ' + ISNULL(@list, N'');

-- T5: có Keyword. Không có FT index: phải chạy được (nhánh Like). Có FT index: chỉ báo INFO để quan sát
IF @ft = 0
BEGIN
    SET @n    = (SELECT COUNT(*) FROM @res WHERE ErrKw = 0);
    SET @list = (SELECT STRING_AGG(UserName + N'=' + CAST(ErrKw AS NVARCHAR(10)), N', ') FROM @res WHERE ErrKw <> 0);
    IF @n = 3 PRINT N'PASS: T5 sp_SearchListings có Keyword chạy được dưới 3 role (chế độ Like)';
    ELSE PRINT N'FAIL: T5 sp_SearchListings có Keyword (chế độ Like), lỗi: ' + ISNULL(@list, N'');
END
ELSE
BEGIN
    SET @list = (SELECT STRING_AGG(UserName + N'=' + CAST(ErrKw AS NVARCHAR(10)), N', ') FROM @res);
    PRINT N'INFO: T5 mkt.Listings CÓ Full-Text index, mã lỗi nhánh Full-Text: ' + @list + N' (229 = giả thuyết đúng, 0 = giả thuyết sai)';
END;

-- T6: ai.sp_SearchKnowledge đã dùng EXECUTE AS OWNER (mẫu đã sửa sẵn trong repo)
IF EXISTS (SELECT 1 FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'ai.sp_SearchKnowledge') AND execute_as_principal_id IS NOT NULL)
    PRINT N'PASS: T6 ai.sp_SearchKnowledge dùng EXECUTE AS OWNER';
ELSE PRINT N'FAIL: T6 ai.sp_SearchKnowledge không dùng EXECUTE AS OWNER';

-- INFO: hiện trạng mkt.sp_SearchListings (không tính PASS, sẽ đổi sau khi sửa ở 2C)
IF EXISTS (SELECT 1 FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'mkt.sp_SearchListings') AND execute_as_principal_id IS NOT NULL)
    PRINT N'INFO: mkt.sp_SearchListings hiện DÙNG EXECUTE AS OWNER';
ELSE PRINT N'INFO: mkt.sp_SearchListings hiện KHÔNG dùng EXECUTE AS OWNER';
PRINT N'INFO: Full-Text index trên mkt.Listings = ' + CASE WHEN @ft = 1 THEN N'có' ELSE N'không' END;

-- ===== 2D: kiểm tra sau khi sửa mkt.sp_SearchListings =====
DECLARE @g1 INT, @g2 INT, @g3 INT, @exp INT, @rows INT, @rows2 INT, @e4 INT;

-- T7: mkt.sp_SearchListings dùng EXECUTE AS OWNER (chống lỗi quay lại)
IF EXISTS (SELECT 1 FROM sys.sql_modules WHERE object_id = OBJECT_ID(N'mkt.sp_SearchListings') AND execute_as_principal_id IS NOT NULL)
    PRINT N'PASS: T7 mkt.sp_SearchListings dùng EXECUTE AS OWNER';
ELSE PRINT N'FAIL: T7 mkt.sp_SearchListings chưa dùng EXECUTE AS OWNER';

-- T8: GRANT EXECUTE trên sp_SearchListings còn nguyên cho Customer, LabOwner, Expert (CREATE OR ALTER không làm mất quyền)
EXECUTE AS USER = N'u_cus22';  SET @g1 = HAS_PERMS_BY_NAME(N'mkt.sp_SearchListings', N'OBJECT', N'EXECUTE');  REVERT;
EXECUTE AS USER = N'u_lab22';  SET @g2 = HAS_PERMS_BY_NAME(N'mkt.sp_SearchListings', N'OBJECT', N'EXECUTE');  REVERT;
EXECUTE AS USER = N'u_exp22';  SET @g3 = HAS_PERMS_BY_NAME(N'mkt.sp_SearchListings', N'OBJECT', N'EXECUTE');  REVERT;
IF @g1 = 1 AND @g2 = 1 AND @g3 = 1 PRINT N'PASS: T8 Customer, LabOwner, Expert vẫn có EXECUTE trên mkt.sp_SearchListings';
ELSE PRINT N'FAIL: T8 EXECUTE sp_SearchListings Customer/LabOwner/Expert = ' + CAST(ISNULL(@g1, -1) AS NVARCHAR(5)) + N'/' + CAST(ISNULL(@g2, -1) AS NVARCHAR(5)) + N'/' + CAST(ISNULL(@g3, -1) AS NVARCHAR(5));

-- T9: kết quả dưới role bằng đúng số tin đang bán (vw_MarketActive đọc bằng sysadmin), có Keyword rỗng và không Keyword
SET @exp = (SELECT COUNT(*) FROM mkt.vw_MarketActive);
SET @e4 = 0; DELETE FROM @sl;
EXECUTE AS USER = N'u_cus22';
BEGIN TRY
    INSERT @sl EXEC mkt.sp_SearchListings @PageNo = 1, @PageSize = 100;
END TRY
BEGIN CATCH
    SET @e4 = ERROR_NUMBER();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
SET @rows = ISNULL((SELECT MAX(TotalRows) FROM @sl), 0);
IF @e4 = 0 AND @rows = @exp PRINT N'PASS: T9 sp_SearchListings dưới role_Customer trả đủ ' + CAST(@rows AS NVARCHAR(10)) + N' tin đang bán';
ELSE PRINT N'FAIL: T9 sp_SearchListings dưới role_Customer, lỗi ' + CAST(@e4 AS NVARCHAR(10)) + N', trả ' + CAST(@rows AS NVARCHAR(10)) + N', mong đợi ' + CAST(@exp AS NVARCHAR(10));
-- ===== DỌN =====
IF USER_ID(N'u_cus22') IS NOT NULL DROP USER u_cus22;
IF USER_ID(N'u_lab22') IS NOT NULL DROP USER u_lab22;
IF USER_ID(N'u_exp22') IS NOT NULL DROP USER u_exp22;
GO