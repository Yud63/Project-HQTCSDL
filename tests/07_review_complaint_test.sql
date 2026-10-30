USE FilmLabDB;
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
SET NOCOUNT ON;
DROP PROCEDURE IF EXISTS #MkCompleted;
GO
CREATE PROCEDURE #MkCompleted @OrderId INT OUTPUT, @BackdateDays INT = 0
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @an INT = (SELECT UserId FROM iam.Users WHERE Email = N'an.nguyen@example.com');
    DECLARE @lab INT = (SELECT LabId FROM lab.FilmLabs WHERE LabName = N'Sài Gòn Film Lab');
    DECLARE @owner INT = (SELECT OwnerUserId FROM lab.FilmLabs WHERE LabId = @lab);
    DECLARE @svc INT = (SELECT LabServiceId FROM lab.LabServices WHERE LabId = @lab AND PackageName = N'Tráng C-41 35mm');
    DECLARE @items NVARCHAR(MAX) = CONCAT(N'[{"labServiceId":', @svc, N',"quantity":1}]');

    EXEC ord.sp_CreateOrder @an, @lab, N'DropOff', N'SelfCollect', NULL, NULL, @items, NULL, @OrderId OUTPUT;

    DECLARE @cur INT = 1, @next INT;
    WHILE @cur < 11
    BEGIN
        SET @next = ord.fn_NextStage(@OrderId, @cur);
        EXEC ord.sp_UpdateOrderStage @OrderId, @owner, @next;
        SET @cur = @next;
    END;

    DECLARE @tot DECIMAL(18,0) = (SELECT TotalAmount FROM ord.Orders WHERE OrderId = @OrderId), @pid INT;
    EXEC ord.sp_ProcessPayment @OrderId = @OrderId, @ActorUserId = @an, @Method = N'Card', @Provider = N'VNPay',
                               @Amount = @tot, @NewPaymentId = @pid OUTPUT;
    EXEC ord.sp_UpdateOrderStage @OrderId, @owner, 12;

    IF @BackdateDays > 0
        UPDATE ord.Orders
        SET CreatedAt   = DATEADD(DAY, -(@BackdateDays + 1), SYSUTCDATETIME()),
            CompletedAt = DATEADD(DAY, -@BackdateDays, SYSUTCDATETIME())
        WHERE OrderId = @OrderId;
END
GO

DECLARE @an INT = (SELECT UserId FROM iam.Users WHERE Email = N'an.nguyen@example.com');
DECLARE @binh INT = (SELECT UserId FROM iam.Users WHERE Email = N'binh.tran@example.com');
DECLARE @admin INT = (SELECT UserId FROM iam.Users WHERE Email = N'admin@filmlab.vn');
DECLARE @lab INT = (SELECT LabId FROM lab.FilmLabs WHERE LabName = N'Sài Gòn Film Lab');
DECLARE @owner INT = (SELECT OwnerUserId FROM lab.FilmLabs WHERE LabId = @lab);
DECLARE @o1 INT = (SELECT OrderId FROM ord.Orders WHERE OrderCode = N'FL-2026-000001');   -- đã có đánh giá trong seed
DECLARE @o2 INT = (SELECT OrderId FROM ord.Orders WHERE OrderCode = N'FL-2026-000002');   -- binh, stage 5
DECLARE @o4 INT = (SELECT OrderId FROM ord.Orders WHERE OrderCode = N'FL-2026-000004');   -- an, Pending
DECLARE @o5 INT = (SELECT OrderId FROM ord.Orders WHERE OrderCode = N'FL-2026-000005');   -- binh, Cancelled
DECLARE @o INT, @rid INT, @cid INT, @e INT, @cnt0 INT, @tot DECIMAL(18,0);

-- 1. fn_IsValidComplaintTransition
IF ord.fn_IsValidComplaintTransition(N'Open', N'InReview') = 1 AND ord.fn_IsValidComplaintTransition(N'InReview', N'Resolved') = 1
   AND ord.fn_IsValidComplaintTransition(N'Open', N'Resolved') = 1 AND ord.fn_IsValidComplaintTransition(N'Resolved', N'InReview') = 0
   AND ord.fn_IsValidComplaintTransition(N'Rejected', N'Open') = 0 AND ord.fn_IsValidComplaintTransition(N'InReview', N'Open') = 0
    PRINT N'PASS: fn_IsValidComplaintTransition';
ELSE PRINT N'FAIL: fn_IsValidComplaintTransition';

-- 2. Đánh giá thành công: có dòng review, lab được tính lại điểm, chủ lab được báo
BEGIN TRAN;
BEGIN TRY
    EXEC #MkCompleted @o OUTPUT;
    SET @cnt0 = (SELECT ReviewCount FROM lab.FilmLabs WHERE LabId = @lab);
    EXEC ord.sp_AddReview @o, @an, 3, 4, 5, N'Rất tốt', @rid OUTPUT;
    IF EXISTS (SELECT 1 FROM ord.Reviews WHERE ReviewId = @rid AND RatingOverall = 3 AND LabId = @lab)
       AND (SELECT ReviewCount FROM lab.FilmLabs WHERE LabId = @lab) = @cnt0 + 1
       AND (SELECT AvgRating FROM lab.FilmLabs WHERE LabId = @lab) =
           (SELECT CAST(AVG(CAST(RatingOverall AS DECIMAL(5,2))) AS DECIMAL(3,2)) FROM ord.Reviews WHERE LabId = @lab AND IsVisible = 1 AND IsDeleted = 0)
       AND EXISTS (SELECT 1 FROM arc.Notifications WHERE OrderId = @o AND UserId = @owner AND Type = N'Review')
        PRINT N'PASS: đánh giá thành công + cập nhật điểm lab + báo chủ lab';
    ELSE PRINT N'FAIL: đánh giá thành công';
END TRY
BEGIN CATCH PRINT N'FAIL: đánh giá thành công, lỗi ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;

-- 3. Đánh giá lần hai -> 50304
SET @e = 0; BEGIN TRAN;
EXEC #MkCompleted @o OUTPUT;
EXEC ord.sp_AddReview @o, @an, 5, NULL, NULL, NULL, @rid OUTPUT;
BEGIN TRY EXEC ord.sp_AddReview @o, @an, 4, NULL, NULL, NULL, @rid OUTPUT; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50304 PRINT N'PASS: đánh giá lần hai -> 50304'; ELSE PRINT N'FAIL: đánh giá lần hai, nhận ' + CAST(@e AS NVARCHAR(10));

-- 4. Đơn chưa Completed -> 50302
SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC ord.sp_AddReview @o2, @binh, 5, NULL, NULL, NULL, @rid OUTPUT; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50302 PRINT N'PASS: đánh giá đơn chưa Completed -> 50302'; ELSE PRINT N'FAIL: chưa Completed, nhận ' + CAST(@e AS NVARCHAR(10));

-- 5. Quá 30 ngày -> 50302
SET @e = 0; BEGIN TRAN;
EXEC #MkCompleted @o OUTPUT, 31;
BEGIN TRY EXEC ord.sp_AddReview @o, @an, 5, NULL, NULL, NULL, @rid OUTPUT; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50302 PRINT N'PASS: đánh giá quá 30 ngày -> 50302'; ELSE PRINT N'FAIL: quá 30 ngày, nhận ' + CAST(@e AS NVARCHAR(10));

-- 6. Người khác đánh giá -> 50303
SET @e = 0; BEGIN TRAN;
EXEC #MkCompleted @o OUTPUT;
BEGIN TRY EXEC ord.sp_AddReview @o, @binh, 5, NULL, NULL, NULL, @rid OUTPUT; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50303 PRINT N'PASS: người khác đánh giá -> 50303'; ELSE PRINT N'FAIL: người khác, nhận ' + CAST(@e AS NVARCHAR(10));

-- 7. Đơn không tồn tại -> 50301
SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC ord.sp_AddReview -1, @an, 5, NULL, NULL, NULL, @rid OUTPUT; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50301 PRINT N'PASS: đánh giá đơn không tồn tại -> 50301'; ELSE PRINT N'FAIL: không tồn tại, nhận ' + CAST(@e AS NVARCHAR(10));

-- 8. Điểm 6 -> 50305
SET @e = 0; BEGIN TRAN;
EXEC #MkCompleted @o OUTPUT;
BEGIN TRY EXEC ord.sp_AddReview @o, @an, 6, NULL, NULL, NULL, @rid OUTPUT; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50305 PRINT N'PASS: điểm 6 -> 50305'; ELSE PRINT N'FAIL: điểm 6, nhận ' + CAST(@e AS NVARCHAR(10));

-- 9. INSERT trực tiếp review cho đơn chưa Completed bị trigger chặn -> 50302
SET @e = 0; BEGIN TRAN;
BEGIN TRY INSERT INTO ord.Reviews (OrderId, CustomerId, LabId, RatingOverall) VALUES (@o2, @binh, @lab, 5); END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50302 PRINT N'PASS: trigger CheckEligible chặn INSERT trực tiếp -> 50302'; ELSE PRINT N'FAIL: trigger CheckEligible, nhận ' + CAST(@e AS NVARCHAR(10));

-- 10. Admin ẩn một đánh giá -> ReviewCount của lab giảm 1
BEGIN TRAN;
BEGIN TRY
    SET @cnt0 = (SELECT ReviewCount FROM lab.FilmLabs WHERE LabId = @lab);
    UPDATE ord.Reviews SET IsVisible = 0, ModerationReason = N'Vi phạm', ModeratedBy = @admin, ModeratedAt = SYSUTCDATETIME()
    WHERE OrderId = @o1;
    IF (SELECT ReviewCount FROM lab.FilmLabs WHERE LabId = @lab) = @cnt0 - 1
        PRINT N'PASS: ẩn đánh giá -> lab tính lại ReviewCount';
    ELSE PRINT N'FAIL: ẩn đánh giá';
END TRY
BEGIN CATCH PRINT N'FAIL: ẩn đánh giá, lỗi ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;

-- 11. lab.sp_RecalcLabRating lab không tồn tại -> 50201
SET @e = 0;
BEGIN TRY EXEC lab.sp_RecalcLabRating -1; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @e = 50201 PRINT N'PASS: RecalcLabRating lab không tồn tại -> 50201'; ELSE PRINT N'FAIL: RecalcLabRating, nhận ' + CAST(@e AS NVARCHAR(10));

-- 12. Khiếu nại thành công: Open, chủ lab được báo, có nhật ký audit INSERT
BEGIN TRAN;
BEGIN TRY
    EXEC #MkCompleted @o OUTPUT;
    EXEC ord.sp_FileComplaint @o, @an, N'ScanQuality', N'Scan tối', N'Khung 5 và 6 scan bị tối', @cid OUTPUT;
    IF EXISTS (SELECT 1 FROM ord.Complaints WHERE ComplaintId = @cid AND Status = N'Open' AND LabId = @lab)
       AND EXISTS (SELECT 1 FROM arc.Notifications WHERE OrderId = @o AND UserId = @owner AND Type = N'Complaint')
       AND EXISTS (SELECT 1 FROM audit.AuditLogs WHERE TableSchema = N'ord' AND TableName = N'Complaints'
                   AND PrimaryKeyValue = CAST(@cid AS NVARCHAR(100)) AND Action = N'INSERT' AND ChangedBy = @an)
        PRINT N'PASS: khiếu nại thành công + báo chủ lab + audit';
    ELSE PRINT N'FAIL: khiếu nại thành công';
END TRY
BEGIN CATCH PRINT N'FAIL: khiếu nại thành công, lỗi ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;

-- 13. Khiếu nại trùng loại đang mở -> 50304
SET @e = 0; BEGIN TRAN;
EXEC #MkCompleted @o OUTPUT;
EXEC ord.sp_FileComplaint @o, @an, N'Delay', N'Chậm', N'Giao chậm', @cid OUTPUT;
BEGIN TRY EXEC ord.sp_FileComplaint @o, @an, N'Delay', N'Chậm nữa', N'Vẫn chậm', @cid OUTPUT; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50304 PRINT N'PASS: khiếu nại trùng loại -> 50304'; ELSE PRINT N'FAIL: trùng loại, nhận ' + CAST(@e AS NVARCHAR(10));

-- 14. Khiếu nại đơn Pending -> 50302
SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC ord.sp_FileComplaint @o4, @an, N'Delay', N'x', N'x', @cid OUTPUT; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50302 PRINT N'PASS: khiếu nại đơn Pending -> 50302'; ELSE PRINT N'FAIL: đơn Pending, nhận ' + CAST(@e AS NVARCHAR(10));

-- 15. Khiếu nại đơn Cancelled -> 50302
SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC ord.sp_FileComplaint @o5, @binh, N'Delay', N'x', N'x', @cid OUTPUT; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50302 PRINT N'PASS: khiếu nại đơn Cancelled -> 50302'; ELSE PRINT N'FAIL: đơn Cancelled, nhận ' + CAST(@e AS NVARCHAR(10));

-- 16. Khiếu nại quá 30 ngày -> 50302
SET @e = 0; BEGIN TRAN;
EXEC #MkCompleted @o OUTPUT, 31;
BEGIN TRY EXEC ord.sp_FileComplaint @o, @an, N'Delay', N'x', N'x', @cid OUTPUT; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50302 PRINT N'PASS: khiếu nại quá 30 ngày -> 50302'; ELSE PRINT N'FAIL: quá 30 ngày, nhận ' + CAST(@e AS NVARCHAR(10));

-- 17. Người khác khiếu nại -> 50303
SET @e = 0; BEGIN TRAN;
EXEC #MkCompleted @o OUTPUT;
BEGIN TRY EXEC ord.sp_FileComplaint @o, @binh, N'Delay', N'x', N'x', @cid OUTPUT; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50303 PRINT N'PASS: người khác khiếu nại -> 50303'; ELSE PRINT N'FAIL: người khác, nhận ' + CAST(@e AS NVARCHAR(10));

-- 18. Loại khiếu nại sai -> 50305
SET @e = 0; BEGIN TRAN;
EXEC #MkCompleted @o OUTPUT;
BEGIN TRY EXEC ord.sp_FileComplaint @o, @an, N'Foo', N'x', N'x', @cid OUTPUT; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50305 PRINT N'PASS: loại khiếu nại sai -> 50305'; ELSE PRINT N'FAIL: loại sai, nhận ' + CAST(@e AS NVARCHAR(10));

-- 19. Khiếu nại đơn không tồn tại -> 50301
SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC ord.sp_FileComplaint -1, @an, N'Delay', N'x', N'x', @cid OUTPUT; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50301 PRINT N'PASS: khiếu nại đơn không tồn tại -> 50301'; ELSE PRINT N'FAIL: không tồn tại, nhận ' + CAST(@e AS NVARCHAR(10));

-- 20. Admin xử lý: InReview rồi Resolved hoàn một phần 20.000đ (đơn vẫn Paid)
BEGIN TRAN;
BEGIN TRY
    EXEC #MkCompleted @o OUTPUT;
    EXEC ord.sp_FileComplaint @o, @an, N'ScanQuality', N'Scan tối', N'Khung 5 và 6 scan bị tối', @cid OUTPUT;
    EXEC ord.sp_ResolveComplaint @cid, @admin, N'InReview', NULL, NULL;
    EXEC ord.sp_ResolveComplaint @cid, @admin, N'Resolved', N'Refund', N'Hoàn một phần phí scan', 20000;
    IF EXISTS (SELECT 1 FROM ord.Complaints WHERE ComplaintId = @cid AND Status = N'Resolved' AND RefundAmount = 20000
                 AND AssignedAdminId = @admin AND ResolvedAt IS NOT NULL)
       AND EXISTS (SELECT 1 FROM ord.Orders WHERE OrderId = @o AND PaymentStatus = N'Paid')
       AND EXISTS (SELECT 1 FROM arc.Notifications WHERE OrderId = @o AND UserId = @an AND Type = N'Complaint')
       AND (SELECT COUNT(*) FROM audit.AuditLogs WHERE TableName = N'Complaints' AND PrimaryKeyValue = CAST(@cid AS NVARCHAR(100)) AND Action = N'UPDATE') = 2
        PRINT N'PASS: InReview -> Resolved hoàn một phần (+ báo khách + audit)';
    ELSE PRINT N'FAIL: xử lý hoàn một phần';
END TRY
BEGIN CATCH PRINT N'FAIL: xử lý hoàn một phần, lỗi ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;

-- 21. Hoàn toàn bộ: Payments Refunded, đơn Refunded
BEGIN TRAN;
BEGIN TRY
    EXEC #MkCompleted @o OUTPUT;
    SET @tot = (SELECT TotalAmount FROM ord.Orders WHERE OrderId = @o);
    EXEC ord.sp_FileComplaint @o, @an, N'LostFilm', N'Mất phim', N'Lab làm mất cuộn phim', @cid OUTPUT;
    EXEC ord.sp_ResolveComplaint @cid, @admin, N'Resolved', N'Refund', N'Hoàn toàn bộ', @tot;
    IF EXISTS (SELECT 1 FROM ord.Payments WHERE OrderId = @o AND Status = N'Refunded' AND RefundedAt IS NOT NULL)
       AND EXISTS (SELECT 1 FROM ord.Orders WHERE OrderId = @o AND PaymentStatus = N'Refunded')
        PRINT N'PASS: hoàn toàn bộ -> Payments/Orders Refunded';
    ELSE PRINT N'FAIL: hoàn toàn bộ';
END TRY
BEGIN CATCH PRINT N'FAIL: hoàn toàn bộ, lỗi ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;

-- 22. Từ chối khiếu nại: Rejected, có ResolvedAt, ResolutionType NULL
BEGIN TRAN;
BEGIN TRY
    EXEC #MkCompleted @o OUTPUT;
    EXEC ord.sp_FileComplaint @o, @an, N'Service', N'Thái độ', N'Nhân viên thiếu nhiệt tình', @cid OUTPUT;
    EXEC ord.sp_ResolveComplaint @cid, @admin, N'Rejected', NULL, N'Không đủ căn cứ';
    IF EXISTS (SELECT 1 FROM ord.Complaints WHERE ComplaintId = @cid AND Status = N'Rejected' AND ResolutionType IS NULL
                 AND Resolution = N'Không đủ căn cứ' AND ResolvedAt IS NOT NULL)
        PRINT N'PASS: từ chối khiếu nại';
    ELSE PRINT N'FAIL: từ chối khiếu nại';
END TRY
BEGIN CATCH PRINT N'FAIL: từ chối khiếu nại, lỗi ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;

-- 23. Người không phải Admin xử lý -> 50303
SET @e = 0; BEGIN TRAN;
EXEC #MkCompleted @o OUTPUT;
EXEC ord.sp_FileComplaint @o, @an, N'Delay', N'Chậm', N'Giao chậm', @cid OUTPUT;
BEGIN TRY EXEC ord.sp_ResolveComplaint @cid, @an, N'InReview', NULL, NULL; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50303 PRINT N'PASS: không phải Admin xử lý -> 50303'; ELSE PRINT N'FAIL: không phải Admin, nhận ' + CAST(@e AS NVARCHAR(10));

-- 24. Hoàn vượt tổng tiền -> 50305
SET @e = 0; BEGIN TRAN;
EXEC #MkCompleted @o OUTPUT;
SET @tot = (SELECT TotalAmount FROM ord.Orders WHERE OrderId = @o) + 1;
EXEC ord.sp_FileComplaint @o, @an, N'Billing', N'Sai phí', N'Tính sai phí', @cid OUTPUT;
BEGIN TRY EXEC ord.sp_ResolveComplaint @cid, @admin, N'Resolved', N'Refund', N'Hoàn quá', @tot; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50305 PRINT N'PASS: hoàn vượt tổng tiền -> 50305'; ELSE PRINT N'FAIL: hoàn vượt, nhận ' + CAST(@e AS NVARCHAR(10));

-- 25. Resolved thiếu nội dung xử lý -> 50305
SET @e = 0; BEGIN TRAN;
EXEC #MkCompleted @o OUTPUT;
EXEC ord.sp_FileComplaint @o, @an, N'Delay', N'Chậm', N'Giao chậm', @cid OUTPUT;
BEGIN TRY EXEC ord.sp_ResolveComplaint @cid, @admin, N'Resolved', N'NoAction', N''; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50305 PRINT N'PASS: Resolved thiếu nội dung -> 50305'; ELSE PRINT N'FAIL: thiếu nội dung, nhận ' + CAST(@e AS NVARCHAR(10));

-- 26. Resolved -> InReview -> 50302
SET @e = 0; BEGIN TRAN;
EXEC #MkCompleted @o OUTPUT;
EXEC ord.sp_FileComplaint @o, @an, N'Delay', N'Chậm', N'Giao chậm', @cid OUTPUT;
EXEC ord.sp_ResolveComplaint @cid, @admin, N'Resolved', N'NoAction', N'Đã làm việc với lab';
BEGIN TRY EXEC ord.sp_ResolveComplaint @cid, @admin, N'InReview', NULL, NULL; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50302 PRINT N'PASS: Resolved -> InReview -> 50302'; ELSE PRINT N'FAIL: Resolved -> InReview, nhận ' + CAST(@e AS NVARCHAR(10));

-- 27. Khiếu nại không tồn tại -> 50301
SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC ord.sp_ResolveComplaint -1, @admin, N'InReview', NULL, NULL; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50301 PRINT N'PASS: xử lý khiếu nại không tồn tại -> 50301'; ELSE PRINT N'FAIL: không tồn tại, nhận ' + CAST(@e AS NVARCHAR(10));

-- 28. UPDATE trực tiếp Rejected -> InReview bị trigger Guard chặn -> 50302
SET @e = 0; BEGIN TRAN;
EXEC #MkCompleted @o OUTPUT;
EXEC ord.sp_FileComplaint @o, @an, N'Other', N'Khác', N'Vấn đề khác', @cid OUTPUT;
EXEC ord.sp_ResolveComplaint @cid, @admin, N'Rejected', NULL, N'Không đủ căn cứ';
BEGIN TRY UPDATE ord.Complaints SET Status = N'InReview' WHERE ComplaintId = @cid; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50302 PRINT N'PASS: trigger Guard chặn Rejected -> InReview -> 50302'; ELSE PRINT N'FAIL: trigger Guard, nhận ' + CAST(@e AS NVARCHAR(10));
GO