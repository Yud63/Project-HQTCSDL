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


-- ===== BLOCK predicate 3 bảng AI (Việc 4C.2b) =====
-- Lưu ý: BEFORE UPDATE/DELETE không chạm tới được vì FILTER (cùng fn_OwnerAccess) đã ẩn dòng người khác, nên chứng minh bằng AFTER INSERT/AFTER UPDATE
GRANT SELECT, INSERT, UPDATE, DELETE ON ai.UserPreferences   TO u_blk;
GRANT SELECT, INSERT, UPDATE, DELETE ON ai.AIChatLogs        TO u_blk;
GRANT SELECT, INSERT, UPDATE, DELETE ON ai.RecommendationLogs TO u_blk;

-- T29: ai.UserPreferences INSERT dòng của người khác phải bị chặn 33504
SET @err = 0; SET @msg = NULL;
BEGIN TRAN;
DELETE FROM ai.UserPreferences WHERE UserId IN (6, @oid);
SET @x = (SELECT COUNT(*) FROM ai.UserPreferences);
EXEC sp_set_session_context N'UserId', 6;
EXECUTE AS USER = N'u_blk';
BEGIN TRY
    INSERT INTO ai.UserPreferences (UserId) VALUES (@oid);
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
SET @g = (SELECT COUNT(*) FROM ai.UserPreferences);
IF @@TRANCOUNT > 0 ROLLBACK;
IF @err = 33504 AND @g = @x PRINT N'PASS: T29 BLOCK AFTER INSERT chặn ghi ai.UserPreferences của người khác (33504)';
ELSE PRINT N'FAIL: T29 ai.UserPreferences INSERT người khác, mong đợi 33504, nhận ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi') + N'; trước=' + CAST(@x AS NVARCHAR(10)) + N', sau=' + CAST(@g AS NVARCHAR(10));

-- T30: ai.UserPreferences INSERT dòng của mình phải thành công (đối chứng, bọc ROLLBACK)
SET @err = 0; SET @msg = NULL;
BEGIN TRAN;
DELETE FROM ai.UserPreferences WHERE UserId IN (6, @oid);
EXEC sp_set_session_context N'UserId', 6;
EXECUTE AS USER = N'u_blk';
BEGIN TRY
    INSERT INTO ai.UserPreferences (UserId) VALUES (6);
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
SET @e = (SELECT COUNT(*) FROM ai.UserPreferences WHERE UserId = 6);
IF @@TRANCOUNT > 0 ROLLBACK;
IF @err = 0 AND @e = 1 PRINT N'PASS: T30 ghi ai.UserPreferences của chính mình vẫn được (đã ROLLBACK)';
ELSE PRINT N'FAIL: T30 ai.UserPreferences INSERT của mình, lỗi ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi') + N'; thấy=' + CAST(@e AS NVARCHAR(10));

-- T31: ai.UserPreferences đổi UserId sang người khác phải bị chặn 33504 (AFTER UPDATE)
SET @err = 0; SET @msg = NULL;
BEGIN TRAN;
DELETE FROM ai.UserPreferences WHERE UserId IN (6, @oid);
INSERT INTO ai.UserPreferences (UserId) VALUES (6);
EXEC sp_set_session_context N'UserId', 6;
EXECUTE AS USER = N'u_blk';
BEGIN TRY
    UPDATE ai.UserPreferences SET UserId = @oid WHERE UserId = 6;
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
SET @e = (SELECT COUNT(*) FROM ai.UserPreferences WHERE UserId = 6);
IF @@TRANCOUNT > 0 ROLLBACK;
IF @err = 33504 AND @e = 1 PRINT N'PASS: T31 BLOCK AFTER UPDATE chặn đổi chủ ai.UserPreferences (33504)';
ELSE PRINT N'FAIL: T31 ai.UserPreferences đổi UserId, mong đợi 33504, nhận ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi') + N'; dòng của 6 còn=' + CAST(@e AS NVARCHAR(10));

-- T32: ai.AIChatLogs INSERT dòng của người khác phải bị chặn 33504
SET @err = 0; SET @msg = NULL;
SET @x = (SELECT COUNT(*) FROM ai.AIChatLogs);
BEGIN TRAN;
EXEC sp_set_session_context N'UserId', 6;
EXECUTE AS USER = N'u_blk';
BEGIN TRY
    INSERT INTO ai.AIChatLogs (SessionId, UserId, [Role], Message) VALUES (NEWID(), @oid, N'User', N'Test17 log người khác');
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
IF @@TRANCOUNT > 0 ROLLBACK;
SET @g = (SELECT COUNT(*) FROM ai.AIChatLogs);
IF @err = 33504 AND @g = @x PRINT N'PASS: T32 BLOCK AFTER INSERT chặn ghi ai.AIChatLogs của người khác (33504)';
ELSE PRINT N'FAIL: T32 ai.AIChatLogs INSERT người khác, mong đợi 33504, nhận ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi') + N'; trước=' + CAST(@x AS NVARCHAR(10)) + N', sau=' + CAST(@g AS NVARCHAR(10));

-- T33: ai.AIChatLogs INSERT dòng của mình phải thành công (đối chứng, bọc ROLLBACK)
SET @err = 0; SET @msg = NULL;
SET @x = (SELECT COUNT(*) FROM ai.AIChatLogs);
BEGIN TRAN;
EXEC sp_set_session_context N'UserId', 6;
EXECUTE AS USER = N'u_blk';
BEGIN TRY
    INSERT INTO ai.AIChatLogs (SessionId, UserId, [Role], Message) VALUES (NEWID(), 6, N'User', N'Test17 log của mình');
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
SET @e = (SELECT COUNT(*) FROM ai.AIChatLogs WHERE Message = N'Test17 log của mình');
IF @@TRANCOUNT > 0 ROLLBACK;
SET @g = (SELECT COUNT(*) FROM ai.AIChatLogs);
IF @err = 0 AND @e = 1 AND @g = @x PRINT N'PASS: T33 ghi ai.AIChatLogs của chính mình vẫn được (đã ROLLBACK, dữ liệu không đổi)';
ELSE PRINT N'FAIL: T33 ai.AIChatLogs INSERT của mình, lỗi ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi') + N'; thấy=' + CAST(@e AS NVARCHAR(10)) + N', trước=' + CAST(@x AS NVARCHAR(10)) + N', sau=' + CAST(@g AS NVARCHAR(10));

-- T34: ai.AIChatLogs đổi UserId sang người khác phải bị chặn 33504 (AFTER UPDATE)
SET @err = 0; SET @msg = NULL;
BEGIN TRAN;
INSERT INTO ai.AIChatLogs (SessionId, UserId, [Role], Message) VALUES (NEWID(), 6, N'User', N'Test17 log chuyển chủ');
EXEC sp_set_session_context N'UserId', 6;
EXECUTE AS USER = N'u_blk';
BEGIN TRY
    UPDATE ai.AIChatLogs SET UserId = @oid WHERE Message = N'Test17 log chuyển chủ';
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
SET @e = (SELECT COUNT(*) FROM ai.AIChatLogs WHERE Message = N'Test17 log chuyển chủ' AND UserId = 6);
IF @@TRANCOUNT > 0 ROLLBACK;
IF @err = 33504 AND @e = 1 PRINT N'PASS: T34 BLOCK AFTER UPDATE chặn đổi chủ ai.AIChatLogs (33504)';
ELSE PRINT N'FAIL: T34 ai.AIChatLogs đổi UserId, mong đợi 33504, nhận ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi') + N'; chủ vẫn là 6=' + CAST(@e AS NVARCHAR(10));

-- T35: ai.AIChatLogs UPDATE Feedback dòng Assistant của mình phải thành công (đường ghi trực tiếp còn lại, BR-AI-02)
SET @err = 0; SET @msg = NULL; SET @c = NULL;
BEGIN TRAN;
INSERT INTO ai.AIChatLogs (SessionId, UserId, [Role], Message, ModelName) VALUES (NEWID(), 6, N'Assistant', N'Test17 trả lời của mình', N'test17-model');
EXEC sp_set_session_context N'UserId', 6;
EXECUTE AS USER = N'u_blk';
BEGIN TRY
    UPDATE ai.AIChatLogs SET Feedback = N'Helpful' WHERE Message = N'Test17 trả lời của mình';
    SET @c = @@ROWCOUNT;
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
SET @e = (SELECT COUNT(*) FROM ai.AIChatLogs WHERE Message = N'Test17 trả lời của mình' AND Feedback = N'Helpful');
IF @@TRANCOUNT > 0 ROLLBACK;
IF @err = 0 AND @c = 1 AND @e = 1 PRINT N'PASS: T35 chủ dòng vẫn UPDATE được Feedback ai.AIChatLogs (đã ROLLBACK)';
ELSE PRINT N'FAIL: T35 ai.AIChatLogs UPDATE Feedback của mình, lỗi ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi') + N'; dòng bị sửa=' + ISNULL(CAST(@c AS NVARCHAR(10)), N'NULL') + N', thấy=' + CAST(@e AS NVARCHAR(10));

-- T36: ai.AIChatLogs UPDATE Feedback dòng của người khác: FILTER ẩn dòng nên 0 dòng bị sửa, Feedback không đổi
SET @err = 0; SET @msg = NULL; SET @c = NULL;
BEGIN TRAN;
INSERT INTO ai.AIChatLogs (SessionId, UserId, [Role], Message, ModelName) VALUES (NEWID(), @oid, N'Assistant', N'Test17 trả lời người khác', N'test17-model');
EXEC sp_set_session_context N'UserId', 6;
EXECUTE AS USER = N'u_blk';
BEGIN TRY
    UPDATE ai.AIChatLogs SET Feedback = N'NotHelpful' WHERE Message = N'Test17 trả lời người khác';
    SET @c = @@ROWCOUNT;
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
SET @e = (SELECT COUNT(*) FROM ai.AIChatLogs WHERE Message = N'Test17 trả lời người khác' AND Feedback IS NULL);
IF @@TRANCOUNT > 0 ROLLBACK;
IF @err = 0 AND @c = 0 AND @e = 1 PRINT N'PASS: T36 UPDATE Feedback dòng của người khác ảnh hưởng 0 dòng, Feedback không đổi';
ELSE PRINT N'FAIL: T36 ai.AIChatLogs UPDATE Feedback người khác, lỗi ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi') + N'; dòng bị sửa=' + ISNULL(CAST(@c AS NVARCHAR(10)), N'NULL') + N', Feedback còn NULL=' + CAST(@e AS NVARCHAR(10));

-- T37: ai.RecommendationLogs INSERT dòng của người khác phải bị chặn 33504
SET @err = 0; SET @msg = NULL;
SET @x = (SELECT COUNT(*) FROM ai.RecommendationLogs);
BEGIN TRAN;
EXEC sp_set_session_context N'UserId', 6;
EXECUTE AS USER = N'u_blk';
BEGIN TRY
    INSERT INTO ai.RecommendationLogs (UserId, RecommendationType, ItemId, [Rank], Score, ModelVersion)
    VALUES (@oid, N'Lab', 1, 1, 0.5, N'test17');
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
IF @@TRANCOUNT > 0 ROLLBACK;
SET @g = (SELECT COUNT(*) FROM ai.RecommendationLogs);
IF @err = 33504 AND @g = @x PRINT N'PASS: T37 BLOCK AFTER INSERT chặn ghi ai.RecommendationLogs của người khác (33504)';
ELSE PRINT N'FAIL: T37 ai.RecommendationLogs INSERT người khác, mong đợi 33504, nhận ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi') + N'; trước=' + CAST(@x AS NVARCHAR(10)) + N', sau=' + CAST(@g AS NVARCHAR(10));

-- T38: ai.RecommendationLogs INSERT dòng của mình phải thành công (đối chứng, bọc ROLLBACK)
SET @err = 0; SET @msg = NULL;
SET @x = (SELECT COUNT(*) FROM ai.RecommendationLogs);
BEGIN TRAN;
EXEC sp_set_session_context N'UserId', 6;
EXECUTE AS USER = N'u_blk';
BEGIN TRY
    INSERT INTO ai.RecommendationLogs (UserId, RecommendationType, ItemId, [Rank], Score, ModelVersion)
    VALUES (6, N'Lab', 1, 1, 0.5, N'test17');
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
SET @e = (SELECT COUNT(*) FROM ai.RecommendationLogs WHERE ModelVersion = N'test17');
IF @@TRANCOUNT > 0 ROLLBACK;
SET @g = (SELECT COUNT(*) FROM ai.RecommendationLogs);
IF @err = 0 AND @e = 1 AND @g = @x PRINT N'PASS: T38 ghi ai.RecommendationLogs của chính mình vẫn được (đã ROLLBACK, dữ liệu không đổi)';
ELSE PRINT N'FAIL: T38 ai.RecommendationLogs INSERT của mình, lỗi ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi') + N'; thấy=' + CAST(@e AS NVARCHAR(10)) + N', trước=' + CAST(@x AS NVARCHAR(10)) + N', sau=' + CAST(@g AS NVARCHAR(10));

-- T39: ai.RecommendationLogs đổi UserId sang người khác phải bị chặn 33504 (AFTER UPDATE)
SET @err = 0; SET @msg = NULL;
BEGIN TRAN;
INSERT INTO ai.RecommendationLogs (UserId, RecommendationType, ItemId, [Rank], Score, ModelVersion)
VALUES (6, N'Lab', 1, 1, 0.5, N'test17chuyen');
EXEC sp_set_session_context N'UserId', 6;
EXECUTE AS USER = N'u_blk';
BEGIN TRY
    UPDATE ai.RecommendationLogs SET UserId = @oid WHERE ModelVersion = N'test17chuyen';
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
SET @e = (SELECT COUNT(*) FROM ai.RecommendationLogs WHERE ModelVersion = N'test17chuyen' AND UserId = 6);
IF @@TRANCOUNT > 0 ROLLBACK;
IF @err = 33504 AND @e = 1 PRINT N'PASS: T39 BLOCK AFTER UPDATE chặn đổi chủ ai.RecommendationLogs (33504)';
ELSE PRINT N'FAIL: T39 ai.RecommendationLogs đổi UserId, mong đợi 33504, nhận ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi') + N'; chủ vẫn là 6=' + CAST(@e AS NVARCHAR(10));


-- ===== BLOCK predicate arc.ScanFiles (Việc 4C.3b) =====
GRANT SELECT, INSERT, UPDATE, DELETE ON arc.ScanFiles TO u_blk;
DECLARE @o1 INT, @lo INT, @cu INT, @st INT, @sf UNIQUEIDENTIFIER;
SELECT @o1 = o.OrderId, @cu = o.CustomerId, @lo = l.OwnerUserId
FROM ord.Orders o JOIN lab.FilmLabs l ON l.LabId = o.LabId WHERE o.OrderCode = N'FL-2026-000001';
SET @st = (SELECT TOP 1 UserId FROM iam.Users WHERE UserId NOT IN (@cu, @lo) AND IsDeleted = 0 ORDER BY UserId);

-- T40: role_LabOwner thật gọi arc.sp_UploadScan cho đơn lab mình phải chạy được dưới BLOCK (test 09 chỉ chạy dưới dbo), bọc ROLLBACK
IF USER_ID(N'u_labs') IS NOT NULL DROP USER u_labs;
CREATE USER u_labs WITHOUT LOGIN;  ALTER ROLE role_LabOwner ADD MEMBER u_labs;
SET @err = 0; SET @msg = NULL; SET @sf = NULL;
BEGIN TRAN;
DISABLE TRIGGER ord.trg_Orders_PreventInvalidStage ON ord.Orders;
UPDATE ord.Orders SET StageId = 8 WHERE OrderId = @o1;
EXECUTE AS USER = N'u_labs';
BEGIN TRY
    EXEC arc.sp_UploadScan @o1, @lo, N'test17_scan.jpg', N'https://storage.example.com/test17_scan.jpg', N'image/jpeg', 1000, @NewScanFileId = @sf OUTPUT;
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
SET @e = (SELECT COUNT(*) FROM arc.ScanFiles WHERE ScanFileId = @sf AND OwnerUserId = @cu AND UploadedBy = @lo);
IF @@TRANCOUNT > 0 ROLLBACK;
SET @g = (SELECT is_disabled FROM sys.triggers WHERE name = N'trg_Orders_PreventInvalidStage' AND parent_id = OBJECT_ID(N'ord.Orders'));
DROP USER u_labs;
IF @err = 0 AND @sf IS NOT NULL AND @e = 1 AND @g = 0 PRINT N'PASS: T40 role_LabOwner gọi arc.sp_UploadScan chạy được dưới BLOCK (đã ROLLBACK, trigger đơn vẫn bật)';
ELSE PRINT N'FAIL: T40 role_LabOwner gọi arc.sp_UploadScan, lỗi ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi') + N'; thấy=' + CAST(@e AS NVARCHAR(10)) + N', trigger bị tắt=' + ISNULL(CAST(@g AS NVARCHAR(10)), N'NULL');

-- T41: người lạ (không phải khách, không phải chủ lab của đơn) INSERT ảnh scan của đơn phải bị chặn 33504
SET @err = 0; SET @msg = NULL;
BEGIN TRAN;
EXEC sp_set_session_context N'UserId', @st;
EXECUTE AS USER = N'u_blk';
BEGIN TRY
    INSERT INTO arc.ScanFiles (OrderId, OwnerUserId, UploadedBy, FileName, StorageUrl, ContentType, FileSizeBytes)
    VALUES (@o1, @cu, @st, N'test17_x.jpg', N'https://storage.example.com/test17_x.jpg', N'image/jpeg', 1000);
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
SET @e = (SELECT COUNT(*) FROM arc.ScanFiles WHERE FileName = N'test17_x.jpg');
IF @@TRANCOUNT > 0 ROLLBACK;
IF @err = 33504 AND @e = 0 PRINT N'PASS: T41 BLOCK AFTER INSERT chặn người lạ ghi ảnh scan của đơn (33504)';
ELSE PRINT N'FAIL: T41 arc.ScanFiles INSERT người lạ, mong đợi 33504, nhận ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi') + N'; dòng đã thêm=' + CAST(@e AS NVARCHAR(10));

-- T42: chủ lab của đơn INSERT trực tiếp ảnh scan của đơn lab mình phải thành công (nhánh chủ lab của fn_ScanAccess), bọc ROLLBACK
SET @err = 0; SET @msg = NULL;
BEGIN TRAN;
EXEC sp_set_session_context N'UserId', @lo;
EXECUTE AS USER = N'u_blk';
BEGIN TRY
    INSERT INTO arc.ScanFiles (OrderId, OwnerUserId, UploadedBy, FileName, StorageUrl, ContentType, FileSizeBytes)
    VALUES (@o1, @cu, @lo, N'test17_y.jpg', N'https://storage.example.com/test17_y.jpg', N'image/jpeg', 1000);
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
SET @e = (SELECT COUNT(*) FROM arc.ScanFiles WHERE FileName = N'test17_y.jpg');
IF @@TRANCOUNT > 0 ROLLBACK;
IF @err = 0 AND @e = 1 PRINT N'PASS: T42 chủ lab của đơn ghi ảnh scan của đơn lab mình vẫn được (đã ROLLBACK)';
ELSE PRINT N'FAIL: T42 arc.ScanFiles INSERT chủ lab, lỗi ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi') + N'; thấy=' + CAST(@e AS NVARCHAR(10));

