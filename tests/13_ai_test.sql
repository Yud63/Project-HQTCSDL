USE FilmLabDB;
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
SET NOCOUNT ON;
DROP TABLE IF EXISTS #r;
CREATE TABLE #r (LabId INT, LabName NVARCHAR(150), [Rank] TINYINT, Score DECIMAL(6,4), AvgRating DECIMAL(3,2), DistanceKm DECIMAL(9,2));

DECLARE @u1 INT, @u2 INT, @exp INT, @adm INT, @nu INT, @oc INT, @ol INT, @kd INT, @fmt INT;
DECLARE @e INT, @msg NVARCHAR(400), @n0 INT, @cnt INT, @deleted INT;
DECLARE @rid BIGINT, @logid BIGINT, @sess UNIQUEIDENTIFIER, @lat FLOAT, @lon FLOAT;

SET @u1  = (SELECT UserId FROM iam.Users WHERE Email = N'an.nguyen@example.com');
SET @u2  = (SELECT UserId FROM iam.Users WHERE Email = N'binh.tran@example.com');
SET @exp = (SELECT UserId FROM iam.Users WHERE Email = N'expert@filmlab.vn');
SET @adm = (SELECT UserId FROM iam.Users WHERE Email = N'admin@filmlab.vn');
SET @fmt = (SELECT TOP 1 FormatId FROM lab.FilmFormats ORDER BY FormatId);

-- F1-F2. Function
IF (SELECT COUNT(*) FROM ai.fn_LabScores(@u1, NULL, NULL)) = (SELECT COUNT(*) FROM lab.FilmLabs WHERE ApprovalStatus = N'Approved' AND IsDeleted = 0)
   AND EXISTS (SELECT 1 FROM ai.fn_LabScores(@u1, NULL, NULL))
   AND NOT EXISTS (SELECT 1 FROM ai.fn_LabScores(@u1, NULL, NULL) WHERE Score < 0 OR Score > 1)
    PRINT N'PASS: fn_LabScores chỉ trả lab Approved, điểm trong [0, 1]';
ELSE PRINT N'FAIL: fn_LabScores phạm vi';

IF EXISTS (SELECT 1 FROM ai.fn_LabScores(@u1, NULL, NULL))
   AND NOT EXISTS (SELECT 1 FROM ai.fn_LabScores(@u1, NULL, NULL)
                   WHERE ABS(Score - (0.35 * RatingScore + 0.25 * DistanceScore + 0.20 * PriceScore
                                      + 0.10 * SpeedScore + 0.10 * HistoryScore)) > 0.0003)
    PRINT N'PASS: fn_LabScores Score = 0.35 Rating + 0.25 Distance + 0.20 Price + 0.10 Speed + 0.10 History';
ELSE PRINT N'FAIL: fn_LabScores trọng số';

