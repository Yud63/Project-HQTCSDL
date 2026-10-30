USE FilmLabDB;
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
SET NOCOUNT ON;

DECLARE @u1 INT, @u2 INT, @u3 INT, @exp INT, @adm INT, @ev INT, @a INT, @a2 INT, @c INT, @c2 INT;
DECLARE @res NVARCHAR(10), @prom INT, @n0 INT, @e INT, @msg NVARCHAR(400);

SET @u1  = (SELECT UserId FROM iam.Users WHERE Email = N'an.nguyen@example.com');
SET @u2  = (SELECT UserId FROM iam.Users WHERE Email = N'binh.tran@example.com');
SET @u3  = (SELECT UserId FROM iam.Users WHERE Email = N'chi.le@example.com');
SET @exp = (SELECT UserId FROM iam.Users WHERE Email = N'expert@filmlab.vn');
SET @adm = (SELECT UserId FROM iam.Users WHERE Email = N'admin@filmlab.vn');

-- 1. Function
IF com.fn_EventSeatsLeft(0) IS NULL PRINT N'PASS: fn_EventSeatsLeft NULL với sự kiện không tồn tại';
ELSE PRINT N'FAIL: fn_EventSeatsLeft sự kiện không tồn tại';

-- A. Luồng đăng ký: Registered, Registered, Waitlisted, hủy -> đẩy hàng chờ, đăng ký lại, hủy hàng chờ
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    INSERT INTO com.Events (OrganizerId, EventType, Title, StartAt, EndAt, RegistrationDeadline, VenueName, AddressLine, City, Capacity, Status)
    VALUES (@exp, N'Workshop', N'Test12 workshop', DATEADD(DAY, 30, SYSUTCDATETIME()), DATEADD(DAY, 31, SYSUTCDATETIME()),
            DATEADD(DAY, 29, SYSUTCDATETIME()), N'Test venue', N'1 Test', N'Hồ Chí Minh', 2, N'Open');
    SET @ev = SCOPE_IDENTITY();

    SET @n0 = (SELECT COUNT(*) FROM arc.Notifications WHERE UserId = @u1 AND Type = N'Event');
    EXEC com.sp_RegisterEvent @ev, @u1, @ResultStatus = @res OUTPUT;
    IF @res = N'Registered'
       AND EXISTS (SELECT 1 FROM com.EventRegistrations WHERE EventId = @ev AND UserId = @u1 AND Status = N'Registered')
       AND com.fn_EventSeatsLeft(@ev) = 1
       AND (SELECT COUNT(*) FROM arc.Notifications WHERE UserId = @u1 AND Type = N'Event') = @n0 + 1
        PRINT N'PASS: sp_RegisterEvent người 1 -> Registered, còn 1 chỗ, có thông báo Event';
    ELSE PRINT N'FAIL: sp_RegisterEvent người 1';

    EXEC com.sp_RegisterEvent @ev, @u2, @ResultStatus = @res OUTPUT;
    IF @res = N'Registered' AND com.fn_EventSeatsLeft(@ev) = 0
        PRINT N'PASS: sp_RegisterEvent người 2 -> Registered, hết chỗ';
    ELSE PRINT N'FAIL: sp_RegisterEvent người 2';

    EXEC com.sp_RegisterEvent @ev, @u3, @ResultStatus = @res OUTPUT;
    IF @res = N'Waitlisted'
       AND EXISTS (SELECT 1 FROM com.vw_UpcomingEvents WHERE EventId = @ev AND SeatsLeft = 0 AND WaitlistCount = 1 AND RegisteredCount = 2)
        PRINT N'PASS: người 3 vào hàng chờ, vw_UpcomingEvents thống kê đúng';
    ELSE PRINT N'FAIL: Waitlisted/vw_UpcomingEvents';

    SET @n0 = (SELECT COUNT(*) FROM arc.Notifications WHERE UserId = @u3 AND Type = N'Event');
    EXEC com.sp_CancelEventRegistration @ev, @u1, @PromotedUserId = @prom OUTPUT;
    IF @prom = @u3
       AND EXISTS (SELECT 1 FROM com.EventRegistrations WHERE EventId = @ev AND UserId = @u3 AND Status = N'Registered')
       AND EXISTS (SELECT 1 FROM com.EventRegistrations WHERE EventId = @ev AND UserId = @u1 AND Status = N'Cancelled' AND CancelledAt IS NOT NULL)
       AND com.fn_EventSeatsLeft(@ev) = 0
       AND (SELECT COUNT(*) FROM arc.Notifications WHERE UserId = @u3 AND Type = N'Event') = @n0 + 1
        PRINT N'PASS: sp_CancelEventRegistration đẩy người hàng chờ lên + thông báo';
    ELSE PRINT N'FAIL: sp_CancelEventRegistration đẩy hàng chờ';

    EXEC com.sp_RegisterEvent @ev, @u1, @ResultStatus = @res OUTPUT;
    IF @res = N'Waitlisted'
       AND EXISTS (SELECT 1 FROM com.EventRegistrations WHERE EventId = @ev AND UserId = @u1 AND Status = N'Waitlisted' AND CancelledAt IS NULL)
        PRINT N'PASS: đăng ký lại sau khi hủy -> dùng lại dòng cũ, vào hàng chờ';
    ELSE PRINT N'FAIL: đăng ký lại sau khi hủy';

    EXEC com.sp_CancelEventRegistration @ev, @u1, @PromotedUserId = @prom OUTPUT;
    IF @prom IS NULL
       AND EXISTS (SELECT 1 FROM com.EventRegistrations WHERE EventId = @ev AND UserId = @u1 AND Status = N'Cancelled')
       AND EXISTS (SELECT 1 FROM com.EventRegistrations WHERE EventId = @ev AND UserId = @u3 AND Status = N'Registered')
        PRINT N'PASS: hủy khi đang hàng chờ không đẩy ai lên';
    ELSE PRINT N'FAIL: hủy hàng chờ';
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e <> 0 PRINT N'FAIL: luồng đăng ký lỗi bất ngờ ' + CAST(@e AS NVARCHAR(10)) + N' ' + ISNULL(@msg, N'');

-- E1. Sự kiện không tồn tại -> 50701
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC com.sp_RegisterEvent 0, @u1, @ResultStatus = @res OUTPUT;
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50701 PRINT N'PASS: sp_RegisterEvent sự kiện không tồn tại (50701)'; ELSE PRINT N'FAIL: RegisterEvent không tồn tại, nhận ' + CAST(@e AS NVARCHAR(10));

-- E2. Sự kiện Draft -> 50702
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    INSERT INTO com.Events (OrganizerId, EventType, Title, StartAt, EndAt, VenueName, AddressLine, City, Capacity, Status)
    VALUES (@exp, N'Workshop', N'Test12 draft', DATEADD(DAY, 30, SYSUTCDATETIME()), DATEADD(DAY, 31, SYSUTCDATETIME()),
            N'Test venue', N'1 Test', N'Hồ Chí Minh', 5, N'Draft');
    SET @ev = SCOPE_IDENTITY();
    EXEC com.sp_RegisterEvent @ev, @u1, @ResultStatus = @res OUTPUT;
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50702 PRINT N'PASS: sp_RegisterEvent sự kiện Draft (50702)'; ELSE PRINT N'FAIL: RegisterEvent Draft, nhận ' + CAST(@e AS NVARCHAR(10));

-- E3. Quá hạn đăng ký -> 50702
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    INSERT INTO com.Events (OrganizerId, EventType, Title, StartAt, EndAt, RegistrationDeadline, VenueName, AddressLine, City, Capacity, Status)
    VALUES (@exp, N'Photowalk', N'Test12 quá hạn', DATEADD(DAY, 10, SYSUTCDATETIME()), DATEADD(DAY, 11, SYSUTCDATETIME()),
            DATEADD(DAY, -1, SYSUTCDATETIME()), N'Test venue', N'1 Test', N'Hồ Chí Minh', 5, N'Open');
    SET @ev = SCOPE_IDENTITY();
    EXEC com.sp_RegisterEvent @ev, @u1, @ResultStatus = @res OUTPUT;
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50702 PRINT N'PASS: sp_RegisterEvent quá hạn đăng ký (50702)'; ELSE PRINT N'FAIL: RegisterEvent quá hạn, nhận ' + CAST(@e AS NVARCHAR(10));