-- T43: người lạ UPDATE điểm chất lượng ảnh của đơn: FILTER ẩn dòng nên 0 dòng bị sửa, điểm không đổi
SET @err = 0; SET @msg = NULL; SET @c = NULL;
BEGIN TRAN;
INSERT INTO arc.ScanFiles (OrderId, OwnerUserId, UploadedBy, FileName, StorageUrl, ContentType, FileSizeBytes, QualityScore, QualityStatus)
VALUES (@o1, @cu, @lo, N'test17_z.jpg', N'https://storage.example.com/test17_z.jpg', N'image/jpeg', 1000, 80, N'Passed');
EXEC sp_set_session_context N'UserId', @st;
EXECUTE AS USER = N'u_blk';
BEGIN TRY
    UPDATE arc.ScanFiles SET QualityScore = 10, QualityStatus = N'Failed' WHERE FileName = N'test17_z.jpg';
    SET @c = @@ROWCOUNT;
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
SET @e = (SELECT COUNT(*) FROM arc.ScanFiles WHERE FileName = N'test17_z.jpg' AND QualityScore = 80 AND QualityStatus = N'Passed');
IF @@TRANCOUNT > 0 ROLLBACK;
IF @err = 0 AND @c = 0 AND @e = 1 PRINT N'PASS: T43 người lạ UPDATE điểm ảnh scan ảnh hưởng 0 dòng, điểm không đổi';
ELSE PRINT N'FAIL: T43 arc.ScanFiles UPDATE người lạ, lỗi ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi') + N'; dòng bị sửa=' + ISNULL(CAST(@c AS NVARCHAR(10)), N'NULL') + N', điểm còn nguyên=' + CAST(@e AS NVARCHAR(10));

-- T44: chủ lab của đơn UPDATE điểm chất lượng ảnh của đơn lab mình phải thành công, bọc ROLLBACK
SET @err = 0; SET @msg = NULL; SET @c = NULL;
BEGIN TRAN;
INSERT INTO arc.ScanFiles (OrderId, OwnerUserId, UploadedBy, FileName, StorageUrl, ContentType, FileSizeBytes, QualityScore, QualityStatus)
VALUES (@o1, @cu, @lo, N'test17_z.jpg', N'https://storage.example.com/test17_z.jpg', N'image/jpeg', 1000, 80, N'Passed');
EXEC sp_set_session_context N'UserId', @lo;
EXECUTE AS USER = N'u_blk';
BEGIN TRY
    UPDATE arc.ScanFiles SET QualityScore = 90 WHERE FileName = N'test17_z.jpg';
    SET @c = @@ROWCOUNT;
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
SET @e = (SELECT COUNT(*) FROM arc.ScanFiles WHERE FileName = N'test17_z.jpg' AND QualityScore = 90);
IF @@TRANCOUNT > 0 ROLLBACK;
IF @err = 0 AND @c = 1 AND @e = 1 PRINT N'PASS: T44 chủ lab của đơn UPDATE điểm ảnh scan vẫn được (đã ROLLBACK)';
ELSE PRINT N'FAIL: T44 arc.ScanFiles UPDATE chủ lab, lỗi ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi') + N'; dòng bị sửa=' + ISNULL(CAST(@c AS NVARCHAR(10)), N'NULL') + N', thấy=' + CAST(@e AS NVARCHAR(10));


-- ===== RLS lab.LabApprovals (Việc 4D.1b) =====
GRANT SELECT, INSERT, UPDATE, DELETE ON lab.LabApprovals TO u_blk;
IF USER_ID(N'u_labs2') IS NOT NULL DROP USER u_labs2;
IF USER_ID(N'u_adm2')  IS NOT NULL DROP USER u_adm2;
CREATE USER u_labs2 WITHOUT LOGIN;  ALTER ROLE role_LabOwner ADD MEMBER u_labs2;
CREATE USER u_adm2  WITHOUT LOGIN;  ALTER ROLE role_Admin    ADD MEMBER u_adm2;
GRANT SELECT, INSERT ON lab.LabApprovals TO u_adm2;
DECLARE @lab1 INT, @own1 INT, @lab2 INT, @own2 INT, @adm INT;
SELECT TOP 1 @lab1 = LabId, @own1 = OwnerUserId FROM lab.FilmLabs WHERE IsDeleted = 0 ORDER BY LabId;
SELECT TOP 1 @lab2 = LabId, @own2 = OwnerUserId FROM lab.FilmLabs WHERE IsDeleted = 0 AND OwnerUserId <> @own1 ORDER BY LabId;
SET @adm = (SELECT TOP 1 ur.UserId FROM iam.UserRoles ur JOIN iam.Roles r ON r.RoleId = ur.RoleId WHERE r.RoleCode = N'Admin' ORDER BY ur.UserId);

-- T45: role_LabOwner thật gọi lab.sp_GetMyLabs phải chạy được dưới FILTER và procedure phải đặt UserId session = chủ lab (nên LastDecision không bị mất)
SET @err = 0; SET @msg = NULL; SET @g = NULL;
BEGIN TRAN;
INSERT INTO lab.LabApprovals (LabId, ReviewedBy, Decision, Reason) VALUES (@lab1, @adm, N'Rejected', N'Test17 lý do');
EXEC sp_set_session_context N'UserId', NULL;
EXECUTE AS USER = N'u_labs2';
BEGIN TRY
    EXEC lab.sp_GetMyLabs @own1;
    SET @g = CONVERT(INT, SESSION_CONTEXT(N'UserId'));
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @err = 0 AND @g = @own1 PRINT N'PASS: T45 role_LabOwner gọi lab.sp_GetMyLabs chạy được, procedure đặt UserId session = chủ lab';
ELSE PRINT N'FAIL: T45 role_LabOwner gọi lab.sp_GetMyLabs, lỗi ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi') + N'; session UserId=' + ISNULL(CAST(@g AS NVARCHAR(10)), N'NULL') + N', mong đợi=' + ISNULL(CAST(@own1 AS NVARCHAR(10)), N'NULL');

-- T46: chủ lab đọc được quyết định duyệt của lab mình (FILTER cho qua nhánh chủ lab)
SET @err = 0; SET @msg = NULL; SET @e = NULL;
BEGIN TRAN;
INSERT INTO lab.LabApprovals (LabId, ReviewedBy, Decision, Reason) VALUES (@lab1, @adm, N'Rejected', N'Test17 lý do');
EXEC sp_set_session_context N'UserId', @own1;
EXECUTE AS USER = N'u_blk';
BEGIN TRY
    SET @e = (SELECT COUNT(*) FROM lab.LabApprovals WHERE LabId = @lab1 AND Reason = N'Test17 lý do');
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @err = 0 AND @e = 1 PRINT N'PASS: T46 chủ lab đọc được quyết định duyệt của lab mình';
ELSE PRINT N'FAIL: T46 chủ lab đọc LabApprovals, lỗi ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi') + N'; thấy=' + ISNULL(CAST(@e AS NVARCHAR(10)), N'NULL');

-- T47: chủ lab khác không thấy quyết định duyệt của lab này
SET @err = 0; SET @msg = NULL; SET @e = NULL;
BEGIN TRAN;
INSERT INTO lab.LabApprovals (LabId, ReviewedBy, Decision, Reason) VALUES (@lab1, @adm, N'Rejected', N'Test17 lý do');
EXEC sp_set_session_context N'UserId', @own2;
EXECUTE AS USER = N'u_blk';
BEGIN TRY
    SET @e = (SELECT COUNT(*) FROM lab.LabApprovals WHERE LabId = @lab1 AND Reason = N'Test17 lý do');
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @err = 0 AND @own2 IS NOT NULL AND @e = 0 PRINT N'PASS: T47 chủ lab khác không thấy quyết định duyệt của lab này';
ELSE PRINT N'FAIL: T47 chủ lab khác đọc LabApprovals, lỗi ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi') + N'; thấy=' + ISNULL(CAST(@e AS NVARCHAR(10)), N'NULL') + N', chủ lab thứ hai=' + ISNULL(CAST(@own2 AS NVARCHAR(10)), N'NULL');

-- T48: Admin (role_Admin) đọc được mọi quyết định duyệt
SET @err = 0; SET @msg = NULL; SET @e = NULL;
BEGIN TRAN;
INSERT INTO lab.LabApprovals (LabId, ReviewedBy, Decision, Reason) VALUES (@lab1, @adm, N'Rejected', N'Test17 lý do');
EXEC sp_set_session_context N'UserId', NULL;
EXECUTE AS USER = N'u_adm2';
BEGIN TRY
    SET @e = (SELECT COUNT(*) FROM lab.LabApprovals WHERE LabId = @lab1 AND Reason = N'Test17 lý do');
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @err = 0 AND @e = 1 PRINT N'PASS: T48 Admin đọc được quyết định duyệt';
ELSE PRINT N'FAIL: T48 Admin đọc LabApprovals, lỗi ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi') + N'; thấy=' + ISNULL(CAST(@e AS NVARCHAR(10)), N'NULL');

