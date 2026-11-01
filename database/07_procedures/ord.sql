/* ============================================================
   File    : database/07_procedures/ord.sql
   Module  : ord - M3 Order, Processing, Payment, Fee
   Purpose : Procedure (★ = bắt buộc): ★sp_CreateOrder, ★sp_UpdateOrderStage, ★sp_CancelOrder, ★sp_ProcessPayment. Dùng templates/procedure_template.sql; chữ ký theo docs/Contracts.md mục 7.
   Owner   : B (xem docs/Phan-cong.md)
   Depends : iam, lab
   Re-run  : CREATE OR ALTER - chạy lại bao nhiêu lần cũng được.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE ord.sp_UpdateOrderStage
    @OrderId          INT,
    @ActorUserId      INT,
    @NewStageId       INT,
    @Note             NVARCHAR(255) = NULL,
    @CallerAuthorized BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        EXEC sp_set_session_context @key = N'UserId', @value = @ActorUserId;

        BEGIN TRAN;

        DECLARE @CurStage INT, @LabId INT, @CustomerId INT, @Code NVARCHAR(20), @Pay NVARCHAR(9);
        SELECT @CurStage = StageId, @LabId = LabId, @CustomerId = CustomerId,
               @Code = OrderCode, @Pay = PaymentStatus
        FROM ord.Orders WITH (UPDLOCK, HOLDLOCK)
        WHERE OrderId = @OrderId AND IsDeleted = 0;

        IF @CurStage IS NULL
            THROW 50301, N'Đơn hàng không tồn tại.', 1;
        IF NOT EXISTS (SELECT 1 FROM ord.ProcessingStages WHERE StageId = @NewStageId)
            THROW 50305, N'Giai đoạn mới không tồn tại.', 1;

        IF @CallerAuthorized = 0
           AND NOT EXISTS (SELECT 1 FROM lab.FilmLabs WHERE LabId = @LabId AND OwnerUserId = @ActorUserId)
           AND NOT EXISTS (SELECT 1 FROM iam.UserRoles ur JOIN iam.Roles r ON r.RoleId = ur.RoleId
                           WHERE ur.UserId = @ActorUserId AND r.RoleCode = N'Admin')
            THROW 50303, N'Chỉ lab của đơn hoặc Admin được đổi giai đoạn.', 1;

        IF @NewStageId = 12 AND @CurStage = 11 AND @Pay <> N'Paid'
            THROW 50302, N'Đơn chưa thanh toán, không thể hoàn tất.', 1;
        IF ord.fn_IsValidTransition(@OrderId, @CurStage, @NewStageId) = 0
            THROW 50302, N'Chuyển giai đoạn không hợp lệ.', 1;

        EXEC sp_set_session_context @key = N'StageNote', @value = @Note;

        UPDATE ord.Orders
        SET StageId     = @NewStageId,
            UpdatedAt   = SYSUTCDATETIME(),
            CompletedAt = CASE WHEN @NewStageId = 12 THEN SYSUTCDATETIME() ELSE CompletedAt END,
            CancelReason = CASE WHEN @NewStageId = 13 THEN @Note ELSE CancelReason END
        WHERE OrderId = @OrderId;

        EXEC sp_set_session_context @key = N'StageNote', @value = NULL;

        DECLARE @StageName NVARCHAR(100) = (SELECT StageName FROM ord.ProcessingStages WHERE StageId = @NewStageId);
        DECLARE @Title NVARCHAR(150) = N'Đơn ' + @Code + N': ' + @StageName;
        EXEC arc.sp_CreateNotification @UserId = @CustomerId, @Type = N'OrderStage',
                                       @Title = @Title, @Body = @Note, @OrderId = @OrderId;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE ord.sp_CreateOrder
    @CustomerId        INT,
    @LabId             INT,
    @FulfillmentMethod NVARCHAR(7),
    @ReturnMethod      NVARCHAR(11),
    @PickupAddressId   INT = NULL,
    @ReturnAddressId   INT = NULL,
    @ItemsJson         NVARCHAR(MAX),
    @CustomerNote      NVARCHAR(500) = NULL,
    @NewOrderId        INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        EXEC sp_set_session_context @key = N'UserId', @value = @CustomerId;

        BEGIN TRAN;

        -- 1. Khách và lab
        IF NOT EXISTS (SELECT 1 FROM iam.Users WHERE UserId = @CustomerId AND IsDeleted = 0 AND IsActive = 1)
            THROW 50301, N'Khách hàng không tồn tại hoặc bị khóa.', 1;

        DECLARE @LabStatus NVARCHAR(12), @LabOwner INT;
        SELECT @LabStatus = ApprovalStatus, @LabOwner = OwnerUserId
        FROM lab.FilmLabs WITH (UPDLOCK, HOLDLOCK)          -- khóa dòng lab: chống vượt năng lực khi đặt đồng thời
        WHERE LabId = @LabId AND IsDeleted = 0;
        IF @LabStatus IS NULL
            THROW 50301, N'Lab không tồn tại.', 1;
        IF @LabStatus <> N'Approved'
            THROW 50302, N'Lab chưa được duyệt hoặc đang bị đình chỉ.', 1;

        -- 2. Hình thức nhận/trả và địa chỉ
        IF @FulfillmentMethod NOT IN (N'DropOff', N'Pickup') OR @ReturnMethod NOT IN (N'SelfCollect', N'Delivery')
            THROW 50305, N'Hình thức nhận/trả phim không hợp lệ.', 1;
        IF (@FulfillmentMethod = N'Pickup' AND @PickupAddressId IS NULL)
           OR (@ReturnMethod = N'Delivery' AND @ReturnAddressId IS NULL)
            THROW 50305, N'Thiếu địa chỉ nhận hoặc địa chỉ trả phim.', 1;
        IF (@PickupAddressId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM iam.Addresses WHERE AddressId = @PickupAddressId AND UserId = @CustomerId AND IsDeleted = 0))
           OR (@ReturnAddressId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM iam.Addresses WHERE AddressId = @ReturnAddressId AND UserId = @CustomerId AND IsDeleted = 0))
            THROW 50305, N'Địa chỉ không tồn tại hoặc không thuộc khách.', 1;

        -- 3. Đọc và kiểm tra dòng đơn
        IF @ItemsJson IS NULL OR ISJSON(@ItemsJson) = 0
            THROW 50305, N'ItemsJson rỗng hoặc không phải JSON hợp lệ.', 1;

        DECLARE @Items TABLE (ItemSeq INT IDENTITY(1,1), LabServiceId INT, FilmStockId INT, Quantity INT, Note NVARCHAR(255),
                              UnitPrice DECIMAL(18,0), Turnaround TINYINT, Category NVARCHAR(10), PriceUnit NVARCHAR(5), IsActive BIT);

        INSERT INTO @Items (LabServiceId, FilmStockId, Quantity, Note)
        SELECT TRY_CONVERT(INT, j.labServiceId), TRY_CONVERT(INT, j.filmStockId), TRY_CONVERT(INT, j.quantity), j.note
        FROM OPENJSON(@ItemsJson) WITH (labServiceId NVARCHAR(20) '$.labServiceId',
                                        filmStockId  NVARCHAR(20) '$.filmStockId',
                                        quantity     NVARCHAR(20) '$.quantity',
                                        note         NVARCHAR(255) '$.note') j;

        IF NOT EXISTS (SELECT 1 FROM @Items)
            THROW 50305, N'Đơn phải có ít nhất một dòng dịch vụ.', 1;
        IF EXISTS (SELECT 1 FROM @Items WHERE LabServiceId IS NULL OR Quantity IS NULL OR Quantity <= 0)
            THROW 50305, N'Dòng dịch vụ thiếu mã hoặc số lượng không hợp lệ.', 1;

        UPDATE i SET UnitPrice = ls.UnitPrice, Turnaround = ls.TurnaroundDays,
                     Category = st.Category, PriceUnit = ls.PriceUnit, IsActive = ls.IsActive
        FROM @Items i
        JOIN lab.LabServices ls ON ls.LabServiceId = i.LabServiceId AND ls.LabId = @LabId AND ls.IsDeleted = 0
        JOIN lab.ServiceTypes st ON st.ServiceTypeId = ls.ServiceTypeId;

        IF EXISTS (SELECT 1 FROM @Items WHERE UnitPrice IS NULL)
            THROW 50301, N'Dịch vụ không tồn tại hoặc không thuộc lab này.', 1;
        IF EXISTS (SELECT 1 FROM @Items WHERE IsActive = 0)
            THROW 50302, N'Có dịch vụ đã ngừng bán.', 1;
        IF EXISTS (SELECT 1 FROM @Items i WHERE i.FilmStockId IS NOT NULL
                   AND NOT EXISTS (SELECT 1 FROM lab.FilmStocks fs WHERE fs.StockId = i.FilmStockId))
            THROW 50301, N'Loại phim không tồn tại.', 1;

        -- 4. Năng lực lab trong ngày
        DECLARE @Today DATE = CAST(SYSUTCDATETIME() AS DATE);
        DECLARE @Rolls INT = ISNULL((SELECT SUM(Quantity) FROM @Items WHERE Category = N'Develop' AND PriceUnit = N'Roll'), 0);
        IF @Rolls > lab.fn_LabCapacityLeft(@LabId, @Today)
            THROW 50306, N'Lab đã hết năng lực nhận cuộn trong ngày.', 1;

        -- 5. Tính tiền
        DECLARE @Subtotal DECIMAL(18,0) = (SELECT SUM(CAST(Quantity AS DECIMAL(18,0)) * UnitPrice) FROM @Items);
        DECLARE @Legs INT = CASE WHEN @FulfillmentMethod = N'Pickup' THEN 1 ELSE 0 END
                          + CASE WHEN @ReturnMethod = N'Delivery' THEN 1 ELSE 0 END;
        DECLARE @LegFee DECIMAL(18,0) = ord.fn_CalcDeliveryFee(@LabId, @Today);
        DECLARE @DeliveryFee DECIMAL(18,0) = @Legs * @LegFee;
        DECLARE @PlatformFee DECIMAL(18,0) = ord.fn_CalcPlatformFee(@LabId, @Subtotal, @Today);
        DECLARE @Total DECIMAL(18,0) = ord.fn_CalcOrderTotal(@Subtotal, @DeliveryFee);
        DECLARE @Ready DATE = DATEADD(DAY, (SELECT MAX(Turnaround) FROM @Items), @Today);
        DECLARE @Code NVARCHAR(20) = N'FL-' + CAST(YEAR(SYSUTCDATETIME()) AS NVARCHAR(4)) + N'-'
                                   + RIGHT(N'000000' + CAST(NEXT VALUE FOR ord.seq_OrderCode AS NVARCHAR(10)), 6);

        -- 6. Ghi đơn, dòng đơn (trigger tự ghi OrderStageLog khởi tạo)
        INSERT INTO ord.Orders (OrderCode, CustomerId, LabId, FulfillmentMethod, ReturnMethod, PickupAddressId, ReturnAddressId,
                                Subtotal, DeliveryFee, PlatformFee, TotalAmount, CustomerNote, EstimatedReadyDate)
        VALUES (@Code, @CustomerId, @LabId, @FulfillmentMethod, @ReturnMethod, @PickupAddressId, @ReturnAddressId,
                @Subtotal, @DeliveryFee, @PlatformFee, @Total, @CustomerNote, @Ready);
        SET @NewOrderId = SCOPE_IDENTITY();

        INSERT INTO ord.OrderItems (OrderId, LabServiceId, FilmStockId, Quantity, UnitPriceSnapshot, ProcessingNote)
        SELECT @NewOrderId, LabServiceId, FilmStockId, Quantity, UnitPrice, Note FROM @Items ORDER BY ItemSeq;

        -- 7. Các chặng giao
        IF @FulfillmentMethod = N'Pickup'
            EXEC dlv.sp_RequestDelivery @OrderId = @NewOrderId, @Direction = N'Pickup',
                                        @CustomerAddressId = @PickupAddressId, @Fee = @LegFee;
        IF @ReturnMethod = N'Delivery'
            EXEC dlv.sp_RequestDelivery @OrderId = @NewOrderId, @Direction = N'Return',
                                        @CustomerAddressId = @ReturnAddressId, @Fee = @LegFee;

        -- 8. Báo cho chủ lab
        DECLARE @Title NVARCHAR(150) = N'Đơn mới ' + @Code;
        EXEC arc.sp_CreateNotification @UserId = @LabOwner, @Type = N'OrderStage',
                                       @Title = @Title, @Body = @CustomerNote, @OrderId = @NewOrderId;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE ord.sp_ProcessPayment
    @OrderId        INT,
    @ActorUserId    INT,
    @Method         NVARCHAR(12),
    @Provider       NVARCHAR(30)  = NULL,
    @ProviderTxnId  NVARCHAR(100) = NULL,
    @Amount         DECIMAL(18,0),
    @Succeeded      BIT = 1,
    @FailureReason  NVARCHAR(255) = NULL,
    @NewPaymentId   INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        EXEC sp_set_session_context @key = N'UserId', @value = @ActorUserId;

        BEGIN TRAN;

        DECLARE @Stage INT, @CustomerId INT, @Total DECIMAL(18,0), @Pay NVARCHAR(9), @Code NVARCHAR(20), @LabOwner INT;
        SELECT @Stage = o.StageId, @CustomerId = o.CustomerId, @Total = o.TotalAmount,
               @Pay = o.PaymentStatus, @Code = o.OrderCode, @LabOwner = l.OwnerUserId
        FROM ord.Orders o WITH (UPDLOCK, HOLDLOCK)
        JOIN lab.FilmLabs l ON l.LabId = o.LabId
        WHERE o.OrderId = @OrderId AND o.IsDeleted = 0;

        IF @Stage IS NULL
            THROW 50301, N'Đơn hàng không tồn tại.', 1;
        IF @ActorUserId <> @CustomerId
           AND NOT EXISTS (SELECT 1 FROM iam.UserRoles ur JOIN iam.Roles r ON r.RoleId = ur.RoleId
                           WHERE ur.UserId = @ActorUserId AND r.RoleCode = N'Admin')
            THROW 50303, N'Chỉ khách của đơn hoặc Admin được thanh toán.', 1;
        IF @Stage IN (1, 13) OR @Pay = N'Paid'
            THROW 50302, N'Đơn chưa được lab xác nhận, đã hủy hoặc đã thanh toán.', 1;
        IF @Method NOT IN (N'Card', N'EWallet', N'BankTransfer')
            THROW 50305, N'Phương thức thanh toán không hợp lệ.', 1;
        IF @Amount IS NULL OR @Amount <> @Total
            THROW 50305, N'Số tiền thanh toán khác tổng tiền của đơn.', 1;
        IF @Succeeded = 0 AND NULLIF(LTRIM(RTRIM(@FailureReason)), N'') IS NULL
            THROW 50305, N'Thanh toán thất bại phải có lý do.', 1;

        INSERT INTO ord.Payments (OrderId, Method, Provider, ProviderTxnId, Amount, Status, PaidAt, FailureReason)
        VALUES (@OrderId, @Method, @Provider, @ProviderTxnId, @Amount,
                CASE WHEN @Succeeded = 1 THEN N'Succeeded' ELSE N'Failed' END,
                CASE WHEN @Succeeded = 1 THEN SYSUTCDATETIME() END,
                CASE WHEN @Succeeded = 0 THEN @FailureReason END);
        SET @NewPaymentId = SCOPE_IDENTITY();      -- trigger trg_Payments_UpdateOrder cập nhật PaymentStatus

        DECLARE @Title NVARCHAR(150) =
            N'Đơn ' + @Code + CASE WHEN @Succeeded = 1 THEN N': thanh toán thành công' ELSE N': thanh toán thất bại' END;
        EXEC arc.sp_CreateNotification @UserId = @CustomerId, @Type = N'Payment', @Title = @Title, @OrderId = @OrderId;
        IF @Succeeded = 1
            EXEC arc.sp_CreateNotification @UserId = @LabOwner, @Type = N'Payment', @Title = @Title, @OrderId = @OrderId;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE ord.sp_CancelOrder
    @OrderId      INT,
    @ActorUserId  INT,
    @Reason       NVARCHAR(255)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        EXEC sp_set_session_context @key = N'UserId', @value = @ActorUserId;

        BEGIN TRAN;

        DECLARE @Stage INT, @CustomerId INT, @Pay NVARCHAR(9), @Code NVARCHAR(20), @LabOwner INT;
        SELECT @Stage = o.StageId, @CustomerId = o.CustomerId, @Pay = o.PaymentStatus,
               @Code = o.OrderCode, @LabOwner = l.OwnerUserId
        FROM ord.Orders o WITH (UPDLOCK, HOLDLOCK)
        JOIN lab.FilmLabs l ON l.LabId = o.LabId
        WHERE o.OrderId = @OrderId AND o.IsDeleted = 0;

        IF @Stage IS NULL
            THROW 50301, N'Đơn hàng không tồn tại.', 1;
        IF @ActorUserId NOT IN (@CustomerId, @LabOwner)
           AND NOT EXISTS (SELECT 1 FROM iam.UserRoles ur JOIN iam.Roles r ON r.RoleId = ur.RoleId
                           WHERE ur.UserId = @ActorUserId AND r.RoleCode = N'Admin')
            THROW 50303, N'Chỉ khách, lab của đơn hoặc Admin được hủy đơn.', 1;
        IF NULLIF(LTRIM(RTRIM(@Reason)), N'') IS NULL
            THROW 50305, N'Phải nhập lý do hủy.', 1;
        IF ord.fn_IsValidTransition(@OrderId, @Stage, 13) = 0
            THROW 50302, N'Đơn đã vào giai đoạn tráng hoặc đã kết thúc, không thể hủy.', 1;
        IF EXISTS (SELECT 1 FROM dlv.DeliveryRequests
                   WHERE OrderId = @OrderId AND Status = N'PickedUp' AND IsDeleted = 0)
            THROW 50302, N'Chặng giao đã lấy hàng, không thể hủy đơn.', 1;

        -- Hủy các chặng giao còn hiệu lực
        DECLARE @LegId INT = 0;
        WHILE 1 = 1
        BEGIN
            SELECT @LegId = MIN(DeliveryRequestId) FROM dlv.DeliveryRequests
            WHERE OrderId = @OrderId AND IsDeleted = 0 AND DeliveryRequestId > @LegId
              AND Status IN (N'Requested', N'Assigned');
            IF @LegId IS NULL BREAK;
            EXEC dlv.sp_UpdateDeliveryStatus @LegId, @ActorUserId, N'Cancelled', @Reason, NULL, 1;
        END;

        -- Hoàn tiền nếu đã thanh toán (trigger trg_Payments_UpdateOrder đặt PaymentStatus = Refunded)
        IF @Pay = N'Paid'
            UPDATE ord.Payments SET Status = N'Refunded', RefundedAt = SYSUTCDATETIME()
            WHERE OrderId = @OrderId AND Status = N'Succeeded';

        EXEC ord.sp_UpdateOrderStage @OrderId, @ActorUserId, 13, @Reason, @CallerAuthorized = 1;

        IF @ActorUserId <> @LabOwner
        BEGIN
            DECLARE @Title NVARCHAR(150) = N'Đơn ' + @Code + N' đã bị hủy';
            EXEC arc.sp_CreateNotification @UserId = @LabOwner, @Type = N'OrderStage',
                                           @Title = @Title, @Body = @Reason, @OrderId = @OrderId;
        END;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE ord.sp_SetFeeConfig
    @AdminUserId   INT,
    @FeeType       NVARCHAR(20),     -- PlatformCommission | MarketplaceFee | DeliveryBase
    @EffectiveFrom DATE,
    @Rate          DECIMAL(5,4)  = NULL,
    @FixedAmount   DECIMAL(18,0) = NULL,
    @EffectiveTo   DATE          = NULL,
    @ScopeLabId    INT           = NULL,   -- NULL: toàn hệ thống
    @NewFeeConfigId INT          = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        EXEC sp_set_session_context @key = N'UserId', @value = @AdminUserId;

        IF NOT EXISTS (SELECT 1 FROM iam.UserRoles ur JOIN iam.Roles r ON r.RoleId = ur.RoleId
                       WHERE ur.UserId = @AdminUserId AND r.RoleCode = N'Admin')
            THROW 50303, N'Chỉ Admin được cấu hình phí.', 1;
        IF @FeeType IS NULL OR @FeeType NOT IN (N'PlatformCommission', N'MarketplaceFee', N'DeliveryBase')
            THROW 50305, N'FeeType không hợp lệ.', 1;
        IF @EffectiveFrom IS NULL
            THROW 50305, N'EffectiveFrom không được rỗng.', 1;
        IF @Rate IS NULL AND @FixedAmount IS NULL
            THROW 50305, N'Phải có Rate hoặc FixedAmount.', 1;
        IF @Rate < 0 OR @Rate > 1
            THROW 50305, N'Rate phải từ 0 đến 1.', 1;
        IF @FixedAmount < 0
            THROW 50305, N'FixedAmount phải từ 0 trở lên.', 1;
        IF @EffectiveTo IS NOT NULL AND @EffectiveTo < @EffectiveFrom
            THROW 50305, N'EffectiveTo phải từ EffectiveFrom trở đi.', 1;
        IF @ScopeLabId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM lab.FilmLabs WHERE LabId = @ScopeLabId AND IsDeleted = 0)
            THROW 50301, N'Lab trong phạm vi cấu hình không tồn tại.', 1;

        BEGIN TRAN;

        -- Đóng bản đang mở (EffectiveTo NULL) cùng loại và phạm vi, bắt đầu trước bản mới
        UPDATE ord.FeeConfigs
        SET EffectiveTo = DATEADD(DAY, -1, @EffectiveFrom)
        WHERE FeeType = @FeeType
          AND ISNULL(ScopeLabId, 0) = ISNULL(@ScopeLabId, 0)
          AND EffectiveTo IS NULL
          AND EffectiveFrom < @EffectiveFrom;

        INSERT INTO ord.FeeConfigs (FeeType, Rate, FixedAmount, ScopeLabId, EffectiveFrom, EffectiveTo, CreatedBy)
        VALUES (@FeeType, @Rate, @FixedAmount, @ScopeLabId, @EffectiveFrom, @EffectiveTo, @AdminUserId);
        SET @NewFeeConfigId = SCOPE_IDENTITY();

        COMMIT;   -- trigger ord.trg_FeeConfigs_NoOverlap ném 50304 nếu vẫn chồng hiệu lực
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO