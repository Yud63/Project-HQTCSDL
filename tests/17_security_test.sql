/* ============================================================
   File    : tests/17_security_test.sql
   Purpose : Kiểm tra GRANT/DENY, RLS, Data Masking cho 5 role (Đợt 7). Mong đợi 23 PASS.
   Cách chạy (trong thư mục tests, KHÔNG dùng -b):
     sqlcmd -S localhost -E -C -f 65001 -d FilmLabDB -i 17_security_test.sql | find /c "PASS:"
   ============================================================ */
USE FilmLabDB;
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
SET NOCOUNT ON;

-- Dựng 5 user không login, mỗi user một role
IF USER_ID(N'u_cus') IS NOT NULL DROP USER u_cus;
IF USER_ID(N'u_lab') IS NOT NULL DROP USER u_lab;
IF USER_ID(N'u_exp') IS NOT NULL DROP USER u_exp;
IF USER_ID(N'u_dlv') IS NOT NULL DROP USER u_dlv;
IF USER_ID(N'u_adm') IS NOT NULL DROP USER u_adm;
CREATE USER u_cus WITHOUT LOGIN;  ALTER ROLE role_Customer ADD MEMBER u_cus;
CREATE USER u_lab WITHOUT LOGIN;  ALTER ROLE role_LabOwner ADD MEMBER u_lab;
CREATE USER u_exp WITHOUT LOGIN;  ALTER ROLE role_Expert   ADD MEMBER u_exp;
CREATE USER u_dlv WITHOUT LOGIN;  ALTER ROLE role_Delivery ADD MEMBER u_dlv;
CREATE USER u_adm WITHOUT LOGIN;  ALTER ROLE role_Admin    ADD MEMBER u_adm;

DECLARE @e INT, @g INT, @b INT, @x INT, @err INT;
DECLARE @v TABLE (OrderId INT);

-- T1: Customer 6 chỉ thấy đơn của mình (BR-ORD-08)
SET @e = (SELECT COUNT(*) FROM ord.Orders WHERE CustomerId = 6);
EXECUTE AS USER = N'u_cus';
EXEC sp_set_session_context N'UserId', 6;
SET @g = (SELECT COUNT(*) FROM ord.Orders);
SET @b = (SELECT COUNT(*) FROM ord.Orders WHERE CustomerId <> 6);
REVERT;
EXEC sp_set_session_context N'UserId', NULL;
IF @e > 0 AND @g = @e AND @b = 0 PRINT N'PASS: T1 Customer 6 chỉ thấy đơn của mình';
ELSE PRINT N'FAIL: T1 Customer 6 chỉ thấy đơn của mình';

-- T2: role_Customer không có UserId thì thấy 0 đơn
EXECUTE AS USER = N'u_cus';
SET @g = (SELECT COUNT(*) FROM ord.Orders);
REVERT;
IF @g = 0 PRINT N'PASS: T2 Không có UserId thì 0 đơn';
ELSE PRINT N'FAIL: T2 Không có UserId thì 0 đơn';

-- T3: LabOwner 2 chỉ thấy đơn của lab mình
SET @e = (SELECT COUNT(*) FROM ord.Orders o JOIN lab.FilmLabs l ON l.LabId = o.LabId WHERE l.OwnerUserId = 2);
EXECUTE AS USER = N'u_lab';
EXEC sp_set_session_context N'UserId', 2;
INSERT @v (OrderId) SELECT OrderId FROM ord.Orders;
REVERT;
EXEC sp_set_session_context N'UserId', NULL;
SET @g = (SELECT COUNT(*) FROM @v);
SET @b = (SELECT COUNT(*) FROM @v v
          JOIN ord.Orders o ON o.OrderId = v.OrderId
          JOIN lab.FilmLabs l ON l.LabId = o.LabId
          WHERE l.OwnerUserId <> 2);
IF @e > 0 AND @g = @e AND @b = 0 PRINT N'PASS: T3 LabOwner 2 chỉ thấy đơn lab mình';
ELSE PRINT N'FAIL: T3 LabOwner 2 chỉ thấy đơn lab mình';

-- T4: Admin thấy tất cả đơn
SET @e = (SELECT COUNT(*) FROM ord.Orders);
EXECUTE AS USER = N'u_adm';
SET @g = (SELECT COUNT(*) FROM ord.Orders);
REVERT;
IF @e > 0 AND @g = @e PRINT N'PASS: T4 Admin thấy tất cả đơn';
ELSE PRINT N'FAIL: T4 Admin thấy tất cả đơn';

-- T5: Delivery không có quyền SELECT trực tiếp ord.Orders
EXECUTE AS USER = N'u_dlv';
SET @g = HAS_PERMS_BY_NAME(N'ord.Orders', N'OBJECT', N'SELECT');
REVERT;
IF @g = 0 PRINT N'PASS: T5 Delivery không SELECT được ord.Orders';
ELSE PRINT N'FAIL: T5 Delivery không SELECT được ord.Orders';

-- T6: Delivery 5 chỉ thấy chặng của mình (BR-DLV-11)
SET @e = (SELECT COUNT(*) FROM dlv.DeliveryRequests d
          JOIN iam.DeliveryPartners p ON p.DeliveryPartnerId = d.DeliveryPartnerId WHERE p.UserId = 5);
EXECUTE AS USER = N'u_dlv';
EXEC sp_set_session_context N'UserId', 5;
SET @g = (SELECT COUNT(*) FROM dlv.DeliveryRequests);
REVERT;
EXEC sp_set_session_context N'UserId', NULL;
IF @g = @e PRINT N'PASS: T6 Delivery 5 chỉ thấy chặng của mình';
ELSE PRINT N'FAIL: T6 Delivery 5 chỉ thấy chặng của mình';

-- T7: Customer 6 chỉ thấy thông báo của mình (BR-ARC-11)
SET @e = (SELECT COUNT(*) FROM arc.Notifications WHERE UserId = 6);
EXECUTE AS USER = N'u_cus';
EXEC sp_set_session_context N'UserId', 6;
SET @g = (SELECT COUNT(*) FROM arc.Notifications);
REVERT;
EXEC sp_set_session_context N'UserId', NULL;
IF @e > 0 AND @g = @e PRINT N'PASS: T7 Customer 6 chỉ thấy thông báo của mình';
ELSE PRINT N'FAIL: T7 Customer 6 chỉ thấy thông báo của mình';

-- T8: Customer 6 chỉ thấy UserPreferences, AIChatLogs, RecommendationLogs của mình (BR-AI-01, AI-03)
SET @e = (SELECT COUNT(*) FROM ai.UserPreferences    WHERE UserId = 6)
       + (SELECT COUNT(*) FROM ai.AIChatLogs         WHERE UserId = 6)
       + (SELECT COUNT(*) FROM ai.RecommendationLogs WHERE UserId = 6);
EXECUTE AS USER = N'u_cus';
EXEC sp_set_session_context N'UserId', 6;
SET @g = (SELECT COUNT(*) FROM ai.UserPreferences)
       + (SELECT COUNT(*) FROM ai.AIChatLogs)
       + (SELECT COUNT(*) FROM ai.RecommendationLogs);
REVERT;
EXEC sp_set_session_context N'UserId', NULL;
IF @g = @e PRINT N'PASS: T8 Customer 6 chỉ thấy dữ liệu AI của mình';
ELSE PRINT N'FAIL: T8 Customer 6 chỉ thấy dữ liệu AI của mình';

-- T9: Album chỉ của mình hoặc IsPublic (BR-ARC-09)
SET @e = (SELECT COUNT(*) FROM arc.Albums WHERE OwnerUserId = 6 OR IsPublic = 1);
EXECUTE AS USER = N'u_cus';
EXEC sp_set_session_context N'UserId', 6;
SET @g = (SELECT COUNT(*) FROM arc.Albums);
REVERT;
EXEC sp_set_session_context N'UserId', NULL;
IF @g = @e PRINT N'PASS: T9 Album chỉ của mình hoặc công khai';
ELSE PRINT N'FAIL: T9 Album chỉ của mình hoặc công khai';

-- T10: Scan chỉ của mình (BR-ARC-09)
SET @e = (SELECT COUNT(*) FROM arc.ScanFiles WHERE OwnerUserId = 6);
EXECUTE AS USER = N'u_cus';
EXEC sp_set_session_context N'UserId', 6;
SET @g = (SELECT COUNT(*) FROM arc.ScanFiles);
REVERT;
EXEC sp_set_session_context N'UserId', NULL;
IF @g = @e PRINT N'PASS: T10 Customer 6 chỉ thấy ảnh scan của mình';
ELSE PRINT N'FAIL: T10 Customer 6 chỉ thấy ảnh scan của mình';

-- T11: DELETE ord.Orders bị chặn (lỗi 229) (BR-ORD-13)
SET @err = 0;
EXECUTE AS USER = N'u_cus';
BEGIN TRY
    EXEC (N'DELETE FROM ord.Orders WHERE 1 = 0');
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER();
END CATCH;
REVERT;
IF @err = 229 PRINT N'PASS: T11 Customer không DELETE được ord.Orders';
ELSE PRINT N'FAIL: T11 Customer không DELETE được ord.Orders';

-- T12: Chỉ Admin đọc được AuditLogs (BR-AUD-05)
EXECUTE AS USER = N'u_cus';
SET @g = HAS_PERMS_BY_NAME(N'audit.AuditLogs', N'OBJECT', N'SELECT');
REVERT;
EXECUTE AS USER = N'u_adm';
SET @e = HAS_PERMS_BY_NAME(N'audit.AuditLogs', N'OBJECT', N'SELECT');
REVERT;
IF @g = 0 AND @e = 1 PRINT N'PASS: T12 Chỉ Admin đọc AuditLogs';
ELSE PRINT N'FAIL: T12 Chỉ Admin đọc AuditLogs';

-- T13: Không role nào gọi trực tiếp audit.sp_WriteAudit (BR-AUD-02)
EXECUTE AS USER = N'u_cus';
SET @g = HAS_PERMS_BY_NAME(N'audit.sp_WriteAudit', N'OBJECT', N'EXECUTE');
REVERT;
EXECUTE AS USER = N'u_adm';
SET @e = HAS_PERMS_BY_NAME(N'audit.sp_WriteAudit', N'OBJECT', N'EXECUTE');
REVERT;
IF @g = 0 AND @e = 0 PRINT N'PASS: T13 Không gọi trực tiếp audit.sp_WriteAudit';
ELSE PRINT N'FAIL: T13 Không gọi trực tiếp audit.sp_WriteAudit';

-- T14: Ma trận EXECUTE theo role
SET @x = 0;
EXECUTE AS USER = N'u_cus';
IF HAS_PERMS_BY_NAME(N'ord.sp_CreateOrder', N'OBJECT', N'EXECUTE') = 1 SET @x += 1;
REVERT;
EXECUTE AS USER = N'u_dlv';
IF HAS_PERMS_BY_NAME(N'ord.sp_CreateOrder', N'OBJECT', N'EXECUTE') = 0 SET @x += 1;
REVERT;
EXECUTE AS USER = N'u_lab';
IF HAS_PERMS_BY_NAME(N'ord.sp_UpdateOrderStage', N'OBJECT', N'EXECUTE') = 1 SET @x += 1;
REVERT;
EXECUTE AS USER = N'u_exp';
IF HAS_PERMS_BY_NAME(N'ord.sp_UpdateOrderStage', N'OBJECT', N'EXECUTE') = 0 SET @x += 1;
REVERT;
IF @x = 4 PRINT N'PASS: T14 Ma trận EXECUTE theo role đúng';
ELSE PRINT N'FAIL: T14 Ma trận EXECUTE theo role đúng';

-- T15: Data Masking: Customer không có UNMASK, Admin có
EXECUTE AS USER = N'u_cus';
SET @g = HAS_PERMS_BY_NAME(DB_NAME(), N'DATABASE', N'UNMASK');
REVERT;
EXECUTE AS USER = N'u_adm';
SET @e = HAS_PERMS_BY_NAME(DB_NAME(), N'DATABASE', N'UNMASK');
REVERT;
IF @g = 0 AND @e = 1 PRINT N'PASS: T15 UNMASK: Customer không, Admin có';
ELSE PRINT N'FAIL: T15 UNMASK: Customer không, Admin có';

-- T16: Nhật ký bất biến, ngay cả với Admin (BR-AUD-01, AUD-02, ORD-13)
EXECUTE AS USER = N'u_adm';
SET @g = HAS_PERMS_BY_NAME(N'audit.AuditLogs',   N'OBJECT', N'UPDATE')
       + HAS_PERMS_BY_NAME(N'audit.AuditLogs',   N'OBJECT', N'DELETE')
       + HAS_PERMS_BY_NAME(N'audit.AuditLogs',   N'OBJECT', N'INSERT')
       + HAS_PERMS_BY_NAME(N'ord.OrderStageLog', N'OBJECT', N'UPDATE')
       + HAS_PERMS_BY_NAME(N'ord.OrderStageLog', N'OBJECT', N'DELETE');
REVERT;
IF @g = 0 PRINT N'PASS: T16 AuditLogs và OrderStageLog bất biến';
ELSE PRINT N'FAIL: T16 AuditLogs và OrderStageLog bất biến';

-- Dọn
DROP USER u_cus;
DROP USER u_lab;
DROP USER u_exp;
DROP USER u_dlv;
DROP USER u_adm;
GO

-- ===== role_System (Việc 3E) =====
IF USER_ID(N'u_sys') IS NOT NULL DROP USER u_sys;
CREATE USER u_sys WITHOUT LOGIN;  ALTER ROLE role_System ADD MEMBER u_sys;
DECLARE @g INT, @e INT, @b INT, @x INT, @err INT, @c INT, @a INT, @oid INT, @msg NVARCHAR(4000);

-- T17: u_sys chỉ thuộc đúng 1 role (role_System), không db_owner
SET @g = (SELECT COUNT(*) FROM sys.database_role_members WHERE member_principal_id = USER_ID(N'u_sys'));
SET @e = IS_ROLEMEMBER(N'role_System', N'u_sys');
SET @b = IS_ROLEMEMBER(N'db_owner', N'u_sys');
IF @g = 1 AND @e = 1 AND @b = 0 PRINT N'PASS: T17 role_System chỉ 1 role, không db_owner';
ELSE PRINT N'FAIL: T17 role_System chỉ 1 role, không db_owner';

-- T18-T20: ma trận EXECUTE của role_System
EXECUTE AS USER = N'u_sys';
SET @g = HAS_PERMS_BY_NAME(N'mkt.sp_RunMaintenance', N'OBJECT', N'EXECUTE');
SET @e = HAS_PERMS_BY_NAME(N'audit.sp_WriteAudit',       N'OBJECT', N'EXECUTE')
       + HAS_PERMS_BY_NAME(N'arc.sp_CreateNotification', N'OBJECT', N'EXECUTE')
       + HAS_PERMS_BY_NAME(N'lab.sp_RecalcLabRating',    N'OBJECT', N'EXECUTE')
       + HAS_PERMS_BY_NAME(N'dlv.sp_RequestDelivery',    N'OBJECT', N'EXECUTE');
SET @b = HAS_PERMS_BY_NAME(N'ai.sp_PurgeOldLogs', N'OBJECT', N'EXECUTE');
REVERT;
IF @g = 1 PRINT N'PASS: T18 role_System EXECUTE được mkt.sp_RunMaintenance';
ELSE PRINT N'FAIL: T18 role_System EXECUTE được mkt.sp_RunMaintenance';
IF @e = 0 PRINT N'PASS: T19 role_System không có quyền 4 procedure nội bộ';
ELSE PRINT N'FAIL: T19 role_System không có quyền 4 procedure nội bộ';
IF @b = 1 PRINT N'PASS: T20 role_System EXECUTE được ai.sp_PurgeOldLogs';
ELSE PRINT N'FAIL: T20 role_System EXECUTE được ai.sp_PurgeOldLogs';

-- T21: gọi thật mkt.sp_RunMaintenance dưới role_System, bọc ROLLBACK, dữ liệu không đổi
SET @x = (SELECT COUNT(*) FROM mkt.Listings WHERE Status = N'Closed')
       + (SELECT COUNT(*) FROM mkt.MarketTransactions WHERE Status = N'Completed');
SET @err = 0; SET @msg = NULL;
BEGIN TRAN;
EXECUTE AS USER = N'u_sys';
BEGIN TRY
    EXEC mkt.sp_RunMaintenance @ClosedListings = @c OUTPUT, @AutoCompleted = @a OUTPUT;
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
IF @@TRANCOUNT > 0 ROLLBACK;
SET @g = (SELECT COUNT(*) FROM mkt.Listings WHERE Status = N'Closed')
       + (SELECT COUNT(*) FROM mkt.MarketTransactions WHERE Status = N'Completed');
IF @err = 0 AND @g = @x PRINT N'PASS: T21 role_System gọi mkt.sp_RunMaintenance chạy được (đã ROLLBACK, dữ liệu không đổi)';
ELSE PRINT N'FAIL: T21 role_System gọi mkt.sp_RunMaintenance, lỗi ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi') + N'; trước=' + CAST(@x AS NVARCHAR(10)) + N', sau=' + CAST(@g AS NVARCHAR(10));

-- T22: role_System gọi ord.sp_CreateOrder phải bị lỗi 229
SET @err = 0; SET @msg = NULL;
EXECUTE AS USER = N'u_sys';
BEGIN TRY
    EXEC ord.sp_CreateOrder @CustomerId = 1, @LabId = 1, @FulfillmentMethod = N'DropOff',
                            @ReturnMethod = N'Delivery', @ItemsJson = N'[]', @NewOrderId = @oid OUTPUT;
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
IF @err = 229 PRINT N'PASS: T22 role_System gọi ord.sp_CreateOrder bị lỗi 229';
ELSE PRINT N'FAIL: T22 role_System gọi ord.sp_CreateOrder, mong đợi 229, nhận ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi');

-- T23: role_System gọi thật ai.sp_PurgeOldLogs, xóa được log quá 180 ngày (không còn xóa 0 dòng do RLS), bọc ROLLBACK
SET @x = (SELECT COUNT(*) FROM ai.AIChatLogs);
SET @err = 0; SET @msg = NULL; SET @c = NULL;
BEGIN TRAN;
INSERT INTO ai.AIChatLogs (SessionId, UserId, [Role], Message, CreatedAt)
VALUES (NEWID(), 6, N'User', N'Test17 log cũ', DATEADD(DAY, -200, SYSUTCDATETIME()));
EXECUTE AS USER = N'u_sys';
BEGIN TRY
    EXEC ai.sp_PurgeOldLogs @DeletedCount = @c OUTPUT;
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
SET @e = CASE WHEN EXISTS (SELECT 1 FROM ai.AIChatLogs WHERE Message = N'Test17 log cũ') THEN 1 ELSE 0 END;
IF @@TRANCOUNT > 0 ROLLBACK;
SET @g = (SELECT COUNT(*) FROM ai.AIChatLogs);
IF @err = 0 AND @c >= 1 AND @e = 0 AND @g = @x PRINT N'PASS: T23 role_System gọi ai.sp_PurgeOldLogs xóa log cũ (đã ROLLBACK, dữ liệu không đổi)';
ELSE PRINT N'FAIL: T23 role_System gọi ai.sp_PurgeOldLogs, lỗi ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi') + N'; đã xóa=' + ISNULL(CAST(@c AS NVARCHAR(10)), N'NULL') + N', còn dòng cũ=' + CAST(@e AS NVARCHAR(10)) + N', trước=' + CAST(@x AS NVARCHAR(10)) + N', sau=' + CAST(@g AS NVARCHAR(10));


-- ===== BLOCK predicate arc.Albums (Việc 4C.1b) =====
IF USER_ID(N'u_blk') IS NOT NULL DROP USER u_blk;
CREATE USER u_blk WITHOUT LOGIN;
GRANT SELECT, INSERT, UPDATE, DELETE ON arc.Albums TO u_blk;
SET @oid = (SELECT TOP 1 UserId FROM iam.Users WHERE UserId <> 6 ORDER BY UserId);

-- T24: INSERT album của người khác (OwnerUserId <> UserId trong session) phải bị chặn 33504
SET @err = 0; SET @msg = NULL;
SET @x = (SELECT COUNT(*) FROM arc.Albums);
BEGIN TRAN;
EXEC sp_set_session_context N'UserId', 6;
EXECUTE AS USER = N'u_blk';
BEGIN TRY
    INSERT INTO arc.Albums (OwnerUserId, Title) VALUES (@oid, N'Test17 album người khác');
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
IF @@TRANCOUNT > 0 ROLLBACK;
SET @g = (SELECT COUNT(*) FROM arc.Albums);
IF @err = 33504 AND @g = @x PRINT N'PASS: T24 BLOCK AFTER INSERT chặn ghi album của người khác (33504)';
ELSE PRINT N'FAIL: T24 BLOCK AFTER INSERT, mong đợi 33504, nhận ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi') + N'; trước=' + CAST(@x AS NVARCHAR(10)) + N', sau=' + CAST(@g AS NVARCHAR(10));

