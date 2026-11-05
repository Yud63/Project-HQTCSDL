/* ============================================================
   File    : database/07_procedures/ai.sql
   Module  : ai - M9 AI Support
   Purpose : Procedure (★ = bắt buộc): ★sp_GetLabRecommendations, sp_SaveUserPreferences, sp_LogChatMessage, sp_RecordRecommendationAction, sp_ApproveKnowledgeDoc, sp_PurgeOldLogs. Dùng templates/procedure_template.sql; chữ ký theo docs/Contracts.md mục 7.
   Owner   : E (xem docs/Phan-cong.md)
   Depends : iam, lab, com
   Re-run  : CREATE OR ALTER - chạy lại bao nhiêu lần cũng được.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE ai.sp_GetLabRecommendations
    @UserId    INT,
    @TopN      TINYINT = 5,
    @Latitude  FLOAT = NULL,
    @Longitude FLOAT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        DECLARE @Ctx NVARCHAR(MAX);
        DECLARE @Top TABLE (LabId INT, LabName NVARCHAR(150), [Rank] TINYINT,
                            Score DECIMAL(6,4), AvgRating DECIMAL(3,2), DistanceKm DECIMAL(9,2));

        EXEC sp_set_session_context @key = N'UserId', @value = @UserId;

        IF NOT EXISTS (SELECT 1 FROM iam.Users WHERE UserId = @UserId AND IsDeleted = 0 AND IsActive = 1)
            THROW 50801, N'Người dùng không tồn tại hoặc đã bị khóa.', 1;
        IF @TopN IS NULL OR @TopN < 1 OR @TopN > 20
            THROW 50805, N'TopN phải từ 1 đến 20.', 1;
        IF (@Latitude IS NULL AND @Longitude IS NOT NULL) OR (@Latitude IS NOT NULL AND @Longitude IS NULL)
            THROW 50805, N'Phải truyền đủ cả vĩ độ và kinh độ.', 1;
        IF @Latitude NOT BETWEEN -90 AND 90 OR @Longitude NOT BETWEEN -180 AND 180
            THROW 50805, N'Tọa độ ngoài phạm vi hợp lệ.', 1;

        SET @Ctx = (SELECT @Latitude AS latitude, @Longitude AS longitude, @TopN AS topN
                    FOR JSON PATH, INCLUDE_NULL_VALUES, WITHOUT_ARRAY_WRAPPER);

        BEGIN TRAN;

        INSERT INTO @Top (LabId, LabName, [Rank], Score, AvgRating, DistanceKm)
        SELECT TOP (@TopN) s.LabId, s.LabName,
               CAST(ROW_NUMBER() OVER (ORDER BY s.Score DESC, s.AvgRating DESC, s.LabId) AS TINYINT),
               s.Score, s.AvgRating, s.DistanceKm
        FROM ai.fn_LabScores(@UserId, @Latitude, @Longitude) s
        ORDER BY s.Score DESC, s.AvgRating DESC, s.LabId;

        INSERT INTO ai.RecommendationLogs (UserId, RecommendationType, ItemId, [Rank], Score, ModelVersion, ContextJson)
        SELECT @UserId, N'Lab', t.LabId, t.[Rank], t.Score, N'tsql-v1', @Ctx
        FROM @Top t;

        COMMIT;

        SELECT LabId, LabName, [Rank], Score, AvgRating, DistanceKm
        FROM @Top
        ORDER BY [Rank];
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE ai.sp_SaveUserPreferences
    @UserId            INT,
    @PreferredFormatId INT = NULL,
    @PreferredFilmType NVARCHAR(15) = NULL,
    @PreferredCity     NVARCHAR(100) = NULL,
    @MaxDistanceKm     DECIMAL(6,2) = NULL,
    @MaxBudgetPerRoll  DECIMAL(18,0) = NULL,
    @PrioritizeQuality BIT = 0,
    @PrioritizeSpeed   BIT = 0,
    @Source            NVARCHAR(8) = N'UserSet',
    @ExtraJson         NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        EXEC sp_set_session_context @key = N'UserId', @value = @UserId;

        IF NOT EXISTS (SELECT 1 FROM iam.Users WHERE UserId = @UserId AND IsDeleted = 0 AND IsActive = 1)
            THROW 50801, N'Người dùng không tồn tại hoặc đã bị khóa.', 1;
        IF @PreferredFilmType IS NOT NULL AND @PreferredFilmType NOT IN (N'ColorNegative', N'BlackWhite', N'ColorSlide')
            THROW 50805, N'Loại phim ưa thích không hợp lệ.', 1;
        IF @PreferredFormatId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM lab.FilmFormats WHERE FormatId = @PreferredFormatId)
            THROW 50805, N'Định dạng phim không tồn tại.', 1;
        IF @MaxDistanceKm IS NOT NULL AND @MaxDistanceKm <= 0
            THROW 50805, N'Khoảng cách tối đa phải lớn hơn 0.', 1;
        IF @MaxBudgetPerRoll IS NOT NULL AND @MaxBudgetPerRoll < 0
            THROW 50805, N'Ngân sách không được âm.', 1;
        IF @Source IS NULL OR @Source NOT IN (N'UserSet', N'Inferred')
            THROW 50805, N'Source phải là UserSet hoặc Inferred.', 1;
        IF @ExtraJson IS NOT NULL AND ISJSON(@ExtraJson) <> 1
            THROW 50805, N'ExtraJson phải là JSON hợp lệ.', 1;

        BEGIN TRAN;

        IF EXISTS (SELECT 1 FROM ai.UserPreferences WITH (UPDLOCK, HOLDLOCK) WHERE UserId = @UserId)
            UPDATE ai.UserPreferences
            SET PreferredFormatId = @PreferredFormatId, PreferredFilmType = @PreferredFilmType,
                PreferredCity = @PreferredCity, MaxDistanceKm = @MaxDistanceKm,
                MaxBudgetPerRoll = @MaxBudgetPerRoll,
                PrioritizeQuality = ISNULL(@PrioritizeQuality, 0), PrioritizeSpeed = ISNULL(@PrioritizeSpeed, 0),
                Source = @Source, ExtraJson = @ExtraJson, UpdatedAt = SYSUTCDATETIME()
            WHERE UserId = @UserId;
        ELSE
            INSERT INTO ai.UserPreferences
                (UserId, PreferredFormatId, PreferredFilmType, PreferredCity, MaxDistanceKm, MaxBudgetPerRoll,
                 PrioritizeQuality, PrioritizeSpeed, Source, ExtraJson)
            VALUES
                (@UserId, @PreferredFormatId, @PreferredFilmType, @PreferredCity, @MaxDistanceKm, @MaxBudgetPerRoll,
                 ISNULL(@PrioritizeQuality, 0), ISNULL(@PrioritizeSpeed, 0), @Source, @ExtraJson);

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE ai.sp_LogChatMessage
    @UserId           INT,
    @SessionId        UNIQUEIDENTIFIER,
    @Role             NVARCHAR(9),
    @Message          NVARCHAR(MAX),
    @ModelName        NVARCHAR(50) = NULL,
    @PromptTokens     INT = NULL,
    @CompletionTokens INT = NULL,
    @LatencyMs        INT = NULL,
    @SourcesJson      NVARCHAR(MAX) = NULL,
    @NewChatLogId     BIGINT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        EXEC sp_set_session_context @key = N'UserId', @value = @UserId;

        IF NOT EXISTS (SELECT 1 FROM iam.Users WHERE UserId = @UserId AND IsDeleted = 0 AND IsActive = 1)
            THROW 50801, N'Người dùng không tồn tại hoặc đã bị khóa.', 1;
        IF @SessionId IS NULL
            THROW 50805, N'Thiếu SessionId.', 1;
        IF @Role IS NULL OR @Role NOT IN (N'User', N'Assistant', N'System')
            THROW 50805, N'Role phải là User, Assistant hoặc System.', 1;
        IF @Role = N'Assistant' AND NULLIF(LTRIM(RTRIM(@ModelName)), N'') IS NULL
            THROW 50805, N'Tin nhắn của Assistant phải có ModelName.', 1;
        IF NULLIF(LTRIM(RTRIM(@Message)), N'') IS NULL
            THROW 50805, N'Nội dung tin nhắn không được rỗng.', 1;
        IF @SourcesJson IS NOT NULL AND ISJSON(@SourcesJson) <> 1
            THROW 50805, N'SourcesJson phải là JSON hợp lệ.', 1;
        IF @PromptTokens < 0 OR @CompletionTokens < 0 OR @LatencyMs < 0
            THROW 50805, N'Số token và độ trễ không được âm.', 1;

        BEGIN TRAN;

        INSERT INTO ai.AIChatLogs (SessionId, UserId, [Role], Message, ModelName, PromptTokens, CompletionTokens, LatencyMs, SourcesJson)
        VALUES (@SessionId, @UserId, @Role, @Message, @ModelName, @PromptTokens, @CompletionTokens, @LatencyMs, @SourcesJson);

        SET @NewChatLogId = SCOPE_IDENTITY();

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE ai.sp_RecordRecommendationAction
    @RecLogId BIGINT,
    @UserId   INT,
    @Action   NVARCHAR(9)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        DECLARE @Owner INT, @Old NVARCHAR(9);

        EXEC sp_set_session_context @key = N'UserId', @value = @UserId;

        IF @Action IS NULL OR @Action NOT IN (N'Clicked', N'Ordered', N'Dismissed')
            THROW 50805, N'Action phải là Clicked, Ordered hoặc Dismissed.', 1;

        BEGIN TRAN;

        SELECT @Owner = UserId, @Old = [Action]
        FROM ai.RecommendationLogs WITH (UPDLOCK)
        WHERE RecLogId = @RecLogId;

        IF @Owner IS NULL
            THROW 50801, N'Bản ghi gợi ý không tồn tại.', 1;
        IF @Owner <> @UserId
            THROW 50803, N'Bản ghi gợi ý không thuộc về người dùng này.', 1;
        IF @Old = N'Ordered' AND @Action <> N'Ordered'
            THROW 50802, N'Gợi ý đã dẫn tới đặt đơn, không đổi được phản ứng.', 1;

        UPDATE ai.RecommendationLogs
        SET [Action] = @Action, ActedAt = SYSUTCDATETIME()
        WHERE RecLogId = @RecLogId;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE ai.sp_ApproveKnowledgeDoc
    @KnowledgeDocId INT,
    @AdminUserId    INT,
    @Approve        BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        DECLARE @IsApproved BIT;

        EXEC sp_set_session_context @key = N'UserId', @value = @AdminUserId;

        IF @Approve IS NULL
            THROW 50805, N'Approve phải là 0 hoặc 1.', 1;
        IF NOT EXISTS (SELECT 1 FROM iam.Users u
                       JOIN iam.UserRoles ur ON ur.UserId = u.UserId
                       JOIN iam.Roles r ON r.RoleId = ur.RoleId
                       WHERE u.UserId = @AdminUserId AND u.IsDeleted = 0 AND r.RoleCode = N'Admin')
            THROW 50803, N'Chỉ Admin được duyệt tri thức.', 1;

        BEGIN TRAN;

        SELECT @IsApproved = IsApproved
        FROM ai.KnowledgeDocs WITH (UPDLOCK)
        WHERE KnowledgeDocId = @KnowledgeDocId AND IsDeleted = 0;

        IF @IsApproved IS NULL
            THROW 50801, N'Chunk tri thức không tồn tại.', 1;
        IF @IsApproved = @Approve
            THROW 50802, N'Trạng thái duyệt không thay đổi.', 1;

        IF @Approve = 1
            UPDATE ai.KnowledgeDocs
            SET IsApproved = 1, ApprovedBy = @AdminUserId, ApprovedAt = SYSUTCDATETIME(), UpdatedAt = SYSUTCDATETIME()
            WHERE KnowledgeDocId = @KnowledgeDocId;
        ELSE
            UPDATE ai.KnowledgeDocs
            SET IsApproved = 0, ApprovedBy = NULL, ApprovedAt = NULL, UpdatedAt = SYSUTCDATETIME()
            WHERE KnowledgeDocId = @KnowledgeDocId;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

-- WITH EXECUTE AS OWNER: role_System (job hệ thống) không qua được RLS của ai.AIChatLogs, nếu không DELETE xóa 0 dòng mà không báo lỗi.
CREATE OR ALTER PROCEDURE ai.sp_PurgeOldLogs
    @ActorUserId   INT = NULL,
    @RetentionDays INT = 180,
    @DeletedCount  INT = NULL OUTPUT
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        IF @ActorUserId IS NOT NULL
            EXEC sp_set_session_context @key = N'UserId', @value = @ActorUserId;

        IF @RetentionDays IS NULL OR @RetentionDays < 1
            THROW 50805, N'Số ngày giữ log phải từ 1 trở lên.', 1;
        IF @ActorUserId IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM iam.Users u
                           JOIN iam.UserRoles ur ON ur.UserId = u.UserId
                           JOIN iam.Roles r ON r.RoleId = ur.RoleId
                           WHERE u.UserId = @ActorUserId AND u.IsDeleted = 0 AND r.RoleCode = N'Admin')
            THROW 50803, N'Chỉ Admin được dọn log.', 1;

        BEGIN TRAN;

        DELETE FROM ai.AIChatLogs
        WHERE CreatedAt < DATEADD(DAY, -@RetentionDays, SYSUTCDATETIME());
        SET @DeletedCount = @@ROWCOUNT;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

-- ===== Đợt 8a-2: đường đọc cho chatbot RAG =====
-- WITH EXECUTE AS OWNER: phần Full-Text chạy bằng dynamic SQL (không đi theo ownership chaining),
-- nếu không role_Customer/LabOwner/Expert bị từ chối đọc ai.KnowledgeDocs.
CREATE OR ALTER PROCEDURE ai.sp_SearchKnowledge
    @UserId INT,
    @Query  NVARCHAR(400),
    @TopN   TINYINT      = 3,
    @Topic  NVARCHAR(50) = NULL
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        DECLARE @Q NVARCHAR(400), @Mode NVARCHAR(10) = N'FullText', @Tokens INT;

        IF NOT EXISTS (SELECT 1 FROM iam.Users WHERE UserId = @UserId AND IsDeleted = 0 AND IsActive = 1)
            THROW 50801, N'Người dùng không tồn tại hoặc đã bị khóa.', 1;

        SET @Q = NULLIF(LTRIM(RTRIM(REPLACE(@Query, N'"', N' '))), N'');
        IF @Q IS NULL
            THROW 50805, N'Câu hỏi không được rỗng.', 1;
        IF @TopN IS NULL OR @TopN < 1 OR @TopN > 10
            THROW 50805, N'TopN phải từ 1 đến 10.', 1;

        CREATE TABLE #hit (KnowledgeDocId INT NOT NULL PRIMARY KEY, Score INT NOT NULL);

        -- Ưu tiên Full-Text nếu đã có FT index
        IF EXISTS (SELECT 1 FROM sys.fulltext_indexes WHERE object_id = OBJECT_ID(N'ai.KnowledgeDocs'))
        BEGIN
            EXEC sp_executesql
                 N'INSERT INTO #hit (KnowledgeDocId, Score)
                   SELECT d.KnowledgeDocId, f.[RANK]
                   FROM FREETEXTTABLE(ai.KnowledgeDocs, (Title, Content), @q) f
                   JOIN ai.KnowledgeDocs d ON d.KnowledgeDocId = f.[KEY]
                   WHERE d.IsApproved = 1 AND d.IsDeleted = 0 AND (@t IS NULL OR d.Topic = @t)',
                 N'@q NVARCHAR(400), @t NVARCHAR(50)', @q = @Q, @t = @Topic;
        END

        -- Không có FT index, FT chưa populate xong, hoặc không khớp -> LIKE theo từng từ
        IF NOT EXISTS (SELECT 1 FROM #hit)
        BEGIN
            SET @Mode = N'Like';
            DECLARE @Tok TABLE (Pat NVARCHAR(210) NOT NULL);

            INSERT INTO @Tok (Pat)
            SELECT TOP (8) t.Pat
            FROM (SELECT DISTINCT N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(s.value)), N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%' AS Pat
                  FROM STRING_SPLIT(@Q, N' ') s
                  WHERE LEN(LTRIM(RTRIM(s.value))) >= 3) t
            ORDER BY LEN(t.Pat) DESC;

            SET @Tokens = (SELECT COUNT(*) FROM @Tok);

            INSERT INTO #hit (KnowledgeDocId, Score)
            SELECT d.KnowledgeDocId, COUNT(*) * 100 / NULLIF(@Tokens, 0)
            FROM ai.KnowledgeDocs d
            JOIN @Tok k ON d.Title LIKE k.Pat OR d.Content LIKE k.Pat
            WHERE d.IsApproved = 1 AND d.IsDeleted = 0 AND (@Topic IS NULL OR d.Topic = @Topic)
            GROUP BY d.KnowledgeDocId;
        END

        -- Chỉ trả chunk đã duyệt; Content là dữ liệu không tin cậy, backend không coi là lệnh
        SELECT TOP (@TopN) d.KnowledgeDocId, d.SourceArticleId, d.ChunkIndex, d.Title, d.Topic, d.Content,
               h.Score, @Mode AS MatchMode
        FROM #hit h
        JOIN ai.KnowledgeDocs d ON d.KnowledgeDocId = h.KnowledgeDocId
        ORDER BY h.Score DESC, d.KnowledgeDocId;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO