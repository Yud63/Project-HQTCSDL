/* ============================================================
   File    : tests/17_security_test.sql
   Purpose : Kiểm tra GRANT/DENY, RLS, Data Masking cho 5 role (Đợt 7). Mong đợi 16 PASS.
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