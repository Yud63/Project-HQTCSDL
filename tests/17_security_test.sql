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


-- ===== RLS com.Articles (Việc 4D.2b) =====
GRANT SELECT, INSERT, UPDATE, DELETE ON com.Articles TO u_blk;
IF USER_ID(N'u_adm3') IS NOT NULL DROP USER u_adm3;
CREATE USER u_adm3 WITHOUT LOGIN;  ALTER ROLE role_Admin ADD MEMBER u_adm3;
GRANT SELECT ON com.Articles TO u_adm3;
DECLARE @au INT, @ot INT;
SET @au = (SELECT TOP 1 UserId FROM iam.Users WHERE IsDeleted = 0 ORDER BY UserId);
SET @ot = (SELECT TOP 1 UserId FROM iam.Users WHERE IsDeleted = 0 AND UserId <> @au ORDER BY UserId);

-- T52: INSERT bài của người khác (AuthorId <> UserId trong session) phải bị chặn 33504
SET @err = 0; SET @msg = NULL;
BEGIN TRAN;
EXEC sp_set_session_context N'UserId', @au;
EXECUTE AS USER = N'u_blk';
BEGIN TRY
    INSERT INTO com.Articles (AuthorId, ArticleType, Title, Slug, Body, Status)
    VALUES (@ot, N'Experience', N'Test17 bài người khác', N'test17-other', N'Nội dung', N'Draft');
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
SET @e = (SELECT COUNT(*) FROM com.Articles WHERE Slug = N'test17-other');
IF @@TRANCOUNT > 0 ROLLBACK;
IF @err = 33504 AND @e = 0 PRINT N'PASS: T52 BLOCK AFTER INSERT chặn ghi bài viết của người khác (33504)';
ELSE PRINT N'FAIL: T52 com.Articles INSERT người khác, mong đợi 33504, nhận ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi') + N'; dòng đã thêm=' + CAST(@e AS NVARCHAR(10));

-- T53: INSERT bài của chính mình phải thành công (đối chứng, bọc ROLLBACK)
SET @err = 0; SET @msg = NULL;
BEGIN TRAN;
EXEC sp_set_session_context N'UserId', @au;
EXECUTE AS USER = N'u_blk';
BEGIN TRY
    INSERT INTO com.Articles (AuthorId, ArticleType, Title, Slug, Body, Status)
    VALUES (@au, N'Experience', N'Test17 bài của mình', N'test17-own', N'Nội dung', N'Draft');
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
SET @e = (SELECT COUNT(*) FROM com.Articles WHERE Slug = N'test17-own');
IF @@TRANCOUNT > 0 ROLLBACK;
IF @err = 0 AND @e = 1 PRINT N'PASS: T53 ghi bài viết của chính mình vẫn được (đã ROLLBACK)';
ELSE PRINT N'FAIL: T53 com.Articles INSERT của mình, lỗi ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi') + N'; thấy=' + CAST(@e AS NVARCHAR(10));

-- T54: người khác đọc được bài Published của tác giả (FILTER cho qua bài Published)
SET @err = 0; SET @msg = NULL; SET @e = NULL;
BEGIN TRAN;
INSERT INTO com.Articles (AuthorId, ArticleType, Title, Slug, Body, Status, PublishedAt)
VALUES (@au, N'Experience', N'Test17 bài công khai', N'test17-pub', N'Nội dung', N'Published', SYSUTCDATETIME());
EXEC sp_set_session_context N'UserId', @ot;
EXECUTE AS USER = N'u_blk';
BEGIN TRY
    SET @e = (SELECT COUNT(*) FROM com.Articles WHERE Slug = N'test17-pub');
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @err = 0 AND @e = 1 PRINT N'PASS: T54 người khác đọc được bài Published';
ELSE PRINT N'FAIL: T54 đọc bài Published, lỗi ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi') + N'; thấy=' + ISNULL(CAST(@e AS NVARCHAR(10)), N'NULL');

-- T55: người khác không thấy bài Draft và Hidden của tác giả
SET @err = 0; SET @msg = NULL; SET @e = NULL;
BEGIN TRAN;
INSERT INTO com.Articles (AuthorId, ArticleType, Title, Slug, Body, Status)
VALUES (@au, N'Experience', N'Test17 bài nháp', N'test17-draft', N'Nội dung', N'Draft');
INSERT INTO com.Articles (AuthorId, ArticleType, Title, Slug, Body, Status, PublishedAt, ModerationReason)
VALUES (@au, N'Experience', N'Test17 bài bị ẩn', N'test17-hidden', N'Nội dung', N'Hidden', SYSUTCDATETIME(), N'Test17 lý do ẩn');
EXEC sp_set_session_context N'UserId', @ot;
EXECUTE AS USER = N'u_blk';
BEGIN TRY
    SET @e = (SELECT COUNT(*) FROM com.Articles WHERE Slug IN (N'test17-draft', N'test17-hidden'));
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @err = 0 AND @e = 0 PRINT N'PASS: T55 người khác không thấy bài Draft và Hidden của tác giả';
ELSE PRINT N'FAIL: T55 đọc bài Draft/Hidden của người khác, lỗi ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi') + N'; thấy=' + ISNULL(CAST(@e AS NVARCHAR(10)), N'NULL');

-- T56: tác giả thấy bài Draft và Hidden của chính mình
SET @err = 0; SET @msg = NULL; SET @e = NULL;
BEGIN TRAN;
INSERT INTO com.Articles (AuthorId, ArticleType, Title, Slug, Body, Status)
VALUES (@au, N'Experience', N'Test17 bài nháp', N'test17-draft', N'Nội dung', N'Draft');
INSERT INTO com.Articles (AuthorId, ArticleType, Title, Slug, Body, Status, PublishedAt, ModerationReason)
VALUES (@au, N'Experience', N'Test17 bài bị ẩn', N'test17-hidden', N'Nội dung', N'Hidden', SYSUTCDATETIME(), N'Test17 lý do ẩn');
EXEC sp_set_session_context N'UserId', @au;
EXECUTE AS USER = N'u_blk';
BEGIN TRY
    SET @e = (SELECT COUNT(*) FROM com.Articles WHERE Slug IN (N'test17-draft', N'test17-hidden'));
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @err = 0 AND @e = 2 PRINT N'PASS: T56 tác giả thấy bài Draft và Hidden của mình';
ELSE PRINT N'FAIL: T56 tác giả đọc bài Draft/Hidden của mình, lỗi ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi') + N'; thấy=' + ISNULL(CAST(@e AS NVARCHAR(10)), N'NULL');

-- T57: Admin (role_Admin) thấy bài Draft của người khác
SET @err = 0; SET @msg = NULL; SET @e = NULL;
BEGIN TRAN;
INSERT INTO com.Articles (AuthorId, ArticleType, Title, Slug, Body, Status)
VALUES (@au, N'Experience', N'Test17 bài nháp', N'test17-draft', N'Nội dung', N'Draft');
EXEC sp_set_session_context N'UserId', NULL;
EXECUTE AS USER = N'u_adm3';
BEGIN TRY
    SET @e = (SELECT COUNT(*) FROM com.Articles WHERE Slug = N'test17-draft');
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @err = 0 AND @e = 1 PRINT N'PASS: T57 Admin thấy bài Draft của người khác';
ELSE PRINT N'FAIL: T57 Admin đọc bài Draft, lỗi ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi') + N'; thấy=' + ISNULL(CAST(@e AS NVARCHAR(10)), N'NULL');

-- T58: người khác UPDATE bài Published của tác giả (đọc được nhờ FILTER) phải bị chặn 33504, tiêu đề không đổi
SET @err = 0; SET @msg = NULL;
BEGIN TRAN;
INSERT INTO com.Articles (AuthorId, ArticleType, Title, Slug, Body, Status, PublishedAt)
VALUES (@au, N'Experience', N'Test17 bài công khai', N'test17-pub', N'Nội dung', N'Published', SYSUTCDATETIME());
EXEC sp_set_session_context N'UserId', @ot;
EXECUTE AS USER = N'u_blk';
BEGIN TRY
    UPDATE com.Articles SET Title = N'Test17 bị sửa' WHERE Slug = N'test17-pub';
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
SET @e = (SELECT COUNT(*) FROM com.Articles WHERE Slug = N'test17-pub' AND Title = N'Test17 bài công khai');
IF @@TRANCOUNT > 0 ROLLBACK;
IF @err = 33504 AND @e = 1 PRINT N'PASS: T58 BLOCK BEFORE UPDATE chặn người khác sửa bài Published (33504)';
ELSE PRINT N'FAIL: T58 com.Articles UPDATE người khác, mong đợi 33504, nhận ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi') + N'; tiêu đề gốc còn=' + CAST(@e AS NVARCHAR(10));

-- T59: người khác DELETE bài Published của tác giả phải bị chặn 33504, dòng còn nguyên
SET @err = 0; SET @msg = NULL;
BEGIN TRAN;
INSERT INTO com.Articles (AuthorId, ArticleType, Title, Slug, Body, Status, PublishedAt)
VALUES (@au, N'Experience', N'Test17 bài công khai', N'test17-pub', N'Nội dung', N'Published', SYSUTCDATETIME());
EXEC sp_set_session_context N'UserId', @ot;
EXECUTE AS USER = N'u_blk';
BEGIN TRY
    DELETE FROM com.Articles WHERE Slug = N'test17-pub';
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
SET @e = (SELECT COUNT(*) FROM com.Articles WHERE Slug = N'test17-pub');
IF @@TRANCOUNT > 0 ROLLBACK;
IF @err = 33504 AND @e = 1 PRINT N'PASS: T59 BLOCK BEFORE DELETE chặn người khác xóa bài Published (33504)';
ELSE PRINT N'FAIL: T59 com.Articles DELETE người khác, mong đợi 33504, nhận ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi') + N'; dòng còn=' + CAST(@e AS NVARCHAR(10));

-- T60: tác giả đổi AuthorId bài của mình sang người khác phải bị chặn 33504 (AFTER UPDATE)
SET @err = 0; SET @msg = NULL;
BEGIN TRAN;
INSERT INTO com.Articles (AuthorId, ArticleType, Title, Slug, Body, Status, PublishedAt)
VALUES (@au, N'Experience', N'Test17 bài công khai', N'test17-pub', N'Nội dung', N'Published', SYSUTCDATETIME());
EXEC sp_set_session_context N'UserId', @au;
EXECUTE AS USER = N'u_blk';
BEGIN TRY
    UPDATE com.Articles SET AuthorId = @ot WHERE Slug = N'test17-pub';
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
SET @e = (SELECT COUNT(*) FROM com.Articles WHERE Slug = N'test17-pub' AND AuthorId = @au);
IF @@TRANCOUNT > 0 ROLLBACK;
IF @err = 33504 AND @e = 1 PRINT N'PASS: T60 BLOCK AFTER UPDATE chặn đổi tác giả sang người khác (33504)';
ELSE PRINT N'FAIL: T60 com.Articles đổi AuthorId, mong đợi 33504, nhận ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi') + N'; tác giả vẫn là mình=' + CAST(@e AS NVARCHAR(10));

-- T61: tác giả UPDATE tiêu đề bài của mình phải thành công (đối chứng, bọc ROLLBACK)
SET @err = 0; SET @msg = NULL; SET @c = NULL;
BEGIN TRAN;
INSERT INTO com.Articles (AuthorId, ArticleType, Title, Slug, Body, Status, PublishedAt)
VALUES (@au, N'Experience', N'Test17 bài công khai', N'test17-pub', N'Nội dung', N'Published', SYSUTCDATETIME());
EXEC sp_set_session_context N'UserId', @au;
EXECUTE AS USER = N'u_blk';
BEGIN TRY
    UPDATE com.Articles SET Title = N'Test17 đã sửa' WHERE Slug = N'test17-pub';
    SET @c = @@ROWCOUNT;
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
SET @e = (SELECT COUNT(*) FROM com.Articles WHERE Slug = N'test17-pub' AND Title = N'Test17 đã sửa');
IF @@TRANCOUNT > 0 ROLLBACK;
IF @err = 0 AND @c = 1 AND @e = 1 PRINT N'PASS: T61 tác giả sửa bài viết của chính mình vẫn được (đã ROLLBACK)';
ELSE PRINT N'FAIL: T61 com.Articles UPDATE của mình, lỗi ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi') + N'; dòng bị sửa=' + ISNULL(CAST(@c AS NVARCHAR(10)), N'NULL') + N', thấy=' + CAST(@e AS NVARCHAR(10));

DROP USER u_adm3;


-- ===== RLS mkt.MarketTransactions + mkt.Messages (Việc 4D.3b) =====
GRANT SELECT, INSERT, UPDATE, DELETE ON mkt.MarketTransactions TO u_blk;
GRANT SELECT, INSERT, UPDATE, DELETE ON mkt.Messages TO u_blk;
GRANT EXECUTE ON mkt.fn_SellerRating TO u_blk;
GRANT EXECUTE ON mkt.fn_SellerRatingCount TO u_blk;
GRANT EXECUTE ON mkt.sp_PlaceMarketOrder TO u_blk;
GRANT EXECUTE ON mkt.sp_SendMessage TO u_blk;
GRANT EXECUTE ON mkt.sp_UpdateMarketTransaction TO u_blk;
IF USER_ID(N'u_adm4') IS NOT NULL DROP USER u_adm4;
CREATE USER u_adm4 WITHOUT LOGIN;  ALTER ROLE role_Admin ADD MEMBER u_adm4;
GRANT SELECT ON mkt.MarketTransactions TO u_adm4;
GRANT SELECT ON mkt.Messages TO u_adm4;
DECLARE @sl INT, @by INT, @ox INT, @mc INT, @ml INT, @mt INT, @k INT, @k2 INT, @xt DECIMAL(3,2), @rt DECIMAL(3,2), @xc INT, @rc INT;
SET @sl = (SELECT TOP 1 UserId FROM iam.Users WHERE IsDeleted = 0 AND IsActive = 1 ORDER BY UserId);
SET @by = (SELECT TOP 1 UserId FROM iam.Users WHERE IsDeleted = 0 AND IsActive = 1 AND UserId <> @sl ORDER BY UserId);
SET @ox = (SELECT TOP 1 UserId FROM iam.Users WHERE IsDeleted = 0 AND IsActive = 1 AND UserId NOT IN (@sl, @by) ORDER BY UserId);
SET @mc = (SELECT TOP 1 CategoryId FROM mkt.ListingCategories ORDER BY CategoryId);

-- T62: người mua và người bán đều thấy giao dịch của mình (FILTER cho qua hai bên)
SET @err = 0; SET @msg = NULL; SET @e = NULL; SET @c = NULL;
BEGIN TRAN;
INSERT INTO mkt.Listings (SellerId, CategoryId, ListingType, Title, Condition, Price, Quantity, City)
VALUES (@sl, @mc, N'Sell', N'Test17 tin đăng', N'Good', 1000000, 5, N'Test17');
SET @ml = SCOPE_IDENTITY();
INSERT INTO mkt.MarketTransactions (TransactionCode, ListingId, SellerId, BuyerId, Quantity, UnitPrice, PlatformFee)
VALUES (N'MK-T17-0001', @ml, @sl, @by, 1, 1000000, 50000);
EXEC sp_set_session_context N'UserId', @by;
EXECUTE AS USER = N'u_blk';
BEGIN TRY
    SET @e = (SELECT COUNT(*) FROM mkt.MarketTransactions WHERE TransactionCode = N'MK-T17-0001');
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
EXEC sp_set_session_context N'UserId', @sl;
EXECUTE AS USER = N'u_blk';
BEGIN TRY
    SET @c = (SELECT COUNT(*) FROM mkt.MarketTransactions WHERE TransactionCode = N'MK-T17-0001');
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @err = 0 AND @e = 1 AND @c = 1 PRINT N'PASS: T62 người mua và người bán đều thấy giao dịch của mình';
ELSE PRINT N'FAIL: T62 đọc giao dịch của mình, lỗi ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi') + N'; người mua thấy=' + ISNULL(CAST(@e AS NVARCHAR(10)), N'NULL') + N', người bán thấy=' + ISNULL(CAST(@c AS NVARCHAR(10)), N'NULL');

-- T63: người lạ không thấy giao dịch của người khác; Admin (role_Admin) thấy
SET @err = 0; SET @msg = NULL; SET @e = NULL; SET @c = NULL;
BEGIN TRAN;
INSERT INTO mkt.Listings (SellerId, CategoryId, ListingType, Title, Condition, Price, Quantity, City)
VALUES (@sl, @mc, N'Sell', N'Test17 tin đăng', N'Good', 1000000, 5, N'Test17');
SET @ml = SCOPE_IDENTITY();
INSERT INTO mkt.MarketTransactions (TransactionCode, ListingId, SellerId, BuyerId, Quantity, UnitPrice, PlatformFee)
VALUES (N'MK-T17-0001', @ml, @sl, @by, 1, 1000000, 50000);
EXEC sp_set_session_context N'UserId', @ox;
EXECUTE AS USER = N'u_blk';
BEGIN TRY
    SET @e = (SELECT COUNT(*) FROM mkt.MarketTransactions WHERE TransactionCode = N'MK-T17-0001');
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
EXEC sp_set_session_context N'UserId', NULL;
EXECUTE AS USER = N'u_adm4';
BEGIN TRY
    SET @c = (SELECT COUNT(*) FROM mkt.MarketTransactions WHERE TransactionCode = N'MK-T17-0001');
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @err = 0 AND @e = 0 AND @c = 1 PRINT N'PASS: T63 người lạ không thấy giao dịch của người khác, Admin thấy';
ELSE PRINT N'FAIL: T63 lọc giao dịch, lỗi ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi') + N'; người lạ thấy=' + ISNULL(CAST(@e AS NVARCHAR(10)), N'NULL') + N', Admin thấy=' + ISNULL(CAST(@c AS NVARCHAR(10)), N'NULL');

-- T64: người lạ INSERT giao dịch hộ người mua khác (BuyerId <> UserId trong session) phải bị chặn 33504
SET @err = 0; SET @msg = NULL;
BEGIN TRAN;
INSERT INTO mkt.Listings (SellerId, CategoryId, ListingType, Title, Condition, Price, Quantity, City)
VALUES (@sl, @mc, N'Sell', N'Test17 tin đăng', N'Good', 1000000, 5, N'Test17');
SET @ml = SCOPE_IDENTITY();
EXEC sp_set_session_context N'UserId', @ox;
EXECUTE AS USER = N'u_blk';
BEGIN TRY
    INSERT INTO mkt.MarketTransactions (TransactionCode, ListingId, SellerId, BuyerId, Quantity, UnitPrice, PlatformFee)
    VALUES (N'MK-T17-0003', @ml, @sl, @by, 1, 1000000, 50000);
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
SET @e = (SELECT COUNT(*) FROM mkt.MarketTransactions WHERE TransactionCode = N'MK-T17-0003');
IF @@TRANCOUNT > 0 ROLLBACK;
IF @err = 33504 AND @e = 0 PRINT N'PASS: T64 BLOCK AFTER INSERT chặn người lạ tạo giao dịch hộ người mua khác (33504)';
ELSE PRINT N'FAIL: T64 mkt.MarketTransactions INSERT người lạ, mong đợi 33504, nhận ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi') + N'; dòng đã thêm=' + CAST(@e AS NVARCHAR(10));

-- T65: người lạ UPDATE và DELETE giao dịch của người khác: FILTER ẩn dòng nên 0 dòng bị ảnh hưởng, dữ liệu nguyên vẹn
SET @err = 0; SET @msg = NULL; SET @c = NULL; SET @k = NULL;
BEGIN TRAN;
INSERT INTO mkt.Listings (SellerId, CategoryId, ListingType, Title, Condition, Price, Quantity, City)
VALUES (@sl, @mc, N'Sell', N'Test17 tin đăng', N'Good', 1000000, 5, N'Test17');
SET @ml = SCOPE_IDENTITY();
INSERT INTO mkt.MarketTransactions (TransactionCode, ListingId, SellerId, BuyerId, Quantity, UnitPrice, PlatformFee)
VALUES (N'MK-T17-0001', @ml, @sl, @by, 1, 1000000, 50000);
EXEC sp_set_session_context N'UserId', @ox;
EXECUTE AS USER = N'u_blk';
BEGIN TRY
    UPDATE mkt.MarketTransactions SET Note = N'Test17 bị sửa' WHERE TransactionCode = N'MK-T17-0001';
    SET @c = @@ROWCOUNT;
    DELETE FROM mkt.MarketTransactions WHERE TransactionCode = N'MK-T17-0001';
    SET @k = @@ROWCOUNT;
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
SET @e = (SELECT COUNT(*) FROM mkt.MarketTransactions WHERE TransactionCode = N'MK-T17-0001' AND Note IS NULL);
IF @@TRANCOUNT > 0 ROLLBACK;
IF @err = 0 AND @c = 0 AND @k = 0 AND @e = 1 PRINT N'PASS: T65 người lạ UPDATE và DELETE giao dịch ảnh hưởng 0 dòng, dữ liệu nguyên vẹn';
ELSE PRINT N'FAIL: T65 người lạ sửa/xóa giao dịch, lỗi ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi') + N'; UPDATE=' + ISNULL(CAST(@c AS NVARCHAR(10)), N'NULL') + N', DELETE=' + ISNULL(CAST(@k AS NVARCHAR(10)), N'NULL') + N', còn nguyên=' + CAST(@e AS NVARCHAR(10));

-- T66: người mua đổi BuyerId của giao dịch sang người khác phải bị chặn 33504 (AFTER UPDATE)
SET @err = 0; SET @msg = NULL;
BEGIN TRAN;
INSERT INTO mkt.Listings (SellerId, CategoryId, ListingType, Title, Condition, Price, Quantity, City)
VALUES (@sl, @mc, N'Sell', N'Test17 tin đăng', N'Good', 1000000, 5, N'Test17');
SET @ml = SCOPE_IDENTITY();
INSERT INTO mkt.MarketTransactions (TransactionCode, ListingId, SellerId, BuyerId, Quantity, UnitPrice, PlatformFee)
VALUES (N'MK-T17-0001', @ml, @sl, @by, 1, 1000000, 50000);
EXEC sp_set_session_context N'UserId', @by;
EXECUTE AS USER = N'u_blk';
BEGIN TRY
    UPDATE mkt.MarketTransactions SET BuyerId = @ox WHERE TransactionCode = N'MK-T17-0001';
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
SET @e = (SELECT COUNT(*) FROM mkt.MarketTransactions WHERE TransactionCode = N'MK-T17-0001' AND BuyerId = @by);
IF @@TRANCOUNT > 0 ROLLBACK;
IF @err = 33504 AND @e = 1 PRINT N'PASS: T66 BLOCK AFTER UPDATE chặn đổi người mua sang người khác (33504)';
ELSE PRINT N'FAIL: T66 mkt.MarketTransactions đổi BuyerId, mong đợi 33504, nhận ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi') + N'; người mua vẫn là mình=' + CAST(@e AS NVARCHAR(10));

-- T67: người gửi và người nhận đều thấy tin nhắn
SET @err = 0; SET @msg = NULL; SET @e = NULL; SET @c = NULL;
BEGIN TRAN;
INSERT INTO mkt.Listings (SellerId, CategoryId, ListingType, Title, Condition, Price, Quantity, City)
VALUES (@sl, @mc, N'Sell', N'Test17 tin đăng', N'Good', 1000000, 5, N'Test17');
SET @ml = SCOPE_IDENTITY();
INSERT INTO mkt.Messages (ListingId, SenderId, ReceiverId, Body) VALUES (@ml, @sl, @by, N'Test17 tin nhắn');
EXEC sp_set_session_context N'UserId', @sl;
EXECUTE AS USER = N'u_blk';
BEGIN TRY
    SET @e = (SELECT COUNT(*) FROM mkt.Messages WHERE Body = N'Test17 tin nhắn');
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
EXEC sp_set_session_context N'UserId', @by;
EXECUTE AS USER = N'u_blk';
BEGIN TRY
    SET @c = (SELECT COUNT(*) FROM mkt.Messages WHERE Body = N'Test17 tin nhắn');
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @err = 0 AND @e = 1 AND @c = 1 PRINT N'PASS: T67 người gửi và người nhận đều thấy tin nhắn';
ELSE PRINT N'FAIL: T67 đọc tin nhắn của mình, lỗi ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi') + N'; người gửi thấy=' + ISNULL(CAST(@e AS NVARCHAR(10)), N'NULL') + N', người nhận thấy=' + ISNULL(CAST(@c AS NVARCHAR(10)), N'NULL');

