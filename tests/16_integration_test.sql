USE FilmLabDB;
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- Kịch bản: khách đặt đơn -> lab xử lý -> thanh toán -> upload scan -> hoàn tất -> review -> khiếu nại -> hoàn tiền
DECLARE @Cust INT = 6, @Admin INT = 1;
DECLARE @Lab INT, @Owner INT, @SvcDev INT, @SvcScan INT, @Stock INT;
DECLARE @Items NVARCHAR(MAX), @Oid INT, @Stage INT, @Next INT, @k INT = 0, @Total DECIMAL(18,0);
DECLARE @Pay INT, @Fid UNIQUEIDENTIFIER, @Meta NVARCHAR(MAX), @Rid INT, @Cid INT, @ok BIT, @n INT, @hist DECIMAL(9,4), @msg NVARCHAR(4000);

SELECT TOP 1 @Lab = l.LabId, @Owner = l.OwnerUserId, @SvcDev = d.LabServiceId, @SvcScan = s.LabServiceId
FROM lab.FilmLabs l
JOIN lab.LabServices d ON d.LabId = l.LabId AND d.IsActive = 1
     AND EXISTS (SELECT 1 FROM lab.ServiceTypes t WHERE t.ServiceTypeId = d.ServiceTypeId AND t.Category = N'Develop')
JOIN lab.LabServices s ON s.LabId = l.LabId AND s.IsActive = 1 AND s.FormatId = d.FormatId
     AND EXISTS (SELECT 1 FROM lab.ServiceTypes t WHERE t.ServiceTypeId = s.ServiceTypeId AND t.Category = N'Scan')
WHERE l.ApprovalStatus = N'Approved' AND l.IsDeleted = 0
ORDER BY l.LabId;
SELECT TOP 1 @Stock = StockId FROM lab.FilmStocks WHERE IsActive = 1 ORDER BY StockId;

SET @Items = N'[{"labServiceId":' + CAST(@SvcDev AS NVARCHAR(10)) + N',"filmStockId":' + CAST(@Stock AS NVARCHAR(10))
           + N',"quantity":1,"note":"e2e"},{"labServiceId":' + CAST(@SvcScan AS NVARCHAR(10)) + N',"filmStockId":'
           + CAST(@Stock AS NVARCHAR(10)) + N',"quantity":1,"note":"e2e"}]';

BEGIN TRY
    BEGIN TRAN;

    -- 1. Tạo đơn
    EXEC ord.sp_CreateOrder @CustomerId = @Cust, @LabId = @Lab, @FulfillmentMethod = N'DropOff', @ReturnMethod = N'SelfCollect',
                            @ItemsJson = @Items, @NewOrderId = @Oid OUTPUT;
    SELECT @Total = TotalAmount FROM ord.Orders WHERE OrderId = @Oid;
    SET @ok = CASE WHEN EXISTS (SELECT 1 FROM ord.Orders WHERE OrderId = @Oid AND StageId = 1 AND TotalAmount = Subtotal + DeliveryFee)
                    AND (SELECT COUNT(*) FROM ord.OrderItems WHERE OrderId = @Oid) = 2 THEN 1 ELSE 0 END;
    PRINT CASE WHEN @ok = 1 THEN N'PASS: sp_CreateOrder tạo đơn Pending, 2 dòng, tổng khớp' ELSE N'FAIL: sp_CreateOrder' END;

    -- 2. Có thông báo gắn với đơn
    SELECT @n = COUNT(*) FROM arc.Notifications WHERE OrderId = @Oid;
    PRINT CASE WHEN @n >= 1 THEN N'PASS: tạo đơn sinh thông báo' ELSE N'FAIL: tạo đơn không sinh thông báo' END;

    -- 3. Lab đẩy đơn tới Scanning (8), mỗi lần đổi giai đoạn được ghi log
    SET @Stage = 1;
    WHILE @Stage < 8
    BEGIN
        SET @Next = ord.fn_NextStage(@Oid, @Stage);
        IF @Next IS NULL OR @Next <= @Stage BREAK;
        EXEC ord.sp_UpdateOrderStage @OrderId = @Oid, @ActorUserId = @Owner, @NewStageId = @Next, @Note = N'e2e';
        SET @Stage = @Next;
        SET @k += 1;
    END;
    SELECT @n = COUNT(*) FROM ord.OrderStageLog WHERE OrderId = @Oid;
    PRINT CASE WHEN @Stage = 8 AND @n = @k + 1 THEN N'PASS: đơn tới Scanning, OrderStageLog đủ dòng'
               ELSE N'FAIL: đẩy giai đoạn (stage ' + CAST(@Stage AS NVARCHAR(10)) + N', log ' + CAST(@n AS NVARCHAR(10)) + N')' END;

    -- 4. Thanh toán
    EXEC ord.sp_ProcessPayment @OrderId = @Oid, @ActorUserId = @Cust, @Method = N'Card', @Provider = N'VNPay',
                               @ProviderTxnId = N'E2E-001', @Amount = @Total, @NewPaymentId = @Pay OUTPUT;
    SET @ok = CASE WHEN EXISTS (SELECT 1 FROM ord.Orders WHERE OrderId = @Oid AND PaymentStatus = N'Paid')
                    AND EXISTS (SELECT 1 FROM ord.Payments WHERE PaymentId = @Pay AND Status = N'Succeeded') THEN 1 ELSE 0 END;
    PRINT CASE WHEN @ok = 1 THEN N'PASS: thanh toán -> trigger đặt Orders.PaymentStatus = Paid' ELSE N'FAIL: thanh toán' END;

    -- 5. Upload scan kèm metadata
    SET @Meta = N'{"cameraModel":"Nikon FM2","exposedIso":400}';
    EXEC arc.sp_UploadScan @OrderId = @Oid, @ActorUserId = @Owner, @FileName = N'e2e_001.jpg',
                           @StorageUrl = N'https://example.com/e2e_001.jpg', @ContentType = N'image/jpeg',
                           @FileSizeBytes = 1048576, @FrameNumber = 1, @MetadataJson = @Meta, @NewScanFileId = @Fid OUTPUT;
    SET @ok = CASE WHEN EXISTS (SELECT 1 FROM arc.ScanFiles WHERE ScanFileId = @Fid AND OwnerUserId = @Cust)
                    AND EXISTS (SELECT 1 FROM arc.PhotoMetadata WHERE ScanFileId = @Fid AND CameraModel = N'Nikon FM2') THEN 1 ELSE 0 END;
    PRINT CASE WHEN @ok = 1 THEN N'PASS: sp_UploadScan tạo ScanFiles + PhotoMetadata, chủ sở hữu = khách' ELSE N'FAIL: sp_UploadScan' END;

    -- 6. Thông báo ScanReady cho khách
    SELECT @n = COUNT(*) FROM arc.Notifications WHERE UserId = @Cust AND OrderId = @Oid AND [Type] = N'ScanReady';
    PRINT CASE WHEN @n >= 1 THEN N'PASS: trigger gửi ScanReady cho khách' ELSE N'FAIL: không có thông báo ScanReady' END;

    -- 7. Hoàn tất đơn (cần đã Paid)
    WHILE @Stage < 12
    BEGIN
        SET @Next = ord.fn_NextStage(@Oid, @Stage);
        IF @Next IS NULL OR @Next <= @Stage BREAK;
        EXEC ord.sp_UpdateOrderStage @OrderId = @Oid, @ActorUserId = @Owner, @NewStageId = @Next, @Note = N'e2e';
        SET @Stage = @Next;
    END;
    SET @ok = CASE WHEN EXISTS (SELECT 1 FROM ord.Orders WHERE OrderId = @Oid AND StageId = 12 AND CompletedAt IS NOT NULL) THEN 1 ELSE 0 END;
    PRINT CASE WHEN @ok = 1 THEN N'PASS: đơn Completed, có CompletedAt' ELSE N'FAIL: hoàn tất đơn (stage ' + CAST(@Stage AS NVARCHAR(10)) + N')' END;

    -- 8. Khách đánh giá -> trigger cập nhật rating của lab
    EXEC ord.sp_AddReview @OrderId = @Oid, @CustomerId = @Cust, @RatingOverall = 5, @Comment = N'E2E', @NewReviewId = @Rid OUTPUT;
    SET @ok = CASE WHEN EXISTS (SELECT 1 FROM lab.FilmLabs WHERE LabId = @Lab AND ReviewCount >= 1
                                  AND AvgRating = ord.fn_LabAvgRating(@Lab)) THEN 1 ELSE 0 END;
    PRINT CASE WHEN @ok = 1 THEN N'PASS: review -> FilmLabs.AvgRating khớp fn_LabAvgRating' ELSE N'FAIL: review/AvgRating' END;

    -- 9. Lab trả lời
    EXEC ord.sp_ReplyReview @ReviewId = @Rid, @LabOwnerId = @Owner, @Reply = N'Cảm ơn bạn';
    SET @ok = CASE WHEN EXISTS (SELECT 1 FROM ord.Reviews WHERE ReviewId = @Rid AND LabReply IS NOT NULL) THEN 1 ELSE 0 END;
    PRINT CASE WHEN @ok = 1 THEN N'PASS: lab trả lời review' ELSE N'FAIL: trả lời review' END;

    -- 10. Khiếu nại xuất hiện ở hàng đợi Admin
    EXEC ord.sp_FileComplaint @OrderId = @Oid, @CustomerId = @Cust, @Category = N'Billing',
                              @Title = N'E2E khiếu nại', @Description = N'Nội dung test', @NewComplaintId = @Cid OUTPUT;
    SET @ok = CASE WHEN EXISTS (SELECT 1 FROM ord.vw_OpenComplaints WHERE ComplaintId = @Cid AND Status = N'Open') THEN 1 ELSE 0 END;
    PRINT CASE WHEN @ok = 1 THEN N'PASS: khiếu nại Open có trong vw_OpenComplaints' ELSE N'FAIL: khiếu nại / vw_OpenComplaints' END;

    -- 11. Admin giải quyết bằng hoàn tiền toàn bộ -> Payments + Orders chuyển Refunded
    EXEC ord.sp_ResolveComplaint @ComplaintId = @Cid, @AdminUserId = @Admin, @Decision = N'InReview', @Resolution = N'Đang xem xét';
    EXEC ord.sp_ResolveComplaint @ComplaintId = @Cid, @AdminUserId = @Admin, @Decision = N'Resolved',
                                 @ResolutionType = N'Refund', @Resolution = N'Hoàn tiền toàn bộ', @RefundAmount = @Total;
    SET @ok = CASE WHEN EXISTS (SELECT 1 FROM ord.Complaints WHERE ComplaintId = @Cid AND Status = N'Resolved')
                    AND EXISTS (SELECT 1 FROM ord.Payments WHERE PaymentId = @Pay AND Status = N'Refunded')
                    AND EXISTS (SELECT 1 FROM ord.Orders WHERE OrderId = @Oid AND PaymentStatus = N'Refunded') THEN 1 ELSE 0 END;
    PRINT CASE WHEN @ok = 1 THEN N'PASS: hoàn tiền -> Complaint Resolved, Payment và Order Refunded' ELSE N'FAIL: hoàn tiền khiếu nại' END;

    -- 12. Nhật ký audit của Payments và Complaints
    SET @ok = CASE WHEN EXISTS (SELECT 1 FROM audit.AuditLogs WHERE TableSchema = N'ord' AND TableName = N'Payments'
                                  AND PrimaryKeyValue = CAST(@Pay AS NVARCHAR(100)) AND Action = N'UPDATE')
                    AND EXISTS (SELECT 1 FROM audit.AuditLogs WHERE TableSchema = N'ord' AND TableName = N'Complaints'
                                  AND PrimaryKeyValue = CAST(@Cid AS NVARCHAR(100))) THEN 1 ELSE 0 END;
    PRINT CASE WHEN @ok = 1 THEN N'PASS: audit ghi thay đổi Payments và Complaints' ELSE N'FAIL: audit Payments/Complaints' END;

    -- 13. Module AI thấy lịch sử đơn Completed của khách tại lab
    SELECT @hist = HistoryScore FROM ai.fn_LabScores(@Cust, NULL, NULL) WHERE LabId = @Lab;
    PRINT CASE WHEN @hist >= 0.5 THEN N'PASS: ai.fn_LabScores tính HistoryScore từ đơn Completed' ELSE N'FAIL: HistoryScore = ' + ISNULL(CAST(@hist AS NVARCHAR(20)), N'NULL') END;

    -- 14. View doanh thu thấy đơn Completed
    SET @ok = CASE WHEN EXISTS (SELECT 1 FROM ord.vw_LabRevenue WHERE LabId = @Lab AND CompletedOrders >= 1) THEN 1 ELSE 0 END;
    PRINT CASE WHEN @ok = 1 THEN N'PASS: vw_LabRevenue ghi nhận đơn Completed' ELSE N'FAIL: vw_LabRevenue' END;

    ROLLBACK;
END TRY
BEGIN CATCH
    SET @msg = ERROR_MESSAGE();
    IF @@TRANCOUNT > 0 ROLLBACK;
    PRINT N'FAIL: kịch bản dừng giữa chừng, lỗi ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' tại dòng '
          + CAST(ERROR_LINE() AS NVARCHAR(10)) + N': ' + @msg;
END CATCH
GO