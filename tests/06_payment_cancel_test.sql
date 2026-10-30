USE FilmLabDB;
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
SET NOCOUNT ON;
DROP PROCEDURE IF EXISTS #MkOrder;
GO
CREATE PROCEDURE #MkOrder
    @UpTo INT, @OrderId INT OUTPUT, @PickLeg INT OUTPUT, @RetLeg INT OUTPUT, @PartnerId INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @an INT = (SELECT UserId FROM iam.Users WHERE Email = N'an.nguyen@example.com');
    DECLARE @binh INT = (SELECT UserId FROM iam.Users WHERE Email = N'binh.tran@example.com');
    DECLARE @lab INT = (SELECT LabId FROM lab.FilmLabs WHERE LabName = N'Sài Gòn Film Lab');
    DECLARE @owner INT = (SELECT OwnerUserId FROM lab.FilmLabs WHERE LabId = @lab);
    DECLARE @svc INT = (SELECT LabServiceId FROM lab.LabServices WHERE LabId = @lab AND PackageName = N'Tráng C-41 35mm');
    DECLARE @addr INT = (SELECT AddressId FROM iam.Addresses WHERE UserId = @an AND Label = N'Nhà');
    DECLARE @items NVARCHAR(MAX) = CONCAT(N'[{"labServiceId":', @svc, N',"quantity":1}]');

    EXEC ord.sp_CreateOrder @an, @lab, N'Pickup', N'Delivery', @addr, @addr, @items, NULL, @OrderId OUTPUT;

    DECLARE @cur INT = 1, @next INT;
    WHILE @cur < @UpTo
    BEGIN
        SET @next = ord.fn_NextStage(@OrderId, @cur);
        EXEC ord.sp_UpdateOrderStage @OrderId, @owner, @next;
        SET @cur = @next;
    END;

    SELECT @PickLeg = DeliveryRequestId FROM dlv.DeliveryRequests WHERE OrderId = @OrderId AND Direction = N'Pickup';
    SELECT @RetLeg  = DeliveryRequestId FROM dlv.DeliveryRequests WHERE OrderId = @OrderId AND Direction = N'Return';

    INSERT INTO iam.DeliveryPartners (ProviderType, PartnerName, UserId) VALUES (N'Individual', N'Test Shipper', @binh);
    SET @PartnerId = SCOPE_IDENTITY();
END
GO

DECLARE @an INT = (SELECT UserId FROM iam.Users WHERE Email = N'an.nguyen@example.com');
DECLARE @binh INT = (SELECT UserId FROM iam.Users WHERE Email = N'binh.tran@example.com');
DECLARE @sgOwner INT = (SELECT OwnerUserId FROM lab.FilmLabs WHERE LabName = N'Sài Gòn Film Lab');
DECLARE @o1 INT = (SELECT OrderId FROM ord.Orders WHERE OrderCode = N'FL-2026-000001');   -- Paid, stage 12
DECLARE @o2 INT = (SELECT OrderId FROM ord.Orders WHERE OrderCode = N'FL-2026-000002');   -- binh, stage 5, Unpaid
DECLARE @o4 INT = (SELECT OrderId FROM ord.Orders WHERE OrderCode = N'FL-2026-000004');   -- an, stage 1
DECLARE @o5 INT = (SELECT OrderId FROM ord.Orders WHERE OrderCode = N'FL-2026-000005');   -- Cancelled
DECLARE @t2 DECIMAL(18,0) = (SELECT TotalAmount FROM ord.Orders WHERE OrderId = @o2);
DECLARE @t1 DECIMAL(18,0) = (SELECT TotalAmount FROM ord.Orders WHERE OrderId = @o1);
DECLARE @t4 DECIMAL(18,0) = (SELECT TotalAmount FROM ord.Orders WHERE OrderId = @o4);
DECLARE @t5 DECIMAL(18,0) = (SELECT TotalAmount FROM ord.Orders WHERE OrderId = @o5);
DECLARE @o INT, @pl INT, @rl INT, @pt INT, @pid INT, @e INT, @tot DECIMAL(18,0);