-- T25: INSERT album của chính mình phải thành công (đối chứng, bọc ROLLBACK)
SET @err = 0; SET @msg = NULL;
SET @x = (SELECT COUNT(*) FROM arc.Albums);
BEGIN TRAN;
EXEC sp_set_session_context N'UserId', 6;
EXECUTE AS USER = N'u_blk';
BEGIN TRY
    INSERT INTO arc.Albums (OwnerUserId, Title) VALUES (6, N'Test17 album của mình');
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
SET @e = (SELECT COUNT(*) FROM arc.Albums WHERE Title = N'Test17 album của mình');
IF @@TRANCOUNT > 0 ROLLBACK;
SET @g = (SELECT COUNT(*) FROM arc.Albums);
IF @err = 0 AND @e = 1 AND @g = @x PRINT N'PASS: T25 ghi album của chính mình vẫn được (đã ROLLBACK, dữ liệu không đổi)';
ELSE PRINT N'FAIL: T25 ghi album của chính mình, lỗi ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi') + N'; thấy=' + CAST(@e AS NVARCHAR(10)) + N', trước=' + CAST(@x AS NVARCHAR(10)) + N', sau=' + CAST(@g AS NVARCHAR(10));

-- T26: UPDATE album công khai của người khác (đọc được nhờ FILTER) phải bị chặn 33504, title không đổi
SET @err = 0; SET @msg = NULL;
BEGIN TRAN;
INSERT INTO arc.Albums (OwnerUserId, Title, IsPublic) VALUES (@oid, N'Test17 album công khai', 1);
EXEC sp_set_session_context N'UserId', 6;
EXECUTE AS USER = N'u_blk';
BEGIN TRY
    UPDATE arc.Albums SET Title = N'Test17 bị sửa' WHERE Title = N'Test17 album công khai';
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
SET @e = (SELECT COUNT(*) FROM arc.Albums WHERE Title = N'Test17 album công khai');
IF @@TRANCOUNT > 0 ROLLBACK;
IF @err = 33504 AND @e = 1 PRINT N'PASS: T26 BLOCK BEFORE UPDATE chặn sửa album công khai của người khác (33504)';
ELSE PRINT N'FAIL: T26 BLOCK BEFORE UPDATE, mong đợi 33504, nhận ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi') + N'; title gốc còn=' + CAST(@e AS NVARCHAR(10));

-- T27: DELETE album công khai của người khác phải bị chặn 33504, dòng còn nguyên
SET @err = 0; SET @msg = NULL;
BEGIN TRAN;
INSERT INTO arc.Albums (OwnerUserId, Title, IsPublic) VALUES (@oid, N'Test17 album công khai', 1);
EXEC sp_set_session_context N'UserId', 6;
EXECUTE AS USER = N'u_blk';
BEGIN TRY
    DELETE FROM arc.Albums WHERE Title = N'Test17 album công khai';
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
SET @e = (SELECT COUNT(*) FROM arc.Albums WHERE Title = N'Test17 album công khai');
IF @@TRANCOUNT > 0 ROLLBACK;
IF @err = 33504 AND @e = 1 PRINT N'PASS: T27 BLOCK BEFORE DELETE chặn xóa album công khai của người khác (33504)';
ELSE PRINT N'FAIL: T27 BLOCK BEFORE DELETE, mong đợi 33504, nhận ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi') + N'; dòng còn=' + CAST(@e AS NVARCHAR(10));

-- T28: chủ album đổi OwnerUserId sang người khác (chuyển album đi) phải bị chặn 33504
SET @err = 0; SET @msg = NULL;
BEGIN TRAN;
INSERT INTO arc.Albums (OwnerUserId, Title) VALUES (6, N'Test17 album chuyển chủ');
EXEC sp_set_session_context N'UserId', 6;
EXECUTE AS USER = N'u_blk';
BEGIN TRY
    UPDATE arc.Albums SET OwnerUserId = @oid WHERE Title = N'Test17 album chuyển chủ';
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
SET @e = (SELECT COUNT(*) FROM arc.Albums WHERE Title = N'Test17 album chuyển chủ' AND OwnerUserId = 6);
IF @@TRANCOUNT > 0 ROLLBACK;
IF @err = 33504 AND @e = 1 PRINT N'PASS: T28 BLOCK AFTER UPDATE chặn đổi chủ album sang người khác (33504)';
ELSE PRINT N'FAIL: T28 BLOCK AFTER UPDATE, mong đợi 33504, nhận ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi') + N'; chủ vẫn là 6=' + CAST(@e AS NVARCHAR(10));

-- Dọn
EXEC sp_set_session_context N'UserId', NULL;
DROP USER u_blk;

DROP USER u_sys;