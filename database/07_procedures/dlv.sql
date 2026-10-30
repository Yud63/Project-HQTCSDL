/* ============================================================
   File    : database/07_procedures/dlv.sql
   Module  : dlv - M4 Delivery
   Purpose : Procedure (★ = bắt buộc): ★sp_UpdateDeliveryStatus, sp_RequestDelivery, sp_AssignPartner. Dùng templates/procedure_template.sql; chữ ký theo docs/Contracts.md mục 7.
   Owner   : A (xem docs/Phan-cong.md)
   Depends : iam, ord
   Re-run  : CREATE OR ALTER - chạy lại bao nhiêu lần cũng được.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE dlv.sp_RequestDelivery
    @OrderId           INT,
    @Direction         NVARCHAR(6),
    @CustomerAddressId INT,
    @Fee               DECIMAL(18,0),
    @NewDeliveryRequestId INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        IF @Direction NOT IN (N'Pickup', N'Return') OR @Fee IS NULL OR @Fee < 0
            THROW 50405, N'Hướng giao hoặc phí giao không hợp lệ.', 1;

        DECLARE @CustomerId INT, @LabLoc geography;
        SELECT @CustomerId = o.CustomerId, @LabLoc = l.Location
        FROM ord.Orders o JOIN lab.FilmLabs l ON l.LabId = o.LabId
        WHERE o.OrderId = @OrderId AND o.IsDeleted = 0;
        IF @CustomerId IS NULL
            THROW 50401, N'Đơn hàng không tồn tại.', 1;

        DECLARE @AddrLoc geography;
        SELECT @AddrLoc = Location FROM iam.Addresses
        WHERE AddressId = @CustomerAddressId AND UserId = @CustomerId AND IsDeleted = 0;
        IF @@ROWCOUNT = 0
            THROW 50405, N'Địa chỉ không tồn tại hoặc không thuộc khách của đơn.', 1;

        IF EXISTS (SELECT 1 FROM dlv.DeliveryRequests
                   WHERE OrderId = @OrderId AND Direction = @Direction
                     AND Status NOT IN (N'Failed', N'Cancelled') AND IsDeleted = 0)
            THROW 50404, N'Đơn đã có chặng giao còn hiệu lực cùng hướng.', 1;

        INSERT INTO dlv.DeliveryRequests (OrderId, Direction, CustomerAddressId, Fee, DistanceKm)
        VALUES (@OrderId, @Direction, @CustomerAddressId, @Fee, lab.fn_DistanceKm(@LabLoc, @AddrLoc));

        SET @NewDeliveryRequestId = SCOPE_IDENTITY();
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE dlv.sp_AssignPartner
    @DeliveryRequestId INT,
    @ActorUserId       INT,
    @DeliveryPartnerId INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        EXEC sp_set_session_context @key = N'UserId', @value = @ActorUserId;

        BEGIN TRAN;

        DECLARE @Cur NVARCHAR(10), @LabOwner INT;
        SELECT @Cur = d.Status, @LabOwner = l.OwnerUserId
        FROM dlv.DeliveryRequests d WITH (UPDLOCK, HOLDLOCK)
        JOIN ord.Orders o ON o.OrderId = d.OrderId
        JOIN lab.FilmLabs l ON l.LabId = o.LabId
        WHERE d.DeliveryRequestId = @DeliveryRequestId AND d.IsDeleted = 0;

        IF @Cur IS NULL
            THROW 50401, N'Chặng giao không tồn tại.', 1;
        IF @ActorUserId <> @LabOwner
           AND NOT EXISTS (SELECT 1 FROM iam.UserRoles ur JOIN iam.Roles r ON r.RoleId = ur.RoleId
                           WHERE ur.UserId = @ActorUserId AND r.RoleCode = N'Admin')
            THROW 50403, N'Chỉ lab của đơn hoặc Admin được phân công đối tác.', 1;
        IF @Cur <> N'Requested'
            THROW 50402, N'Chỉ phân công được chặng đang ở trạng thái Requested.', 1;
        IF NOT EXISTS (SELECT 1 FROM iam.DeliveryPartners
                       WHERE DeliveryPartnerId = @DeliveryPartnerId AND IsActive = 1 AND IsDeleted = 0)
            THROW 50405, N'Đối tác giao nhận không tồn tại hoặc đã ngừng hoạt động.', 1;

        EXEC sp_set_session_context @key = N'DeliveryNote', @value = N'Phân công đối tác';
        UPDATE dlv.DeliveryRequests
        SET DeliveryPartnerId = @DeliveryPartnerId, Status = N'Assigned', UpdatedAt = SYSUTCDATETIME()
        WHERE DeliveryRequestId = @DeliveryRequestId;
        EXEC sp_set_session_context @key = N'DeliveryNote', @value = NULL;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE dlv.sp_UpdateDeliveryStatus
    @DeliveryRequestId INT,
    @ActorUserId       INT,
    @NewStatus         NVARCHAR(10),
    @Note              NVARCHAR(255) = NULL,
    @FailureReason     NVARCHAR(255) = NULL,
    @CallerAuthorized  BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        EXEC sp_set_session_context @key = N'UserId', @value = @ActorUserId;

        BEGIN TRAN;

        DECLARE @OrderId INT, @Cur NVARCHAR(10), @Dir NVARCHAR(6), @PartnerId INT;
        SELECT @OrderId = OrderId, @Cur = Status, @Dir = Direction, @PartnerId = DeliveryPartnerId
        FROM dlv.DeliveryRequests WITH (UPDLOCK, HOLDLOCK)
        WHERE DeliveryRequestId = @DeliveryRequestId AND IsDeleted = 0;

        IF @Cur IS NULL
            THROW 50401, N'Chặng giao không tồn tại.', 1;
        IF @NewStatus NOT IN (N'Requested', N'Assigned', N'PickedUp', N'Delivered', N'Failed', N'Cancelled')
            THROW 50405, N'Trạng thái chặng giao không hợp lệ.', 1;

        DECLARE @CustomerId INT, @Code NVARCHAR(20), @Stage INT, @Pay NVARCHAR(9), @LabOwner INT;
        SELECT @CustomerId = o.CustomerId, @Code = o.OrderCode, @Stage = o.StageId,
               @Pay = o.PaymentStatus, @LabOwner = l.OwnerUserId
        FROM ord.Orders o JOIN lab.FilmLabs l ON l.LabId = o.LabId
        WHERE o.OrderId = @OrderId;

        IF @CallerAuthorized = 0
           AND @ActorUserId <> @LabOwner
           AND NOT EXISTS (SELECT 1 FROM iam.DeliveryPartners WHERE DeliveryPartnerId = @PartnerId AND UserId = @ActorUserId)
           AND NOT EXISTS (SELECT 1 FROM iam.UserRoles ur JOIN iam.Roles r ON r.RoleId = ur.RoleId
                           WHERE ur.UserId = @ActorUserId AND r.RoleCode = N'Admin')
            THROW 50403, N'Chỉ đối tác của chặng, lab của đơn hoặc Admin được đổi trạng thái.', 1;
        IF @NewStatus = N'Failed' AND NULLIF(LTRIM(RTRIM(@FailureReason)), N'') IS NULL
            THROW 50405, N'Chặng giao thất bại phải có lý do.', 1;
        IF @NewStatus = N'Assigned' AND @PartnerId IS NULL
            THROW 50402, N'Phải phân công đối tác qua dlv.sp_AssignPartner.', 1;
        IF @Dir = N'Return' AND @NewStatus IN (N'PickedUp', N'Delivered') AND @Pay <> N'Paid'
            THROW 50402, N'Đơn chưa thanh toán, không được giao trả phim.', 1;
        IF dlv.fn_IsValidDeliveryTransition(@Cur, @NewStatus) = 0
            THROW 50402, N'Chuyển trạng thái chặng giao không hợp lệ.', 1;

        DECLARE @LogNote NVARCHAR(255) = COALESCE(@Note, @FailureReason);
        EXEC sp_set_session_context @key = N'DeliveryNote', @value = @LogNote;

        UPDATE dlv.DeliveryRequests
        SET Status        = @NewStatus,
            UpdatedAt     = SYSUTCDATETIME(),
            PickedUpAt    = CASE WHEN @NewStatus = N'PickedUp'  THEN SYSUTCDATETIME() ELSE PickedUpAt END,
            DeliveredAt   = CASE WHEN @NewStatus = N'Delivered' THEN SYSUTCDATETIME() ELSE DeliveredAt END,
            FailureReason = CASE WHEN @NewStatus = N'Failed'    THEN @FailureReason ELSE FailureReason END
        WHERE DeliveryRequestId = @DeliveryRequestId;

        EXEC sp_set_session_context @key = N'DeliveryNote', @value = NULL;

        -- Đồng bộ giai đoạn của đơn
        IF @NewStatus = N'Delivered' AND @Dir = N'Pickup' AND @Stage = 3
            EXEC ord.sp_UpdateOrderStage @OrderId, @ActorUserId, 4, N'Đã nhận phim qua chặng lấy phim', @CallerAuthorized = 1;
        IF @NewStatus = N'Delivered' AND @Dir = N'Return' AND @Stage = 11
            EXEC ord.sp_UpdateOrderStage @OrderId, @ActorUserId, 12, N'Đã giao trả phim', @CallerAuthorized = 1;

        -- Thông báo cho khách (hủy chặng do hủy đơn đã có thông báo riêng)
        IF @NewStatus <> N'Cancelled'
        BEGIN
            DECLARE @Title NVARCHAR(150) = N'Đơn ' + @Code + N': chặng '
                + CASE WHEN @Dir = N'Pickup' THEN N'lấy phim' ELSE N'trả phim' END + N' - ' + @NewStatus;
            EXEC arc.sp_CreateNotification @UserId = @CustomerId, @Type = N'Delivery',
                                           @Title = @Title, @Body = @Note, @OrderId = @OrderId;
        END;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO