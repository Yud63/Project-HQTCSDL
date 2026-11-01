/* ============================================================
   File    : database/07_procedures/com.sql
   Module  : com - M8 Community & Knowledge
   Purpose : Procedure (★ = bắt buộc): ★sp_RegisterEvent, sp_PublishArticle, sp_ModerateArticle, sp_AddComment, sp_AcceptAnswer, sp_CancelEventRegistration. Dùng templates/procedure_template.sql; chữ ký theo docs/Contracts.md mục 7.
   Owner   : D (xem docs/Phan-cong.md)
   Depends : iam, lab
   Re-run  : CREATE OR ALTER - chạy lại bao nhiêu lần cũng được.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE com.sp_RegisterEvent
    @EventId      INT,
    @UserId       INT,
    @ResultStatus NVARCHAR(10) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        DECLARE @EvStatus NVARCHAR(9), @Start DATETIME2(0), @Deadline DATETIME2(0), @Title NVARCHAR(200);
        DECLARE @OldStatus NVARCHAR(10), @Seats INT, @NotiTitle NVARCHAR(150), @NotiBody NVARCHAR(500);

        EXEC sp_set_session_context @key = N'UserId', @value = @UserId;

        IF NOT EXISTS (SELECT 1 FROM iam.Users WHERE UserId = @UserId AND IsDeleted = 0 AND IsActive = 1)
            THROW 50705, N'Người dùng không tồn tại hoặc đã bị khóa.', 1;

        BEGIN TRAN;

        SELECT @EvStatus = Status, @Start = StartAt, @Deadline = RegistrationDeadline, @Title = Title
        FROM com.Events WITH (UPDLOCK, HOLDLOCK)
        WHERE EventId = @EventId AND IsDeleted = 0;

        IF @EvStatus IS NULL
            THROW 50701, N'Sự kiện không tồn tại.', 1;
        IF @EvStatus <> N'Open' OR SYSUTCDATETIME() >= ISNULL(@Deadline, @Start)
            THROW 50702, N'Sự kiện không mở đăng ký hoặc đã quá hạn đăng ký.', 1;

        SELECT @OldStatus = Status
        FROM com.EventRegistrations WITH (UPDLOCK, HOLDLOCK)
        WHERE EventId = @EventId AND UserId = @UserId;

        IF @OldStatus IN (N'Registered', N'Waitlisted', N'Attended')
            THROW 50704, N'Bạn đã đăng ký sự kiện này.', 1;

        SET @Seats = com.fn_EventSeatsLeft(@EventId);
        SET @ResultStatus = CASE WHEN @Seats > 0 THEN N'Registered' ELSE N'Waitlisted' END;

        IF @OldStatus = N'Cancelled'
            UPDATE com.EventRegistrations
            SET Status = @ResultStatus, IsPaid = 0, CancelledAt = NULL,
                CreatedAt = SYSUTCDATETIME(), UpdatedAt = SYSUTCDATETIME()
            WHERE EventId = @EventId AND UserId = @UserId;
        ELSE
            INSERT INTO com.EventRegistrations (EventId, UserId, Status)
            VALUES (@EventId, @UserId, @ResultStatus);

        IF @ResultStatus = N'Registered'
        BEGIN
            SET @NotiTitle = N'Đăng ký sự kiện thành công';
            SET @NotiBody = N'Bạn đã có chỗ trong sự kiện: ' + LEFT(@Title, 150);
        END
        ELSE
        BEGIN
            SET @NotiTitle = N'Bạn đang ở hàng chờ sự kiện';
            SET @NotiBody = N'Sự kiện đã đủ chỗ, bạn được đưa vào hàng chờ: ' + LEFT(@Title, 150);
        END
        EXEC arc.sp_CreateNotification @UserId, N'Event', @NotiTitle, @NotiBody;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE com.sp_CancelEventRegistration
    @EventId        INT,
    @UserId         INT,
    @PromotedUserId INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        DECLARE @EvStatus NVARCHAR(9), @Title NVARCHAR(200), @OldStatus NVARCHAR(10);
        DECLARE @NotiTitle NVARCHAR(150), @NotiBody NVARCHAR(500);

        SET @PromotedUserId = NULL;
        EXEC sp_set_session_context @key = N'UserId', @value = @UserId;

        BEGIN TRAN;

        SELECT @EvStatus = Status, @Title = Title
        FROM com.Events WITH (UPDLOCK, HOLDLOCK)
        WHERE EventId = @EventId AND IsDeleted = 0;

        IF @EvStatus IS NULL
            THROW 50701, N'Sự kiện không tồn tại.', 1;

        SELECT @OldStatus = Status
        FROM com.EventRegistrations WITH (UPDLOCK, HOLDLOCK)
        WHERE EventId = @EventId AND UserId = @UserId;

        IF @OldStatus IS NULL
            THROW 50701, N'Bạn chưa đăng ký sự kiện này.', 1;
        IF @OldStatus IN (N'Cancelled', N'Attended') OR @EvStatus = N'Completed'
            THROW 50702, N'Không thể hủy đăng ký ở trạng thái hiện tại.', 1;

        UPDATE com.EventRegistrations
        SET Status = N'Cancelled', CancelledAt = SYSUTCDATETIME(), UpdatedAt = SYSUTCDATETIME()
        WHERE EventId = @EventId AND UserId = @UserId;

        IF @OldStatus = N'Registered'
        BEGIN
            SELECT TOP (1) @PromotedUserId = UserId
            FROM com.EventRegistrations WITH (UPDLOCK)
            WHERE EventId = @EventId AND Status = N'Waitlisted'
            ORDER BY CreatedAt, UserId;

            IF @PromotedUserId IS NOT NULL
            BEGIN
                UPDATE com.EventRegistrations
                SET Status = N'Registered', UpdatedAt = SYSUTCDATETIME()
                WHERE EventId = @EventId AND UserId = @PromotedUserId;

                SET @NotiTitle = N'Bạn đã có chỗ trong sự kiện';
                SET @NotiBody = N'Có chỗ trống, bạn được chuyển từ hàng chờ sang đăng ký: ' + LEFT(@Title, 150);
                EXEC arc.sp_CreateNotification @PromotedUserId, N'Event', @NotiTitle, @NotiBody;
            END
        END

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE com.sp_PublishArticle
    @AuthorId       INT,
    @ArticleType    NVARCHAR(10),
    @Title          NVARCHAR(200),
    @Summary        NVARCHAR(500) = NULL,
    @Body           NVARCHAR(MAX),
    @Tags           NVARCHAR(MAX) = NULL,
    @RelatedLabId   INT = NULL,
    @RelatedStockId INT = NULL,
    @Slug           NVARCHAR(220) = NULL,
    @NewArticleId   INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        EXEC sp_set_session_context @key = N'UserId', @value = @AuthorId;

        IF @ArticleType IS NULL OR @ArticleType NOT IN (N'Tutorial', N'Review', N'Technical', N'LabGuide', N'Experience', N'Question')
            THROW 50705, N'Loại bài viết không hợp lệ.', 1;
        IF NULLIF(LTRIM(RTRIM(@Title)), N'') IS NULL OR NULLIF(LTRIM(RTRIM(@Body)), N'') IS NULL
            THROW 50705, N'Tiêu đề và nội dung bài viết không được rỗng.', 1;
        IF @Tags IS NOT NULL AND ISJSON(@Tags) <> 1
            THROW 50705, N'Tags phải là mảng JSON hợp lệ.', 1;
        IF NOT EXISTS (SELECT 1 FROM iam.Users WHERE UserId = @AuthorId AND IsDeleted = 0 AND IsActive = 1)
            THROW 50705, N'Tác giả không tồn tại hoặc đã bị khóa.', 1;
        IF @RelatedLabId IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM lab.FilmLabs WHERE LabId = @RelatedLabId AND IsDeleted = 0)
            THROW 50705, N'Lab liên quan không tồn tại.', 1;
        IF @RelatedStockId IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM lab.FilmStocks WHERE StockId = @RelatedStockId)
            THROW 50705, N'Loại phim liên quan không tồn tại.', 1;

        IF @Slug IS NULL
            SET @Slug = N'bai-viet-' + LOWER(CONVERT(NVARCHAR(36), NEWID()));

        BEGIN TRAN;

        IF EXISTS (SELECT 1 FROM com.Articles WHERE Slug = @Slug AND IsDeleted = 0)
            THROW 50704, N'Slug đã tồn tại.', 1;

        INSERT INTO com.Articles
            (AuthorId, ArticleType, Title, Slug, Summary, Body, Tags, RelatedLabId, RelatedStockId, Status, PublishedAt)
        VALUES
            (@AuthorId, @ArticleType, @Title, @Slug, @Summary, @Body, @Tags, @RelatedLabId, @RelatedStockId,
             N'Published', SYSUTCDATETIME());

        SET @NewArticleId = SCOPE_IDENTITY();

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE com.sp_ModerateArticle
    @ArticleId   INT,
    @AdminUserId INT,
    @Action      NVARCHAR(4),
    @Reason      NVARCHAR(255) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        DECLARE @Status NVARCHAR(9);

        EXEC sp_set_session_context @key = N'UserId', @value = @AdminUserId;

        IF @Action IS NULL OR @Action NOT IN (N'Hide', N'Show')
            THROW 50705, N'Action phải là Hide hoặc Show.', 1;
        IF @Action = N'Hide' AND NULLIF(LTRIM(RTRIM(@Reason)), N'') IS NULL
            THROW 50705, N'Phải nhập lý do khi ẩn bài viết.', 1;
        IF NOT EXISTS (SELECT 1 FROM iam.Users u
                       JOIN iam.UserRoles ur ON ur.UserId = u.UserId
                       JOIN iam.Roles r ON r.RoleId = ur.RoleId
                       WHERE u.UserId = @AdminUserId AND u.IsDeleted = 0 AND r.RoleCode = N'Admin')
            THROW 50703, N'Chỉ Admin được ẩn/hiện bài viết.', 1;

        BEGIN TRAN;

        SELECT @Status = Status FROM com.Articles WITH (UPDLOCK) WHERE ArticleId = @ArticleId AND IsDeleted = 0;

        IF @Status IS NULL
            THROW 50701, N'Bài viết không tồn tại.', 1;
        IF (@Action = N'Hide' AND @Status <> N'Published') OR (@Action = N'Show' AND @Status <> N'Hidden')
            THROW 50702, N'Trạng thái bài viết không cho phép thao tác này.', 1;

        IF @Action = N'Hide'
            UPDATE com.Articles
            SET Status = N'Hidden', ModerationReason = @Reason, ModeratedBy = @AdminUserId, UpdatedAt = SYSUTCDATETIME()
            WHERE ArticleId = @ArticleId;
        ELSE
            UPDATE com.Articles
            SET Status = N'Published', ModerationReason = NULL, ModeratedBy = @AdminUserId, UpdatedAt = SYSUTCDATETIME()
            WHERE ArticleId = @ArticleId;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE com.sp_AddComment
    @ArticleId       INT,
    @UserId          INT,
    @Body            NVARCHAR(1000),
    @ParentCommentId INT = NULL,
    @NewCommentId    INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        DECLARE @Status NVARCHAR(9), @ParentArticle INT;

        EXEC sp_set_session_context @key = N'UserId', @value = @UserId;

        IF NULLIF(LTRIM(RTRIM(@Body)), N'') IS NULL
            THROW 50705, N'Nội dung bình luận không được rỗng.', 1;
        IF NOT EXISTS (SELECT 1 FROM iam.Users WHERE UserId = @UserId AND IsDeleted = 0 AND IsActive = 1)
            THROW 50705, N'Người bình luận không tồn tại hoặc đã bị khóa.', 1;

        BEGIN TRAN;

        SELECT @Status = Status FROM com.Articles WHERE ArticleId = @ArticleId AND IsDeleted = 0;
        IF @Status IS NULL
            THROW 50701, N'Bài viết không tồn tại.', 1;
        IF @Status <> N'Published'
            THROW 50702, N'Chỉ bình luận được bài viết đã xuất bản.', 1;

        IF @ParentCommentId IS NOT NULL
        BEGIN
            SELECT @ParentArticle = ArticleId FROM com.ArticleComments
            WHERE CommentId = @ParentCommentId AND IsDeleted = 0;
            IF @ParentArticle IS NULL
                THROW 50701, N'Bình luận cha không tồn tại.', 1;
            IF @ParentArticle <> @ArticleId
                THROW 50705, N'Bình luận cha phải thuộc cùng bài viết.', 1;
        END

        INSERT INTO com.ArticleComments (ArticleId, UserId, ParentCommentId, Body)
        VALUES (@ArticleId, @UserId, @ParentCommentId, @Body);

        SET @NewCommentId = SCOPE_IDENTITY();

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE com.sp_AcceptAnswer
    @CommentId INT,
    @UserId    INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        DECLARE @ArticleId INT, @Parent INT, @Visible BIT, @Type NVARCHAR(10), @Author INT;

        EXEC sp_set_session_context @key = N'UserId', @value = @UserId;

        BEGIN TRAN;

        SELECT @ArticleId = ArticleId, @Parent = ParentCommentId, @Visible = IsVisible
        FROM com.ArticleComments WITH (UPDLOCK)
        WHERE CommentId = @CommentId AND IsDeleted = 0;

        IF @ArticleId IS NULL
            THROW 50701, N'Bình luận không tồn tại.', 1;

        SELECT @Type = ArticleType, @Author = AuthorId
        FROM com.Articles WHERE ArticleId = @ArticleId AND IsDeleted = 0;

        IF @Type IS NULL
            THROW 50701, N'Bài viết không tồn tại.', 1;
        IF @Type <> N'Question'
            THROW 50702, N'Chỉ chọn câu trả lời cho bài viết loại Question.', 1;
        IF @Author <> @UserId
            THROW 50703, N'Chỉ tác giả bài viết được chọn câu trả lời.', 1;
        IF @Parent IS NOT NULL
            THROW 50705, N'Chỉ chọn được bình luận cấp 1 làm câu trả lời.', 1;
        IF @Visible = 0
            THROW 50702, N'Bình luận đang bị ẩn.', 1;

        UPDATE com.ArticleComments
        SET IsAccepted = 0, UpdatedAt = SYSUTCDATETIME()
        WHERE ArticleId = @ArticleId AND IsAccepted = 1 AND CommentId <> @CommentId;

        UPDATE com.ArticleComments
        SET IsAccepted = 1, UpdatedAt = SYSUTCDATETIME()
        WHERE CommentId = @CommentId;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE com.sp_SaveEvent
    @OrganizerId          INT,
    @EventType            NVARCHAR(9),        -- Workshop | Photowalk
    @Title                NVARCHAR(200),
    @VenueName            NVARCHAR(200),
    @AddressLine          NVARCHAR(255),
    @City                 NVARCHAR(100),
    @StartAt              DATETIME2(0),       -- giờ UTC, theo quy ước SYSUTCDATETIME()
    @EndAt                DATETIME2(0),
    @Capacity             SMALLINT,
    @EventId              INT             = NULL,   -- NULL: tạo mới
    @Description          NVARCHAR(2000)  = NULL,
    @RegistrationDeadline DATETIME2(0)    = NULL,
    @Latitude             FLOAT           = NULL,
    @Longitude            FLOAT           = NULL,
    @Fee                  DECIMAL(18,0)   = 0,
    @HostLabId            INT             = NULL,
    @Status               NVARCHAR(9)     = N'Draft',   -- Draft | Open | Closed
    @NewEventId           INT             = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        EXEC sp_set_session_context @key = N'UserId', @value = @OrganizerId;

        BEGIN TRAN;

        DECLARE @CurOrganizer INT, @CurStatus NVARCHAR(9), @HostOwner INT, @Registered INT;
        DECLARE @IsAdmin BIT = CASE WHEN EXISTS (SELECT 1 FROM iam.UserRoles ur JOIN iam.Roles r ON r.RoleId = ur.RoleId
                                                 WHERE ur.UserId = @OrganizerId AND r.RoleCode = N'Admin')
                                    THEN 1 ELSE 0 END;

        IF @EventId IS NOT NULL
        BEGIN
            SELECT @CurOrganizer = OrganizerId, @CurStatus = Status
            FROM com.Events WITH (UPDLOCK, HOLDLOCK)
            WHERE EventId = @EventId AND IsDeleted = 0;
            IF @CurOrganizer IS NULL
                THROW 50701, N'Sự kiện không tồn tại.', 1;
        END;

        IF NOT EXISTS (SELECT 1 FROM iam.UserRoles ur
                       JOIN iam.Roles r ON r.RoleId = ur.RoleId
                       JOIN iam.Users u ON u.UserId = ur.UserId
                       WHERE ur.UserId = @OrganizerId AND r.RoleCode IN (N'Expert', N'LabOwner', N'Admin')
                         AND u.IsActive = 1 AND u.IsDeleted = 0)
            THROW 50703, N'Chỉ Expert, LabOwner hoặc Admin được tổ chức sự kiện.', 1;
        IF @CurOrganizer IS NOT NULL AND @CurOrganizer <> @OrganizerId AND @IsAdmin = 0
            THROW 50703, N'Chỉ người tổ chức hoặc Admin được sửa sự kiện.', 1;
        IF @CurStatus IN (N'Cancelled', N'Completed')
            THROW 50702, N'Sự kiện đã hủy hoặc đã hoàn tất, không sửa được.', 1;
        IF @CurStatus IS NOT NULL AND @CurStatus <> N'Draft' AND @Status = N'Draft'
            THROW 50702, N'Không đưa sự kiện đã công bố về Draft.', 1;

        SET @Title = LTRIM(RTRIM(@Title));
        SET @VenueName = LTRIM(RTRIM(@VenueName));
        SET @AddressLine = LTRIM(RTRIM(@AddressLine));
        SET @City = LTRIM(RTRIM(@City));
        IF @EventType IS NULL OR @EventType NOT IN (N'Workshop', N'Photowalk')
            THROW 50705, N'EventType phải là Workshop hoặc Photowalk.', 1;
        IF @Status IS NULL OR @Status NOT IN (N'Draft', N'Open', N'Closed')
            THROW 50705, N'Status chỉ được là Draft, Open hoặc Closed.', 1;
        IF NULLIF(@Title, N'') IS NULL OR NULLIF(@VenueName, N'') IS NULL
           OR NULLIF(@AddressLine, N'') IS NULL OR NULLIF(@City, N'') IS NULL
            THROW 50705, N'Tiêu đề, địa điểm, địa chỉ và thành phố không được rỗng.', 1;
        IF @StartAt IS NULL OR @EndAt IS NULL OR @EndAt <= @StartAt
            THROW 50705, N'Thời gian kết thúc phải sau thời gian bắt đầu.', 1;
        IF @EventId IS NULL AND @StartAt <= SYSUTCDATETIME()
            THROW 50705, N'Sự kiện mới phải bắt đầu trong tương lai.', 1;
        IF @RegistrationDeadline IS NOT NULL AND @RegistrationDeadline > @StartAt
            THROW 50705, N'Hạn đăng ký không được sau giờ bắt đầu.', 1;
        IF @Capacity IS NULL OR @Capacity < 1
            THROW 50705, N'Sức chứa phải lớn hơn 0.', 1;
        IF @Fee IS NULL OR @Fee < 0
            THROW 50705, N'Phí phải từ 0 trở lên.', 1;
        IF (@Latitude IS NULL AND @Longitude IS NOT NULL) OR (@Latitude IS NOT NULL AND @Longitude IS NULL)
            THROW 50705, N'Phải truyền đủ cả vĩ độ và kinh độ.', 1;
        IF (@Latitude < -90 OR @Latitude > 90) OR (@Longitude < -180 OR @Longitude > 180)
            THROW 50705, N'Vĩ độ hoặc kinh độ nằm ngoài phạm vi hợp lệ.', 1;

        IF @HostLabId IS NOT NULL
        BEGIN
            SELECT @HostOwner = OwnerUserId FROM lab.FilmLabs WHERE LabId = @HostLabId AND IsDeleted = 0;
            IF @HostOwner IS NULL
                THROW 50705, N'Lab đăng cai không tồn tại.', 1;
            IF @HostOwner <> @OrganizerId AND @IsAdmin = 0
                THROW 50703, N'Chỉ chủ lab được dùng lab làm nơi đăng cai.', 1;
        END;

        IF @EventId IS NOT NULL
        BEGIN
            SET @Registered = (SELECT COUNT(*) FROM com.EventRegistrations
                               WHERE EventId = @EventId AND Status IN (N'Registered', N'Attended'));
            IF @Capacity < @Registered
                THROW 50705, N'Sức chứa không được nhỏ hơn số người đã đăng ký.', 1;
        END;

        DECLARE @pt geography = CASE WHEN @Latitude IS NOT NULL THEN geography::Point(@Latitude, @Longitude, 4326) END;

        IF @EventId IS NULL
        BEGIN
            INSERT INTO com.Events (OrganizerId, HostLabId, EventType, Title, Description, StartAt, EndAt,
                                    RegistrationDeadline, VenueName, AddressLine, City, Location, Capacity, Fee, Status)
            VALUES (@OrganizerId, @HostLabId, @EventType, @Title, @Description, @StartAt, @EndAt,
                    @RegistrationDeadline, @VenueName, @AddressLine, @City, @pt, @Capacity, @Fee, @Status);
            SET @NewEventId = SCOPE_IDENTITY();
        END
        ELSE
        BEGIN
            UPDATE com.Events
            SET HostLabId = @HostLabId, EventType = @EventType, Title = @Title, Description = @Description,
                StartAt = @StartAt, EndAt = @EndAt, RegistrationDeadline = @RegistrationDeadline,
                VenueName = @VenueName, AddressLine = @AddressLine, City = @City, Location = @pt,
                Capacity = @Capacity, Fee = @Fee, Status = @Status, UpdatedAt = SYSUTCDATETIME()
            WHERE EventId = @EventId;
            SET @NewEventId = @EventId;
        END;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO