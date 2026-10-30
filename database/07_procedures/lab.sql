/* ============================================================
   File    : database/07_procedures/lab.sql
   Module  : lab - M2 Lab & Catalog
   Purpose : Procedure (★ = bắt buộc): ★sp_ApproveLab, ★sp_SearchLabs, sp_RecalcLabRating. Dùng templates/procedure_template.sql; chữ ký theo docs/Contracts.md mục 7.
   Owner   : B (xem docs/Phan-cong.md)
   Depends : iam
   Re-run  : CREATE OR ALTER - chạy lại bao nhiêu lần cũng được.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE lab.sp_RecalcLabRating
    @LabId INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM lab.FilmLabs WHERE LabId = @LabId)
            THROW 50201, N'Lab không tồn tại.', 1;

        UPDATE l
        SET AvgRating   = ISNULL(r.AvgR, 0),
            ReviewCount = ISNULL(r.Cnt, 0),
            UpdatedAt   = SYSUTCDATETIME()
        FROM lab.FilmLabs l
        OUTER APPLY (SELECT CAST(AVG(CAST(RatingOverall AS DECIMAL(5,2))) AS DECIMAL(3,2)) AS AvgR, COUNT(*) AS Cnt
                     FROM ord.Reviews
                     WHERE LabId = l.LabId AND IsVisible = 1 AND IsDeleted = 0) r
        WHERE l.LabId = @LabId;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE lab.sp_ApproveLab
    @LabId       INT,
    @AdminUserId INT,
    @Decision    NVARCHAR(12),
    @Reason      NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        EXEC sp_set_session_context @key = N'UserId', @value = @AdminUserId;

        BEGIN TRAN;

        DECLARE @Cur NVARCHAR(12);
        SELECT @Cur = ApprovalStatus
        FROM lab.FilmLabs WITH (UPDLOCK, HOLDLOCK)
        WHERE LabId = @LabId AND IsDeleted = 0;

        IF @Cur IS NULL
            THROW 50201, N'Lab không tồn tại.', 1;
        IF NOT EXISTS (SELECT 1 FROM iam.UserRoles ur JOIN iam.Roles r ON r.RoleId = ur.RoleId
                       WHERE ur.UserId = @AdminUserId AND r.RoleCode = N'Admin')
            THROW 50203, N'Chỉ Admin được duyệt, từ chối hoặc đình chỉ lab.', 1;
        IF @Decision NOT IN (N'Approved', N'Rejected', N'Suspended')
            THROW 50205, N'Quyết định phải là Approved, Rejected hoặc Suspended.', 1;
        IF @Decision <> N'Approved' AND NULLIF(LTRIM(RTRIM(@Reason)), N'') IS NULL
            THROW 50205, N'Từ chối hoặc đình chỉ lab phải có lý do.', 1;
        IF @Decision = @Cur
            THROW 50202, N'Lab đã ở trạng thái này.', 1;

        UPDATE lab.FilmLabs
        SET ApprovalStatus = @Decision, UpdatedAt = SYSUTCDATETIME()
        WHERE LabId = @LabId;

        INSERT INTO lab.LabApprovals (LabId, ReviewedBy, Decision, Reason)
        VALUES (@LabId, @AdminUserId, @Decision, NULLIF(LTRIM(RTRIM(@Reason)), N''));

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE lab.sp_SearchLabs
    @Latitude          FLOAT         = NULL,
    @Longitude         FLOAT         = NULL,
    @MaxDistanceKm     DECIMAL(6,2)  = NULL,
    @FormatId          INT           = NULL,
    @ServiceTypeId     INT           = NULL,
    @MaxPrice          DECIMAL(18,0) = NULL,
    @MaxTurnaroundDays TINYINT       = NULL,
    @MinRating         DECIMAL(3,2)  = NULL,
    @Technique         NVARCHAR(50)  = NULL,
    @SortBy            NVARCHAR(20)  = N'Relevance',
    @PageNo            INT           = 1,
    @PageSize          INT           = 20
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        IF @PageNo IS NULL OR @PageNo < 1 OR @PageSize IS NULL OR @PageSize < 1 OR @PageSize > 100
            THROW 50205, N'PageNo phải từ 1, PageSize phải từ 1 đến 100.', 1;
        IF @SortBy IS NULL OR @SortBy NOT IN (N'Relevance', N'Distance', N'Price', N'Rating', N'Turnaround')
            THROW 50205, N'SortBy phải là Relevance, Distance, Price, Rating hoặc Turnaround.', 1;
        IF (@Latitude IS NULL AND @Longitude IS NOT NULL) OR (@Latitude IS NOT NULL AND @Longitude IS NULL)
            THROW 50205, N'Phải truyền đủ cả vĩ độ và kinh độ.', 1;
        IF (@Latitude IS NOT NULL AND (@Latitude < -90 OR @Latitude > 90))
           OR (@Longitude IS NOT NULL AND (@Longitude < -180 OR @Longitude > 180))
            THROW 50205, N'Vĩ độ hoặc kinh độ nằm ngoài phạm vi hợp lệ.', 1;
        IF @Latitude IS NULL AND (@MaxDistanceKm IS NOT NULL OR @SortBy = N'Distance')
            THROW 50205, N'Lọc hoặc sắp xếp theo khoảng cách cần có tọa độ.', 1;

        DECLARE @pt geography = CASE WHEN @Latitude IS NOT NULL THEN geography::Point(@Latitude, @Longitude, 4326) END;

        ;WITH svc AS (
            SELECT ls.LabId,
                   MIN(ls.UnitPrice)                 AS MinPrice,
                   MIN(CAST(ls.TurnaroundDays AS INT)) AS MinTurn
            FROM lab.LabServices ls
            WHERE ls.IsActive = 1 AND ls.IsDeleted = 0
              AND (@FormatId IS NULL OR ls.FormatId = @FormatId)
              AND (@ServiceTypeId IS NULL OR ls.ServiceTypeId = @ServiceTypeId)
              AND (@MaxPrice IS NULL OR ls.UnitPrice <= @MaxPrice)
              AND (@MaxTurnaroundDays IS NULL OR ls.TurnaroundDays <= @MaxTurnaroundDays)
            GROUP BY ls.LabId),
        base AS (
            SELECT l.LabId, l.LabName, l.City,
                   lab.fn_DistanceKm(l.Location, @pt)  AS DistanceKm,
                   l.AvgRating, l.ReviewCount,
                   s.MinPrice,
                   CAST(s.MinTurn AS TINYINT)          AS MinTurnaroundDays
            FROM lab.FilmLabs l
            JOIN svc s ON s.LabId = l.LabId
            WHERE l.ApprovalStatus = N'Approved' AND l.IsDeleted = 0
              AND (@MinRating IS NULL OR l.AvgRating >= @MinRating)
              AND (@Technique IS NULL OR EXISTS (SELECT 1 FROM OPENJSON(l.SpecialTechniques) j WHERE j.[value] = @Technique)))
        SELECT LabId, LabName, City, DistanceKm, AvgRating, ReviewCount, MinPrice, MinTurnaroundDays
        FROM base
        WHERE @MaxDistanceKm IS NULL OR DistanceKm <= @MaxDistanceKm
        ORDER BY
            CASE WHEN @SortBy = N'Distance' AND DistanceKm IS NULL THEN 1 ELSE 0 END,
            CASE WHEN @SortBy = N'Distance'   THEN DistanceKm END ASC,
            CASE WHEN @SortBy = N'Price'      THEN MinPrice END ASC,
            CASE WHEN @SortBy = N'Turnaround' THEN MinTurnaroundDays END ASC,
            CASE WHEN @SortBy IN (N'Rating', N'Relevance') THEN AvgRating END DESC,
            ReviewCount DESC,
            CASE WHEN DistanceKm IS NULL THEN 1 ELSE 0 END,
            DistanceKm ASC,
            LabId
        OFFSET (@PageNo - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO