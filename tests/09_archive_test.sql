USE FilmLabDB;
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
SET NOCOUNT ON;

DECLARE @o1 INT = (SELECT OrderId FROM ord.Orders WHERE OrderCode = N'FL-2026-000001');
DECLARE @o2 INT = (SELECT OrderId FROM ord.Orders WHERE OrderCode = N'FL-2026-000002');
DECLARE @cust INT, @owner INT, @owner2 INT, @admin INT, @other INT, @fs INT, @e INT;
DECLARE @sf UNIQUEIDENTIFIER, @ghost UNIQUEIDENTIFIER, @alb INT, @alb2 INT, @nid INT;
DECLARE @base INT, @n0 INT, @n1 INT, @exp INT, @fut NVARCHAR(10);
DECLARE @s1 NVARCHAR(10), @s2 NVARCHAR(10), @s3 NVARCHAR(10), @s4 NVARCHAR(10), @s5 NVARCHAR(10);

SELECT @cust = o.CustomerId, @owner = l.OwnerUserId
FROM ord.Orders o JOIN lab.FilmLabs l ON l.LabId = o.LabId WHERE o.OrderId = @o1;
SELECT @owner2 = l.OwnerUserId
FROM ord.Orders o JOIN lab.FilmLabs l ON l.LabId = o.LabId WHERE o.OrderId = @o2;
SET @admin = (SELECT UserId FROM iam.Users WHERE Email = N'admin@filmlab.vn');
SET @other = (SELECT TOP 1 u.UserId FROM iam.Users u
              WHERE u.IsDeleted = 0 AND u.UserId NOT IN (@cust, @owner)
                AND NOT EXISTS (SELECT 1 FROM iam.UserRoles ur JOIN iam.Roles r ON r.RoleId = ur.RoleId
                                WHERE ur.UserId = u.UserId AND r.RoleCode = N'Admin')
              ORDER BY u.UserId);
SET @fs = (SELECT TOP 1 StockId FROM lab.FilmStocks ORDER BY StockId);
SET @fut = CONVERT(NVARCHAR(10), DATEADD(DAY, 10, SYSUTCDATETIME()), 23);

DECLARE @json NVARCHAR(MAX) = N'{"filmStockId":' + CAST(@fs AS NVARCHAR(10))
    + N',"cameraModel":"Nikon F3","lensModel":"50mm f/1.4","shootingDate":"2025-01-15","exposedIso":400,"processMethod":"C-41","scannerModel":"Noritsu HS-1800","scanResolutionDpi":3000,"note":"push +1"}';
DECLARE @jsonBad NVARCHAR(MAX) = N'{khong hop le';
DECLARE @jsonFuture NVARCHAR(MAX) = N'{"shootingDate":"' + @fut + N'"}';
DECLARE @jsonStock NVARCHAR(MAX) = N'{"filmStockId":-1}';

-- A. Luồng đúng (chủ lab upload) + thông báo + fn + chất lượng + album + view, cuối cùng trùng tên -> 50504
SET @e = 0; SET @sf = NULL;
BEGIN TRAN;
BEGIN TRY
    DISABLE TRIGGER ord.trg_Orders_PreventInvalidStage ON ord.Orders;
    UPDATE ord.Orders SET StageId = 8 WHERE OrderId = @o1;
    SET @base = (SELECT COUNT(*) FROM arc.ScanFiles WHERE OrderId = @o1);
    SET @exp = CASE WHEN @base = 0 THEN 1 ELSE 0 END;
    SET @n0 = (SELECT COUNT(*) FROM arc.Notifications WHERE OrderId = @o1 AND UserId = @cust AND Type = N'ScanReady');

    EXEC arc.sp_UploadScan @o1, @owner, N'test09_f01.jpg', N'https://storage.example.com/test09_f01.jpg', N'image/jpeg', 5242880,
         @FrameNumber = 1, @WidthPx = 6000, @HeightPx = 4000, @MetadataJson = @json, @NewScanFileId = @sf OUTPUT;

    IF @sf IS NOT NULL
       AND EXISTS (SELECT 1 FROM arc.ScanFiles WHERE ScanFileId = @sf AND OrderId = @o1 AND OwnerUserId = @cust
                   AND UploadedBy = @owner AND QualityStatus = N'NotChecked')
       AND EXISTS (SELECT 1 FROM arc.PhotoMetadata WHERE ScanFileId = @sf AND FilmStockId = @fs AND CameraModel = N'Nikon F3'
                   AND ExposedIso = 400 AND ScanResolutionDpi = 3000 AND JSON_VALUE(ExtraJson, N'$.note') = N'push +1')
        PRINT N'PASS: sp_UploadScan tạo ScanFiles + PhotoMetadata (ExtraJson giữ khóa phụ)';
    ELSE PRINT N'FAIL: sp_UploadScan hợp lệ';

    SET @n1 = (SELECT COUNT(*) FROM arc.Notifications WHERE OrderId = @o1 AND UserId = @cust AND Type = N'ScanReady');
    IF @n1 = @n0 + @exp PRINT N'PASS: trigger Notify gửi ScanReady cho khách ở lần upload đầu';
    ELSE PRINT N'FAIL: Notify lần đầu, trước ' + CAST(@n0 AS NVARCHAR(10)) + N' sau ' + CAST(@n1 AS NVARCHAR(10));

    EXEC arc.sp_UploadScan @o1, @owner, N'test09_f02.jpg', N'https://storage.example.com/test09_f02.jpg', N'image/jpeg', 1048576;
    IF (SELECT COUNT(*) FROM arc.Notifications WHERE OrderId = @o1 AND UserId = @cust AND Type = N'ScanReady') = @n1
        PRINT N'PASS: upload lần hai không gửi thêm ScanReady';
    ELSE PRINT N'FAIL: Notify lần hai';

    IF (SELECT COUNT(*) FROM arc.fn_GetPhotoMetadata(@sf)) = 1
       AND EXISTS (SELECT 1 FROM arc.fn_GetPhotoMetadata(@sf) WHERE MetaKey = N'note' AND MetaValue = N'push +1')
        PRINT N'PASS: fn_GetPhotoMetadata đọc ExtraJson';
    ELSE PRINT N'FAIL: fn_GetPhotoMetadata';

    EXEC arc.sp_SetScanQuality @sf, @owner, 85;
    SET @s1 = (SELECT QualityStatus FROM arc.ScanFiles WHERE ScanFileId = @sf);
    EXEC arc.sp_SetScanQuality @sf, @owner, 70;
    SET @s2 = (SELECT QualityStatus FROM arc.ScanFiles WHERE ScanFileId = @sf);
    EXEC arc.sp_SetScanQuality @sf, @owner, 69.99;
    SET @s3 = (SELECT QualityStatus FROM arc.ScanFiles WHERE ScanFileId = @sf);
    EXEC arc.sp_SetScanQuality @sf, @owner, 50;
    SET @s4 = (SELECT QualityStatus FROM arc.ScanFiles WHERE ScanFileId = @sf);
    EXEC arc.sp_SetScanQuality @sf, @owner, 49.99;
    SET @s5 = (SELECT QualityStatus FROM arc.ScanFiles WHERE ScanFileId = @sf);
    IF @s1 = N'Passed' AND @s2 = N'Passed' AND @s3 = N'Warning' AND @s4 = N'Warning' AND @s5 = N'Failed'
        PRINT N'PASS: sp_SetScanQuality tự suy ra trạng thái (ngưỡng 70 / 50)';
    ELSE PRINT N'FAIL: sp_SetScanQuality ngưỡng';

    INSERT INTO arc.Albums (OwnerUserId, Title) VALUES (@cust, N'Test09 Album');
    SET @alb = SCOPE_IDENTITY();
    INSERT INTO arc.AlbumPhotos (AlbumId, ScanFileId) VALUES (@alb, @sf);
    IF EXISTS (SELECT 1 FROM arc.AlbumPhotos WHERE AlbumId = @alb AND ScanFileId = @sf)
        PRINT N'PASS: AlbumPhotos_CheckOwner cho phép ảnh cùng chủ';
    ELSE PRINT N'FAIL: thêm ảnh vào album cùng chủ';

    IF EXISTS (SELECT 1 FROM arc.vw_CustomerArchive WHERE OwnerUserId = @cust AND ScanFileId = @sf
               AND OrderCode IS NOT NULL AND AlbumCount = 1 AND CameraModel = N'Nikon F3')
        PRINT N'PASS: arc.vw_CustomerArchive';
    ELSE PRINT N'FAIL: arc.vw_CustomerArchive';

    EXEC arc.sp_UploadScan @o1, @owner, N'test09_f01.jpg', N'https://storage.example.com/dup.jpg', N'image/jpeg', 1000;
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50504 PRINT N'PASS: trùng tên file -> 50504'; ELSE PRINT N'FAIL: trùng tên file, nhận ' + CAST(@e AS NVARCHAR(10));

-- B. Album khác chủ -> 50503
SET @e = 0; SET @sf = NULL;
BEGIN TRAN;
BEGIN TRY
    DISABLE TRIGGER ord.trg_Orders_PreventInvalidStage ON ord.Orders;
    UPDATE ord.Orders SET StageId = 8 WHERE OrderId = @o1;
    EXEC arc.sp_UploadScan @o1, @owner, N'test09_f01.jpg', N'https://storage.example.com/b.jpg', N'image/jpeg', 1000, @NewScanFileId = @sf OUTPUT;
    INSERT INTO arc.Albums (OwnerUserId, Title) VALUES (@other, N'Test09 Album Other');
    SET @alb2 = SCOPE_IDENTITY();
    INSERT INTO arc.AlbumPhotos (AlbumId, ScanFileId) VALUES (@alb2, @sf);
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50503 PRINT N'PASS: album khác chủ -> 50503'; ELSE PRINT N'FAIL: album khác chủ, nhận ' + CAST(@e AS NVARCHAR(10));

-- C. Admin upload được
SET @e = 0; SET @sf = NULL;
BEGIN TRAN;
BEGIN TRY
    DISABLE TRIGGER ord.trg_Orders_PreventInvalidStage ON ord.Orders;
    UPDATE ord.Orders SET StageId = 9 WHERE OrderId = @o1;
    EXEC arc.sp_UploadScan @o1, @admin, N'test09_admin.jpg', N'https://storage.example.com/admin.jpg', N'image/tiff', 2000, @NewScanFileId = @sf OUTPUT;
    IF EXISTS (SELECT 1 FROM arc.ScanFiles WHERE ScanFileId = @sf AND UploadedBy = @admin AND OwnerUserId = @cust)
        PRINT N'PASS: Admin upload được (giai đoạn 9)';
    ELSE PRINT N'FAIL: Admin upload';
END TRY
BEGIN CATCH PRINT N'FAIL: Admin upload, lỗi ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;

-- D. Người ngoài -> 50503
SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC arc.sp_UploadScan @o1, @other, N'test09_x.jpg', N'https://storage.example.com/x.jpg', N'image/jpeg', 1000; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50503 PRINT N'PASS: người ngoài upload -> 50503'; ELSE PRINT N'FAIL: người ngoài, nhận ' + CAST(@e AS NVARCHAR(10));

-- E. Đơn không tồn tại -> 50501
SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC arc.sp_UploadScan -1, @owner, N'test09_x.jpg', N'https://storage.example.com/x.jpg', N'image/jpeg', 1000; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50501 PRINT N'PASS: đơn không tồn tại -> 50501'; ELSE PRINT N'FAIL: đơn không tồn tại, nhận ' + CAST(@e AS NVARCHAR(10));

-- F. Sai giai đoạn (5) -> 50502
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    DISABLE TRIGGER ord.trg_Orders_PreventInvalidStage ON ord.Orders;
    UPDATE ord.Orders SET StageId = 5 WHERE OrderId = @o1;
    EXEC arc.sp_UploadScan @o1, @owner, N'test09_x.jpg', N'https://storage.example.com/x.jpg', N'image/jpeg', 1000;
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50502 PRINT N'PASS: sai giai đoạn -> 50502'; ELSE PRINT N'FAIL: sai giai đoạn, nhận ' + CAST(@e AS NVARCHAR(10));

-- G. Đơn không có dịch vụ Scan (đơn 000002, giai đoạn 9) -> 50502
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    DISABLE TRIGGER ord.trg_Orders_PreventInvalidStage ON ord.Orders;
    UPDATE ord.Orders SET StageId = 9 WHERE OrderId = @o2;
    EXEC arc.sp_UploadScan @o2, @owner2, N'test09_x.jpg', N'https://storage.example.com/x.jpg', N'image/jpeg', 1000;
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50502 PRINT N'PASS: đơn không có dịch vụ scan -> 50502'; ELSE PRINT N'FAIL: đơn không có scan, nhận ' + CAST(@e AS NVARCHAR(10));

-- H. ContentType sai -> 50505
SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC arc.sp_UploadScan @o1, @owner, N'test09_x.gif', N'https://storage.example.com/x.gif', N'image/gif', 1000; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50505 PRINT N'PASS: ContentType sai -> 50505'; ELSE PRINT N'FAIL: ContentType, nhận ' + CAST(@e AS NVARCHAR(10));

-- I. Kích thước 0 và > 200 MB -> 50505
SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC arc.sp_UploadScan @o1, @owner, N'test09_x.jpg', N'https://storage.example.com/x.jpg', N'image/jpeg', 0; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50505 PRINT N'PASS: kích thước 0 -> 50505'; ELSE PRINT N'FAIL: kích thước 0, nhận ' + CAST(@e AS NVARCHAR(10));

SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC arc.sp_UploadScan @o1, @owner, N'test09_x.jpg', N'https://storage.example.com/x.jpg', N'image/jpeg', 209715201; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50505 PRINT N'PASS: kích thước > 200 MB -> 50505'; ELSE PRINT N'FAIL: kích thước lớn, nhận ' + CAST(@e AS NVARCHAR(10));

-- J. FrameNumber 0 -> 50505
SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC arc.sp_UploadScan @o1, @owner, N'test09_x.jpg', N'https://storage.example.com/x.jpg', N'image/jpeg', 1000, @FrameNumber = 0; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50505 PRINT N'PASS: FrameNumber = 0 -> 50505'; ELSE PRINT N'FAIL: FrameNumber, nhận ' + CAST(@e AS NVARCHAR(10));

-- K. MetadataJson không hợp lệ -> 50505
SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC arc.sp_UploadScan @o1, @owner, N'test09_x.jpg', N'https://storage.example.com/x.jpg', N'image/jpeg', 1000, @MetadataJson = @jsonBad; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50505 PRINT N'PASS: MetadataJson sai -> 50505'; ELSE PRINT N'FAIL: MetadataJson sai, nhận ' + CAST(@e AS NVARCHAR(10));

-- L. shootingDate tương lai -> 50505
SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC arc.sp_UploadScan @o1, @owner, N'test09_x.jpg', N'https://storage.example.com/x.jpg', N'image/jpeg', 1000, @MetadataJson = @jsonFuture; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50505 PRINT N'PASS: shootingDate tương lai -> 50505'; ELSE PRINT N'FAIL: shootingDate, nhận ' + CAST(@e AS NVARCHAR(10));

-- M. filmStockId không tồn tại -> 50505
SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC arc.sp_UploadScan @o1, @owner, N'test09_x.jpg', N'https://storage.example.com/x.jpg', N'image/jpeg', 1000, @MetadataJson = @jsonStock; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50505 PRINT N'PASS: filmStockId không tồn tại -> 50505'; ELSE PRINT N'FAIL: filmStockId, nhận ' + CAST(@e AS NVARCHAR(10));

-- N. INSERT trực tiếp sai chủ -> trigger CheckOwner 50505
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    INSERT INTO arc.ScanFiles (OrderId, OwnerUserId, UploadedBy, FileName, StorageUrl, ContentType, FileSizeBytes)
    VALUES (@o1, @other, @owner, N'test09_direct.jpg', N'https://storage.example.com/direct.jpg', N'image/jpeg', 1000);
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50505 PRINT N'PASS: trigger ScanFiles_CheckOwner chặn sai chủ -> 50505'; ELSE PRINT N'FAIL: CheckOwner, nhận ' + CAST(@e AS NVARCHAR(10));

-- O. sp_SetScanQuality: điểm 101 -> 50505; người ngoài -> 50503; không tồn tại -> 50501
SET @e = 0; SET @sf = NULL; BEGIN TRAN;
BEGIN TRY
    DISABLE TRIGGER ord.trg_Orders_PreventInvalidStage ON ord.Orders;
    UPDATE ord.Orders SET StageId = 8 WHERE OrderId = @o1;
    EXEC arc.sp_UploadScan @o1, @owner, N'test09_q.jpg', N'https://storage.example.com/q.jpg', N'image/jpeg', 1000, @NewScanFileId = @sf OUTPUT;
    EXEC arc.sp_SetScanQuality @sf, @owner, 101;
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50505 PRINT N'PASS: điểm chất lượng 101 -> 50505'; ELSE PRINT N'FAIL: điểm 101, nhận ' + CAST(@e AS NVARCHAR(10));

SET @e = 0; SET @sf = NULL; BEGIN TRAN;
BEGIN TRY
    DISABLE TRIGGER ord.trg_Orders_PreventInvalidStage ON ord.Orders;
    UPDATE ord.Orders SET StageId = 8 WHERE OrderId = @o1;
    EXEC arc.sp_UploadScan @o1, @owner, N'test09_q.jpg', N'https://storage.example.com/q.jpg', N'image/jpeg', 1000, @NewScanFileId = @sf OUTPUT;
    EXEC arc.sp_SetScanQuality @sf, @other, 80;
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50503 PRINT N'PASS: SetScanQuality người ngoài -> 50503'; ELSE PRINT N'FAIL: SetScanQuality người ngoài, nhận ' + CAST(@e AS NVARCHAR(10));

SET @e = 0; SET @ghost = NEWID(); BEGIN TRAN;
BEGIN TRY EXEC arc.sp_SetScanQuality @ghost, @owner, 80; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50501 PRINT N'PASS: SetScanQuality file không tồn tại -> 50501'; ELSE PRINT N'FAIL: SetScanQuality không tồn tại, nhận ' + CAST(@e AS NVARCHAR(10));

-- P. sp_MarkNotificationRead
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC arc.sp_CreateNotification @cust, N'System', N'Test09 thông báo', N'Nội dung test', NULL, @NewNotificationId = @nid OUTPUT;
    EXEC arc.sp_MarkNotificationRead @nid, @cust;
    EXEC arc.sp_MarkNotificationRead @nid, @cust;
    IF EXISTS (SELECT 1 FROM arc.Notifications WHERE NotificationId = @nid AND IsRead = 1 AND ReadAt IS NOT NULL)
        PRINT N'PASS: sp_MarkNotificationRead đánh dấu đã đọc (gọi lại không lỗi)';
    ELSE PRINT N'FAIL: sp_MarkNotificationRead';
END TRY
BEGIN CATCH PRINT N'FAIL: sp_MarkNotificationRead, lỗi ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;

SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC arc.sp_CreateNotification @cust, N'System', N'Test09 thông báo', N'Nội dung test', NULL, @NewNotificationId = @nid OUTPUT;
    EXEC arc.sp_MarkNotificationRead @nid, @other;
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50503 PRINT N'PASS: đọc thông báo của người khác -> 50503'; ELSE PRINT N'FAIL: thông báo người khác, nhận ' + CAST(@e AS NVARCHAR(10));

SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC arc.sp_MarkNotificationRead -1, @cust; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50501 PRINT N'PASS: thông báo không tồn tại -> 50501'; ELSE PRINT N'FAIL: thông báo không tồn tại, nhận ' + CAST(@e AS NVARCHAR(10));

-- Q. An toàn: trigger đã bị tắt trong test phải còn bật sau ROLLBACK
IF (SELECT COUNT(*) FROM sys.triggers WHERE name = N'trg_Orders_PreventInvalidStage' AND is_disabled = 0) = 1
    PRINT N'PASS: trg_Orders_PreventInvalidStage vẫn bật sau test';
ELSE PRINT N'FAIL: trg_Orders_PreventInvalidStage đang bị tắt';
GO