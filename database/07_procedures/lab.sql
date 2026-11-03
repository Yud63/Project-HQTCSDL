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

CREATE OR ALTER PROCEDURE lab.sp_SaveLabProfile
    @OwnerUserId        INT,
    @LabName            NVARCHAR(150),
    @AddressLine        NVARCHAR(255),
    @Ward               NVARCHAR(100),
    @District           NVARCHAR(100),
    @City               NVARCHAR(100),
    @LabId              INT            = NULL,   -- NULL: tạo lab mới (ApprovalStatus = Pending)
    @Description        NVARCHAR(1000) = NULL,
    @Latitude           FLOAT          = NULL,
    @Longitude          FLOAT          = NULL,
    @Phone              NVARCHAR(20)   = NULL,
    @Email              NVARCHAR(255)  = NULL,
    @OpenHoursJson      NVARCHAR(MAX)  = NULL,
    @SpecialTechniques  NVARCHAR(MAX)  = NULL,
    @DailyCapacityRolls SMALLINT       = 50,
    @NewLabId           INT            = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        EXEC sp_set_session_context @key = N'UserId', @value = @OwnerUserId;

        BEGIN TRAN;

        DECLARE @CurOwner INT;
        IF @LabId IS NOT NULL
        BEGIN
            SELECT @CurOwner = OwnerUserId
            FROM lab.FilmLabs WITH (UPDLOCK, HOLDLOCK)
            WHERE LabId = @LabId AND IsDeleted = 0;
            IF @CurOwner IS NULL
                THROW 50201, N'Lab không tồn tại.', 1;
        END;

        IF NOT EXISTS (SELECT 1 FROM iam.UserRoles ur
                       JOIN iam.Roles r ON r.RoleId = ur.RoleId
                       JOIN iam.Users u ON u.UserId = ur.UserId
                       WHERE ur.UserId = @OwnerUserId AND r.RoleCode = N'LabOwner' AND u.IsActive = 1 AND u.IsDeleted = 0)
            THROW 50203, N'Chỉ người dùng có role LabOwner được quản lý hồ sơ lab.', 1;
        IF @CurOwner IS NOT NULL AND @CurOwner <> @OwnerUserId
            THROW 50203, N'Chỉ chủ lab được sửa hồ sơ lab.', 1;

        SET @LabName = LTRIM(RTRIM(@LabName));
        SET @AddressLine = LTRIM(RTRIM(@AddressLine));
        SET @Ward = LTRIM(RTRIM(@Ward));
        SET @District = LTRIM(RTRIM(@District));
        SET @City = LTRIM(RTRIM(@City));
        IF NULLIF(@LabName, N'') IS NULL OR NULLIF(@AddressLine, N'') IS NULL OR NULLIF(@Ward, N'') IS NULL
           OR NULLIF(@District, N'') IS NULL OR NULLIF(@City, N'') IS NULL
            THROW 50205, N'Tên lab, địa chỉ, phường, quận và thành phố không được rỗng.', 1;
        IF @DailyCapacityRolls IS NULL OR @DailyCapacityRolls < 1
            THROW 50205, N'DailyCapacityRolls phải lớn hơn 0.', 1;
        IF (@Latitude IS NULL AND @Longitude IS NOT NULL) OR (@Latitude IS NOT NULL AND @Longitude IS NULL)
            THROW 50205, N'Phải truyền đủ cả vĩ độ và kinh độ.', 1;
        IF (@Latitude < -90 OR @Latitude > 90) OR (@Longitude < -180 OR @Longitude > 180)
            THROW 50205, N'Vĩ độ hoặc kinh độ nằm ngoài phạm vi hợp lệ.', 1;
        IF (@OpenHoursJson IS NOT NULL AND ISJSON(@OpenHoursJson) = 0)
           OR (@SpecialTechniques IS NOT NULL AND ISJSON(@SpecialTechniques) = 0)
            THROW 50205, N'OpenHoursJson và SpecialTechniques phải là JSON hợp lệ.', 1;

        DECLARE @pt geography = CASE WHEN @Latitude IS NOT NULL THEN geography::Point(@Latitude, @Longitude, 4326) END;

        IF @LabId IS NULL
        BEGIN
            INSERT INTO lab.FilmLabs (OwnerUserId, LabName, Description, AddressLine, Ward, District, City, Location,
                                      Phone, Email, OpenHoursJson, SpecialTechniques, DailyCapacityRolls)
            VALUES (@OwnerUserId, @LabName, @Description, @AddressLine, @Ward, @District, @City, @pt,
                    @Phone, @Email, @OpenHoursJson, @SpecialTechniques, @DailyCapacityRolls);
            SET @NewLabId = SCOPE_IDENTITY();
        END
        ELSE
        BEGIN
            -- Ghi đè toàn bộ trường hồ sơ; KHÔNG đụng ApprovalStatus, AvgRating, ReviewCount
            UPDATE lab.FilmLabs
            SET LabName = @LabName, Description = @Description, AddressLine = @AddressLine, Ward = @Ward,
                District = @District, City = @City, Location = @pt, Phone = @Phone, Email = @Email,
                OpenHoursJson = @OpenHoursJson, SpecialTechniques = @SpecialTechniques,
                DailyCapacityRolls = @DailyCapacityRolls, UpdatedAt = SYSUTCDATETIME()
            WHERE LabId = @LabId;
            SET @NewLabId = @LabId;
        END;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE lab.sp_SaveLabService
    @OwnerUserId     INT,
    @LabId           INT,
    @ServiceTypeId   INT,
    @FormatId        INT,
    @PackageName     NVARCHAR(150),
    @UnitPrice       DECIMAL(18,0),
    @TurnaroundDays  TINYINT,
    @LabServiceId    INT           = NULL,      -- NULL: thêm gói mới
    @ProcessCode     NVARCHAR(10)  = N'ANY',
    @Description     NVARCHAR(500) = NULL,
    @PriceUnit       NVARCHAR(5)   = N'Roll',
    @ScanQuality     NVARCHAR(5)   = NULL,      -- bắt buộc với gói Scan, để trống với gói khác
    @IsActive        BIT           = 1,
    @IsDeleted       BIT           = 0,
    @NewLabServiceId INT           = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        EXEC sp_set_session_context @key = N'UserId', @value = @OwnerUserId;

        BEGIN TRAN;

        DECLARE @CurOwner INT;
        SELECT @CurOwner = OwnerUserId
        FROM lab.FilmLabs WITH (UPDLOCK, HOLDLOCK)
        WHERE LabId = @LabId AND IsDeleted = 0;
        IF @CurOwner IS NULL
            THROW 50201, N'Lab không tồn tại.', 1;
        IF @CurOwner <> @OwnerUserId
            THROW 50203, N'Chỉ chủ lab được quản lý gói dịch vụ.', 1;
        IF @LabServiceId IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM lab.LabServices WITH (UPDLOCK, HOLDLOCK)
                           WHERE LabServiceId = @LabServiceId AND LabId = @LabId AND IsDeleted = 0)
            THROW 50201, N'Gói dịch vụ không tồn tại trong lab này.', 1;

        SET @PackageName = LTRIM(RTRIM(@PackageName));
        IF NULLIF(@PackageName, N'') IS NULL
            THROW 50205, N'Tên gói không được rỗng.', 1;
        IF @UnitPrice IS NULL OR @UnitPrice < 0
            THROW 50205, N'Giá phải từ 0 trở lên.', 1;
        IF @TurnaroundDays IS NULL OR @TurnaroundDays NOT BETWEEN 1 AND 60
            THROW 50205, N'Thời gian xử lý phải từ 1 đến 60 ngày.', 1;
        IF @ProcessCode IS NULL OR @ProcessCode NOT IN (N'C-41', N'E-6', N'BW', N'ECN-2', N'ANY')
            THROW 50205, N'ProcessCode không hợp lệ.', 1;
        IF @PriceUnit IS NULL OR @PriceUnit NOT IN (N'Roll', N'Frame')
            THROW 50205, N'PriceUnit phải là Roll hoặc Frame.', 1;
        IF @ScanQuality IS NOT NULL AND @ScanQuality NOT IN (N'Basic', N'High', N'Ultra')
            THROW 50205, N'ScanQuality phải là Basic, High hoặc Ultra.', 1;
        IF @IsActive IS NULL OR @IsDeleted IS NULL
            THROW 50205, N'IsActive và IsDeleted không được NULL.', 1;
        IF NOT EXISTS (SELECT 1 FROM lab.ServiceTypes WHERE ServiceTypeId = @ServiceTypeId)
            THROW 50205, N'Loại dịch vụ không tồn tại.', 1;
        IF NOT EXISTS (SELECT 1 FROM lab.FilmFormats WHERE FormatId = @FormatId)
            THROW 50205, N'Định dạng phim không tồn tại.', 1;
        IF @IsDeleted = 1 SET @IsActive = 0;

        IF @LabServiceId IS NULL
        BEGIN
            INSERT INTO lab.LabServices (LabId, ServiceTypeId, FormatId, ProcessCode, PackageName, Description,
                                         UnitPrice, PriceUnit, ScanQuality, TurnaroundDays, IsActive, IsDeleted)
            VALUES (@LabId, @ServiceTypeId, @FormatId, @ProcessCode, @PackageName, @Description,
                    @UnitPrice, @PriceUnit, @ScanQuality, @TurnaroundDays, @IsActive, @IsDeleted);
            SET @NewLabServiceId = SCOPE_IDENTITY();
        END
        ELSE
        BEGIN
            UPDATE lab.LabServices
            SET ServiceTypeId = @ServiceTypeId, FormatId = @FormatId, ProcessCode = @ProcessCode,
                PackageName = @PackageName, Description = @Description, UnitPrice = @UnitPrice,
                PriceUnit = @PriceUnit, ScanQuality = @ScanQuality, TurnaroundDays = @TurnaroundDays,
                IsActive = @IsActive, IsDeleted = @IsDeleted, UpdatedAt = SYSUTCDATETIME()
            WHERE LabServiceId = @LabServiceId;
            SET @NewLabServiceId = @LabServiceId;
        END;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        IF ERROR_NUMBER() IN (2601, 2627)
            THROW 50205, N'Tên gói đã tồn tại trong lab này.', 1;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE lab.sp_GetLabDetail
    @LabId INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM lab.FilmLabs WHERE LabId = @LabId AND ApprovalStatus = N'Approved' AND IsDeleted = 0)
            THROW 50201, N'Lab không tồn tại hoặc chưa được duyệt.', 1;

        -- Result set 1: thông tin lab
        SELECT l.LabId, l.LabName, l.Description, l.AddressLine, l.Ward, l.District, l.City,
               l.Location.Lat AS Latitude, l.Location.Long AS Longitude,
               l.Phone, l.Email, l.OpenHoursJson, l.SpecialTechniques, l.DailyCapacityRolls,
               l.AvgRating, l.ReviewCount
        FROM lab.FilmLabs l
        WHERE l.LabId = @LabId;

        -- Result set 2: gói dịch vụ đang bán
        SELECT ls.LabServiceId, ls.ServiceTypeId, st.ServiceCode, st.ServiceName, st.Category,
               ls.FormatId, ff.FormatCode, ff.FormatName, ls.ProcessCode, ls.PackageName, ls.Description,
               ls.UnitPrice, ls.PriceUnit, ls.ScanQuality, ls.TurnaroundDays
        FROM lab.LabServices ls
        JOIN lab.ServiceTypes st ON st.ServiceTypeId = ls.ServiceTypeId
        JOIN lab.FilmFormats  ff ON ff.FormatId = ls.FormatId
        WHERE ls.LabId = @LabId AND ls.IsActive = 1 AND ls.IsDeleted = 0
        ORDER BY st.Category, ls.PackageName;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE lab.sp_GetMyLabs
    @OwnerUserId INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        -- Result set 1: lab của chủ, mọi trạng thái duyệt, kèm quyết định gần nhất (lý do từ chối/đình chỉ)
        SELECT l.LabId, l.LabName, l.Description, l.AddressLine, l.Ward, l.District, l.City,
               l.Location.Lat AS Latitude, l.Location.Long AS Longitude,
               l.Phone, l.Email, l.OpenHoursJson, l.SpecialTechniques, l.DailyCapacityRolls,
               l.ApprovalStatus, l.AvgRating, l.ReviewCount,
               a.Decision AS LastDecision, a.Reason AS LastDecisionReason, a.DecidedAt AS LastDecidedAt
        FROM lab.FilmLabs l
        OUTER APPLY (SELECT TOP 1 x.Decision, x.Reason, x.DecidedAt
                     FROM lab.LabApprovals x
                     WHERE x.LabId = l.LabId
                     ORDER BY x.DecidedAt DESC, x.ApprovalId DESC) a
        WHERE l.OwnerUserId = @OwnerUserId AND l.IsDeleted = 0
        ORDER BY l.LabId;

        -- Result set 2: gói dịch vụ của các lab đó, kể cả gói đang ẩn
        SELECT ls.LabId, ls.LabServiceId, ls.ServiceTypeId, st.ServiceCode, st.ServiceName, st.Category,
               ls.FormatId, ff.FormatCode, ff.FormatName, ls.ProcessCode, ls.PackageName, ls.Description,
               ls.UnitPrice, ls.PriceUnit, ls.ScanQuality, ls.TurnaroundDays, ls.IsActive
        FROM lab.LabServices ls
        JOIN lab.FilmLabs     l  ON l.LabId = ls.LabId
        JOIN lab.ServiceTypes st ON st.ServiceTypeId = ls.ServiceTypeId
        JOIN lab.FilmFormats  ff ON ff.FormatId = ls.FormatId
        WHERE l.OwnerUserId = @OwnerUserId AND l.IsDeleted = 0 AND ls.IsDeleted = 0
        ORDER BY ls.LabId, st.Category, ls.PackageName;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO

-- ===== Đợt 8a-2: đường đọc cho web =====
CREATE OR ALTER PROCEDURE lab.sp_GetReferenceData
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        -- Result set 1: khổ phim
        SELECT FormatId, FormatCode, FormatName
        FROM lab.FilmFormats
        ORDER BY FormatId;

        -- Result set 2: loại dịch vụ
        SELECT ServiceTypeId, ServiceCode, ServiceName, Category, Description
        FROM lab.ServiceTypes
        ORDER BY Category, ServiceTypeId;

        -- Result set 3: các stage xử lý đơn (theo thứ tự)
        SELECT StageId, StageCode, StageName, SortOrder, IsTerminal
        FROM ord.ProcessingStages
        ORDER BY SortOrder;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE lab.sp_ListLabsForApproval
    @AdminUserId INT,
    @Status      NVARCHAR(12) = N'Pending',   -- NULL = mọi trạng thái
    @PageNo      INT          = 1,
    @PageSize    INT          = 20
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM iam.UserRoles ur JOIN iam.Roles r ON r.RoleId = ur.RoleId
                       WHERE ur.UserId = @AdminUserId AND r.RoleCode = N'Admin')
            THROW 50203, N'Chỉ Admin được xem danh sách lab chờ duyệt.', 1;
        IF @Status IS NOT NULL AND @Status NOT IN (N'Pending', N'Approved', N'Rejected', N'Suspended')
            THROW 50205, N'Trạng thái duyệt không hợp lệ.', 1;
        IF @PageNo IS NULL OR @PageNo < 1 OR @PageSize IS NULL OR @PageSize < 1 OR @PageSize > 100
            THROW 50205, N'PageNo phải từ 1, PageSize phải từ 1 đến 100.', 1;

        SELECT l.LabId, l.LabName, l.OwnerUserId, u.FullName AS OwnerName, u.Email AS OwnerEmail,
               l.AddressLine, l.Ward, l.District, l.City, l.Phone, l.ApprovalStatus,
               (SELECT COUNT(*) FROM lab.LabServices s WHERE s.LabId = l.LabId AND s.IsDeleted = 0) AS ServiceCount,
               l.CreatedAt,
               a.Decision AS LastDecision, a.Reason AS LastDecisionReason, a.DecidedAt AS LastDecidedAt,
               COUNT(*) OVER () AS TotalRows
        FROM lab.FilmLabs l
        JOIN iam.Users u ON u.UserId = l.OwnerUserId
        OUTER APPLY (SELECT TOP 1 x.Decision, x.Reason, x.DecidedAt
                     FROM lab.LabApprovals x
                     WHERE x.LabId = l.LabId
                     ORDER BY x.DecidedAt DESC, x.ApprovalId DESC) a
        WHERE l.IsDeleted = 0
          AND (@Status IS NULL OR l.ApprovalStatus = @Status)
        ORDER BY l.CreatedAt, l.LabId          -- hàng chờ: lab nộp trước xử lý trước
        OFFSET (@PageNo - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO