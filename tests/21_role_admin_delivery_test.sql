/* ============================================================
   File    : tests/21_role_admin_delivery_test.sql
   Purpose : Kiểm tra quyền EXECUTE/SELECT của role_Admin và role_Delivery:
             quyền hàng loạt (HAS_PERMS_BY_NAME) + gọi thật bọc ROLLBACK.
             Mong đợi 23 PASS (không đổi khi thêm procedure mới).
   Cách chạy (trong thư mục tests, KHÔNG dùng -b):
     sqlcmd -S localhost -E -C -f 65001 -d FilmLabDB -i 21_role_admin_delivery_test.sql | find /c "PASS:"
   ============================================================ */
USE FilmLabDB;
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
SET NOCOUNT ON;

-- Dựng 2 user không login, mỗi user đúng 1 role (không db_owner)
IF USER_ID(N'u_adm21') IS NOT NULL DROP USER u_adm21;
IF USER_ID(N'u_dlv21') IS NOT NULL DROP USER u_dlv21;
CREATE USER u_adm21 WITHOUT LOGIN;  ALTER ROLE role_Admin    ADD MEMBER u_adm21;
CREATE USER u_dlv21 WITHOUT LOGIN;  ALTER ROLE role_Delivery ADD MEMBER u_dlv21;

DECLARE @n INT, @ok INT;

-- T1: u_adm21 chỉ thuộc đúng 1 role là role_Admin (không db_owner)
SET @n  = (SELECT COUNT(*) FROM sys.database_role_members WHERE member_principal_id = USER_ID(N'u_adm21'));
SET @ok = IS_ROLEMEMBER(N'role_Admin', N'u_adm21');
IF @n = 1 AND @ok = 1 AND IS_ROLEMEMBER(N'db_owner', N'u_adm21') = 0
    PRINT N'PASS: T1 u_adm21 chỉ thuộc role_Admin, không db_owner';
ELSE PRINT N'FAIL: T1 u_adm21 chỉ thuộc role_Admin, không db_owner';

-- T2: u_dlv21 chỉ thuộc đúng 1 role là role_Delivery (không db_owner)
SET @n  = (SELECT COUNT(*) FROM sys.database_role_members WHERE member_principal_id = USER_ID(N'u_dlv21'));
SET @ok = IS_ROLEMEMBER(N'role_Delivery', N'u_dlv21');
IF @n = 1 AND @ok = 1 AND IS_ROLEMEMBER(N'db_owner', N'u_dlv21') = 0
    PRINT N'PASS: T2 u_dlv21 chỉ thuộc role_Delivery, không db_owner';
ELSE PRINT N'FAIL: T2 u_dlv21 chỉ thuộc role_Delivery, không db_owner';

-- ===== P2: role_Admin, HAS_PERMS_BY_NAME hàng loạt =====
-- Lấy danh sách procedure bằng quyền sysadmin, vì user bị DENY không thấy metadata
DECLARE @r TABLE (SchemaName SYSNAME, ProcName SYSNAME, FullName NVARCHAR(300), IsDeny BIT, P INT NULL);
INSERT @r (SchemaName, ProcName, FullName, IsDeny)
SELECT s.name, p.name, QUOTENAME(s.name) + N'.' + QUOTENAME(p.name),
       CASE WHEN s.name + N'.' + p.name IN (N'audit.sp_WriteAudit', N'arc.sp_CreateNotification',
                                            N'lab.sp_RecalcLabRating', N'dlv.sp_RequestDelivery')
            THEN 1 ELSE 0 END
FROM sys.procedures p
JOIN sys.schemas s ON s.schema_id = p.schema_id
WHERE s.name IN (N'iam', N'lab', N'ord', N'dlv', N'arc', N'mkt', N'com', N'ai', N'audit');

EXECUTE AS USER = N'u_adm21';
UPDATE @r SET P = HAS_PERMS_BY_NAME(FullName, N'OBJECT', N'EXECUTE');
REVERT;

DECLARE @sch SYSNAME, @i INT = 1, @t INT = 3, @tot INT, @list NVARCHAR(MAX);
DECLARE @s TABLE (Id INT IDENTITY(1,1), Sch SYSNAME);
INSERT @s (Sch) VALUES (N'iam'), (N'lab'), (N'ord'), (N'dlv'), (N'arc'), (N'mkt'), (N'com'), (N'ai');

-- T3-T10: mỗi schema 1 PASS. Procedure thường = 1, procedure DENY = 0
WHILE @i <= 8
BEGIN
    SET @sch  = (SELECT Sch FROM @s WHERE Id = @i);
    SET @tot  = (SELECT COUNT(*) FROM @r WHERE SchemaName = @sch);
    SET @list = (SELECT STRING_AGG(ProcName + N'=' + ISNULL(CAST(P AS NVARCHAR(5)), N'NULL'), N', ')
                 FROM @r
                 WHERE SchemaName = @sch
                   AND (P IS NULL OR P <> CASE WHEN IsDeny = 1 THEN 0 ELSE 1 END));
    IF @tot > 0 AND @list IS NULL
        PRINT N'PASS: T' + CAST(@t AS NVARCHAR(3)) + N' Admin schema ' + @sch + N' không có procedure sai quyền (' + CAST(@tot AS NVARCHAR(5)) + N' procedure)';
    ELSE
        PRINT N'FAIL: T' + CAST(@t AS NVARCHAR(3)) + N' Admin schema ' + @sch + N' sai quyền: ' + ISNULL(@list, N'schema không có procedure');
    SET @i += 1;
    SET @t += 1;
END;

-- T11: schema audit, Admin không có quyền procedure nào
SET @tot  = (SELECT COUNT(*) FROM @r WHERE SchemaName = N'audit');
SET @list = (SELECT STRING_AGG(ProcName + N'=' + ISNULL(CAST(P AS NVARCHAR(5)), N'NULL'), N', ')
             FROM @r WHERE SchemaName = N'audit' AND (P IS NULL OR P <> 0));
IF @tot > 0 AND @list IS NULL PRINT N'PASS: T11 Admin schema audit không có quyền procedure nào';
ELSE PRINT N'FAIL: T11 Admin schema audit sai quyền: ' + ISNULL(@list, N'schema không có procedure');

-- T12: đủ 4 procedure DENY tồn tại và Admin = 0 cả 4
SET @tot  = (SELECT COUNT(*) FROM @r WHERE IsDeny = 1);
SET @list = (SELECT STRING_AGG(SchemaName + N'.' + ProcName + N'=' + ISNULL(CAST(P AS NVARCHAR(5)), N'NULL'), N', ')
             FROM @r WHERE IsDeny = 1 AND (P IS NULL OR P <> 0));
IF @tot = 4 AND @list IS NULL PRINT N'PASS: T12 Admin bị DENY đủ 4 procedure nội bộ';
ELSE PRINT N'FAIL: T12 Admin DENY 4 procedure, tìm thấy ' + CAST(@tot AS NVARCHAR(5)) + N', sai quyền: ' + ISNULL(@list, N'không');

-- ===== P3: role_Delivery, HAS_PERMS_BY_NAME hàng loạt =====
DECLARE @dv INT, @cnt INT;

UPDATE @r SET P = NULL;
EXECUTE AS USER = N'u_dlv21';
UPDATE @r SET P = HAS_PERMS_BY_NAME(FullName, N'OBJECT', N'EXECUTE');
SET @dv = HAS_PERMS_BY_NAME(N'dlv.vw_DeliveryBoard', N'OBJECT', N'SELECT');
REVERT;

-- T13: đúng 2 procedure được phép, Delivery = 1 cả 2
SET @cnt  = (SELECT COUNT(*) FROM @r
             WHERE (SchemaName = N'dlv' AND ProcName = N'sp_UpdateDeliveryStatus')
                OR (SchemaName = N'arc' AND ProcName = N'sp_MarkNotificationRead'));
SET @list = (SELECT STRING_AGG(SchemaName + N'.' + ProcName + N'=' + ISNULL(CAST(P AS NVARCHAR(5)), N'NULL'), N', ')
             FROM @r
             WHERE ((SchemaName = N'dlv' AND ProcName = N'sp_UpdateDeliveryStatus')
                 OR (SchemaName = N'arc' AND ProcName = N'sp_MarkNotificationRead'))
               AND (P IS NULL OR P <> 1));
IF @cnt = 2 AND @list IS NULL PRINT N'PASS: T13 Delivery có quyền dlv.sp_UpdateDeliveryStatus và arc.sp_MarkNotificationRead';
ELSE PRINT N'FAIL: T13 Delivery 2 procedure được phép, tìm thấy ' + CAST(@cnt AS NVARCHAR(5)) + N', sai quyền: ' + ISNULL(@list, N'không');

-- T14: mọi procedure còn lại (cả schema audit và 4 procedure DENY) Delivery = 0
SET @cnt  = (SELECT COUNT(*) FROM @r
             WHERE NOT ((SchemaName = N'dlv' AND ProcName = N'sp_UpdateDeliveryStatus')
                     OR (SchemaName = N'arc' AND ProcName = N'sp_MarkNotificationRead')));
SET @list = (SELECT STRING_AGG(SchemaName + N'.' + ProcName + N'=' + ISNULL(CAST(P AS NVARCHAR(5)), N'NULL'), N', ')
             FROM @r
             WHERE NOT ((SchemaName = N'dlv' AND ProcName = N'sp_UpdateDeliveryStatus')
                     OR (SchemaName = N'arc' AND ProcName = N'sp_MarkNotificationRead'))
               AND (P IS NULL OR P <> 0));
IF @cnt > 0 AND @list IS NULL PRINT N'PASS: T14 Delivery không có quyền ở ' + CAST(@cnt AS NVARCHAR(5)) + N' procedure còn lại';
ELSE PRINT N'FAIL: T14 Delivery sai quyền: ' + ISNULL(@list, N'không có procedure để kiểm tra');

-- T15: Delivery được SELECT dlv.vw_DeliveryBoard
IF @dv = 1 PRINT N'PASS: T15 Delivery SELECT được dlv.vw_DeliveryBoard';
ELSE PRINT N'FAIL: T15 Delivery SELECT dlv.vw_DeliveryBoard, nhận ' + ISNULL(CAST(@dv AS NVARCHAR(5)), N'NULL');

-- ===== P4: gọi thật, bọc BEGIN TRAN ... ROLLBACK =====
DECLARE @adm INT, @lab INT, @usr INT, @doc INT, @err INT, @msg NVARCHAR(400), @st NVARCHAR(30), @oid INT;
DECLARE @snap0 NVARCHAR(200), @snap1 NVARCHAR(200);

SET @adm = (SELECT UserId FROM iam.Users WHERE Email = N'admin@filmlab.vn');
SET @lab = (SELECT TOP 1 LabId FROM lab.FilmLabs WHERE ApprovalStatus = N'Pending' AND IsDeleted = 0 ORDER BY LabId);
SET @usr = (SELECT UserId FROM iam.Users WHERE Email = N'khach.minh@example.com');
SET @doc = (SELECT TOP 1 KnowledgeDocId FROM ai.KnowledgeDocs WHERE IsApproved = 0 AND IsDeleted = 0 ORDER BY KnowledgeDocId);

-- Ảnh chụp dữ liệu trước khi gọi (dùng cho T23)
SET @snap0 = CONCAT((SELECT COUNT(*) FROM ord.Orders), N'|',
                    (SELECT COUNT(*) FROM ai.KnowledgeDocs), N'|',
                    (SELECT COUNT(*) FROM ai.KnowledgeDocs WHERE IsApproved = 1), N'|',
                    (SELECT COUNT(*) FROM lab.FilmLabs WHERE ApprovalStatus = N'Pending'), N'|',
                    (SELECT COUNT(*) FROM lab.LabApprovals), N'|',
                    (SELECT COUNT(*) FROM iam.Users WHERE IsActive = 1), N'|',
                    (SELECT COUNT(*) FROM audit.AuditLogs));

-- T16: Admin gọi lab.sp_ApproveLab (ghi lab, LabApprovals, trigger audit/notification)
SET @err = 0; SET @msg = NULL; SET @st = NULL;
EXECUTE AS USER = N'u_adm21';
BEGIN TRY
    BEGIN TRAN;
    EXEC lab.sp_ApproveLab @LabId = @lab, @AdminUserId = @adm, @Decision = N'Approved';
    REVERT;
    SET @st = (SELECT ApprovalStatus FROM lab.FilmLabs WHERE LabId = @lab);
    ROLLBACK;
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
    IF @@TRANCOUNT > 0 ROLLBACK;
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
IF @err = 0 AND @st = N'Approved' PRINT N'PASS: T16 Admin gọi lab.sp_ApproveLab chạy được (Pending sang Approved, đã ROLLBACK)';
ELSE PRINT N'FAIL: T16 Admin gọi lab.sp_ApproveLab, lỗi ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'trạng thái = ' + ISNULL(@st, N'NULL'));

-- T17: Admin gọi iam.sp_SetUserStatus (khóa khach.minh)
SET @err = 0; SET @msg = NULL; SET @st = NULL;
EXECUTE AS USER = N'u_adm21';
BEGIN TRY
    BEGIN TRAN;
    EXEC iam.sp_SetUserStatus @AdminUserId = @adm, @UserId = @usr, @IsActive = 0;
    REVERT;
    SET @st = (SELECT CAST(IsActive AS NVARCHAR(5)) FROM iam.Users WHERE UserId = @usr);
    ROLLBACK;
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
    IF @@TRANCOUNT > 0 ROLLBACK;
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
IF @err = 0 AND @st = N'0' PRINT N'PASS: T17 Admin gọi iam.sp_SetUserStatus chạy được (đã ROLLBACK)';
ELSE PRINT N'FAIL: T17 Admin gọi iam.sp_SetUserStatus, lỗi ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'IsActive = ' + ISNULL(@st, N'NULL'));

-- T18: Admin gọi ai.sp_ApproveKnowledgeDoc (duyệt 1 chunk chưa duyệt)
SET @err = 0; SET @msg = NULL; SET @st = NULL;
EXECUTE AS USER = N'u_adm21';
BEGIN TRY
    BEGIN TRAN;
    EXEC ai.sp_ApproveKnowledgeDoc @KnowledgeDocId = @doc, @AdminUserId = @adm, @Approve = 1;
    REVERT;
    SET @st = (SELECT CAST(IsApproved AS NVARCHAR(5)) FROM ai.KnowledgeDocs WHERE KnowledgeDocId = @doc);
    ROLLBACK;
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
    IF @@TRANCOUNT > 0 ROLLBACK;
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
IF @err = 0 AND @st = N'1' PRINT N'PASS: T18 Admin gọi ai.sp_ApproveKnowledgeDoc chạy được (đã ROLLBACK)';
ELSE PRINT N'FAIL: T18 Admin gọi ai.sp_ApproveKnowledgeDoc, lỗi ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'IsApproved = ' + ISNULL(@st, N'NULL'));

-- T19: Admin gọi iam.sp_ListUsers, trả về ít nhất 1 dòng (kết quả đổ vào bảng tạm, không in ra)
DECLARE @lu TABLE (UserId INT, Email NVARCHAR(MAX), FullName NVARCHAR(MAX), AuthProvider NVARCHAR(MAX),
                   IsActive BIT, Roles NVARCHAR(MAX), LastLoginAt DATETIME2, CreatedAt DATETIME2, TotalRows INT);
SET @err = 0; SET @msg = NULL;
EXECUTE AS USER = N'u_adm21';
BEGIN TRY
    INSERT @lu EXEC iam.sp_ListUsers @AdminUserId = @adm, @PageNo = 1, @PageSize = 100;
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
SET @cnt = (SELECT COUNT(*) FROM @lu);
IF @err = 0 AND @cnt > 0 PRINT N'PASS: T19 Admin gọi iam.sp_ListUsers chạy được (' + CAST(@cnt AS NVARCHAR(10)) + N' dòng)';
ELSE PRINT N'FAIL: T19 Admin gọi iam.sp_ListUsers, lỗi ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'0 dòng');

-- T20: Admin gọi mkt.sp_SearchListings có Keyword (nhánh Like hoặc Full-Text tùy máy)
DECLARE @sl TABLE (ListingId INT, SellerId INT, SellerName NVARCHAR(MAX), SellerRating FLOAT, CategoryId INT,
                   CategoryName NVARCHAR(MAX), ListingType NVARCHAR(MAX), Title NVARCHAR(MAX), Brand NVARCHAR(MAX),
                   Model NVARCHAR(MAX), Condition NVARCHAR(MAX), Price FLOAT, ExchangeWanted NVARCHAR(MAX),
                   Quantity INT, City NVARCHAR(MAX), PrimaryImageUrl NVARCHAR(MAX), ExpiresAt DATETIME2,
                   CreatedAt DATETIME2, TotalRows INT);
DECLARE @mode NVARCHAR(20) = CASE WHEN EXISTS (SELECT 1 FROM sys.fulltext_indexes WHERE object_id = OBJECT_ID(N'mkt.Listings'))
                                  THEN N'Full-Text' ELSE N'Like' END;
SET @err = 0; SET @msg = NULL;
EXECUTE AS USER = N'u_adm21';
BEGIN TRY
    INSERT @sl EXEC mkt.sp_SearchListings @Keyword = N'canon', @PageNo = 1, @PageSize = 20;
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
IF @err = 0 PRINT N'PASS: T20 Admin gọi mkt.sp_SearchListings chạy được (chế độ ' + @mode + N')';
ELSE PRINT N'FAIL: T20 Admin gọi mkt.sp_SearchListings (chế độ ' + @mode + N'), lỗi ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'');

-- T21: Delivery gọi ord.sp_CreateOrder, phải bị lỗi 229 (không có quyền EXECUTE)
SET @err = 0; SET @msg = NULL;
EXECUTE AS USER = N'u_dlv21';
BEGIN TRY
    EXEC ord.sp_CreateOrder @CustomerId = 1, @LabId = 1, @FulfillmentMethod = N'DropOff',
                            @ReturnMethod = N'Delivery', @ItemsJson = N'[]', @NewOrderId = @oid OUTPUT;
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
IF @err = 229 PRINT N'PASS: T21 Delivery gọi ord.sp_CreateOrder bị lỗi 229';
ELSE PRINT N'FAIL: T21 Delivery gọi ord.sp_CreateOrder, mong đợi 229, nhận ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi');

-- T22: Admin gọi trực tiếp audit.sp_WriteAudit, phải bị lỗi 229 (BR-AUD-02)
SET @err = 0; SET @msg = NULL;
EXECUTE AS USER = N'u_adm21';
BEGIN TRY
    EXEC audit.sp_WriteAudit @TableSchema = N'x', @TableName = N'x', @PrimaryKeyValue = N'1', @Action = N'INSERT';
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
IF @err = 229 PRINT N'PASS: T22 Admin gọi audit.sp_WriteAudit bị lỗi 229';
ELSE PRINT N'FAIL: T22 Admin gọi audit.sp_WriteAudit, mong đợi 229, nhận ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi');

-- T23: dữ liệu seed không đổi sau toàn bộ lệnh gọi thật
EXEC sp_set_session_context N'UserId', NULL;
SET @snap1 = CONCAT((SELECT COUNT(*) FROM ord.Orders), N'|',
                    (SELECT COUNT(*) FROM ai.KnowledgeDocs), N'|',
                    (SELECT COUNT(*) FROM ai.KnowledgeDocs WHERE IsApproved = 1), N'|',
                    (SELECT COUNT(*) FROM lab.FilmLabs WHERE ApprovalStatus = N'Pending'), N'|',
                    (SELECT COUNT(*) FROM lab.LabApprovals), N'|',
                    (SELECT COUNT(*) FROM iam.Users WHERE IsActive = 1), N'|',
                    (SELECT COUNT(*) FROM audit.AuditLogs));
IF @snap0 = @snap1 AND @@TRANCOUNT = 0 PRINT N'PASS: T23 Dữ liệu không đổi sau khi gọi thật (' + @snap1 + N')';
ELSE PRINT N'FAIL: T23 Dữ liệu đổi. Trước: ' + @snap0 + N' | Sau: ' + @snap1 + N' | TRANCOUNT = ' + CAST(@@TRANCOUNT AS NVARCHAR(5));

-- ===== DỌN =====
IF USER_ID(N'u_adm21') IS NOT NULL DROP USER u_adm21;
IF USER_ID(N'u_dlv21') IS NOT NULL DROP USER u_dlv21;
GO