-- E4. Đăng ký trùng -> 50704
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    INSERT INTO com.Events (OrganizerId, EventType, Title, StartAt, EndAt, VenueName, AddressLine, City, Capacity, Status)
    VALUES (@exp, N'Workshop', N'Test12 trùng', DATEADD(DAY, 30, SYSUTCDATETIME()), DATEADD(DAY, 31, SYSUTCDATETIME()),
            N'Test venue', N'1 Test', N'Hồ Chí Minh', 5, N'Open');
    SET @ev = SCOPE_IDENTITY();
    EXEC com.sp_RegisterEvent @ev, @u1, @ResultStatus = @res OUTPUT;
    EXEC com.sp_RegisterEvent @ev, @u1, @ResultStatus = @res OUTPUT;
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50704 PRINT N'PASS: sp_RegisterEvent đăng ký trùng (50704)'; ELSE PRINT N'FAIL: RegisterEvent trùng, nhận ' + CAST(@e AS NVARCHAR(10));

-- E5. Hủy khi chưa đăng ký -> 50701
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    INSERT INTO com.Events (OrganizerId, EventType, Title, StartAt, EndAt, VenueName, AddressLine, City, Capacity, Status)
    VALUES (@exp, N'Workshop', N'Test12 hủy', DATEADD(DAY, 30, SYSUTCDATETIME()), DATEADD(DAY, 31, SYSUTCDATETIME()),
            N'Test venue', N'1 Test', N'Hồ Chí Minh', 5, N'Open');
    SET @ev = SCOPE_IDENTITY();
    EXEC com.sp_CancelEventRegistration @ev, @u1, @PromotedUserId = @prom OUTPUT;
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50701 PRINT N'PASS: sp_CancelEventRegistration chưa đăng ký (50701)'; ELSE PRINT N'FAIL: Cancel chưa đăng ký, nhận ' + CAST(@e AS NVARCHAR(10));

-- E6. Hủy hai lần -> 50702
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    INSERT INTO com.Events (OrganizerId, EventType, Title, StartAt, EndAt, VenueName, AddressLine, City, Capacity, Status)
    VALUES (@exp, N'Workshop', N'Test12 hủy hai lần', DATEADD(DAY, 30, SYSUTCDATETIME()), DATEADD(DAY, 31, SYSUTCDATETIME()),
            N'Test venue', N'1 Test', N'Hồ Chí Minh', 5, N'Open');
    SET @ev = SCOPE_IDENTITY();
    EXEC com.sp_RegisterEvent @ev, @u1, @ResultStatus = @res OUTPUT;
    EXEC com.sp_CancelEventRegistration @ev, @u1, @PromotedUserId = @prom OUTPUT;
    EXEC com.sp_CancelEventRegistration @ev, @u1, @PromotedUserId = @prom OUTPUT;
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50702 PRINT N'PASS: sp_CancelEventRegistration hủy hai lần (50702)'; ELSE PRINT N'FAIL: Cancel hai lần, nhận ' + CAST(@e AS NVARCHAR(10));

-- E7. Trigger CheckSeats: INSERT trực tiếp vượt sức chứa -> 50706
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    INSERT INTO com.Events (OrganizerId, EventType, Title, StartAt, EndAt, VenueName, AddressLine, City, Capacity, Status)
    VALUES (@exp, N'Workshop', N'Test12 sức chứa 1', DATEADD(DAY, 30, SYSUTCDATETIME()), DATEADD(DAY, 31, SYSUTCDATETIME()),
            N'Test venue', N'1 Test', N'Hồ Chí Minh', 1, N'Open');
    SET @ev = SCOPE_IDENTITY();
    INSERT INTO com.EventRegistrations (EventId, UserId, Status)
    VALUES (@ev, @u1, N'Registered'), (@ev, @u2, N'Registered');
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50706 PRINT N'PASS: trigger CheckSeats chặn vượt sức chứa (50706)'; ELSE PRINT N'FAIL: CheckSeats, nhận ' + CAST(@e AS NVARCHAR(10));

-- B1. Đăng bài Experience (khách) -> Published
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC com.sp_PublishArticle @AuthorId = @u1, @ArticleType = N'Experience', @Title = N'Test12 kinh nghiệm',
         @Body = N'Nội dung bài viết', @Tags = N'["film","c41"]', @NewArticleId = @a OUTPUT;
    IF EXISTS (SELECT 1 FROM com.Articles WHERE ArticleId = @a AND AuthorId = @u1 AND Status = N'Published'
               AND PublishedAt IS NOT NULL AND Slug LIKE N'bai-viet-%')
        PRINT N'PASS: sp_PublishArticle Experience của khách -> Published, tự sinh slug';
    ELSE PRINT N'FAIL: sp_PublishArticle Experience';
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e <> 0 PRINT N'FAIL: PublishArticle lỗi bất ngờ ' + CAST(@e AS NVARCHAR(10)) + N' ' + ISNULL(@msg, N'');

-- B2. Tutorial của Expert -> Published
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC com.sp_PublishArticle @AuthorId = @exp, @ArticleType = N'Tutorial', @Title = N'Test12 tutorial',
         @Body = N'Hướng dẫn', @NewArticleId = @a OUTPUT;
    IF EXISTS (SELECT 1 FROM com.Articles WHERE ArticleId = @a AND ArticleType = N'Tutorial' AND Status = N'Published')
        PRINT N'PASS: sp_PublishArticle Tutorial của Expert';
    ELSE PRINT N'FAIL: sp_PublishArticle Tutorial Expert';
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e <> 0 PRINT N'FAIL: PublishArticle Tutorial lỗi bất ngờ ' + CAST(@e AS NVARCHAR(10)) + N' ' + ISNULL(@msg, N'');

-- B3. Tutorial của khách -> 50703
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC com.sp_PublishArticle @AuthorId = @u1, @ArticleType = N'Tutorial', @Title = N'Test12 sai role',
         @Body = N'x', @NewArticleId = @a OUTPUT;
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50703 PRINT N'PASS: trigger CheckAuthorRole chặn khách đăng Tutorial (50703)'; ELSE PRINT N'FAIL: CheckAuthorRole, nhận ' + CAST(@e AS NVARCHAR(10));

-- B4. Trùng slug -> 50704
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC com.sp_PublishArticle @AuthorId = @u1, @ArticleType = N'Review', @Title = N'Test12 a', @Body = N'x',
         @Slug = N'test12-slug-trung', @NewArticleId = @a OUTPUT;
    EXEC com.sp_PublishArticle @AuthorId = @u2, @ArticleType = N'Review', @Title = N'Test12 b', @Body = N'x',
         @Slug = N'test12-slug-trung', @NewArticleId = @a2 OUTPUT;
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50704 PRINT N'PASS: sp_PublishArticle trùng slug (50704)'; ELSE PRINT N'FAIL: PublishArticle trùng slug, nhận ' + CAST(@e AS NVARCHAR(10));

-- B5. Tags không phải JSON -> 50705
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC com.sp_PublishArticle @AuthorId = @u1, @ArticleType = N'Review', @Title = N'Test12 tags', @Body = N'x',
         @Tags = N'khong phai json', @NewArticleId = @a OUTPUT;
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50705 PRINT N'PASS: sp_PublishArticle Tags sai JSON (50705)'; ELSE PRINT N'FAIL: PublishArticle Tags, nhận ' + CAST(@e AS NVARCHAR(10));

-- B6. Admin ẩn rồi hiện lại bài
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC com.sp_PublishArticle @AuthorId = @u1, @ArticleType = N'Review', @Title = N'Test12 moderate', @Body = N'x',
         @NewArticleId = @a OUTPUT;
    EXEC com.sp_ModerateArticle @a, @adm, N'Hide', N'Vi phạm test';
    IF EXISTS (SELECT 1 FROM com.Articles WHERE ArticleId = @a AND Status = N'Hidden'
               AND ModerationReason = N'Vi phạm test' AND ModeratedBy = @adm)
        PRINT N'PASS: sp_ModerateArticle Hide ghi lý do và người ẩn';
    ELSE PRINT N'FAIL: sp_ModerateArticle Hide';
    EXEC com.sp_ModerateArticle @a, @adm, N'Show';
    IF EXISTS (SELECT 1 FROM com.Articles WHERE ArticleId = @a AND Status = N'Published' AND ModerationReason IS NULL)
        PRINT N'PASS: sp_ModerateArticle Show khôi phục Published';
    ELSE PRINT N'FAIL: sp_ModerateArticle Show';
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e <> 0 PRINT N'FAIL: ModerateArticle lỗi bất ngờ ' + CAST(@e AS NVARCHAR(10)) + N' ' + ISNULL(@msg, N'');

-- B7. Ẩn không có lý do -> 50705
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC com.sp_PublishArticle @AuthorId = @u1, @ArticleType = N'Review', @Title = N'Test12 lý do', @Body = N'x',
         @NewArticleId = @a OUTPUT;
    EXEC com.sp_ModerateArticle @a, @adm, N'Hide';
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50705 PRINT N'PASS: sp_ModerateArticle Hide thiếu lý do (50705)'; ELSE PRINT N'FAIL: Moderate thiếu lý do, nhận ' + CAST(@e AS NVARCHAR(10));

-- B8. Người không phải Admin ẩn bài -> 50703
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC com.sp_PublishArticle @AuthorId = @u1, @ArticleType = N'Review', @Title = N'Test12 quyền', @Body = N'x',
         @NewArticleId = @a OUTPUT;
    EXEC com.sp_ModerateArticle @a, @u2, N'Hide', N'Không có quyền';
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50703 PRINT N'PASS: sp_ModerateArticle không phải Admin (50703)'; ELSE PRINT N'FAIL: Moderate không phải Admin, nhận ' + CAST(@e AS NVARCHAR(10));

-- B9. Ẩn hai lần -> 50702
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC com.sp_PublishArticle @AuthorId = @u1, @ArticleType = N'Review', @Title = N'Test12 hai lần', @Body = N'x',
         @NewArticleId = @a OUTPUT;
    EXEC com.sp_ModerateArticle @a, @adm, N'Hide', N'Lần 1';
    EXEC com.sp_ModerateArticle @a, @adm, N'Hide', N'Lần 2';
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50702 PRINT N'PASS: sp_ModerateArticle ẩn bài đã ẩn (50702)'; ELSE PRINT N'FAIL: Moderate ẩn hai lần, nhận ' + CAST(@e AS NVARCHAR(10));

-- C1. Bình luận cấp 1 + trả lời
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC com.sp_PublishArticle @AuthorId = @u1, @ArticleType = N'Question', @Title = N'Test12 câu hỏi', @Body = N'?',
         @NewArticleId = @a OUTPUT;
    EXEC com.sp_AddComment @a, @u2, N'Trả lời cấp 1', @NewCommentId = @c OUTPUT;
    EXEC com.sp_AddComment @a, @u3, N'Trả lời cấp 2', @ParentCommentId = @c, @NewCommentId = @c2 OUTPUT;
    IF EXISTS (SELECT 1 FROM com.ArticleComments WHERE CommentId = @c AND ParentCommentId IS NULL AND IsVisible = 1 AND IsAccepted = 0)
       AND EXISTS (SELECT 1 FROM com.ArticleComments WHERE CommentId = @c2 AND ParentCommentId = @c)
        PRINT N'PASS: sp_AddComment bình luận cấp 1 và trả lời 1 cấp';
    ELSE PRINT N'FAIL: sp_AddComment hợp lệ';
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e <> 0 PRINT N'FAIL: AddComment lỗi bất ngờ ' + CAST(@e AS NVARCHAR(10)) + N' ' + ISNULL(@msg, N'');

-- C2. Trả lời của trả lời -> 50705 (trigger CheckLevel)
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC com.sp_PublishArticle @AuthorId = @u1, @ArticleType = N'Question', @Title = N'Test12 cấp', @Body = N'?',
         @NewArticleId = @a OUTPUT;
    EXEC com.sp_AddComment @a, @u2, N'cấp 1', @NewCommentId = @c OUTPUT;
    EXEC com.sp_AddComment @a, @u3, N'cấp 2', @ParentCommentId = @c, @NewCommentId = @c2 OUTPUT;
    EXEC com.sp_AddComment @a, @u1, N'cấp 3', @ParentCommentId = @c2, @NewCommentId = @c OUTPUT;
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50705 PRINT N'PASS: trigger CheckLevel chặn trả lời cấp 3 (50705)'; ELSE PRINT N'FAIL: CheckLevel, nhận ' + CAST(@e AS NVARCHAR(10));

-- C3. Bình luận bài Draft -> 50702
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    INSERT INTO com.Articles (AuthorId, ArticleType, Title, Slug, Body)
    VALUES (@u1, N'Experience', N'Test12 nháp', N'test12-draft', N'x');
    SET @a = SCOPE_IDENTITY();
    EXEC com.sp_AddComment @a, @u2, N'bình luận', @NewCommentId = @c OUTPUT;
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50702 PRINT N'PASS: sp_AddComment bài chưa xuất bản (50702)'; ELSE PRINT N'FAIL: AddComment bài Draft, nhận ' + CAST(@e AS NVARCHAR(10));

-- C4. Bài không tồn tại -> 50701
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC com.sp_AddComment 0, @u2, N'bình luận', @NewCommentId = @c OUTPUT;
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50701 PRINT N'PASS: sp_AddComment bài không tồn tại (50701)'; ELSE PRINT N'FAIL: AddComment không tồn tại, nhận ' + CAST(@e AS NVARCHAR(10));

-- D1-D2. Chọn câu trả lời, rồi chuyển sang câu khác (chỉ 1 câu được chọn)
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC com.sp_PublishArticle @AuthorId = @u1, @ArticleType = N'Question', @Title = N'Test12 accept', @Body = N'?',
         @NewArticleId = @a OUTPUT;
    EXEC com.sp_AddComment @a, @u2, N'đáp án 1', @NewCommentId = @c OUTPUT;
    EXEC com.sp_AddComment @a, @u3, N'đáp án 2', @NewCommentId = @c2 OUTPUT;

    EXEC com.sp_AcceptAnswer @c, @u1;
    IF EXISTS (SELECT 1 FROM com.ArticleComments WHERE CommentId = @c AND IsAccepted = 1)
        PRINT N'PASS: sp_AcceptAnswer đánh dấu câu trả lời được chọn';
    ELSE PRINT N'FAIL: sp_AcceptAnswer';

    EXEC com.sp_AcceptAnswer @c2, @u1;
    IF EXISTS (SELECT 1 FROM com.ArticleComments WHERE CommentId = @c2 AND IsAccepted = 1)
       AND (SELECT COUNT(*) FROM com.ArticleComments WHERE ArticleId = @a AND IsAccepted = 1) = 1
        PRINT N'PASS: sp_AcceptAnswer đổi sang câu khác, chỉ còn 1 câu được chọn';
    ELSE PRINT N'FAIL: sp_AcceptAnswer đổi câu';
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e <> 0 PRINT N'FAIL: AcceptAnswer lỗi bất ngờ ' + CAST(@e AS NVARCHAR(10)) + N' ' + ISNULL(@msg, N'');

-- D3. Không phải tác giả -> 50703
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC com.sp_PublishArticle @AuthorId = @u1, @ArticleType = N'Question', @Title = N'Test12 quyền chọn', @Body = N'?',
         @NewArticleId = @a OUTPUT;
    EXEC com.sp_AddComment @a, @u2, N'đáp án', @NewCommentId = @c OUTPUT;
    EXEC com.sp_AcceptAnswer @c, @u2;
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50703 PRINT N'PASS: sp_AcceptAnswer không phải tác giả (50703)'; ELSE PRINT N'FAIL: AcceptAnswer không phải tác giả, nhận ' + CAST(@e AS NVARCHAR(10));

-- D4. Bài không phải Question -> 50702
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC com.sp_PublishArticle @AuthorId = @u1, @ArticleType = N'Experience', @Title = N'Test12 không phải Question', @Body = N'x',
         @NewArticleId = @a OUTPUT;
    EXEC com.sp_AddComment @a, @u2, N'bình luận', @NewCommentId = @c OUTPUT;
    EXEC com.sp_AcceptAnswer @c, @u1;
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50702 PRINT N'PASS: sp_AcceptAnswer bài không phải Question (50702)'; ELSE PRINT N'FAIL: AcceptAnswer sai loại bài, nhận ' + CAST(@e AS NVARCHAR(10));

-- D5. Bình luận không tồn tại -> 50701
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC com.sp_AcceptAnswer 0, @u1;
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50701 PRINT N'PASS: sp_AcceptAnswer bình luận không tồn tại (50701)'; ELSE PRINT N'FAIL: AcceptAnswer không tồn tại, nhận ' + CAST(@e AS NVARCHAR(10));

-- D6. Chọn bình luận trả lời (cấp 2) -> 50705
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC com.sp_PublishArticle @AuthorId = @u1, @ArticleType = N'Question', @Title = N'Test12 cấp 2', @Body = N'?',
         @NewArticleId = @a OUTPUT;
    EXEC com.sp_AddComment @a, @u2, N'cấp 1', @NewCommentId = @c OUTPUT;
    EXEC com.sp_AddComment @a, @u3, N'cấp 2', @ParentCommentId = @c, @NewCommentId = @c2 OUTPUT;
    EXEC com.sp_AcceptAnswer @c2, @u1;
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50705 PRINT N'PASS: sp_AcceptAnswer chỉ chọn bình luận cấp 1 (50705)'; ELSE PRINT N'FAIL: AcceptAnswer cấp 2, nhận ' + CAST(@e AS NVARCHAR(10));

-- V1. vw_ExpertContributions khớp số bài Published của Expert
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC com.sp_PublishArticle @AuthorId = @exp, @ArticleType = N'Technical', @Title = N'Test12 view', @Body = N'x',
         @NewArticleId = @a OUTPUT;
    IF EXISTS (SELECT 1 FROM com.vw_ExpertContributions
               WHERE ExpertId = @exp AND PublishedArticles >= 1
                 AND PublishedArticles = (SELECT COUNT(*) FROM com.Articles WHERE AuthorId = @exp AND Status = N'Published' AND IsDeleted = 0))
        PRINT N'PASS: vw_ExpertContributions thống kê bài của Expert';
    ELSE PRINT N'FAIL: vw_ExpertContributions';
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e <> 0 PRINT N'FAIL: view lỗi bất ngờ ' + CAST(@e AS NVARCHAR(10)) + N' ' + ISNULL(@msg, N'');
GO