-- T68: người lạ không thấy tin nhắn của người khác; Admin thấy
SET @err = 0; SET @msg = NULL; SET @e = NULL; SET @c = NULL;
BEGIN TRAN;
INSERT INTO mkt.Listings (SellerId, CategoryId, ListingType, Title, Condition, Price, Quantity, City)
VALUES (@sl, @mc, N'Sell', N'Test17 tin đăng', N'Good', 1000000, 5, N'Test17');
SET @ml = SCOPE_IDENTITY();
INSERT INTO mkt.Messages (ListingId, SenderId, ReceiverId, Body) VALUES (@ml, @sl, @by, N'Test17 tin nhắn');
EXEC sp_set_session_context N'UserId', @ox;
EXECUTE AS USER = N'u_blk';
BEGIN TRY
    SET @e = (SELECT COUNT(*) FROM mkt.Messages WHERE Body = N'Test17 tin nhắn');
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
EXEC sp_set_session_context N'UserId', NULL;
EXECUTE AS USER = N'u_adm4';
BEGIN TRY
    SET @c = (SELECT COUNT(*) FROM mkt.Messages WHERE Body = N'Test17 tin nhắn');
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @err = 0 AND @e = 0 AND @c = 1 PRINT N'PASS: T68 người lạ không thấy tin nhắn của người khác, Admin thấy';
ELSE PRINT N'FAIL: T68 lọc tin nhắn, lỗi ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi') + N'; người lạ thấy=' + ISNULL(CAST(@e AS NVARCHAR(10)), N'NULL') + N', Admin thấy=' + ISNULL(CAST(@c AS NVARCHAR(10)), N'NULL');

-- T69: người lạ INSERT tin nhắn giả mạo người gửi (SenderId <> UserId trong session) phải bị chặn 33504
SET @err = 0; SET @msg = NULL;
BEGIN TRAN;
INSERT INTO mkt.Listings (SellerId, CategoryId, ListingType, Title, Condition, Price, Quantity, City)
VALUES (@sl, @mc, N'Sell', N'Test17 tin đăng', N'Good', 1000000, 5, N'Test17');
SET @ml = SCOPE_IDENTITY();
EXEC sp_set_session_context N'UserId', @ox;
EXECUTE AS USER = N'u_blk';
BEGIN TRY
    INSERT INTO mkt.Messages (ListingId, SenderId, ReceiverId, Body) VALUES (@ml, @sl, @by, N'Test17 tin giả');
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
SET @e = (SELECT COUNT(*) FROM mkt.Messages WHERE Body = N'Test17 tin giả');
IF @@TRANCOUNT > 0 ROLLBACK;
IF @err = 33504 AND @e = 0 PRINT N'PASS: T69 BLOCK AFTER INSERT chặn tin nhắn giả mạo người gửi (33504)';
ELSE PRINT N'FAIL: T69 mkt.Messages INSERT giả mạo, mong đợi 33504, nhận ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi') + N'; dòng đã thêm=' + CAST(@e AS NVARCHAR(10));

-- T70: người lạ UPDATE ReadAt ảnh hưởng 0 dòng; người nhận UPDATE ReadAt thành công 1 dòng
SET @err = 0; SET @msg = NULL; SET @c = NULL; SET @k = NULL;
BEGIN TRAN;
INSERT INTO mkt.Listings (SellerId, CategoryId, ListingType, Title, Condition, Price, Quantity, City)
VALUES (@sl, @mc, N'Sell', N'Test17 tin đăng', N'Good', 1000000, 5, N'Test17');
SET @ml = SCOPE_IDENTITY();
INSERT INTO mkt.Messages (ListingId, SenderId, ReceiverId, Body) VALUES (@ml, @sl, @by, N'Test17 tin nhắn');
EXEC sp_set_session_context N'UserId', @ox;
EXECUTE AS USER = N'u_blk';
BEGIN TRY
    UPDATE mkt.Messages SET ReadAt = SYSUTCDATETIME() WHERE Body = N'Test17 tin nhắn';
    SET @c = @@ROWCOUNT;
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
EXEC sp_set_session_context N'UserId', @by;
EXECUTE AS USER = N'u_blk';
BEGIN TRY
    UPDATE mkt.Messages SET ReadAt = SYSUTCDATETIME() WHERE Body = N'Test17 tin nhắn';
    SET @k = @@ROWCOUNT;
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
SET @e = (SELECT COUNT(*) FROM mkt.Messages WHERE Body = N'Test17 tin nhắn' AND ReadAt IS NOT NULL);
IF @@TRANCOUNT > 0 ROLLBACK;
IF @err = 0 AND @c = 0 AND @k = 1 AND @e = 1 PRINT N'PASS: T70 người lạ UPDATE ReadAt 0 dòng, người nhận UPDATE ReadAt được (đã ROLLBACK)';
ELSE PRINT N'FAIL: T70 UPDATE ReadAt, lỗi ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi') + N'; người lạ=' + ISNULL(CAST(@c AS NVARCHAR(10)), N'NULL') + N', người nhận=' + ISNULL(CAST(@k AS NVARCHAR(10)), N'NULL') + N', đã đọc=' + CAST(@e AS NVARCHAR(10));

-- T71: fn_SellerRating và fn_SellerRatingCount (EXECUTE AS OWNER) vẫn đúng khi người gọi không thấy dòng giao dịch nào của người bán
SET @err = 0; SET @msg = NULL; SET @e = NULL; SET @rt = NULL; SET @rc = NULL;
BEGIN TRAN;
INSERT INTO mkt.Listings (SellerId, CategoryId, ListingType, Title, Condition, Price, Quantity, City)
VALUES (@sl, @mc, N'Sell', N'Test17 tin đăng', N'Good', 1000000, 5, N'Test17');
SET @ml = SCOPE_IDENTITY();
INSERT INTO mkt.MarketTransactions (TransactionCode, ListingId, SellerId, BuyerId, Quantity, UnitPrice, PlatformFee, Status, CompletedAt, BuyerRating, RatedAt)
VALUES (N'MK-T17-0001', @ml, @sl, @by, 1, 1000000, 50000, N'Completed', SYSUTCDATETIME(), 4, SYSUTCDATETIME());
SET @xt = (SELECT CAST(AVG(CAST(BuyerRating AS DECIMAL(5,2))) AS DECIMAL(3,2)) FROM mkt.MarketTransactions WHERE SellerId = @sl AND BuyerRating IS NOT NULL);
SET @xc = (SELECT COUNT(BuyerRating) FROM mkt.MarketTransactions WHERE SellerId = @sl);
EXEC sp_set_session_context N'UserId', @ox;
EXECUTE AS USER = N'u_blk';
BEGIN TRY
    SET @e = (SELECT COUNT(*) FROM mkt.MarketTransactions WHERE TransactionCode = N'MK-T17-0001');
    SET @rt = mkt.fn_SellerRating(@sl);
    SET @rc = mkt.fn_SellerRatingCount(@sl);
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @err = 0 AND @e = 0 AND @xc >= 1 AND @rt = @xt AND @rc = @xc PRINT N'PASS: T71 fn_SellerRating và fn_SellerRatingCount đúng dù người gọi không thấy giao dịch nào của người bán';
ELSE PRINT N'FAIL: T71 điểm người bán, lỗi ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi') + N'; thấy dòng=' + ISNULL(CAST(@e AS NVARCHAR(10)), N'NULL') + N', điểm=' + ISNULL(CAST(@rt AS NVARCHAR(10)), N'NULL') + N' (mong đợi ' + ISNULL(CAST(@xt AS NVARCHAR(10)), N'NULL') + N'), số lượt=' + ISNULL(CAST(@rc AS NVARCHAR(10)), N'NULL') + N' (mong đợi ' + ISNULL(CAST(@xc AS NVARCHAR(10)), N'NULL') + N')';

-- T72: người mua gọi mkt.sp_PlaceMarketOrder chạy được dưới BLOCK (procedure đặt UserId session = người mua), bọc ROLLBACK
SET @err = 0; SET @msg = NULL; SET @mt = NULL;
BEGIN TRAN;
INSERT INTO mkt.Listings (SellerId, CategoryId, ListingType, Title, Condition, Price, Quantity, City)
VALUES (@sl, @mc, N'Sell', N'Test17 tin đăng', N'Good', 1000000, 5, N'Test17');
SET @ml = SCOPE_IDENTITY();
EXECUTE AS USER = N'u_blk';
BEGIN TRY
    EXEC mkt.sp_PlaceMarketOrder @ListingId = @ml, @BuyerId = @by, @Quantity = 1, @NewTransactionId = @mt OUTPUT;
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
SET @e = (SELECT COUNT(*) FROM mkt.MarketTransactions WHERE TransactionId = @mt AND BuyerId = @by AND ListingId = @ml);
IF @@TRANCOUNT > 0 ROLLBACK;
IF @err = 0 AND @mt IS NOT NULL AND @e = 1 PRINT N'PASS: T72 người mua gọi mkt.sp_PlaceMarketOrder chạy được dưới BLOCK (đã ROLLBACK)';
ELSE PRINT N'FAIL: T72 mkt.sp_PlaceMarketOrder, lỗi ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi') + N'; giao dịch=' + ISNULL(CAST(@mt AS NVARCHAR(10)), N'NULL') + N', thấy=' + CAST(@e AS NVARCHAR(10));

-- T73: người gửi gọi mkt.sp_SendMessage chạy được dưới BLOCK (procedure đặt UserId session = người gửi), bọc ROLLBACK
SET @err = 0; SET @msg = NULL; SET @k = NULL;
BEGIN TRAN;
INSERT INTO mkt.Listings (SellerId, CategoryId, ListingType, Title, Condition, Price, Quantity, City)
VALUES (@sl, @mc, N'Sell', N'Test17 tin đăng', N'Good', 1000000, 5, N'Test17');
SET @ml = SCOPE_IDENTITY();
EXECUTE AS USER = N'u_blk';
BEGIN TRY
    EXEC mkt.sp_SendMessage @ListingId = @ml, @SenderId = @by, @ReceiverId = @sl, @Body = N'Test17 qua procedure', @NewMessageId = @k OUTPUT;
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
SET @e = (SELECT COUNT(*) FROM mkt.Messages WHERE MessageId = @k AND SenderId = @by AND ReceiverId = @sl);
IF @@TRANCOUNT > 0 ROLLBACK;
IF @err = 0 AND @k IS NOT NULL AND @e = 1 PRINT N'PASS: T73 người gửi gọi mkt.sp_SendMessage chạy được dưới BLOCK (đã ROLLBACK)';
ELSE PRINT N'FAIL: T73 mkt.sp_SendMessage, lỗi ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi') + N'; tin nhắn=' + ISNULL(CAST(@k AS NVARCHAR(10)), N'NULL') + N', thấy=' + CAST(@e AS NVARCHAR(10));

-- T74: hồi quy RLS: người mua hoàn tất giao dịch của mình, tin KHÔNG được thành Sold vì còn giao dịch Pending của người mua khác (người mua không thấy dòng đó nhưng procedure chạy OWNER vẫn thấy)
SET @err = 0; SET @msg = NULL; SET @mt = NULL; SET @e = NULL; SET @c = NULL;
BEGIN TRAN;
INSERT INTO mkt.Listings (SellerId, CategoryId, ListingType, Title, Condition, Price, Quantity, City, Status)
VALUES (@sl, @mc, N'Sell', N'Test17 tin đăng', N'Good', 1000000, 0, N'Test17', N'Reserved');
SET @ml = SCOPE_IDENTITY();
INSERT INTO mkt.MarketTransactions (TransactionCode, ListingId, SellerId, BuyerId, Quantity, UnitPrice, PlatformFee, Status, ShippedAt)
VALUES (N'MK-T17-0001', @ml, @sl, @by, 1, 1000000, 50000, N'Shipped', SYSUTCDATETIME());
SET @mt = SCOPE_IDENTITY();
INSERT INTO mkt.MarketTransactions (TransactionCode, ListingId, SellerId, BuyerId, Quantity, UnitPrice, PlatformFee)
VALUES (N'MK-T17-0002', @ml, @sl, @ox, 1, 1000000, 50000);
EXECUTE AS USER = N'u_blk';
BEGIN TRY
    EXEC mkt.sp_UpdateMarketTransaction @TransactionId = @mt, @ActorUserId = @by, @NewStatus = N'Completed';
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
SET @e = (SELECT COUNT(*) FROM mkt.MarketTransactions WHERE TransactionId = @mt AND Status = N'Completed');
SET @c = (SELECT COUNT(*) FROM mkt.Listings WHERE ListingId = @ml AND Status = N'Reserved');
IF @@TRANCOUNT > 0 ROLLBACK;
IF @err = 0 AND @e = 1 AND @c = 1 PRINT N'PASS: T74 hoàn tất giao dịch không làm tin thành Sold khi còn giao dịch khác (OWNER thấy đủ dòng)';
ELSE PRINT N'FAIL: T74 hồi quy Sold, lỗi ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi') + N'; giao dịch Completed=' + ISNULL(CAST(@e AS NVARCHAR(10)), N'NULL') + N', tin còn Reserved=' + ISNULL(CAST(@c AS NVARCHAR(10)), N'NULL');

-- T75: job role_System (UserId session NULL) gọi mkt.sp_RunMaintenance phải tự hoàn tất được giao dịch Shipped quá 7 ngày (OWNER bỏ qua RLS)
SET @err = 0; SET @msg = NULL; SET @mt = NULL; SET @e = NULL; SET @k = NULL; SET @k2 = NULL;
BEGIN TRAN;
INSERT INTO mkt.Listings (SellerId, CategoryId, ListingType, Title, Condition, Price, Quantity, City, Status)
VALUES (@sl, @mc, N'Sell', N'Test17 tin đăng', N'Good', 1000000, 0, N'Test17', N'Reserved');
SET @ml = SCOPE_IDENTITY();
INSERT INTO mkt.MarketTransactions (TransactionCode, ListingId, SellerId, BuyerId, Quantity, UnitPrice, PlatformFee, Status, ShippedAt)
VALUES (N'MK-T17-0001', @ml, @sl, @by, 1, 1000000, 50000, N'Shipped', DATEADD(DAY, -8, SYSUTCDATETIME()));
SET @mt = SCOPE_IDENTITY();
EXEC sp_set_session_context N'UserId', NULL;
EXECUTE AS USER = N'u_sys';
BEGIN TRY
    EXEC mkt.sp_RunMaintenance @ClosedListings = @k OUTPUT, @AutoCompleted = @k2 OUTPUT;
END TRY
BEGIN CATCH
    SET @err = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
END CATCH
IF USER_NAME() <> N'dbo' REVERT;
SET @e = (SELECT COUNT(*) FROM mkt.MarketTransactions WHERE TransactionId = @mt AND Status = N'Completed');
IF @@TRANCOUNT > 0 ROLLBACK;
EXEC sp_set_session_context N'UserId', NULL;
IF @err = 0 AND @k2 >= 1 AND @e = 1 PRINT N'PASS: T75 role_System chạy mkt.sp_RunMaintenance tự hoàn tất giao dịch Shipped quá 7 ngày (đã ROLLBACK)';
ELSE PRINT N'FAIL: T75 mkt.sp_RunMaintenance role_System, lỗi ' + CAST(@err AS NVARCHAR(10)) + N': ' + ISNULL(@msg, N'không lỗi') + N'; tự hoàn tất=' + ISNULL(CAST(@k2 AS NVARCHAR(10)), N'NULL') + N', giao dịch Completed=' + ISNULL(CAST(@e AS NVARCHAR(10)), N'NULL');

DROP USER u_adm4;

-- Dọn
EXEC sp_set_session_context N'UserId', NULL;
DROP USER u_blk;

DROP USER u_sys;