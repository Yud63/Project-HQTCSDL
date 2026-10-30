/* ============================================================
   File    : database/07_procedures/ord_feedback.sql
   Module  : ord_feedback - M6 Review & Complaint
   Purpose : Procedure (★ = bắt buộc): ★sp_AddReview, ★sp_FileComplaint, ★sp_ResolveComplaint, sp_ReplyReview, sp_ModerateReview. Dùng templates/procedure_template.sql; chữ ký theo docs/Contracts.md mục 7.
   Owner   : C (xem docs/Phan-cong.md)
   Depends : iam, lab, ord (ord.sql chạy trước)
   Re-run  : CREATE OR ALTER - chạy lại bao nhiêu lần cũng được.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE ord.sp_AddReview
    @OrderId           INT,
    @CustomerId        INT,
    @RatingOverall     TINYINT,
    @RatingScanQuality TINYINT = NULL,
    @RatingSpeed       TINYINT = NULL,
    @Comment           NVARCHAR(1000) = NULL,
    @NewReviewId       INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        EXEC sp_set_session_context @key = N'UserId', @value = @CustomerId;

        BEGIN TRAN;

        DECLARE @OrderCustomer INT, @LabId INT, @Stage INT, @CompletedAt DATETIME2(0), @Code NVARCHAR(20), @LabOwner INT;
        SELECT @OrderCustomer = o.CustomerId, @LabId = o.LabId, @Stage = o.StageId,
               @CompletedAt = o.CompletedAt, @Code = o.OrderCode, @LabOwner = l.OwnerUserId
        FROM ord.Orders o WITH (UPDLOCK, HOLDLOCK)
        JOIN lab.FilmLabs l ON l.LabId = o.LabId
        WHERE o.OrderId = @OrderId AND o.IsDeleted = 0;

        IF @OrderCustomer IS NULL
            THROW 50301, N'Đơn hàng không tồn tại.', 1;
        IF @OrderCustomer <> @CustomerId
            THROW 50303, N'Chỉ khách của đơn được đánh giá.', 1;
        IF @Stage <> 12 OR @CompletedAt IS NULL OR DATEADD(DAY, 30, @CompletedAt) < SYSUTCDATETIME()
            THROW 50302, N'Đơn chưa hoàn tất hoặc đã quá 30 ngày kể từ lúc hoàn tất.', 1;
        IF EXISTS (SELECT 1 FROM ord.Reviews WHERE OrderId = @OrderId)
            THROW 50304, N'Đơn này đã được đánh giá.', 1;
        IF @RatingOverall NOT BETWEEN 1 AND 5
           OR @RatingScanQuality NOT BETWEEN 1 AND 5
           OR @RatingSpeed NOT BETWEEN 1 AND 5
            THROW 50305, N'Điểm đánh giá phải từ 1 đến 5.', 1;

        INSERT INTO ord.Reviews (OrderId, CustomerId, LabId, RatingOverall, RatingScanQuality, RatingSpeed, Comment)
        VALUES (@OrderId, @CustomerId, @LabId, @RatingOverall, @RatingScanQuality, @RatingSpeed, @Comment);
        SET @NewReviewId = SCOPE_IDENTITY();      -- trigger cập nhật AvgRating/ReviewCount của lab

        DECLARE @Title NVARCHAR(150) = N'Đánh giá mới cho đơn ' + @Code;
        DECLARE @Body NVARCHAR(500) = LEFT(@Comment, 500);
        EXEC arc.sp_CreateNotification @UserId = @LabOwner, @Type = N'Review',
                                       @Title = @Title, @Body = @Body, @OrderId = @OrderId;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE ord.sp_FileComplaint
    @OrderId        INT,
    @CustomerId     INT,
    @Category       NVARCHAR(12),
    @Title          NVARCHAR(150),
    @Description    NVARCHAR(2000),
    @NewComplaintId INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        EXEC sp_set_session_context @key = N'UserId', @value = @CustomerId;

        BEGIN TRAN;

        DECLARE @OrderCustomer INT, @LabId INT, @Stage INT, @CompletedAt DATETIME2(0);
        SELECT @OrderCustomer = CustomerId, @LabId = LabId, @Stage = StageId, @CompletedAt = CompletedAt
        FROM ord.Orders WITH (UPDLOCK, HOLDLOCK)
        WHERE OrderId = @OrderId AND IsDeleted = 0;

        IF @OrderCustomer IS NULL
            THROW 50301, N'Đơn hàng không tồn tại.', 1;
        IF @OrderCustomer <> @CustomerId
            THROW 50303, N'Chỉ khách của đơn được khiếu nại.', 1;
        IF @Category NOT IN (N'LostFilm', N'DamagedFilm', N'ScanQuality', N'Delay', N'Billing', N'Service', N'Other')
           OR NULLIF(LTRIM(RTRIM(@Title)), N'') IS NULL OR NULLIF(LTRIM(RTRIM(@Description)), N'') IS NULL
            THROW 50305, N'Loại khiếu nại, tiêu đề hoặc nội dung không hợp lệ.', 1;
        IF @Stage IN (1, 13)
           OR (@Stage = 12 AND (@CompletedAt IS NULL OR DATEADD(DAY, 30, @CompletedAt) < SYSUTCDATETIME()))
            THROW 50302, N'Đơn đang chờ xác nhận, đã hủy hoặc đã quá 30 ngày kể từ lúc hoàn tất.', 1;
        IF EXISTS (SELECT 1 FROM ord.Complaints
                   WHERE OrderId = @OrderId AND Category = @Category AND Status IN (N'Open', N'InReview') AND IsDeleted = 0)
            THROW 50304, N'Đơn đã có khiếu nại đang xử lý cùng loại.', 1;

        INSERT INTO ord.Complaints (OrderId, CustomerId, LabId, Category, Title, Description)
        VALUES (@OrderId, @CustomerId, @LabId, @Category, @Title, @Description);
        SET @NewComplaintId = SCOPE_IDENTITY();    -- trigger Notify báo chủ lab, trigger Audit ghi nhật ký

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE ord.sp_ResolveComplaint
    @ComplaintId    INT,
    @AdminUserId    INT,
    @Decision       NVARCHAR(9),
    @ResolutionType NVARCHAR(12) = NULL,
    @Resolution     NVARCHAR(1000),
    @RefundAmount   DECIMAL(18,0) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        EXEC sp_set_session_context @key = N'UserId', @value = @AdminUserId;

        BEGIN TRAN;

        DECLARE @Cur NVARCHAR(9), @OrderId INT, @Total DECIMAL(18,0), @Pay NVARCHAR(9);
        SELECT @Cur = c.Status, @OrderId = c.OrderId, @Total = o.TotalAmount, @Pay = o.PaymentStatus
        FROM ord.Complaints c WITH (UPDLOCK, HOLDLOCK)
        JOIN ord.Orders o ON o.OrderId = c.OrderId
        WHERE c.ComplaintId = @ComplaintId AND c.IsDeleted = 0;

        IF @Cur IS NULL
            THROW 50301, N'Khiếu nại không tồn tại.', 1;
        IF NOT EXISTS (SELECT 1 FROM iam.UserRoles ur JOIN iam.Roles r ON r.RoleId = ur.RoleId
                       WHERE ur.UserId = @AdminUserId AND r.RoleCode = N'Admin')
            THROW 50303, N'Chỉ Admin được xử lý khiếu nại.', 1;
        IF @Decision NOT IN (N'InReview', N'Resolved', N'Rejected')
            THROW 50305, N'Quyết định không hợp lệ.', 1;
        IF ord.fn_IsValidComplaintTransition(@Cur, @Decision) = 0
            THROW 50302, N'Chuyển trạng thái khiếu nại không hợp lệ.', 1;

        IF @Decision IN (N'Resolved', N'Rejected') AND NULLIF(LTRIM(RTRIM(@Resolution)), N'') IS NULL
            THROW 50305, N'Thiếu nội dung kết quả xử lý.', 1;
        IF @Decision = N'Resolved'
           AND (@ResolutionType IS NULL OR @ResolutionType NOT IN (N'Refund', N'Redo', N'Compensation', N'NoAction'))
            THROW 50305, N'Giải quyết khiếu nại phải có loại xử lý hợp lệ.', 1;

        DECLARE @IsRefund BIT = CASE WHEN @Decision = N'Resolved' AND @ResolutionType = N'Refund' THEN 1 ELSE 0 END;
        IF @IsRefund = 1
        BEGIN
            IF @RefundAmount IS NULL OR @RefundAmount < 0 OR @RefundAmount > @Total
                THROW 50305, N'Số tiền hoàn bị thiếu hoặc vượt tổng tiền của đơn.', 1;
            IF @RefundAmount > 0 AND @Pay <> N'Paid'
                THROW 50305, N'Đơn chưa thanh toán, không có tiền để hoàn.', 1;
        END;

        UPDATE ord.Complaints
        SET Status          = @Decision,
            AssignedAdminId = COALESCE(AssignedAdminId, @AdminUserId),
            ResolutionType  = CASE WHEN @Decision = N'Resolved' THEN @ResolutionType END,
            Resolution      = CASE WHEN @Decision IN (N'Resolved', N'Rejected') THEN @Resolution ELSE Resolution END,
            RefundAmount    = CASE WHEN @IsRefund = 1 THEN @RefundAmount END,
            ResolvedAt      = CASE WHEN @Decision IN (N'Resolved', N'Rejected') THEN SYSUTCDATETIME() END,
            UpdatedAt       = SYSUTCDATETIME()
        WHERE ComplaintId = @ComplaintId;

        -- Hoàn toàn bộ: chuyển các payment đã thu sang Refunded (trigger đặt Orders.PaymentStatus = Refunded)
        IF @IsRefund = 1 AND @RefundAmount = @Total AND @Total > 0 AND @Pay = N'Paid'
            UPDATE ord.Payments SET Status = N'Refunded', RefundedAt = SYSUTCDATETIME()
            WHERE OrderId = @OrderId AND Status = N'Succeeded';

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE ord.sp_ReplyReview
    @ReviewId   INT,
    @LabOwnerId INT,
    @Reply      NVARCHAR(1000)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        EXEC sp_set_session_context @key = N'UserId', @value = @LabOwnerId;

        BEGIN TRAN;

        DECLARE @Owner INT, @Visible BIT, @RepliedAt DATETIME2(0), @CustomerId INT, @OrderId INT;
        SELECT @Owner = l.OwnerUserId, @Visible = r.IsVisible, @RepliedAt = r.LabRepliedAt,
               @CustomerId = r.CustomerId, @OrderId = r.OrderId
        FROM ord.Reviews r WITH (UPDLOCK, HOLDLOCK)
        JOIN lab.FilmLabs l ON l.LabId = r.LabId
        WHERE r.ReviewId = @ReviewId AND r.IsDeleted = 0;

        IF @Owner IS NULL
            THROW 50301, N'Đánh giá không tồn tại.', 1;
        IF @Owner <> @LabOwnerId
            THROW 50303, N'Chỉ chủ lab của đơn được trả lời đánh giá.', 1;
        IF NULLIF(LTRIM(RTRIM(@Reply)), N'') IS NULL
            THROW 50305, N'Nội dung trả lời không được để trống.', 1;
        IF @Visible = 0
            THROW 50302, N'Đánh giá đang bị ẩn, không thể trả lời.', 1;
        IF @RepliedAt IS NOT NULL
            THROW 50304, N'Đánh giá này đã được trả lời.', 1;

        UPDATE ord.Reviews
        SET LabReply = @Reply, LabRepliedAt = SYSUTCDATETIME(), UpdatedAt = SYSUTCDATETIME()
        WHERE ReviewId = @ReviewId;

        DECLARE @Title NVARCHAR(150) = N'Lab đã trả lời đánh giá của bạn';
        DECLARE @Body NVARCHAR(500) = LEFT(@Reply, 500);
        EXEC arc.sp_CreateNotification @UserId = @CustomerId, @Type = N'Review',
                                       @Title = @Title, @Body = @Body, @OrderId = @OrderId;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE ord.sp_ModerateReview
    @ReviewId    INT,
    @AdminUserId INT,
    @Action      NVARCHAR(4),
    @Reason      NVARCHAR(255) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        EXEC sp_set_session_context @key = N'UserId', @value = @AdminUserId;

        BEGIN TRAN;

        DECLARE @Visible BIT, @LabId INT, @CustomerId INT, @OrderId INT;
        SELECT @Visible = IsVisible, @LabId = LabId, @CustomerId = CustomerId, @OrderId = OrderId
        FROM ord.Reviews WITH (UPDLOCK, HOLDLOCK)
        WHERE ReviewId = @ReviewId AND IsDeleted = 0;

        IF @LabId IS NULL
            THROW 50301, N'Đánh giá không tồn tại.', 1;
        IF NOT EXISTS (SELECT 1 FROM iam.UserRoles ur JOIN iam.Roles r ON r.RoleId = ur.RoleId
                       WHERE ur.UserId = @AdminUserId AND r.RoleCode = N'Admin')
            THROW 50303, N'Chỉ Admin được kiểm duyệt đánh giá.', 1;
        IF @Action NOT IN (N'Hide', N'Show')
           OR (@Action = N'Hide' AND NULLIF(LTRIM(RTRIM(@Reason)), N'') IS NULL)
            THROW 50305, N'Hành động không hợp lệ hoặc thiếu lý do khi ẩn.', 1;
        IF (@Action = N'Hide' AND @Visible = 0) OR (@Action = N'Show' AND @Visible = 1)
            THROW 50302, N'Trạng thái hiển thị của đánh giá không thay đổi.', 1;

        UPDATE ord.Reviews
        SET IsVisible        = CASE WHEN @Action = N'Show' THEN 1 ELSE 0 END,
            ModeratedBy      = @AdminUserId,
            ModeratedAt      = SYSUTCDATETIME(),
            ModerationReason = CASE WHEN @Action = N'Hide' THEN @Reason END,
            UpdatedAt        = SYSUTCDATETIME()
        WHERE ReviewId = @ReviewId;

        EXEC lab.sp_RecalcLabRating @LabId = @LabId;

        DECLARE @Title NVARCHAR(150) = CASE WHEN @Action = N'Hide'
                 THEN N'Đánh giá của bạn đã bị ẩn' ELSE N'Đánh giá của bạn được hiển thị lại' END;
        DECLARE @Body NVARCHAR(500) = CASE WHEN @Action = N'Hide' THEN LEFT(@Reason, 500) END;
        EXEC arc.sp_CreateNotification @UserId = @CustomerId, @Type = N'Review',
                                       @Title = @Title, @Body = @Body, @OrderId = @OrderId;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO
