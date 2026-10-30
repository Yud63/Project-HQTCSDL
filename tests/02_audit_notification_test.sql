USE FilmLabDB;
GO
SET NOCOUNT ON;

BEGIN TRAN;

DECLARE @uid INT = (SELECT UserId FROM iam.Users WHERE Email = N'an.nguyen@example.com');
DECLARE @nid INT, @before BIGINT = (SELECT ISNULL(MAX(AuditLogId), 0) FROM audit.AuditLogs);
EXEC sp_set_session_context @key = N'UserId', @value = @uid;

-- Trường hợp đúng
EXEC audit.sp_WriteAudit N'ord', N'Orders', N'1', N'UPDATE', N'{"StageId":1}', N'{"StageId":2}';
EXEC arc.sp_CreateNotification @UserId = @uid, @Type = N'System', @Title = N'Test', @NewNotificationId = @nid OUTPUT;

IF EXISTS (SELECT 1 FROM audit.AuditLogs WHERE AuditLogId > @before AND ChangedBy = @uid)
   AND EXISTS (SELECT 1 FROM arc.Notifications WHERE NotificationId = @nid AND UserId = @uid)
    PRINT N'PASS: ghi audit và tạo notification';
ELSE
    PRINT N'FAIL: ghi audit và tạo notification';

-- Trường hợp lỗi: mong đợi 50905, 50505, 50501, 50501
DECLARE @e INT;
SET @e = 0; BEGIN TRY EXEC audit.sp_WriteAudit N'ord', N'Orders', N'1', N'INSERT', N'{"a":1}'; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
PRINT IIF(@e = 50905, N'PASS: audit INSERT có OldValues -> 50905', N'FAIL: audit, nhận ' + CAST(@e AS NVARCHAR(10)));

SET @e = 0; BEGIN TRY EXEC arc.sp_CreateNotification @UserId = @uid, @Type = N'Foo', @Title = N'x'; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
PRINT IIF(@e = 50505, N'PASS: Type sai -> 50505', N'FAIL: Type, nhận ' + CAST(@e AS NVARCHAR(10)));

SET @e = 0; BEGIN TRY EXEC arc.sp_CreateNotification @UserId = -1, @Type = N'System', @Title = N'x'; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
PRINT IIF(@e = 50501, N'PASS: user không tồn tại -> 50501', N'FAIL: user, nhận ' + CAST(@e AS NVARCHAR(10)));

SET @e = 0; BEGIN TRY EXEC arc.sp_CreateNotification @UserId = @uid, @Type = N'System', @Title = N'x', @OrderId = -1; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
PRINT IIF(@e = 50501, N'PASS: đơn không tồn tại -> 50501', N'FAIL: đơn, nhận ' + CAST(@e AS NVARCHAR(10)));

ROLLBACK;
GO