-- R1. Gợi ý cơ bản: số dòng, Rank liên tục, Score giảm dần, ghi RecommendationLogs
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    DELETE FROM #r;
    SET @n0 = (SELECT COUNT(*) FROM ai.RecommendationLogs WHERE UserId = @u1 AND RecommendationType = N'Lab' AND ModelVersion = N'tsql-v1');
    INSERT INTO #r EXEC ai.sp_GetLabRecommendations @UserId = @u1, @TopN = 5;
    SET @cnt = (SELECT COUNT(*) FROM #r);
    IF @cnt = (SELECT CASE WHEN COUNT(*) > 5 THEN 5 ELSE COUNT(*) END FROM lab.FilmLabs WHERE ApprovalStatus = N'Approved' AND IsDeleted = 0)
       AND @cnt >= 1
       AND (SELECT MIN([Rank]) FROM #r) = 1 AND (SELECT MAX([Rank]) FROM #r) = @cnt
       AND NOT EXISTS (SELECT 1 FROM #r a JOIN #r b ON b.[Rank] = a.[Rank] + 1 WHERE b.Score > a.Score)
       AND (SELECT COUNT(*) FROM ai.RecommendationLogs WHERE UserId = @u1 AND RecommendationType = N'Lab' AND ModelVersion = N'tsql-v1') = @n0 + @cnt
        PRINT N'PASS: sp_GetLabRecommendations trả Top, Rank liên tục, Score giảm dần, ghi RecommendationLogs';
    ELSE PRINT N'FAIL: sp_GetLabRecommendations cơ bản';
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e <> 0 PRINT N'FAIL: gợi ý lỗi bất ngờ ' + CAST(@e AS NVARCHAR(10)) + N' ' + ISNULL(@msg, N'');

-- R2. TopN = 1
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    DELETE FROM #r;
    INSERT INTO #r EXEC ai.sp_GetLabRecommendations @UserId = @u1, @TopN = 1;
    IF (SELECT COUNT(*) FROM #r) = 1 AND (SELECT [Rank] FROM #r) = 1
        PRINT N'PASS: sp_GetLabRecommendations TopN = 1';
    ELSE PRINT N'FAIL: TopN = 1';
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e <> 0 PRINT N'FAIL: TopN lỗi bất ngờ ' + CAST(@e AS NVARCHAR(10)) + N' ' + ISNULL(@msg, N'');

-- R3. Có tọa độ: lab ngay tại điểm đó có khoảng cách ~ 0
SELECT TOP 1 @lat = Location.Lat, @lon = Location.Long
FROM lab.FilmLabs
WHERE ApprovalStatus = N'Approved' AND IsDeleted = 0 AND Location IS NOT NULL
ORDER BY LabId;
IF @lat IS NULL
    PRINT N'SKIP: seed không có lab Approved nào có Location';
ELSE
BEGIN
    SET @e = 0; BEGIN TRAN;
    BEGIN TRY
        DELETE FROM #r;
        INSERT INTO #r EXEC ai.sp_GetLabRecommendations @UserId = @u1, @TopN = 5, @Latitude = @lat, @Longitude = @lon;
        IF EXISTS (SELECT 1 FROM #r WHERE DistanceKm IS NOT NULL AND DistanceKm <= 0.1)
            PRINT N'PASS: gợi ý theo tọa độ trả DistanceKm, lab tại điểm đó ~ 0 km';
        ELSE PRINT N'FAIL: gợi ý theo tọa độ';
    END TRY
    BEGIN CATCH SET @e = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE(); END CATCH;
    IF @@TRANCOUNT > 0 ROLLBACK;
    IF @e <> 0 PRINT N'FAIL: tọa độ lỗi bất ngờ ' + CAST(@e AS NVARCHAR(10)) + N' ' + ISNULL(@msg, N'');
END

-- R4. Ngân sách quá thấp -> PriceScore = 0
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC ai.sp_SaveUserPreferences @UserId = @u2, @MaxBudgetPerRoll = 1;
    IF EXISTS (SELECT 1 FROM ai.fn_LabScores(@u2, NULL, NULL) WHERE MinPrice IS NOT NULL)
       AND NOT EXISTS (SELECT 1 FROM ai.fn_LabScores(@u2, NULL, NULL) WHERE MinPrice IS NOT NULL AND PriceScore <> 0)
        PRINT N'PASS: giá vượt MaxBudgetPerRoll -> PriceScore = 0';
    ELSE PRINT N'FAIL: ngân sách';
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e <> 0 PRINT N'FAIL: ngân sách lỗi bất ngờ ' + CAST(@e AS NVARCHAR(10)) + N' ' + ISNULL(@msg, N'');

-- R5. Lịch sử: khách có đơn Completed tại lab -> HistoryScore > 0
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    SET @oc = (SELECT CustomerId FROM ord.Orders WHERE OrderCode = N'FL-2026-000001');
    SET @ol = (SELECT LabId FROM ord.Orders WHERE OrderCode = N'FL-2026-000001');
    EXEC sp_set_session_context @key = N'UserId', @value = @adm;
    DISABLE TRIGGER ord.trg_Orders_PreventInvalidStage ON ord.Orders;
    UPDATE ord.Orders SET StageId = 12 WHERE OrderCode = N'FL-2026-000001';
    IF EXISTS (SELECT 1 FROM ai.fn_LabScores(@oc, NULL, NULL) WHERE LabId = @ol AND HistoryScore > 0)
        PRINT N'PASS: khách có đơn Completed tại lab -> HistoryScore > 0';
    ELSE PRINT N'FAIL: HistoryScore';
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e <> 0 PRINT N'FAIL: lịch sử lỗi bất ngờ ' + CAST(@e AS NVARCHAR(10)) + N' ' + ISNULL(@msg, N'');

-- R6. Người dùng mới: không lịch sử, không tọa độ -> HistoryScore = 0, DistanceScore = 0.5
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC iam.sp_RegisterUser @Email = N'test13.new@example.com', @FullName = N'Test13 New', @PasswordHash = N'x', @NewUserId = @nu OUTPUT;
    IF EXISTS (SELECT 1 FROM ai.fn_LabScores(@nu, NULL, NULL))
       AND NOT EXISTS (SELECT 1 FROM ai.fn_LabScores(@nu, NULL, NULL) WHERE HistoryScore <> 0 OR DistanceScore <> 0.5)
        PRINT N'PASS: người dùng mới -> HistoryScore = 0, DistanceScore trung tính 0.5';
    ELSE PRINT N'FAIL: người dùng mới';
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e <> 0 PRINT N'FAIL: người dùng mới lỗi bất ngờ ' + CAST(@e AS NVARCHAR(10)) + N' ' + ISNULL(@msg, N'');

-- R7-R10. Lỗi của sp_GetLabRecommendations
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC ai.sp_GetLabRecommendations 0;
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50801 PRINT N'PASS: gợi ý cho người dùng không tồn tại (50801)'; ELSE PRINT N'FAIL: gợi ý user không tồn tại, nhận ' + CAST(@e AS NVARCHAR(10));

SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC ai.sp_GetLabRecommendations @u1, 0;
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50805 PRINT N'PASS: TopN = 0 (50805)'; ELSE PRINT N'FAIL: TopN = 0, nhận ' + CAST(@e AS NVARCHAR(10));

SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC ai.sp_GetLabRecommendations @UserId = @u1, @TopN = 5, @Latitude = 10.7;
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50805 PRINT N'PASS: chỉ có vĩ độ, thiếu kinh độ (50805)'; ELSE PRINT N'FAIL: thiếu kinh độ, nhận ' + CAST(@e AS NVARCHAR(10));

SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC ai.sp_GetLabRecommendations @UserId = @u1, @TopN = 5, @Latitude = 91, @Longitude = 106;
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50805 PRINT N'PASS: vĩ độ ngoài phạm vi (50805)'; ELSE PRINT N'FAIL: vĩ độ 91, nhận ' + CAST(@e AS NVARCHAR(10));

-- P1. Lưu sở thích: insert rồi update (ghi đè toàn bộ, không tạo dòng thứ hai)
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC ai.sp_SaveUserPreferences @UserId = @u2, @PreferredFormatId = @fmt, @PreferredFilmType = N'BlackWhite',
         @PreferredCity = N'Hồ Chí Minh', @MaxDistanceKm = 15, @MaxBudgetPerRoll = 200000, @PrioritizeSpeed = 1;
    EXEC ai.sp_SaveUserPreferences @UserId = @u2, @PreferredCity = N'Hà Nội', @MaxDistanceKm = 20;
    IF (SELECT COUNT(*) FROM ai.UserPreferences WHERE UserId = @u2) = 1
       AND EXISTS (SELECT 1 FROM ai.UserPreferences WHERE UserId = @u2 AND PreferredCity = N'Hà Nội' AND MaxDistanceKm = 20
                   AND PreferredFilmType IS NULL AND PrioritizeSpeed = 0 AND Source = N'UserSet')
        PRINT N'PASS: sp_SaveUserPreferences upsert, ghi đè toàn bộ';
    ELSE PRINT N'FAIL: sp_SaveUserPreferences upsert';
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e <> 0 PRINT N'FAIL: SaveUserPreferences lỗi bất ngờ ' + CAST(@e AS NVARCHAR(10)) + N' ' + ISNULL(@msg, N'');

SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC ai.sp_SaveUserPreferences @UserId = @u2, @PreferredFilmType = N'Sepia';
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50805 PRINT N'PASS: loại phim ưa thích sai (50805)'; ELSE PRINT N'FAIL: FilmType sai, nhận ' + CAST(@e AS NVARCHAR(10));

SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC ai.sp_SaveUserPreferences @UserId = @u2, @PreferredFormatId = 9999;
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50805 PRINT N'PASS: định dạng phim không tồn tại (50805)'; ELSE PRINT N'FAIL: Format không tồn tại, nhận ' + CAST(@e AS NVARCHAR(10));

SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC ai.sp_SaveUserPreferences @UserId = @u2, @MaxDistanceKm = 0;
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50805 PRINT N'PASS: MaxDistanceKm = 0 (50805)'; ELSE PRINT N'FAIL: MaxDistanceKm = 0, nhận ' + CAST(@e AS NVARCHAR(10));

SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC ai.sp_SaveUserPreferences @UserId = 0;
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50801 PRINT N'PASS: lưu sở thích cho người dùng không tồn tại (50801)'; ELSE PRINT N'FAIL: Save user không tồn tại, nhận ' + CAST(@e AS NVARCHAR(10));

-- L1. Ghi log chat
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    SET @sess = NEWID();
    EXEC ai.sp_LogChatMessage @u1, @sess, N'User', N'Lab nào tráng C-41 giá rẻ?', @NewChatLogId = @logid OUTPUT;
    EXEC ai.sp_LogChatMessage @u1, @sess, N'Assistant', N'Bạn có thể thử lab gần nhất.', @ModelName = N'test-model',
         @PromptTokens = 10, @CompletionTokens = 20, @LatencyMs = 300, @SourcesJson = N'[1,2]', @NewChatLogId = @logid OUTPUT;
    IF (SELECT COUNT(*) FROM ai.AIChatLogs WHERE SessionId = @sess) = 2
       AND EXISTS (SELECT 1 FROM ai.AIChatLogs WHERE ChatLogId = @logid AND [Role] = N'Assistant' AND ModelName = N'test-model')
        PRINT N'PASS: sp_LogChatMessage ghi lượt User và Assistant cùng session';
    ELSE PRINT N'FAIL: sp_LogChatMessage';
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e <> 0 PRINT N'FAIL: LogChatMessage lỗi bất ngờ ' + CAST(@e AS NVARCHAR(10)) + N' ' + ISNULL(@msg, N'');

SET @e = 0; BEGIN TRAN;
BEGIN TRY
    SET @sess = NEWID();
    EXEC ai.sp_LogChatMessage @u1, @sess, N'Assistant', N'thiếu model', @NewChatLogId = @logid OUTPUT;
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50805 PRINT N'PASS: Assistant thiếu ModelName (50805)'; ELSE PRINT N'FAIL: Assistant thiếu ModelName, nhận ' + CAST(@e AS NVARCHAR(10));

SET @e = 0; BEGIN TRAN;
BEGIN TRY
    SET @sess = NEWID();
    EXEC ai.sp_LogChatMessage @u1, @sess, N'Bot', N'role lạ', @NewChatLogId = @logid OUTPUT;
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50805 PRINT N'PASS: Role lạ (50805)'; ELSE PRINT N'FAIL: Role lạ, nhận ' + CAST(@e AS NVARCHAR(10));

SET @e = 0; BEGIN TRAN;
BEGIN TRY
    SET @sess = NEWID();
    EXEC ai.sp_LogChatMessage @u1, @sess, N'User', N'json sai', @SourcesJson = N'khong phai json', @NewChatLogId = @logid OUTPUT;
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50805 PRINT N'PASS: SourcesJson sai (50805)'; ELSE PRINT N'FAIL: SourcesJson sai, nhận ' + CAST(@e AS NVARCHAR(10));

SET @e = 0; BEGIN TRAN;
BEGIN TRY
    SET @sess = NEWID();
    EXEC ai.sp_LogChatMessage 0, @sess, N'User', N'user không tồn tại', @NewChatLogId = @logid OUTPUT;
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50801 PRINT N'PASS: ghi log cho người dùng không tồn tại (50801)'; ELSE PRINT N'FAIL: LogChat user không tồn tại, nhận ' + CAST(@e AS NVARCHAR(10));

-- A1. Phản ứng với gợi ý: Clicked rồi Ordered
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    DELETE FROM #r;
    INSERT INTO #r EXEC ai.sp_GetLabRecommendations @UserId = @u1, @TopN = 1;
    SET @rid = (SELECT TOP 1 RecLogId FROM ai.RecommendationLogs WHERE UserId = @u1 ORDER BY RecLogId DESC);
    EXEC ai.sp_RecordRecommendationAction @rid, @u1, N'Clicked';
    IF NOT EXISTS (SELECT 1 FROM ai.RecommendationLogs WHERE RecLogId = @rid AND [Action] = N'Clicked' AND ActedAt IS NOT NULL)
        PRINT N'FAIL: Action Clicked';
    EXEC ai.sp_RecordRecommendationAction @rid, @u1, N'Ordered';
    IF EXISTS (SELECT 1 FROM ai.RecommendationLogs WHERE RecLogId = @rid AND [Action] = N'Ordered' AND ActedAt IS NOT NULL)
        PRINT N'PASS: sp_RecordRecommendationAction Clicked -> Ordered';
    ELSE PRINT N'FAIL: Action Ordered';
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e <> 0 PRINT N'FAIL: RecordAction lỗi bất ngờ ' + CAST(@e AS NVARCHAR(10)) + N' ' + ISNULL(@msg, N'');

-- A2. Ordered là trạng thái cuối -> 50802
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    DELETE FROM #r;
    INSERT INTO #r EXEC ai.sp_GetLabRecommendations @UserId = @u1, @TopN = 1;
    SET @rid = (SELECT TOP 1 RecLogId FROM ai.RecommendationLogs WHERE UserId = @u1 ORDER BY RecLogId DESC);
    EXEC ai.sp_RecordRecommendationAction @rid, @u1, N'Ordered';
    EXEC ai.sp_RecordRecommendationAction @rid, @u1, N'Clicked';
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50802 PRINT N'PASS: đổi phản ứng sau Ordered (50802)'; ELSE PRINT N'FAIL: Ordered -> Clicked, nhận ' + CAST(@e AS NVARCHAR(10));

-- A3. Log của người khác -> 50803
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    DELETE FROM #r;
    INSERT INTO #r EXEC ai.sp_GetLabRecommendations @UserId = @u1, @TopN = 1;
    SET @rid = (SELECT TOP 1 RecLogId FROM ai.RecommendationLogs WHERE UserId = @u1 ORDER BY RecLogId DESC);
    EXEC ai.sp_RecordRecommendationAction @rid, @u2, N'Clicked';
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50803 PRINT N'PASS: ghi phản ứng cho log của người khác (50803)'; ELSE PRINT N'FAIL: log người khác, nhận ' + CAST(@e AS NVARCHAR(10));

-- A4. Log không tồn tại -> 50801
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC ai.sp_RecordRecommendationAction 0, @u1, N'Clicked';
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50801 PRINT N'PASS: log gợi ý không tồn tại (50801)'; ELSE PRINT N'FAIL: log không tồn tại, nhận ' + CAST(@e AS NVARCHAR(10));

-- A5. Action lạ -> 50805
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC ai.sp_RecordRecommendationAction 1, @u1, N'Liked';
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50805 PRINT N'PASS: Action lạ (50805)'; ELSE PRINT N'FAIL: Action lạ, nhận ' + CAST(@e AS NVARCHAR(10));

-- K1. Duyệt rồi bỏ duyệt chunk tri thức
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    INSERT INTO ai.KnowledgeDocs (Title, Content, ContributedBy) VALUES (N'Test13 doc', N'Nội dung chunk test', @exp);
    SET @kd = SCOPE_IDENTITY();
    EXEC ai.sp_ApproveKnowledgeDoc @kd, @adm;
    IF EXISTS (SELECT 1 FROM ai.KnowledgeDocs WHERE KnowledgeDocId = @kd AND IsApproved = 1 AND ApprovedBy = @adm AND ApprovedAt IS NOT NULL)
        PRINT N'PASS: sp_ApproveKnowledgeDoc duyệt chunk';
    ELSE PRINT N'FAIL: Approve chunk';
    EXEC ai.sp_ApproveKnowledgeDoc @kd, @adm, 0;
    IF EXISTS (SELECT 1 FROM ai.KnowledgeDocs WHERE KnowledgeDocId = @kd AND IsApproved = 0 AND ApprovedBy IS NULL AND ApprovedAt IS NULL)
        PRINT N'PASS: sp_ApproveKnowledgeDoc bỏ duyệt chunk';
    ELSE PRINT N'FAIL: Unapprove chunk';
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e <> 0 PRINT N'FAIL: ApproveKnowledgeDoc lỗi bất ngờ ' + CAST(@e AS NVARCHAR(10)) + N' ' + ISNULL(@msg, N'');

-- K2. Không phải Admin -> 50803
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    INSERT INTO ai.KnowledgeDocs (Title, Content, ContributedBy) VALUES (N'Test13 doc', N'Nội dung', @exp);
    SET @kd = SCOPE_IDENTITY();
    EXEC ai.sp_ApproveKnowledgeDoc @kd, @u1;
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50803 PRINT N'PASS: duyệt chunk không phải Admin (50803)'; ELSE PRINT N'FAIL: Approve không phải Admin, nhận ' + CAST(@e AS NVARCHAR(10));

-- K3. Chunk không tồn tại -> 50801
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC ai.sp_ApproveKnowledgeDoc 0, @adm;
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50801 PRINT N'PASS: chunk không tồn tại (50801)'; ELSE PRINT N'FAIL: chunk không tồn tại, nhận ' + CAST(@e AS NVARCHAR(10));

-- K4. Duyệt hai lần -> 50802
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    INSERT INTO ai.KnowledgeDocs (Title, Content, ContributedBy) VALUES (N'Test13 doc', N'Nội dung', @exp);
    SET @kd = SCOPE_IDENTITY();
    EXEC ai.sp_ApproveKnowledgeDoc @kd, @adm;
    EXEC ai.sp_ApproveKnowledgeDoc @kd, @adm;
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50802 PRINT N'PASS: duyệt chunk đã duyệt (50802)'; ELSE PRINT N'FAIL: duyệt hai lần, nhận ' + CAST(@e AS NVARCHAR(10));

-- K5. Trigger: người đóng góp không phải Expert -> 50803
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    INSERT INTO ai.KnowledgeDocs (Title, Content, ContributedBy) VALUES (N'Test13 sai role', N'Nội dung', @u1);
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50803 PRINT N'PASS: trigger KnowledgeDocs_Guard chặn người đóng góp không phải Expert (50803)'; ELSE PRINT N'FAIL: Guard contributor, nhận ' + CAST(@e AS NVARCHAR(10));

-- K6. Trigger: UPDATE trực tiếp duyệt bởi người không phải Admin -> 50803
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    INSERT INTO ai.KnowledgeDocs (Title, Content, ContributedBy) VALUES (N'Test13 duyệt sai', N'Nội dung', @exp);
    SET @kd = SCOPE_IDENTITY();
    UPDATE ai.KnowledgeDocs SET IsApproved = 1, ApprovedBy = @u1, ApprovedAt = SYSUTCDATETIME() WHERE KnowledgeDocId = @kd;
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50803 PRINT N'PASS: trigger KnowledgeDocs_Guard chặn duyệt bởi người không phải Admin (50803)'; ELSE PRINT N'FAIL: Guard approver, nhận ' + CAST(@e AS NVARCHAR(10));

-- U1. Dọn log chat quá hạn
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    INSERT INTO ai.AIChatLogs (SessionId, UserId, [Role], Message, CreatedAt)
    VALUES (NEWID(), @u1, N'User', N'Test13 cũ',  DATEADD(DAY, -200, SYSUTCDATETIME())),
           (NEWID(), @u1, N'User', N'Test13 mới', DATEADD(DAY, -10,  SYSUTCDATETIME()));
    EXEC ai.sp_PurgeOldLogs @DeletedCount = @deleted OUTPUT;
    IF @deleted >= 1
       AND NOT EXISTS (SELECT 1 FROM ai.AIChatLogs WHERE Message = N'Test13 cũ')
       AND EXISTS (SELECT 1 FROM ai.AIChatLogs WHERE Message = N'Test13 mới')
        PRINT N'PASS: sp_PurgeOldLogs (job hệ thống) xóa log quá 180 ngày, giữ log mới';
    ELSE PRINT N'FAIL: sp_PurgeOldLogs hệ thống';

    EXEC ai.sp_PurgeOldLogs @ActorUserId = @adm, @RetentionDays = 5, @DeletedCount = @deleted OUTPUT;
    IF @deleted >= 1 AND NOT EXISTS (SELECT 1 FROM ai.AIChatLogs WHERE Message = N'Test13 mới')
        PRINT N'PASS: sp_PurgeOldLogs Admin với RetentionDays tùy chỉnh';
    ELSE PRINT N'FAIL: sp_PurgeOldLogs Admin';
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e <> 0 PRINT N'FAIL: PurgeOldLogs lỗi bất ngờ ' + CAST(@e AS NVARCHAR(10)) + N' ' + ISNULL(@msg, N'');

SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC ai.sp_PurgeOldLogs @ActorUserId = @u1, @DeletedCount = @deleted OUTPUT;
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50803 PRINT N'PASS: dọn log không phải Admin (50803)'; ELSE PRINT N'FAIL: Purge không phải Admin, nhận ' + CAST(@e AS NVARCHAR(10));

SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC ai.sp_PurgeOldLogs @RetentionDays = 0, @DeletedCount = @deleted OUTPUT;
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50805 PRINT N'PASS: RetentionDays = 0 (50805)'; ELSE PRINT N'FAIL: RetentionDays = 0, nhận ' + CAST(@e AS NVARCHAR(10));

-- V1. vw_RecommendationMetrics
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    DELETE FROM #r;
    INSERT INTO #r EXEC ai.sp_GetLabRecommendations @UserId = @u1, @TopN = 2;
    SET @rid = (SELECT TOP 1 RecLogId FROM ai.RecommendationLogs WHERE UserId = @u1 ORDER BY RecLogId DESC);
    EXEC ai.sp_RecordRecommendationAction @rid, @u1, N'Clicked';
    IF EXISTS (SELECT 1 FROM ai.vw_RecommendationMetrics
               WHERE ModelVersion = N'tsql-v1' AND RecommendationType = N'Lab'
                 AND Impressions = (SELECT COUNT(*) FROM ai.RecommendationLogs WHERE ModelVersion = N'tsql-v1' AND RecommendationType = N'Lab')
                 AND Clicked >= 1 AND CtrRate > 0)
        PRINT N'PASS: vw_RecommendationMetrics thống kê Impressions, Clicked, CTR';
    ELSE PRINT N'FAIL: vw_RecommendationMetrics';
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e <> 0 PRINT N'FAIL: view lỗi bất ngờ ' + CAST(@e AS NVARCHAR(10)) + N' ' + ISNULL(@msg, N'');
GO