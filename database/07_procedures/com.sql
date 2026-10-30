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