-- 1. fn_IsValidDeliveryTransition
IF dlv.fn_IsValidDeliveryTransition(N'Requested', N'Assigned') = 1 AND dlv.fn_IsValidDeliveryTransition(N'Assigned', N'PickedUp') = 1
   AND dlv.fn_IsValidDeliveryTransition(N'PickedUp', N'Delivered') = 1 AND dlv.fn_IsValidDeliveryTransition(N'Requested', N'Delivered') = 0
   AND dlv.fn_IsValidDeliveryTransition(N'PickedUp', N'Cancelled') = 0 AND dlv.fn_IsValidDeliveryTransition(N'Delivered', N'Failed') = 0
    PRINT N'PASS: fn_IsValidDeliveryTransition';
ELSE PRINT N'FAIL: fn_IsValidDeliveryTransition';

-- 2. Thanh toán thành công: Payments Succeeded, PaymentStatus = Paid, có thông báo
BEGIN TRAN;
BEGIN TRY
    EXEC ord.sp_ProcessPayment @OrderId = @o2, @ActorUserId = @binh, @Method = N'Card', @Provider = N'VNPay',
                               @ProviderTxnId = N'T-OK', @Amount = @t2, @NewPaymentId = @pid OUTPUT;
    IF EXISTS (SELECT 1 FROM ord.Payments WHERE PaymentId = @pid AND Status = N'Succeeded' AND PaidAt IS NOT NULL)
       AND EXISTS (SELECT 1 FROM ord.Orders WHERE OrderId = @o2 AND PaymentStatus = N'Paid')
       AND EXISTS (SELECT 1 FROM arc.Notifications WHERE OrderId = @o2 AND UserId = @binh AND Type = N'Payment')
        PRINT N'PASS: thanh toán thành công -> Paid + thông báo';
    ELSE PRINT N'FAIL: thanh toán thành công';
END TRY
BEGIN CATCH PRINT N'FAIL: thanh toán thành công, lỗi ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;

-- 3. Thanh toán thất bại: ghi Failed, đơn vẫn Unpaid
BEGIN TRAN;
BEGIN TRY
    EXEC ord.sp_ProcessPayment @OrderId = @o2, @ActorUserId = @binh, @Method = N'Card', @Provider = N'VNPay',
                               @Amount = @t2, @Succeeded = 0, @FailureReason = N'Thẻ hết hạn', @NewPaymentId = @pid OUTPUT;
    IF EXISTS (SELECT 1 FROM ord.Payments WHERE PaymentId = @pid AND Status = N'Failed' AND PaidAt IS NULL)
       AND EXISTS (SELECT 1 FROM ord.Orders WHERE OrderId = @o2 AND PaymentStatus = N'Unpaid')
        PRINT N'PASS: thanh toán thất bại -> Failed, đơn vẫn Unpaid';
    ELSE PRINT N'FAIL: thanh toán thất bại';
END TRY
BEGIN CATCH PRINT N'FAIL: thanh toán thất bại, lỗi ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;

-- 4. Sai số tiền -> 50305
SET @e = 0; SET @tot = @t2 - 1; BEGIN TRAN;
BEGIN TRY EXEC ord.sp_ProcessPayment @OrderId = @o2, @ActorUserId = @binh, @Method = N'Card', @Amount = @tot, @NewPaymentId = @pid OUTPUT; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50305 PRINT N'PASS: sai số tiền -> 50305'; ELSE PRINT N'FAIL: sai số tiền, nhận ' + CAST(@e AS NVARCHAR(10));

-- 5. Đơn đã Paid -> 50302
SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC ord.sp_ProcessPayment @OrderId = @o1, @ActorUserId = @an, @Method = N'Card', @Amount = @t1, @NewPaymentId = @pid OUTPUT; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50302 PRINT N'PASS: đơn đã Paid -> 50302'; ELSE PRINT N'FAIL: đơn đã Paid, nhận ' + CAST(@e AS NVARCHAR(10));

-- 6. Đơn Pending -> 50302
SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC ord.sp_ProcessPayment @OrderId = @o4, @ActorUserId = @an, @Method = N'Card', @Amount = @t4, @NewPaymentId = @pid OUTPUT; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50302 PRINT N'PASS: đơn Pending -> 50302'; ELSE PRINT N'FAIL: đơn Pending, nhận ' + CAST(@e AS NVARCHAR(10));

-- 7. Đơn Cancelled -> 50302
SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC ord.sp_ProcessPayment @OrderId = @o5, @ActorUserId = @binh, @Method = N'Card', @Amount = @t5, @NewPaymentId = @pid OUTPUT; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50302 PRINT N'PASS: đơn Cancelled -> 50302'; ELSE PRINT N'FAIL: đơn Cancelled, nhận ' + CAST(@e AS NVARCHAR(10));

-- 8. Người khác thanh toán hộ -> 50303
SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC ord.sp_ProcessPayment @OrderId = @o2, @ActorUserId = @an, @Method = N'Card', @Amount = @t2, @NewPaymentId = @pid OUTPUT; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50303 PRINT N'PASS: người khác thanh toán -> 50303'; ELSE PRINT N'FAIL: người khác, nhận ' + CAST(@e AS NVARCHAR(10));

-- 9. Đơn không tồn tại -> 50301
SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC ord.sp_ProcessPayment @OrderId = -1, @ActorUserId = @an, @Method = N'Card', @Amount = 1000, @NewPaymentId = @pid OUTPUT; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50301 PRINT N'PASS: thanh toán đơn không tồn tại -> 50301'; ELSE PRINT N'FAIL: không tồn tại, nhận ' + CAST(@e AS NVARCHAR(10));

-- 10. Thất bại không có lý do -> 50305
SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC ord.sp_ProcessPayment @OrderId = @o2, @ActorUserId = @binh, @Method = N'Card', @Amount = @t2, @Succeeded = 0, @NewPaymentId = @pid OUTPUT; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50305 PRINT N'PASS: thất bại thiếu lý do -> 50305'; ELSE PRINT N'FAIL: thiếu lý do, nhận ' + CAST(@e AS NVARCHAR(10));

-- 11. Phân công đối tác: chặng Assigned, có partner, có 2 dòng log (Requested, Assigned)
BEGIN TRAN;
BEGIN TRY
    EXEC #MkOrder 3, @o OUTPUT, @pl OUTPUT, @rl OUTPUT, @pt OUTPUT;
    EXEC dlv.sp_AssignPartner @pl, @sgOwner, @pt;
    IF EXISTS (SELECT 1 FROM dlv.DeliveryRequests WHERE DeliveryRequestId = @pl AND Status = N'Assigned' AND DeliveryPartnerId = @pt)
       AND (SELECT COUNT(*) FROM dlv.DeliveryStatusLog WHERE DeliveryRequestId = @pl) = 2
        PRINT N'PASS: sp_AssignPartner + DeliveryStatusLog';
    ELSE PRINT N'FAIL: sp_AssignPartner';
END TRY
BEGIN CATCH PRINT N'FAIL: sp_AssignPartner, lỗi ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;

-- 12. Chặng Pickup giao xong -> đơn sang FilmReceived (4), có PickedUpAt/DeliveredAt
BEGIN TRAN;
BEGIN TRY
    EXEC #MkOrder 3, @o OUTPUT, @pl OUTPUT, @rl OUTPUT, @pt OUTPUT;
    EXEC dlv.sp_AssignPartner @pl, @sgOwner, @pt;
    EXEC dlv.sp_UpdateDeliveryStatus @pl, @binh, N'PickedUp';
    EXEC dlv.sp_UpdateDeliveryStatus @pl, @binh, N'Delivered', N'Giao phim tới lab';
    IF (SELECT StageId FROM ord.Orders WHERE OrderId = @o) = 4
       AND EXISTS (SELECT 1 FROM dlv.DeliveryRequests WHERE DeliveryRequestId = @pl AND Status = N'Delivered' AND PickedUpAt IS NOT NULL AND DeliveredAt IS NOT NULL)
        PRINT N'PASS: Pickup Delivered -> đơn sang FilmReceived';
    ELSE PRINT N'FAIL: Pickup Delivered';
END TRY
BEGIN CATCH PRINT N'FAIL: Pickup Delivered, lỗi ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;

-- 13. Khách đổi trạng thái chặng -> 50403
SET @e = 0; BEGIN TRAN;
EXEC #MkOrder 3, @o OUTPUT, @pl OUTPUT, @rl OUTPUT, @pt OUTPUT;
BEGIN TRY EXEC dlv.sp_UpdateDeliveryStatus @rl, @an, N'Cancelled'; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50403 PRINT N'PASS: khách đổi trạng thái chặng -> 50403'; ELSE PRINT N'FAIL: khách đổi chặng, nhận ' + CAST(@e AS NVARCHAR(10));

-- 14. UPDATE trực tiếp sai thứ tự bị trigger chặn -> 50402
SET @e = 0; BEGIN TRAN;
EXEC #MkOrder 3, @o OUTPUT, @pl OUTPUT, @rl OUTPUT, @pt OUTPUT;
BEGIN TRY UPDATE dlv.DeliveryRequests SET Status = N'Failed', FailureReason = N'x' WHERE DeliveryRequestId = @rl; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50402 PRINT N'PASS: trigger Guard chặn Requested -> Failed -> 50402'; ELSE PRINT N'FAIL: trigger Guard, nhận ' + CAST(@e AS NVARCHAR(10));

-- 15. Failed thiếu lý do -> 50405
SET @e = 0; BEGIN TRAN;
EXEC #MkOrder 3, @o OUTPUT, @pl OUTPUT, @rl OUTPUT, @pt OUTPUT;
EXEC dlv.sp_AssignPartner @pl, @sgOwner, @pt;
BEGIN TRY EXEC dlv.sp_UpdateDeliveryStatus @pl, @sgOwner, N'Failed'; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50405 PRINT N'PASS: Failed thiếu lý do -> 50405'; ELSE PRINT N'FAIL: Failed thiếu lý do, nhận ' + CAST(@e AS NVARCHAR(10));

-- 16. D-07: chặng Return lấy hàng khi đơn chưa Paid -> 50402
SET @e = 0; BEGIN TRAN;
EXEC #MkOrder 3, @o OUTPUT, @pl OUTPUT, @rl OUTPUT, @pt OUTPUT;
EXEC dlv.sp_AssignPartner @rl, @sgOwner, @pt;
BEGIN TRY EXEC dlv.sp_UpdateDeliveryStatus @rl, @binh, N'PickedUp'; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50402 PRINT N'PASS: D-07 Return khi chưa Paid -> 50402'; ELSE PRINT N'FAIL: D-07, nhận ' + CAST(@e AS NVARCHAR(10));

-- 17. Trọn vòng đời: đơn ở ReadyToReturn, thanh toán, giao trả xong -> Completed
BEGIN TRAN;
BEGIN TRY
    EXEC #MkOrder 11, @o OUTPUT, @pl OUTPUT, @rl OUTPUT, @pt OUTPUT;
    SET @tot = (SELECT TotalAmount FROM ord.Orders WHERE OrderId = @o);
    EXEC ord.sp_ProcessPayment @OrderId = @o, @ActorUserId = @an, @Method = N'EWallet', @Provider = N'MoMo',
                               @Amount = @tot, @NewPaymentId = @pid OUTPUT;
    EXEC dlv.sp_AssignPartner @rl, @sgOwner, @pt;
    EXEC dlv.sp_UpdateDeliveryStatus @rl, @binh, N'PickedUp';
    EXEC dlv.sp_UpdateDeliveryStatus @rl, @binh, N'Delivered';
    IF EXISTS (SELECT 1 FROM ord.Orders WHERE OrderId = @o AND StageId = 12 AND CompletedAt IS NOT NULL AND PaymentStatus = N'Paid')
       AND (SELECT COUNT(*) FROM dlv.DeliveryStatusLog WHERE DeliveryRequestId = @rl) = 4
        PRINT N'PASS: Return Delivered -> đơn Completed';
    ELSE PRINT N'FAIL: Return Delivered -> Completed';
END TRY
BEGIN CATCH PRINT N'FAIL: Return Delivered -> Completed, lỗi ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;

-- 18. Khách hủy đơn Confirmed chưa thanh toán: đơn Cancelled, 2 chặng Cancelled, chủ lab được báo
BEGIN TRAN;
BEGIN TRY
    EXEC #MkOrder 2, @o OUTPUT, @pl OUTPUT, @rl OUTPUT, @pt OUTPUT;
    EXEC ord.sp_CancelOrder @o, @an, N'Khách đổi ý';
    IF EXISTS (SELECT 1 FROM ord.Orders WHERE OrderId = @o AND StageId = 13 AND CancelReason = N'Khách đổi ý')
       AND (SELECT COUNT(*) FROM dlv.DeliveryRequests WHERE OrderId = @o AND Status = N'Cancelled') = 2
       AND EXISTS (SELECT 1 FROM arc.Notifications n JOIN lab.FilmLabs l ON l.OwnerUserId = n.UserId
                   WHERE n.OrderId = @o AND n.Title LIKE N'%hủy%')
        PRINT N'PASS: hủy đơn chưa trả tiền (đơn + 2 chặng + thông báo lab)';
    ELSE PRINT N'FAIL: hủy đơn chưa trả tiền';
END TRY
BEGIN CATCH PRINT N'FAIL: hủy đơn chưa trả tiền, lỗi ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;

-- 19. Hủy đơn đã Paid: Payments Refunded, PaymentStatus Refunded
BEGIN TRAN;
BEGIN TRY
    EXEC #MkOrder 2, @o OUTPUT, @pl OUTPUT, @rl OUTPUT, @pt OUTPUT;
    SET @tot = (SELECT TotalAmount FROM ord.Orders WHERE OrderId = @o);
    EXEC ord.sp_ProcessPayment @OrderId = @o, @ActorUserId = @an, @Method = N'Card', @Amount = @tot, @NewPaymentId = @pid OUTPUT;
    EXEC ord.sp_CancelOrder @o, @an, N'Đổi kế hoạch';
    IF EXISTS (SELECT 1 FROM ord.Payments WHERE PaymentId = @pid AND Status = N'Refunded' AND RefundedAt IS NOT NULL)
       AND EXISTS (SELECT 1 FROM ord.Orders WHERE OrderId = @o AND StageId = 13 AND PaymentStatus = N'Refunded')
        PRINT N'PASS: hủy đơn đã Paid -> hoàn tiền';
    ELSE PRINT N'FAIL: hủy đơn đã Paid';
END TRY
BEGIN CATCH PRINT N'FAIL: hủy đơn đã Paid, lỗi ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;

-- 20. Hủy đơn đã vào Developing -> 50302
SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC ord.sp_CancelOrder @o2, @binh, N'Thử hủy'; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50302 PRINT N'PASS: hủy sau Developing -> 50302'; ELSE PRINT N'FAIL: hủy sau Developing, nhận ' + CAST(@e AS NVARCHAR(10));

-- 21. Người lạ hủy đơn -> 50303
SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC ord.sp_CancelOrder @o2, @an, N'Thử hủy'; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50303 PRINT N'PASS: người lạ hủy đơn -> 50303'; ELSE PRINT N'FAIL: người lạ, nhận ' + CAST(@e AS NVARCHAR(10));

-- 22. Chặng Pickup đã PickedUp -> không hủy được, 50302
SET @e = 0; BEGIN TRAN;
EXEC #MkOrder 3, @o OUTPUT, @pl OUTPUT, @rl OUTPUT, @pt OUTPUT;
EXEC dlv.sp_AssignPartner @pl, @sgOwner, @pt;
EXEC dlv.sp_UpdateDeliveryStatus @pl, @binh, N'PickedUp';
BEGIN TRY EXEC ord.sp_CancelOrder @o, @an, N'Thử hủy'; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50302 PRINT N'PASS: Pickup đã lấy hàng, không hủy -> 50302'; ELSE PRINT N'FAIL: Pickup PickedUp, nhận ' + CAST(@e AS NVARCHAR(10));

-- 23. Hủy đơn không tồn tại -> 50301
SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC ord.sp_CancelOrder -1, @an, N'x'; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50301 PRINT N'PASS: hủy đơn không tồn tại -> 50301'; ELSE PRINT N'FAIL: không tồn tại, nhận ' + CAST(@e AS NVARCHAR(10));

-- 24. Hủy không có lý do -> 50305
SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC ord.sp_CancelOrder @o4, @an, N''; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50305 PRINT N'PASS: hủy thiếu lý do -> 50305'; ELSE PRINT N'FAIL: thiếu lý do, nhận ' + CAST(@e AS NVARCHAR(10));
GO