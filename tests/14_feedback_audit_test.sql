USE FilmLabDB;
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF OBJECT_ID('tempdb..#mk') IS NOT NULL DROP PROCEDURE #mk;
GO
-- Helper: ép một đơn chưa có review sang Completed rồi tạo review (gọi TRONG BEGIN TRAN của test)
CREATE PROCEDURE #mk @Rid INT OUTPUT, @Cust INT OUTPUT, @Lab INT OUTPUT, @Owner INT OUTPUT, @Oid INT OUTPUT, @Hide BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP 1 @Oid = o.OrderId, @Cust = o.CustomerId, @Lab = o.LabId
    FROM ord.Orders o
    WHERE o.IsDeleted = 0 AND NOT EXISTS (SELECT 1 FROM ord.Reviews r WHERE r.OrderId = o.OrderId)
    ORDER BY o.OrderId;
    SELECT @Owner = OwnerUserId FROM lab.FilmLabs WHERE LabId = @Lab;
    DISABLE TRIGGER ord.trg_Orders_PreventInvalidStage ON ord.Orders;
    UPDATE ord.Orders SET StageId = 12, CompletedAt = SYSUTCDATETIME() WHERE OrderId = @Oid;
    EXEC ord.sp_AddReview @OrderId = @Oid, @CustomerId = @Cust, @RatingOverall = 4, @Comment = N'Test', @NewReviewId = @Rid OUTPUT;
    IF @Hide = 1
        EXEC ord.sp_ModerateReview @ReviewId = @Rid, @AdminUserId = 1, @Action = N'Hide', @Reason = N'Test';
END
GO

-- A1 fn_LabAvgRating: lab không có review -> NULL
DECLARE @v DECIMAL(3,2) = ord.fn_LabAvgRating(2147483647);
PRINT CASE WHEN @v IS NULL THEN N'PASS: fn_LabAvgRating NULL khi chưa có review' ELSE N'FAIL: fn_LabAvgRating NULL' END;
GO

-- A2 fn_LabAvgRating = trung bình review hiển thị
DECLARE @Rid INT, @Cust INT, @Lab INT, @Owner INT, @Oid INT, @ok BIT;
BEGIN TRAN;
EXEC #mk @Rid OUTPUT, @Cust OUTPUT, @Lab OUTPUT, @Owner OUTPUT, @Oid OUTPUT;
SET @ok = CASE WHEN ord.fn_LabAvgRating(@Lab) IS NOT NULL
                AND ord.fn_LabAvgRating(@Lab) = (SELECT CAST(AVG(CAST(RatingOverall AS DECIMAL(5,2))) AS DECIMAL(3,2))
                                                 FROM ord.Reviews WHERE LabId = @Lab AND IsVisible = 1 AND IsDeleted = 0)
               THEN 1 ELSE 0 END;
ROLLBACK;
PRINT CASE WHEN @ok = 1 THEN N'PASS: fn_LabAvgRating đúng trung bình review hiển thị' ELSE N'FAIL: fn_LabAvgRating trung bình' END;
GO

-- B1 sp_ReplyReview thành công
DECLARE @Rid INT, @Cust INT, @Lab INT, @Owner INT, @Oid INT, @ok BIT;
BEGIN TRAN;
EXEC #mk @Rid OUTPUT, @Cust OUTPUT, @Lab OUTPUT, @Owner OUTPUT, @Oid OUTPUT;
EXEC ord.sp_ReplyReview @ReviewId = @Rid, @LabOwnerId = @Owner, @Reply = N'Cảm ơn bạn';
SET @ok = CASE WHEN EXISTS (SELECT 1 FROM ord.Reviews WHERE ReviewId = @Rid AND LabReply = N'Cảm ơn bạn' AND LabRepliedAt IS NOT NULL) THEN 1 ELSE 0 END;
ROLLBACK;
PRINT CASE WHEN @ok = 1 THEN N'PASS: sp_ReplyReview ghi LabReply + LabRepliedAt' ELSE N'FAIL: sp_ReplyReview thành công' END;
GO

-- B2 sp_ReplyReview gửi thông báo cho khách (+1)
DECLARE @Rid INT, @Cust INT, @Lab INT, @Owner INT, @Oid INT, @n0 INT, @n1 INT;
BEGIN TRAN;
EXEC #mk @Rid OUTPUT, @Cust OUTPUT, @Lab OUTPUT, @Owner OUTPUT, @Oid OUTPUT;
SELECT @n0 = COUNT(*) FROM arc.Notifications WHERE UserId = @Cust;
EXEC ord.sp_ReplyReview @ReviewId = @Rid, @LabOwnerId = @Owner, @Reply = N'Cảm ơn bạn';
SELECT @n1 = COUNT(*) FROM arc.Notifications WHERE UserId = @Cust;
ROLLBACK;
PRINT CASE WHEN @n1 = @n0 + 1 THEN N'PASS: sp_ReplyReview thông báo cho khách' ELSE N'FAIL: sp_ReplyReview thông báo' END;
GO

-- B3 trả lời lần 2 -> 50304
DECLARE @Rid INT, @Cust INT, @Lab INT, @Owner INT, @Oid INT, @e INT = 0;
BEGIN TRY
    BEGIN TRAN;
    EXEC #mk @Rid OUTPUT, @Cust OUTPUT, @Lab OUTPUT, @Owner OUTPUT, @Oid OUTPUT;
    EXEC ord.sp_ReplyReview @ReviewId = @Rid, @LabOwnerId = @Owner, @Reply = N'Lần 1';
    EXEC ord.sp_ReplyReview @ReviewId = @Rid, @LabOwnerId = @Owner, @Reply = N'Lần 2';
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;
PRINT CASE WHEN @e = 50304 THEN N'PASS: sp_ReplyReview lần 2 -> 50304' ELSE N'FAIL: sp_ReplyReview lần 2, got ' + CAST(@e AS NVARCHAR(10)) END;
GO

-- B4 không phải chủ lab -> 50303
DECLARE @Rid INT, @Cust INT, @Lab INT, @Owner INT, @Oid INT, @e INT = 0;
BEGIN TRY
    BEGIN TRAN;
    EXEC #mk @Rid OUTPUT, @Cust OUTPUT, @Lab OUTPUT, @Owner OUTPUT, @Oid OUTPUT;
    EXEC ord.sp_ReplyReview @ReviewId = @Rid, @LabOwnerId = @Cust, @Reply = N'Không phải chủ lab';
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;
PRINT CASE WHEN @e = 50303 THEN N'PASS: sp_ReplyReview không phải chủ lab -> 50303' ELSE N'FAIL: sp_ReplyReview 50303, got ' + CAST(@e AS NVARCHAR(10)) END;
GO

-- B5 review không tồn tại -> 50301
DECLARE @e INT = 0;
BEGIN TRY
    EXEC ord.sp_ReplyReview @ReviewId = 0, @LabOwnerId = 2, @Reply = N'x';
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;
PRINT CASE WHEN @e = 50301 THEN N'PASS: sp_ReplyReview không tồn tại -> 50301' ELSE N'FAIL: sp_ReplyReview 50301, got ' + CAST(@e AS NVARCHAR(10)) END;
GO

-- B6 nội dung rỗng -> 50305
DECLARE @Rid INT, @Cust INT, @Lab INT, @Owner INT, @Oid INT, @e INT = 0;
BEGIN TRY
    BEGIN TRAN;
    EXEC #mk @Rid OUTPUT, @Cust OUTPUT, @Lab OUTPUT, @Owner OUTPUT, @Oid OUTPUT;
    EXEC ord.sp_ReplyReview @ReviewId = @Rid, @LabOwnerId = @Owner, @Reply = N'   ';
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;
PRINT CASE WHEN @e = 50305 THEN N'PASS: sp_ReplyReview rỗng -> 50305' ELSE N'FAIL: sp_ReplyReview 50305, got ' + CAST(@e AS NVARCHAR(10)) END;
GO

-- B7 review đang ẩn -> 50302
DECLARE @Rid INT, @Cust INT, @Lab INT, @Owner INT, @Oid INT, @e INT = 0;
BEGIN TRY
    BEGIN TRAN;
    EXEC #mk @Rid OUTPUT, @Cust OUTPUT, @Lab OUTPUT, @Owner OUTPUT, @Oid OUTPUT, 1;
    EXEC ord.sp_ReplyReview @ReviewId = @Rid, @LabOwnerId = @Owner, @Reply = N'Trả lời review ẩn';
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;
PRINT CASE WHEN @e = 50302 THEN N'PASS: sp_ReplyReview review ẩn -> 50302' ELSE N'FAIL: sp_ReplyReview 50302, got ' + CAST(@e AS NVARCHAR(10)) END;
GO

-- C1 Hide thành công
DECLARE @Rid INT, @Cust INT, @Lab INT, @Owner INT, @Oid INT, @ok BIT;
BEGIN TRAN;
EXEC #mk @Rid OUTPUT, @Cust OUTPUT, @Lab OUTPUT, @Owner OUTPUT, @Oid OUTPUT;
EXEC ord.sp_ModerateReview @ReviewId = @Rid, @AdminUserId = 1, @Action = N'Hide', @Reason = N'Vi phạm';
SET @ok = CASE WHEN EXISTS (SELECT 1 FROM ord.Reviews WHERE ReviewId = @Rid AND IsVisible = 0
                            AND ModerationReason = N'Vi phạm' AND ModeratedBy = 1 AND ModeratedAt IS NOT NULL) THEN 1 ELSE 0 END;
ROLLBACK;
PRINT CASE WHEN @ok = 1 THEN N'PASS: sp_ModerateReview Hide' ELSE N'FAIL: sp_ModerateReview Hide' END;
GO

-- C2 Sau Hide, AvgRating của lab khớp fn_LabAvgRating
DECLARE @Rid INT, @Cust INT, @Lab INT, @Owner INT, @Oid INT, @ok BIT;
BEGIN TRAN;
EXEC #mk @Rid OUTPUT, @Cust OUTPUT, @Lab OUTPUT, @Owner OUTPUT, @Oid OUTPUT, 1;
SET @ok = CASE WHEN ISNULL(ord.fn_LabAvgRating(@Lab), 0) = (SELECT AvgRating FROM lab.FilmLabs WHERE LabId = @Lab) THEN 1 ELSE 0 END;
ROLLBACK;
PRINT CASE WHEN @ok = 1 THEN N'PASS: Hide tính lại AvgRating khớp fn_LabAvgRating' ELSE N'FAIL: Hide tính lại AvgRating' END;
GO

-- C3 Show thành công
DECLARE @Rid INT, @Cust INT, @Lab INT, @Owner INT, @Oid INT, @ok BIT;
BEGIN TRAN;
EXEC #mk @Rid OUTPUT, @Cust OUTPUT, @Lab OUTPUT, @Owner OUTPUT, @Oid OUTPUT, 1;
EXEC ord.sp_ModerateReview @ReviewId = @Rid, @AdminUserId = 1, @Action = N'Show';
SET @ok = CASE WHEN EXISTS (SELECT 1 FROM ord.Reviews WHERE ReviewId = @Rid AND IsVisible = 1 AND ModerationReason IS NULL) THEN 1 ELSE 0 END;
ROLLBACK;
PRINT CASE WHEN @ok = 1 THEN N'PASS: sp_ModerateReview Show' ELSE N'FAIL: sp_ModerateReview Show' END;
GO

-- C4 Hide thiếu Reason -> 50305
DECLARE @Rid INT, @Cust INT, @Lab INT, @Owner INT, @Oid INT, @e INT = 0;
BEGIN TRY
    BEGIN TRAN;
    EXEC #mk @Rid OUTPUT, @Cust OUTPUT, @Lab OUTPUT, @Owner OUTPUT, @Oid OUTPUT;
    EXEC ord.sp_ModerateReview @ReviewId = @Rid, @AdminUserId = 1, @Action = N'Hide';
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;
PRINT CASE WHEN @e = 50305 THEN N'PASS: sp_ModerateReview Hide thiếu Reason -> 50305' ELSE N'FAIL: sp_ModerateReview 50305 Reason, got ' + CAST(@e AS NVARCHAR(10)) END;
GO

-- C5 Hide khi đã ẩn -> 50302
DECLARE @Rid INT, @Cust INT, @Lab INT, @Owner INT, @Oid INT, @e INT = 0;
BEGIN TRY
    BEGIN TRAN;
    EXEC #mk @Rid OUTPUT, @Cust OUTPUT, @Lab OUTPUT, @Owner OUTPUT, @Oid OUTPUT, 1;
    EXEC ord.sp_ModerateReview @ReviewId = @Rid, @AdminUserId = 1, @Action = N'Hide', @Reason = N'Lần 2';
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;
PRINT CASE WHEN @e = 50302 THEN N'PASS: sp_ModerateReview Hide hai lần -> 50302' ELSE N'FAIL: sp_ModerateReview 50302, got ' + CAST(@e AS NVARCHAR(10)) END;
GO

-- C6 không phải Admin -> 50303
DECLARE @Rid INT, @Cust INT, @Lab INT, @Owner INT, @Oid INT, @e INT = 0;
BEGIN TRY
    BEGIN TRAN;
    EXEC #mk @Rid OUTPUT, @Cust OUTPUT, @Lab OUTPUT, @Owner OUTPUT, @Oid OUTPUT;
    EXEC ord.sp_ModerateReview @ReviewId = @Rid, @AdminUserId = @Cust, @Action = N'Hide', @Reason = N'x';
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;
PRINT CASE WHEN @e = 50303 THEN N'PASS: sp_ModerateReview không phải Admin -> 50303' ELSE N'FAIL: sp_ModerateReview 50303, got ' + CAST(@e AS NVARCHAR(10)) END;
GO

-- C7 Action sai -> 50305
DECLARE @Rid INT, @Cust INT, @Lab INT, @Owner INT, @Oid INT, @e INT = 0;
BEGIN TRY
    BEGIN TRAN;
    EXEC #mk @Rid OUTPUT, @Cust OUTPUT, @Lab OUTPUT, @Owner OUTPUT, @Oid OUTPUT;
    EXEC ord.sp_ModerateReview @ReviewId = @Rid, @AdminUserId = 1, @Action = N'Del', @Reason = N'x';
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;
PRINT CASE WHEN @e = 50305 THEN N'PASS: sp_ModerateReview Action sai -> 50305' ELSE N'FAIL: sp_ModerateReview 50305 Action, got ' + CAST(@e AS NVARCHAR(10)) END;
GO

-- C8 review không tồn tại -> 50301
DECLARE @e INT = 0;
BEGIN TRY
    EXEC ord.sp_ModerateReview @ReviewId = 0, @AdminUserId = 1, @Action = N'Hide', @Reason = N'x';
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;
PRINT CASE WHEN @e = 50301 THEN N'PASS: sp_ModerateReview không tồn tại -> 50301' ELSE N'FAIL: sp_ModerateReview 50301, got ' + CAST(@e AS NVARCHAR(10)) END;
GO

-- D1 FeeConfigs chồng khoảng -> 50304
DECLARE @Lab INT = (SELECT MIN(LabId) FROM lab.FilmLabs), @e INT = 0;
BEGIN TRY
    BEGIN TRAN;
    INSERT ord.FeeConfigs (FeeType, FixedAmount, ScopeLabId, EffectiveFrom, EffectiveTo, CreatedBy)
    VALUES (N'DeliveryBase', 1000, @Lab, '2035-01-01', '2035-12-31', 1);
    INSERT ord.FeeConfigs (FeeType, FixedAmount, ScopeLabId, EffectiveFrom, EffectiveTo, CreatedBy)
    VALUES (N'DeliveryBase', 2000, @Lab, '2035-06-01', NULL, 1);
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;
PRINT CASE WHEN @e = 50304 THEN N'PASS: trg_FeeConfigs_NoOverlap INSERT chồng -> 50304' ELSE N'FAIL: FeeConfigs INSERT chồng, got ' + CAST(@e AS NVARCHAR(10)) END;
GO

-- D2 FeeConfigs liền kề, không chồng -> OK
DECLARE @Lab INT = (SELECT MIN(LabId) FROM lab.FilmLabs), @n INT = 0;
BEGIN TRAN;
INSERT ord.FeeConfigs (FeeType, FixedAmount, ScopeLabId, EffectiveFrom, EffectiveTo, CreatedBy)
VALUES (N'DeliveryBase', 1000, @Lab, '2035-01-01', '2035-12-31', 1);
INSERT ord.FeeConfigs (FeeType, FixedAmount, ScopeLabId, EffectiveFrom, EffectiveTo, CreatedBy)
VALUES (N'DeliveryBase', 2000, @Lab, '2036-01-01', NULL, 1);
SELECT @n = COUNT(*) FROM ord.FeeConfigs WHERE ScopeLabId = @Lab AND FeeType = N'DeliveryBase' AND EffectiveFrom >= '2035-01-01';
ROLLBACK;
PRINT CASE WHEN @n = 2 THEN N'PASS: FeeConfigs liền kề được phép' ELSE N'FAIL: FeeConfigs liền kề' END;
GO

-- D3 FeeConfigs UPDATE gây chồng -> 50304
DECLARE @Lab INT = (SELECT MIN(LabId) FROM lab.FilmLabs), @e INT = 0;
BEGIN TRY
    BEGIN TRAN;
    INSERT ord.FeeConfigs (FeeType, FixedAmount, ScopeLabId, EffectiveFrom, EffectiveTo, CreatedBy)
    VALUES (N'DeliveryBase', 1000, @Lab, '2035-01-01', '2035-12-31', 1);
    INSERT ord.FeeConfigs (FeeType, FixedAmount, ScopeLabId, EffectiveFrom, EffectiveTo, CreatedBy)
    VALUES (N'DeliveryBase', 2000, @Lab, '2036-01-01', NULL, 1);
    UPDATE ord.FeeConfigs SET EffectiveFrom = '2035-06-01'
    WHERE ScopeLabId = @Lab AND FeeType = N'DeliveryBase' AND EffectiveFrom = '2036-01-01';
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;
PRINT CASE WHEN @e = 50304 THEN N'PASS: trg_FeeConfigs_NoOverlap UPDATE chồng -> 50304' ELSE N'FAIL: FeeConfigs UPDATE chồng, got ' + CAST(@e AS NVARCHAR(10)) END;
GO

-- E1 trg_Payments_Audit ghi 1 dòng khi đổi Status
DECLARE @Oid INT, @Amt DECIMAL(18,0), @Pid INT, @n INT, @by INT;
SELECT TOP 1 @Oid = OrderId, @Amt = TotalAmount FROM ord.Orders
WHERE IsDeleted = 0 AND PaymentStatus = N'Unpaid' AND TotalAmount > 0 ORDER BY OrderId;
EXEC sp_set_session_context @key = N'UserId', @value = 1;
BEGIN TRAN;
INSERT ord.Payments (OrderId, Method, Amount, Status) VALUES (@Oid, N'Card', @Amt, N'Pending');
SET @Pid = SCOPE_IDENTITY();
UPDATE ord.Payments SET Status = N'Succeeded', PaidAt = SYSUTCDATETIME() WHERE PaymentId = @Pid;
SELECT @n = COUNT(*), @by = MAX(ChangedBy) FROM audit.AuditLogs
WHERE TableSchema = N'ord' AND TableName = N'Payments' AND PrimaryKeyValue = CAST(@Pid AS NVARCHAR(100)) AND Action = N'UPDATE';
ROLLBACK;
PRINT CASE WHEN @n = 1 AND @by = 1 THEN N'PASS: trg_Payments_Audit ghi UPDATE kèm ChangedBy' ELSE N'FAIL: trg_Payments_Audit' END;
GO

-- E2 Payments đổi cột không theo dõi (Provider) -> không ghi thêm
DECLARE @Oid INT, @Amt DECIMAL(18,0), @Pid INT, @n INT;
SELECT TOP 1 @Oid = OrderId, @Amt = TotalAmount FROM ord.Orders
WHERE IsDeleted = 0 AND PaymentStatus = N'Unpaid' AND TotalAmount > 0 ORDER BY OrderId;
EXEC sp_set_session_context @key = N'UserId', @value = 1;
BEGIN TRAN;
INSERT ord.Payments (OrderId, Method, Amount, Status) VALUES (@Oid, N'Card', @Amt, N'Pending');
SET @Pid = SCOPE_IDENTITY();
UPDATE ord.Payments SET Provider = N'VNPay' WHERE PaymentId = @Pid;
SELECT @n = COUNT(*) FROM audit.AuditLogs
WHERE TableSchema = N'ord' AND TableName = N'Payments' AND PrimaryKeyValue = CAST(@Pid AS NVARCHAR(100));
ROLLBACK;
PRINT CASE WHEN @n = 0 THEN N'PASS: trg_Payments_Audit bỏ qua cột không theo dõi' ELSE N'FAIL: trg_Payments_Audit cột không theo dõi' END;
GO

-- F1 trg_Users_Audit ghi khi đổi FullName
DECLARE @n INT, @by INT;
EXEC sp_set_session_context @key = N'UserId', @value = 1;
BEGIN TRAN;
UPDATE iam.Users SET FullName = FullName + N' (test)' WHERE UserId = 6;
SELECT @n = COUNT(*), @by = MAX(ChangedBy) FROM audit.AuditLogs
WHERE TableSchema = N'iam' AND TableName = N'Users' AND PrimaryKeyValue = N'6' AND Action = N'UPDATE'
  AND NewValues LIKE N'%(test)%';
ROLLBACK;
PRINT CASE WHEN @n = 1 AND @by = 1 THEN N'PASS: trg_Users_Audit ghi đổi FullName' ELSE N'FAIL: trg_Users_Audit FullName' END;
GO

-- F2 trg_Users_Audit không lộ PasswordHash, có cờ PasswordChanged
DECLARE @ok BIT;
EXEC sp_set_session_context @key = N'UserId', @value = 1;
BEGIN TRAN;
UPDATE iam.Users SET PasswordHash = N'hash-test-xyz' WHERE UserId = 6;
SET @ok = CASE WHEN EXISTS (SELECT 1 FROM audit.AuditLogs
                            WHERE TableSchema = N'iam' AND TableName = N'Users' AND PrimaryKeyValue = N'6'
                              AND NewValues LIKE N'%"PasswordChanged":true%'
                              AND NewValues NOT LIKE N'%hash-test-xyz%'
                              AND OldValues NOT LIKE N'%PasswordHash%'
                              AND NewValues NOT LIKE N'%"PasswordHash"%') THEN 1 ELSE 0 END;
ROLLBACK;
PRINT CASE WHEN @ok = 1 THEN N'PASS: trg_Users_Audit không ghi PasswordHash' ELSE N'FAIL: trg_Users_Audit PasswordHash' END;
GO

-- F3 trg_Users_Audit bỏ qua LastLoginAt
DECLARE @n INT;
EXEC sp_set_session_context @key = N'UserId', @value = 1;
BEGIN TRAN;
UPDATE iam.Users SET LastLoginAt = SYSUTCDATETIME() WHERE UserId = 6;
SELECT @n = COUNT(*) FROM audit.AuditLogs WHERE TableSchema = N'iam' AND TableName = N'Users' AND PrimaryKeyValue = N'6';
ROLLBACK;
PRINT CASE WHEN @n = 0 THEN N'PASS: trg_Users_Audit bỏ qua LastLoginAt' ELSE N'FAIL: trg_Users_Audit LastLoginAt' END;
GO

-- V1 ord.vw_LabReviews
DECLARE @Rid INT, @Cust INT, @Lab INT, @Owner INT, @Oid INT, @ok BIT;
BEGIN TRAN;
EXEC #mk @Rid OUTPUT, @Cust OUTPUT, @Lab OUTPUT, @Owner OUTPUT, @Oid OUTPUT;
SET @ok = CASE WHEN EXISTS (SELECT 1 FROM ord.vw_LabReviews WHERE ReviewId = @Rid AND LabName IS NOT NULL AND CustomerName IS NOT NULL) THEN 1 ELSE 0 END;
ROLLBACK;
PRINT CASE WHEN @ok = 1 THEN N'PASS: vw_LabReviews có review mới' ELSE N'FAIL: vw_LabReviews' END;
GO

-- V2 ord.vw_OpenComplaints
DECLARE @Rid INT, @Cust INT, @Lab INT, @Owner INT, @Oid INT, @Cid INT, @ok BIT;
BEGIN TRAN;
EXEC #mk @Rid OUTPUT, @Cust OUTPUT, @Lab OUTPUT, @Owner OUTPUT, @Oid OUTPUT;
EXEC ord.sp_FileComplaint @OrderId = @Oid, @CustomerId = @Cust, @Category = N'Service',
                          @Title = N'Test khiếu nại', @Description = N'Nội dung test', @NewComplaintId = @Cid OUTPUT;
SET @ok = CASE WHEN EXISTS (SELECT 1 FROM ord.vw_OpenComplaints WHERE ComplaintId = @Cid AND Status = N'Open') THEN 1 ELSE 0 END;
ROLLBACK;
PRINT CASE WHEN @ok = 1 THEN N'PASS: vw_OpenComplaints có khiếu nại Open' ELSE N'FAIL: vw_OpenComplaints' END;
GO

-- V3 ord.vw_OrdersInProgress (giai đoạn 5 có, giai đoạn 12 không)
DECLARE @Oid INT, @a BIT, @b BIT;
SELECT TOP 1 @Oid = OrderId FROM ord.Orders WHERE IsDeleted = 0 ORDER BY OrderId;
BEGIN TRAN;
DISABLE TRIGGER ord.trg_Orders_PreventInvalidStage ON ord.Orders;
UPDATE ord.Orders SET StageId = 5 WHERE OrderId = @Oid;
SET @a = CASE WHEN EXISTS (SELECT 1 FROM ord.vw_OrdersInProgress WHERE OrderId = @Oid AND StageCode IS NOT NULL) THEN 1 ELSE 0 END;
UPDATE ord.Orders SET StageId = 12, CompletedAt = SYSUTCDATETIME() WHERE OrderId = @Oid;
SET @b = CASE WHEN EXISTS (SELECT 1 FROM ord.vw_OrdersInProgress WHERE OrderId = @Oid) THEN 0 ELSE 1 END;
ROLLBACK;
PRINT CASE WHEN @a = 1 AND @b = 1 THEN N'PASS: vw_OrdersInProgress lọc đúng giai đoạn' ELSE N'FAIL: vw_OrdersInProgress' END;
GO

-- V4 ord.vw_LabRevenue
DECLARE @Oid INT, @Lab INT, @ok BIT;
SELECT TOP 1 @Oid = OrderId, @Lab = LabId FROM ord.Orders WHERE IsDeleted = 0 ORDER BY OrderId;
BEGIN TRAN;
DISABLE TRIGGER ord.trg_Orders_PreventInvalidStage ON ord.Orders;
UPDATE ord.Orders SET StageId = 12, CompletedAt = SYSUTCDATETIME(), PaymentStatus = N'Paid' WHERE OrderId = @Oid;
SET @ok = CASE WHEN EXISTS (
    SELECT 1 FROM ord.vw_LabRevenue v
    WHERE v.LabId = @Lab
      AND v.CompletedOrders = (SELECT COUNT(*) FROM ord.Orders WHERE LabId = @Lab AND StageId = 12 AND IsDeleted = 0)
      AND v.NetRevenue = (SELECT SUM(Subtotal - PlatformFee) FROM ord.Orders
                          WHERE LabId = @Lab AND StageId = 12 AND PaymentStatus = N'Paid' AND IsDeleted = 0)) THEN 1 ELSE 0 END;
ROLLBACK;
PRINT CASE WHEN @ok = 1 THEN N'PASS: vw_LabRevenue đúng số đơn và doanh thu ròng' ELSE N'FAIL: vw_LabRevenue' END;
GO

-- V5 dlv.vw_DeliveryBoard
DECLARE @a INT, @b INT;
SELECT @a = COUNT(*) FROM dlv.vw_DeliveryBoard;
SELECT @b = COUNT(*) FROM dlv.DeliveryRequests dr JOIN ord.Orders o ON o.OrderId = dr.OrderId AND o.IsDeleted = 0
WHERE dr.IsDeleted = 0 AND dr.Status IN (N'Requested', N'Assigned', N'PickedUp');
PRINT CASE WHEN @a = @b THEN N'PASS: vw_DeliveryBoard khớp chặng đang mở' ELSE N'FAIL: vw_DeliveryBoard' END;
GO

-- V6 audit.vw_RecentChanges
DECLARE @ok BIT;
EXEC sp_set_session_context @key = N'UserId', @value = 1;
BEGIN TRAN;
UPDATE iam.Users SET FullName = FullName + N' (v)' WHERE UserId = 6;
SET @ok = CASE WHEN EXISTS (SELECT 1 FROM audit.vw_RecentChanges
                            WHERE TableName = N'Users' AND PrimaryKeyValue = N'6' AND ChangedByName IS NOT NULL) THEN 1 ELSE 0 END;
ROLLBACK;
PRINT CASE WHEN @ok = 1 THEN N'PASS: vw_RecentChanges thấy thay đổi mới kèm tên người đổi' ELSE N'FAIL: vw_RecentChanges' END;
GO

-- V7 audit.vw_AdminDashboard
DECLARE @rows INT, @ok BIT;
SELECT @rows = COUNT(*) FROM audit.vw_AdminDashboard;
SET @ok = CASE WHEN EXISTS (SELECT 1 FROM audit.vw_AdminDashboard
                            WHERE TotalUsers = (SELECT COUNT(*) FROM iam.Users WHERE IsDeleted = 0)) THEN 1 ELSE 0 END;
PRINT CASE WHEN @rows = 1 AND @ok = 1 THEN N'PASS: vw_AdminDashboard một dòng, TotalUsers đúng' ELSE N'FAIL: vw_AdminDashboard' END;
GO