-- T49: chủ lab INSERT trực tiếp quyết định duyệt phải bị chặn 33504 (chỉ Admin được ghi)
SET @err = 0; SET @msg = NULL;
BEGIN TRAN;
EXEC sp_set_session_context N'UserId', @own1;
EXECUTE AS USER = N'u_blk';
BEGIN TRY
    INSERT INTO lab.LabApprovals (LabId, ReviewedBy, Decision, Reason) VALUES (@lab1, @own1, N'Approved', N'Test17 chủ lab tự ghi');
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
SET @e = (SELECT COUNT(*) FROM lab.LabApprovals WHERE Reason = N'Test17 chủ lab tự ghi');
IF @@TRANCOUNT > 0 ROLLBACK;
IF @err = 33504 AND @e = 0 PRINT N'PASS: T49 BLOCK AFTER INSERT chặn chủ lab tự ghi quyết định duyệt (33504)';
ELSE PRINT N'FAIL: T49 chủ lab INSERT LabApprovals, mong đợi 33504, nhận ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi') + N'; dòng đã thêm=' + CAST(@e AS NVARCHAR(10));

-- T50: Admin INSERT quyết định duyệt phải thành công (đối chứng, bọc ROLLBACK)
SET @err = 0; SET @msg = NULL;
BEGIN TRAN;
EXEC sp_set_session_context N'UserId', NULL;
EXECUTE AS USER = N'u_adm2';
BEGIN TRY
    INSERT INTO lab.LabApprovals (LabId, ReviewedBy, Decision, Reason) VALUES (@lab1, @adm, N'Approved', N'Test17 admin ghi');
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
SET @e = (SELECT COUNT(*) FROM lab.LabApprovals WHERE Reason = N'Test17 admin ghi');
IF @@TRANCOUNT > 0 ROLLBACK;
IF @err = 0 AND @e = 1 PRINT N'PASS: T50 Admin ghi quyết định duyệt vẫn được (đã ROLLBACK)';
ELSE PRINT N'FAIL: T50 Admin INSERT LabApprovals, lỗi ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi') + N'; thấy=' + CAST(@e AS NVARCHAR(10));

-- T51: chủ lab UPDATE lý do của quyết định duyệt lab mình phải bị chặn 33504 (đọc được nhờ FILTER, ghi bị BLOCK)
SET @err = 0; SET @msg = NULL;
BEGIN TRAN;
INSERT INTO lab.LabApprovals (LabId, ReviewedBy, Decision, Reason) VALUES (@lab1, @adm, N'Rejected', N'Test17 lý do');
EXEC sp_set_session_context N'UserId', @own1;
EXECUTE AS USER = N'u_blk';
BEGIN TRY
    UPDATE lab.LabApprovals SET Reason = N'Test17 bị sửa' WHERE LabId = @lab1 AND Reason = N'Test17 lý do';
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
SET @e = (SELECT COUNT(*) FROM lab.LabApprovals WHERE LabId = @lab1 AND Reason = N'Test17 lý do');
IF @@TRANCOUNT > 0 ROLLBACK;
IF @err = 33504 AND @e = 1 PRINT N'PASS: T51 BLOCK BEFORE UPDATE chặn chủ lab sửa quyết định duyệt (33504)';
ELSE PRINT N'FAIL: T51 chủ lab UPDATE LabApprovals, mong đợi 33504, nhận ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi') + N'; dòng gốc còn=' + CAST(@e AS NVARCHAR(10));

DROP USER u_labs2;
DROP USER u_adm2;

-- Dọn
EXEC sp_set_session_context N'UserId', NULL;
DROP USER u_blk;

DROP USER u_sys;