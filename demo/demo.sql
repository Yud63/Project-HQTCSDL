/* ============================================================
   File    : demo/demo.sql
   Purpose : Chạy luồng chính dưới role thật (EXECUTE AS USER), kiểm chứng
             ownership chaining + RLS + GRANT/DENY. Mong đợi 13 PASS.
   Cách chạy (từ thư mục gốc repo):
     sqlcmd -S localhost -E -C -f 65001 -d FilmLabDB -i demo\demo.sql
   @Commit = 0 : chạy xong ROLLBACK, không đổi dữ liệu (chạy lại thoải mái)
   @Commit = 1 : giữ dữ liệu (đơn demo, user demo, lab được duyệt)
   ============================================================ */
USE FilmLabDB;
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
SET NOCOUNT ON;

DECLARE @Commit BIT = 0;
DECLARE @Admin INT = 1, @Cust INT = 6;
DECLARE @Lab INT, @Owner INT, @SvcDev INT, @SvcScan INT, @Stock INT, @Items NVARCHAR(MAX);
DECLARE @PickAddr INT, @RetAddr INT, @PendingLab INT;
DECLARE @Email NVARCHAR(255) = N'demo.' + LEFT(CONVERT(NVARCHAR(36), NEWID()), 8) + N'@example.com';
DECLARE @NewUser INT, @Oid INT, @Total DECIMAL(18,0), @Pay INT, @Fid UNIQUEIDENTIFIER, @Rid INT;
DECLARE @i INT, @n INT, @Stage INT, @ok BIT, @err INT;
DECLARE @Path TABLE (Step INT IDENTITY(1,1), StageId INT);
DECLARE @Login TABLE (UserId INT, FullName NVARCHAR(100), AuthProvider NVARCHAR(20),
                      PasswordHash NVARCHAR(255), IsActive BIT, Roles NVARCHAR(MAX));

-- ===== 0. Dựng 4 user không login, mỗi user một role =====
IF USER_ID(N'u_demo_auth') IS NOT NULL DROP USER u_demo_auth;
IF USER_ID(N'u_demo_cus')  IS NOT NULL DROP USER u_demo_cus;
IF USER_ID(N'u_demo_lab')  IS NOT NULL DROP USER u_demo_lab;
IF USER_ID(N'u_demo_adm')  IS NOT NULL DROP USER u_demo_adm;

BEGIN TRY
    BEGIN TRAN;

    CREATE USER u_demo_auth WITHOUT LOGIN;  ALTER ROLE role_Auth     ADD MEMBER u_demo_auth;
    CREATE USER u_demo_cus  WITHOUT LOGIN;  ALTER ROLE role_Customer ADD MEMBER u_demo_cus;
    CREATE USER u_demo_lab  WITHOUT LOGIN;  ALTER ROLE role_LabOwner ADD MEMBER u_demo_lab;
    CREATE USER u_demo_adm  WITHOUT LOGIN;  ALTER ROLE role_Admin    ADD MEMBER u_demo_adm;

    -- Dữ liệu đầu vào (đọc bằng dbo): lab Approved có cả dịch vụ Develop và Scan cùng khổ phim
    SELECT TOP 1 @Lab = l.LabId, @Owner = l.OwnerUserId, @SvcDev = d.LabServiceId, @SvcScan = s.LabServiceId
    FROM lab.FilmLabs l
    JOIN lab.LabServices d ON d.LabId = l.LabId AND d.IsActive = 1
         AND EXISTS (SELECT 1 FROM lab.ServiceTypes t WHERE t.ServiceTypeId = d.ServiceTypeId AND t.Category = N'Develop')
    JOIN lab.LabServices s ON s.LabId = l.LabId AND s.IsActive = 1 AND s.FormatId = d.FormatId
         AND EXISTS (SELECT 1 FROM lab.ServiceTypes t WHERE t.ServiceTypeId = s.ServiceTypeId AND t.Category = N'Scan')
    WHERE l.ApprovalStatus = N'Approved' AND l.IsDeleted = 0
    ORDER BY l.LabId;
    SELECT TOP 1 @Stock = StockId FROM lab.FilmStocks WHERE IsActive = 1 ORDER BY StockId;
    SELECT TOP 1 @PickAddr = AddressId FROM iam.Addresses
    WHERE UserId = @Cust AND IsDeleted = 0 ORDER BY IsDefault DESC, AddressId;
    SET @RetAddr = @PickAddr;

    SET @Items = N'[{"labServiceId":' + CAST(@SvcDev AS NVARCHAR(10)) + N',"filmStockId":' + CAST(@Stock AS NVARCHAR(10))
               + N',"quantity":1,"note":"demo"},{"labServiceId":' + CAST(@SvcScan AS NVARCHAR(10)) + N',"filmStockId":'
               + CAST(@Stock AS NVARCHAR(10)) + N',"quantity":1,"note":"demo"}]';

    -- ===== 1. role_Auth: đăng ký + lấy thông tin đăng nhập =====
    PRINT N'--- 1. role_Auth: sp_RegisterUser + sp_GetLoginInfo';
    EXECUTE AS USER = N'u_demo_auth';
    EXEC iam.sp_RegisterUser @Email = @Email, @FullName = N'Demo User', @PasswordHash = N'$2b$10$demo.hash.only',
                             @NewUserId = @NewUser OUTPUT;
    INSERT @Login EXEC iam.sp_GetLoginInfo @Email = @Email;
    REVERT;
    EXEC sp_set_session_context N'UserId', NULL;
    SET @ok = CASE WHEN @NewUser IS NOT NULL
                    AND EXISTS (SELECT 1 FROM @Login WHERE UserId = @NewUser AND IsActive = 1 AND Roles LIKE N'%Customer%')
                   THEN 1 ELSE 0 END;
    PRINT CASE WHEN @ok = 1 THEN N'PASS: D1 role_Auth đăng ký được, GetLoginInfo trả đúng user + role Customer'
               ELSE N'FAIL: D1 đăng ký / GetLoginInfo' END;

    SET @err = 0;
    BEGIN TRY
        EXECUTE AS USER = N'u_demo_auth';
        SET @n = (SELECT COUNT(*) FROM iam.Users);
        REVERT;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_NUMBER();
        REVERT;
    END CATCH;
    PRINT CASE WHEN @err = 229 THEN N'PASS: D2 role_Auth không SELECT trực tiếp được iam.Users (229)'
               ELSE N'FAIL: D2 role_Auth đọc được iam.Users (err ' + CAST(@err AS NVARCHAR(10)) + N')' END;

    -- ===== 2. Customer đặt đơn (Pickup + Delivery) =====
    PRINT N'--- 2. role_Customer: sp_CreateOrder (gọi nội bộ sp_RequestDelivery, sp_CreateNotification)';
    EXECUTE AS USER = N'u_demo_cus';
    EXEC ord.sp_CreateOrder @CustomerId = @Cust, @LabId = @Lab, @FulfillmentMethod = N'Pickup', @ReturnMethod = N'Delivery',
                            @PickupAddressId = @PickAddr, @ReturnAddressId = @RetAddr, @ItemsJson = @Items,
                            @CustomerNote = N'demo', @NewOrderId = @Oid OUTPUT;
    REVERT;
    EXEC sp_set_session_context N'UserId', NULL;
    SET @ok = CASE WHEN EXISTS (SELECT 1 FROM ord.Orders WHERE OrderId = @Oid AND StageId = 1)
                    AND (SELECT COUNT(*) FROM dlv.DeliveryRequests WHERE OrderId = @Oid) = 2
                    AND EXISTS (SELECT 1 FROM arc.Notifications WHERE OrderId = @Oid AND UserId = @Owner)
                   THEN 1 ELSE 0 END;
    PRINT CASE WHEN @ok = 1 THEN N'PASS: D3 Customer đặt đơn được: Pending, 2 chặng giao, có thông báo cho lab (ownership chaining vượt DENY)'
               ELSE N'FAIL: D3 sp_CreateOrder dưới role_Customer' END;

    SET @err = 0;
    BEGIN TRY
        EXECUTE AS USER = N'u_demo_cus';
        EXEC dlv.sp_RequestDelivery @OrderId = @Oid, @Direction = N'Pickup', @CustomerAddressId = @PickAddr, @Fee = 0;
        REVERT;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_NUMBER();
        REVERT;
    END CATCH;
    PRINT CASE WHEN @err = 229 THEN N'PASS: D4 Customer gọi trực tiếp sp_RequestDelivery bị chặn (229)'
               ELSE N'FAIL: D4 Customer gọi được sp_RequestDelivery (err ' + CAST(@err AS NVARCHAR(10)) + N')' END;

    SET @err = 0;
    BEGIN TRY
        EXECUTE AS USER = N'u_demo_cus';
        EXEC ord.sp_UpdateOrderStage @OrderId = @Oid, @ActorUserId = @Cust, @NewStageId = 2, @Note = N'khách tự đổi';
        REVERT;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_NUMBER();
        REVERT;
    END CATCH;
    PRINT CASE WHEN @err = 229 THEN N'PASS: D5 Customer không có EXECUTE sp_UpdateOrderStage (229)'
               ELSE N'FAIL: D5 Customer đổi được stage (err ' + CAST(@err AS NVARCHAR(10)) + N')' END;

    -- RLS: Customer 7 không thấy đơn của Customer 6
    EXECUTE AS USER = N'u_demo_cus';
    EXEC sp_set_session_context N'UserId', 7;
    SET @n = (SELECT COUNT(*) FROM ord.Orders WHERE OrderId = @Oid);
    REVERT;
    EXEC sp_set_session_context N'UserId', NULL;
    PRINT CASE WHEN @n = 0 THEN N'PASS: D6 RLS: Customer 7 không thấy đơn của Customer 6'
               ELSE N'FAIL: D6 RLS lộ đơn cho user khác' END;

    -- Đường đọc cho web (hiển thị kết quả, không đếm PASS)
    PRINT N'--- sp_GetMyOrders / sp_GetOrderDetail dưới role_Customer';
    EXECUTE AS USER = N'u_demo_cus';
    EXEC ord.sp_GetMyOrders @UserId = @Cust, @AsRole = N'Customer';
    EXEC ord.sp_GetOrderDetail @OrderId = @Oid, @UserId = @Cust;
    REVERT;
    EXEC sp_set_session_context N'UserId', NULL;

    -- Lộ trình stage của đơn (tính bằng dbo vì role không có EXECUTE fn_NextStage)
    SET @Stage = 1;
    WHILE 1 = 1
    BEGIN
        SET @n = ord.fn_NextStage(@Oid, @Stage);
        IF @n IS NULL OR @n <= @Stage BREAK;
        INSERT @Path (StageId) VALUES (@n);
        SET @Stage = @n;
    END;
    SET @n = (SELECT COUNT(*) FROM @Path);

    -- ===== 3. LabOwner xác nhận đơn -> Customer thanh toán =====
    PRINT N'--- 3. role_LabOwner xác nhận, role_Customer thanh toán';
    SET @Stage = (SELECT StageId FROM @Path WHERE Step = 1);
    EXECUTE AS USER = N'u_demo_lab';
    EXEC ord.sp_UpdateOrderStage @OrderId = @Oid, @ActorUserId = @Owner, @NewStageId = @Stage, @Note = N'demo';
    REVERT;
    EXEC sp_set_session_context N'UserId', NULL;

    SET @Total = (SELECT TotalAmount FROM ord.Orders WHERE OrderId = @Oid);
    EXECUTE AS USER = N'u_demo_cus';
    EXEC ord.sp_ProcessPayment @OrderId = @Oid, @ActorUserId = @Cust, @Method = N'EWallet', @Provider = N'MoMo',
                               @ProviderTxnId = N'DEMO-001', @Amount = @Total, @NewPaymentId = @Pay OUTPUT;
    REVERT;
    EXEC sp_set_session_context N'UserId', NULL;
    SET @ok = CASE WHEN EXISTS (SELECT 1 FROM ord.Orders WHERE OrderId = @Oid AND PaymentStatus = N'Paid')
                    AND EXISTS (SELECT 1 FROM ord.Payments WHERE PaymentId = @Pay AND Status = N'Succeeded') THEN 1 ELSE 0 END;
    PRINT CASE WHEN @ok = 1 THEN N'PASS: D7 Lab xác nhận đơn, Customer thanh toán, đơn chuyển Paid'
               ELSE N'FAIL: D7 xác nhận / thanh toán' END;

    -- ===== 4. LabOwner đẩy stage tới Scanning, upload scan, hoàn tất =====
    PRINT N'--- 4. role_LabOwner: đổi stage, upload scan, hoàn tất';
    SET @i = 2;
    EXECUTE AS USER = N'u_demo_lab';
    WHILE @i <= @n
    BEGIN
        SET @Stage = (SELECT StageId FROM @Path WHERE Step = @i);
        EXEC ord.sp_UpdateOrderStage @OrderId = @Oid, @ActorUserId = @Owner, @NewStageId = @Stage, @Note = N'demo';
        SET @i += 1;
        IF @Stage = 8 BREAK;
    END;
    EXEC arc.sp_UploadScan @OrderId = @Oid, @ActorUserId = @Owner, @FileName = N'demo_001.jpg',
                           @StorageUrl = N'https://example.com/demo_001.jpg', @ContentType = N'image/jpeg',
                           @FileSizeBytes = 1048576, @FrameNumber = 1,
                           @MetadataJson = N'{"cameraModel":"Nikon FM2","exposedIso":400}', @NewScanFileId = @Fid OUTPUT;
    WHILE @i <= @n
    BEGIN
        SET @Stage = (SELECT StageId FROM @Path WHERE Step = @i);
        EXEC ord.sp_UpdateOrderStage @OrderId = @Oid, @ActorUserId = @Owner, @NewStageId = @Stage, @Note = N'demo';
        SET @i += 1;
    END;
    REVERT;
    EXEC sp_set_session_context N'UserId', NULL;
    SET @ok = CASE WHEN EXISTS (SELECT 1 FROM arc.ScanFiles WHERE ScanFileId = @Fid AND OwnerUserId = @Cust)
                    AND EXISTS (SELECT 1 FROM arc.Notifications WHERE UserId = @Cust AND OrderId = @Oid AND [Type] = N'ScanReady')
                   THEN 1 ELSE 0 END;
    PRINT CASE WHEN @ok = 1 THEN N'PASS: D8 Lab upload scan, chủ sở hữu = khách, có thông báo ScanReady'
               ELSE N'FAIL: D8 upload scan' END;
    SET @ok = CASE WHEN EXISTS (SELECT 1 FROM ord.Orders WHERE OrderId = @Oid AND StageId = 12 AND CompletedAt IS NOT NULL)
                   THEN 1 ELSE 0 END;
    PRINT CASE WHEN @ok = 1 THEN N'PASS: D9 Đơn Completed, có CompletedAt'
               ELSE N'FAIL: D9 hoàn tất đơn' END;

    -- ===== 5. Customer đánh giá =====
    PRINT N'--- 5. role_Customer: sp_AddReview';
    EXECUTE AS USER = N'u_demo_cus';
    EXEC ord.sp_AddReview @OrderId = @Oid, @CustomerId = @Cust, @RatingOverall = 5, @Comment = N'Demo', @NewReviewId = @Rid OUTPUT;
    REVERT;
    EXEC sp_set_session_context N'UserId', NULL;
    SET @ok = CASE WHEN EXISTS (SELECT 1 FROM lab.FilmLabs WHERE LabId = @Lab AND ReviewCount >= 1
                                 AND AvgRating = ord.fn_LabAvgRating(@Lab)) THEN 1 ELSE 0 END;
    PRINT CASE WHEN @ok = 1 THEN N'PASS: D10 Review ghi được, AvgRating của lab khớp fn_LabAvgRating'
               ELSE N'FAIL: D10 review' END;

    -- ===== 6. Admin: duyệt lab, khóa/mở user =====
    PRINT N'--- 6. role_Admin: duyệt lab, khóa/mở user';
    SET @PendingLab = (SELECT TOP 1 LabId FROM lab.FilmLabs WHERE ApprovalStatus = N'Pending' AND IsDeleted = 0 ORDER BY LabId);
    IF @PendingLab IS NULL
    BEGIN
        PRINT N'SKIP: D11 không còn lab Pending (đã duyệt ở lần chạy @Commit = 1 trước đó)';
    END
    ELSE
    BEGIN
        EXECUTE AS USER = N'u_demo_adm';
        EXEC lab.sp_ListLabsForApproval @AdminUserId = @Admin, @Status = N'Pending';
        EXEC lab.sp_ApproveLab @LabId = @PendingLab, @AdminUserId = @Admin, @Decision = N'Approved';
        REVERT;
        EXEC sp_set_session_context N'UserId', NULL;
        SET @ok = CASE WHEN EXISTS (SELECT 1 FROM lab.FilmLabs WHERE LabId = @PendingLab AND ApprovalStatus = N'Approved')
                        AND EXISTS (SELECT 1 FROM lab.LabApprovals WHERE LabId = @PendingLab AND Decision = N'Approved')
                       THEN 1 ELSE 0 END;
        PRINT CASE WHEN @ok = 1 THEN N'PASS: D11 Admin duyệt lab Pending, có bản ghi LabApprovals'
                   ELSE N'FAIL: D11 duyệt lab' END;
    END;

    EXECUTE AS USER = N'u_demo_adm';
    EXEC iam.sp_SetUserStatus @AdminUserId = @Admin, @UserId = @NewUser, @IsActive = 0;
    REVERT;
    EXEC sp_set_session_context N'UserId', NULL;
    SET @ok = CASE WHEN EXISTS (SELECT 1 FROM iam.Users WHERE UserId = @NewUser AND IsActive = 0) THEN 1 ELSE 0 END;
    EXECUTE AS USER = N'u_demo_adm';
    EXEC iam.sp_SetUserStatus @AdminUserId = @Admin, @UserId = @NewUser, @IsActive = 1;
    REVERT;
    EXEC sp_set_session_context N'UserId', NULL;
    SET @ok = CASE WHEN @ok = 1 AND EXISTS (SELECT 1 FROM iam.Users WHERE UserId = @NewUser AND IsActive = 1) THEN 1 ELSE 0 END;
    PRINT CASE WHEN @ok = 1 THEN N'PASS: D12 Admin khóa rồi mở lại user'
               ELSE N'FAIL: D12 khóa/mở user' END;

    SET @err = 0;
    BEGIN TRY
        EXECUTE AS USER = N'u_demo_adm';
        SET @n = (SELECT COUNT(*) FROM iam.Users);
        REVERT;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_NUMBER();
        REVERT;
    END CATCH;
    PRINT CASE WHEN @err = 229 THEN N'PASS: D13 Admin không SELECT trực tiếp được iam.Users (phải qua procedure)'
               ELSE N'FAIL: D13 Admin đọc được iam.Users (err ' + CAST(@err AS NVARCHAR(10)) + N')' END;

    -- ===== Dọn dẹp =====
    DROP USER u_demo_auth;
    DROP USER u_demo_cus;
    DROP USER u_demo_lab;
    DROP USER u_demo_adm;

    IF @Commit = 1
    BEGIN
        COMMIT;
        PRINT N'Đã COMMIT: dữ liệu demo được giữ lại.';
    END
    ELSE
    BEGIN
        ROLLBACK;
        PRINT N'Đã ROLLBACK: dữ liệu không đổi (đặt @Commit = 1 nếu muốn giữ).';
    END;
END TRY
BEGIN CATCH
    REVERT;
    EXEC sp_set_session_context N'UserId', NULL;
    PRINT N'FAIL: demo dừng do lỗi ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' tại dòng '
          + CAST(ERROR_LINE() AS NVARCHAR(10)) + N': ' + ERROR_MESSAGE();
    IF @@TRANCOUNT > 0 ROLLBACK;
END CATCH;
GO