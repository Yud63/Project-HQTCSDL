USE FilmLabDB;
GO
SET NOCOUNT ON;

DECLARE @o1 INT = (SELECT OrderId FROM ord.Orders WHERE OrderCode = N'FL-2026-000001');
DECLARE @o2 INT = (SELECT OrderId FROM ord.Orders WHERE OrderCode = N'FL-2026-000002');
DECLARE @o3 INT = (SELECT OrderId FROM ord.Orders WHERE OrderCode = N'FL-2026-000003');
DECLARE @o4 INT = (SELECT OrderId FROM ord.Orders WHERE OrderCode = N'FL-2026-000004');
DECLARE @saigon INT = (SELECT UserId FROM iam.Users WHERE Email = N'lab.saigon@filmlab.vn');
DECLARE @hanoi  INT = (SELECT UserId FROM iam.Users WHERE Email = N'lab.hanoi@filmlab.vn');
DECLARE @an     INT = (SELECT UserId FROM iam.Users WHERE Email = N'an.nguyen@example.com');
DECLARE @e INT, @logs INT, @noti INT;

-- 1. fn_NextStage: đơn chỉ tráng bỏ qua Scan (7 -> 10); đơn tráng + scan đi đủ (7 -> 8; 4 -> 5)
IF ord.fn_NextStage(@o2, 7) = 10 AND ord.fn_NextStage(@o1, 7) = 8 AND ord.fn_NextStage(@o1, 4) = 5
    PRINT N'PASS: fn_NextStage bỏ qua bước không áp dụng';
ELSE PRINT N'FAIL: fn_NextStage';

-- 2. fn_IsValidTransition
IF ord.fn_IsValidTransition(@o2, 5, 6) = 1 AND ord.fn_IsValidTransition(@o2, 5, 7) = 0
   AND ord.fn_IsValidTransition(@o2, 5, 4) = 0 AND ord.fn_IsValidTransition(@o2, 5, 13) = 0
   AND ord.fn_IsValidTransition(@o4, 1, 13) = 1 AND ord.fn_IsValidTransition(@o4, 12, 13) = 0
    PRINT N'PASS: fn_IsValidTransition (tiến đúng bước, không lùi/nhảy, hủy chỉ trước Developing)';
ELSE PRINT N'FAIL: fn_IsValidTransition';

-- 3. sp đúng: lab Sài Gòn đưa đơn 000002 từ 5 sang 6, có log + thông báo
SET @e = 0;
BEGIN TRAN;
BEGIN TRY
    SET @logs = (SELECT COUNT(*) FROM ord.OrderStageLog WHERE OrderId = @o2);
    SET @noti = (SELECT COUNT(*) FROM arc.Notifications WHERE OrderId = @o2);
    EXEC ord.sp_UpdateOrderStage @o2, @saigon, 6, N'Bắt đầu rửa';
    IF (SELECT StageId FROM ord.Orders WHERE OrderId = @o2) = 6
       AND (SELECT COUNT(*) FROM ord.OrderStageLog WHERE OrderId = @o2) = @logs + 1
       AND EXISTS (SELECT 1 FROM ord.OrderStageLog WHERE OrderId = @o2 AND ToStageId = 6 AND ChangedBy = @saigon AND Note = N'Bắt đầu rửa')
       AND (SELECT COUNT(*) FROM arc.Notifications WHERE OrderId = @o2) = @noti + 1
        PRINT N'PASS: sp_UpdateOrderStage đổi giai đoạn + log + thông báo';
    ELSE PRINT N'FAIL: sp_UpdateOrderStage đúng';
END TRY
BEGIN CATCH PRINT N'FAIL: sp_UpdateOrderStage đúng, lỗi ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;

-- 4. Nhảy cóc 5 -> 8 -> 50302
SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC ord.sp_UpdateOrderStage @o2, @saigon, 8; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50302 PRINT N'PASS: nhảy cóc -> 50302'; ELSE PRINT N'FAIL: nhảy cóc, nhận ' + CAST(@e AS NVARCHAR(10));

-- 5. Hủy khi đã Developing -> 50302
SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC ord.sp_UpdateOrderStage @o2, @saigon, 13, N'Thử hủy'; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50302 PRINT N'PASS: hủy sau Developing -> 50302'; ELSE PRINT N'FAIL: hủy sau Developing, nhận ' + CAST(@e AS NVARCHAR(10));

-- 6. Người không phải lab của đơn -> 50303 (khách; lab Hà Nội không sở hữu đơn của lab Sài Gòn)
SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC ord.sp_UpdateOrderStage @o2, @an, 6; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50303 PRINT N'PASS: khách đổi giai đoạn -> 50303'; ELSE PRINT N'FAIL: khách, nhận ' + CAST(@e AS NVARCHAR(10));

SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC ord.sp_UpdateOrderStage @o2, @hanoi, 6; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50303 PRINT N'PASS: lab khác -> 50303'; ELSE PRINT N'FAIL: lab khác, nhận ' + CAST(@e AS NVARCHAR(10));

-- 7. Đơn không tồn tại -> 50301
SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC ord.sp_UpdateOrderStage -1, @saigon, 6; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50301 PRINT N'PASS: đơn không tồn tại -> 50301'; ELSE PRINT N'FAIL: không tồn tại, nhận ' + CAST(@e AS NVARCHAR(10));

-- 8. Completed khi chưa Paid -> 50302; đã Paid thì được
SET @e = 0; BEGIN TRAN;
UPDATE ord.Orders SET PaymentStatus = N'Unpaid' WHERE OrderId = @o3;
BEGIN TRY EXEC ord.sp_UpdateOrderStage @o3, @hanoi, 12; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50302 PRINT N'PASS: Completed khi chưa Paid -> 50302'; ELSE PRINT N'FAIL: Completed chưa Paid, nhận ' + CAST(@e AS NVARCHAR(10));

SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC ord.sp_UpdateOrderStage @o3, @hanoi, 12;
    IF (SELECT StageId FROM ord.Orders WHERE OrderId = @o3) = 12
       AND (SELECT CompletedAt FROM ord.Orders WHERE OrderId = @o3) IS NOT NULL
        PRINT N'PASS: Completed khi đã Paid';
    ELSE PRINT N'FAIL: Completed khi đã Paid';
END TRY
BEGIN CATCH PRINT N'FAIL: Completed khi đã Paid, lỗi ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;

-- 9. UPDATE trực tiếp (không qua procedure) bị trigger chặn -> 50302
SET @e = 0; BEGIN TRAN;
BEGIN TRY UPDATE ord.Orders SET StageId = 9 WHERE OrderId = @o2; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50302 PRINT N'PASS: trigger chặn UPDATE trực tiếp -> 50302'; ELSE PRINT N'FAIL: trigger, nhận ' + CAST(@e AS NVARCHAR(10));
GO