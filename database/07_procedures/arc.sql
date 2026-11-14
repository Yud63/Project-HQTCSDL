/* ============================================================
   File    : database/07_procedures/arc.sql
   Module  : arc - M5 Digital Archive
   Purpose : Procedure của module arc (hiện có sp_CreateNotification)
   Owner   : C (xem docs/Phan-cong.md)
   Depends : arc.Notifications, iam.Users, ord.Orders
   Re-run  : CREATE OR ALTER, chạy lại được
   Ref     : docs/Conventions.md, docs/Contracts.md
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE arc.sp_CreateNotification
    @UserId            INT,
    @Type              NVARCHAR(12),
    @Title             NVARCHAR(150),
    @Body              NVARCHAR(500) = NULL,
    @OrderId           INT = NULL,
    @NewNotificationId INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        IF @Type NOT IN (N'OrderStage', N'ScanReady', N'Delivery', N'Payment', N'Review',
                         N'Complaint', N'Event', N'Market', N'System')
            THROW 50505, N'Loại thông báo không hợp lệ.', 1;
        IF NULLIF(LTRIM(RTRIM(@Title)), N'') IS NULL
            THROW 50505, N'Tiêu đề thông báo không được rỗng.', 1;
        IF NOT EXISTS (SELECT 1 FROM iam.Users WHERE UserId = @UserId AND IsDeleted = 0)
            THROW 50501, N'Người nhận thông báo không tồn tại.', 1;
        IF @OrderId IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM ord.Orders WHERE OrderId = @OrderId)
            THROW 50501, N'Đơn liên quan không tồn tại.', 1;

        INSERT INTO arc.Notifications (UserId, Type, Title, Body, OrderId)
        VALUES (@UserId, @Type, @Title, @Body, @OrderId);

        SET @NewNotificationId = SCOPE_IDENTITY();
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE arc.sp_UploadScan
    @OrderId         INT,
    @ActorUserId     INT,
    @FileName        NVARCHAR(255),
    @StorageUrl      NVARCHAR(1000),
    @ContentType     NVARCHAR(20),
    @FileSizeBytes   BIGINT,
    @FrameNumber     SMALLINT = NULL,
    @OrderItemId     INT = NULL,
    @WidthPx         INT = NULL,
    @HeightPx        INT = NULL,
    @ChecksumSha256  CHAR(64) = NULL,
    @MetadataJson    NVARCHAR(MAX) = NULL,
    @NewScanFileId   UNIQUEIDENTIFIER = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        DECLARE @CustomerId INT, @StageId INT, @LabOwnerId INT;
        DECLARE @FilmStockId INT, @ShootingDate DATE, @ExposedIso SMALLINT, @ScanDpi INT;
        DECLARE @CameraModel NVARCHAR(100), @LensModel NVARCHAR(100);
        DECLARE @ProcessMethod NVARCHAR(100), @ScannerModel NVARCHAR(100);
        DECLARE @ExtraJson NVARCHAR(MAX);
        DECLARE @Ids TABLE (ScanFileId UNIQUEIDENTIFIER);

        EXEC sp_set_session_context @key = N'UserId', @value = @ActorUserId;

        SELECT @CustomerId = o.CustomerId, @StageId = o.StageId, @LabOwnerId = l.OwnerUserId
        FROM ord.Orders o
        JOIN lab.FilmLabs l ON l.LabId = o.LabId
        WHERE o.OrderId = @OrderId AND o.IsDeleted = 0;
        IF @CustomerId IS NULL
            THROW 50501, N'Đơn không tồn tại.', 1;

        IF @ActorUserId <> @LabOwnerId
           AND NOT EXISTS (SELECT 1 FROM iam.UserRoles ur JOIN iam.Roles r ON r.RoleId = ur.RoleId
                           WHERE ur.UserId = @ActorUserId AND r.RoleCode = N'Admin')
            THROW 50503, N'Chỉ lab của đơn hoặc Admin mới được upload ảnh scan.', 1;

        IF NULLIF(LTRIM(RTRIM(@FileName)), N'') IS NULL OR NULLIF(LTRIM(RTRIM(@StorageUrl)), N'') IS NULL
            THROW 50505, N'Tên file và StorageUrl không được rỗng.', 1;
        IF @ContentType NOT IN (N'image/jpeg', N'image/tiff', N'image/png')
            THROW 50505, N'Loại file không hợp lệ (chỉ jpeg, tiff, png).', 1;
        IF @FileSizeBytes IS NULL OR @FileSizeBytes NOT BETWEEN 1 AND 209715200
            THROW 50505, N'Kích thước file phải từ 1 byte đến 200 MB.', 1;
        IF @FrameNumber IS NOT NULL AND @FrameNumber <= 0
            THROW 50505, N'Số khung phải lớn hơn 0.', 1;
        IF (@WidthPx IS NOT NULL AND @WidthPx <= 0) OR (@HeightPx IS NOT NULL AND @HeightPx <= 0)
            THROW 50505, N'Kích thước ảnh (px) phải lớn hơn 0.', 1;
        IF @ChecksumSha256 IS NOT NULL AND (LEN(@ChecksumSha256) <> 64 OR @ChecksumSha256 LIKE '%[^0-9A-Fa-f]%')
            THROW 50505, N'ChecksumSha256 phải gồm đúng 64 ký tự hex.', 1;
        IF @OrderItemId IS NOT NULL
           AND NOT EXISTS (SELECT 1
                           FROM ord.OrderItems oi
                           JOIN lab.LabServices ls ON ls.LabServiceId = oi.LabServiceId
                           JOIN lab.ServiceTypes st ON st.ServiceTypeId = ls.ServiceTypeId
                           WHERE oi.OrderItemId = @OrderItemId AND oi.OrderId = @OrderId AND st.Category = N'Scan')
            THROW 50505, N'Dòng đơn không thuộc đơn này hoặc không phải dịch vụ scan.', 1;

        IF @MetadataJson IS NOT NULL
        BEGIN
            IF ISJSON(@MetadataJson) <> 1 OR LEFT(LTRIM(@MetadataJson), 1) <> N'{'
                THROW 50505, N'MetadataJson phải là một đối tượng JSON hợp lệ.', 1;

            SET @FilmStockId = TRY_CAST(JSON_VALUE(@MetadataJson, N'$.filmStockId') AS INT);
            IF JSON_VALUE(@MetadataJson, N'$.filmStockId') IS NOT NULL
               AND (@FilmStockId IS NULL OR NOT EXISTS (SELECT 1 FROM lab.FilmStocks WHERE StockId = @FilmStockId))
                THROW 50505, N'filmStockId trong metadata không tồn tại.', 1;

            SET @ShootingDate = TRY_CAST(JSON_VALUE(@MetadataJson, N'$.shootingDate') AS DATE);
            IF JSON_VALUE(@MetadataJson, N'$.shootingDate') IS NOT NULL
               AND (@ShootingDate IS NULL OR @ShootingDate > CAST(SYSUTCDATETIME() AS DATE))
                THROW 50505, N'shootingDate không hợp lệ hoặc ở tương lai.', 1;

            SET @ExposedIso = TRY_CAST(JSON_VALUE(@MetadataJson, N'$.exposedIso') AS SMALLINT);
            IF JSON_VALUE(@MetadataJson, N'$.exposedIso') IS NOT NULL AND (@ExposedIso IS NULL OR @ExposedIso <= 0)
                THROW 50505, N'exposedIso phải là số dương.', 1;

            SET @ScanDpi = TRY_CAST(JSON_VALUE(@MetadataJson, N'$.scanResolutionDpi') AS INT);
            IF JSON_VALUE(@MetadataJson, N'$.scanResolutionDpi') IS NOT NULL AND (@ScanDpi IS NULL OR @ScanDpi <= 0)
                THROW 50505, N'scanResolutionDpi phải là số dương.', 1;

            SET @CameraModel   = LEFT(JSON_VALUE(@MetadataJson, N'$.cameraModel'), 100);
            SET @LensModel     = LEFT(JSON_VALUE(@MetadataJson, N'$.lensModel'), 100);
            SET @ProcessMethod = LEFT(JSON_VALUE(@MetadataJson, N'$.processMethod'), 100);
            SET @ScannerModel  = LEFT(JSON_VALUE(@MetadataJson, N'$.scannerModel'), 100);

            SET @ExtraJson = (
                SELECT N'{' + STRING_AGG(
                           CONCAT(N'"', STRING_ESCAPE(j.[key], N'json'), N'":',
                                  CASE j.[type]
                                      WHEN 0 THEN N'null'
                                      WHEN 1 THEN CONCAT(N'"', STRING_ESCAPE(j.[value], N'json'), N'"')
                                      ELSE j.[value]
                                  END), N',') + N'}'
                FROM OPENJSON(@MetadataJson) j
                WHERE j.[key] NOT IN (N'filmStockId', N'cameraModel', N'lensModel', N'shootingDate',
                                      N'exposedIso', N'processMethod', N'scannerModel', N'scanResolutionDpi'));
        END

        IF @FilmStockId IS NULL AND @OrderItemId IS NOT NULL
            SELECT @FilmStockId = FilmStockId FROM ord.OrderItems WHERE OrderItemId = @OrderItemId;

        IF @StageId NOT BETWEEN 8 AND 10
           OR NOT EXISTS (SELECT 1
                          FROM ord.OrderItems oi
                          JOIN lab.LabServices ls ON ls.LabServiceId = oi.LabServiceId
                          JOIN lab.ServiceTypes st ON st.ServiceTypeId = ls.ServiceTypeId
                          WHERE oi.OrderId = @OrderId AND st.Category = N'Scan')
            THROW 50502, N'Đơn không có dịch vụ scan hoặc chưa/đã qua giai đoạn scan.', 1;

        IF EXISTS (SELECT 1 FROM arc.ScanFiles WHERE OrderId = @OrderId AND FileName = @FileName)
            THROW 50504, N'Tên file đã tồn tại trong đơn.', 1;

        BEGIN TRAN;

        INSERT INTO arc.ScanFiles
            (OrderId, OrderItemId, OwnerUserId, UploadedBy, FrameNumber, FileName, StorageUrl,
             ContentType, FileSizeBytes, WidthPx, HeightPx, ChecksumSha256)
        OUTPUT inserted.ScanFileId INTO @Ids (ScanFileId)
        VALUES
            (@OrderId, @OrderItemId, @CustomerId, @ActorUserId, @FrameNumber, @FileName, @StorageUrl,
             @ContentType, @FileSizeBytes, @WidthPx, @HeightPx, @ChecksumSha256);

        SELECT @NewScanFileId = ScanFileId FROM @Ids;

        INSERT INTO arc.PhotoMetadata
            (ScanFileId, FilmStockId, CameraModel, LensModel, ShootingDate, ExposedIso,
             ProcessMethod, ScannerModel, ScanResolutionDpi, ExtraJson)
        VALUES
            (@NewScanFileId, @FilmStockId, @CameraModel, @LensModel, @ShootingDate, @ExposedIso,
             @ProcessMethod, @ScannerModel, @ScanDpi, @ExtraJson);

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE arc.sp_SetScanQuality
    @ScanFileId     UNIQUEIDENTIFIER,
    @ActorUserId    INT,
    @QualityScore   DECIMAL(5,2),
    @QualityStatus  NVARCHAR(10) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        DECLARE @LabOwnerId INT;

        EXEC sp_set_session_context @key = N'UserId', @value = @ActorUserId;

        SELECT @LabOwnerId = l.OwnerUserId
        FROM arc.ScanFiles s
        JOIN ord.Orders o ON o.OrderId = s.OrderId
        JOIN lab.FilmLabs l ON l.LabId = o.LabId
        WHERE s.ScanFileId = @ScanFileId AND s.IsDeleted = 0;
        IF @LabOwnerId IS NULL
            THROW 50501, N'File scan không tồn tại.', 1;

        IF @ActorUserId <> @LabOwnerId
           AND NOT EXISTS (SELECT 1 FROM iam.UserRoles ur JOIN iam.Roles r ON r.RoleId = ur.RoleId
                           WHERE ur.UserId = @ActorUserId AND r.RoleCode = N'Admin')
            THROW 50503, N'Chỉ lab của đơn hoặc Admin mới được ghi điểm chất lượng.', 1;

        IF @QualityScore IS NULL OR @QualityScore NOT BETWEEN 0 AND 100
            THROW 50505, N'Điểm chất lượng phải từ 0 đến 100.', 1;

        IF @QualityStatus IS NULL
            SET @QualityStatus = CASE WHEN @QualityScore >= 70 THEN N'Passed'
                                      WHEN @QualityScore >= 50 THEN N'Warning'
                                      ELSE N'Failed' END;
        ELSE IF @QualityStatus NOT IN (N'Passed', N'Warning', N'Failed')
            THROW 50505, N'Trạng thái chất lượng không hợp lệ.', 1;

        BEGIN TRAN;
        UPDATE arc.ScanFiles
        SET QualityScore = @QualityScore, QualityStatus = @QualityStatus, UpdatedAt = SYSUTCDATETIME()
        WHERE ScanFileId = @ScanFileId;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE arc.sp_MarkNotificationRead
    @NotificationId INT,
    @UserId         INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        DECLARE @Recipient INT;

        EXEC sp_set_session_context @key = N'UserId', @value = @UserId;

        SELECT @Recipient = UserId FROM arc.Notifications WHERE NotificationId = @NotificationId;
        IF @Recipient IS NULL
            THROW 50501, N'Thông báo không tồn tại.', 1;
        IF @Recipient <> @UserId
            THROW 50503, N'Thông báo không thuộc về bạn.', 1;

        BEGIN TRAN;
        UPDATE arc.Notifications
        SET IsRead = 1, ReadAt = SYSUTCDATETIME()
        WHERE NotificationId = @NotificationId AND IsRead = 0;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE arc.sp_SaveAlbum
    @OwnerUserId     INT,
    @Title           NVARCHAR(150),
    @AlbumId         INT              = NULL,   -- NULL: tạo album mới
    @Description     NVARCHAR(500)    = NULL,
    @IsPublic        BIT              = 0,
    @CoverScanFileId UNIQUEIDENTIFIER = NULL,
    @IsDeleted       BIT              = 0,
    @NewAlbumId      INT              = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        EXEC sp_set_session_context @key = N'UserId', @value = @OwnerUserId;

        IF NOT EXISTS (SELECT 1 FROM iam.Users WHERE UserId = @OwnerUserId AND IsActive = 1 AND IsDeleted = 0)
            THROW 50501, N'Người dùng không tồn tại hoặc đã bị khóa.', 1;

        BEGIN TRAN;

        DECLARE @CurOwner INT;
        IF @AlbumId IS NOT NULL
        BEGIN
            SELECT @CurOwner = OwnerUserId
            FROM arc.Albums WITH (UPDLOCK, HOLDLOCK)
            WHERE AlbumId = @AlbumId AND IsDeleted = 0;
            IF @CurOwner IS NULL
                THROW 50501, N'Album không tồn tại.', 1;
            IF @CurOwner <> @OwnerUserId
                THROW 50503, N'Album không thuộc về bạn.', 1;
        END;

        SET @Title = LTRIM(RTRIM(@Title));
        IF NULLIF(@Title, N'') IS NULL
            THROW 50505, N'Tên album không được rỗng.', 1;
        IF @IsPublic IS NULL OR @IsDeleted IS NULL
            THROW 50505, N'IsPublic và IsDeleted không được NULL.', 1;
        IF @CoverScanFileId IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM arc.ScanFiles WHERE ScanFileId = @CoverScanFileId AND OwnerUserId = @OwnerUserId)
            THROW 50505, N'Ảnh bìa phải là ảnh của bạn.', 1;

        IF @AlbumId IS NULL
        BEGIN
            INSERT INTO arc.Albums (OwnerUserId, Title, Description, CoverScanFileId, IsPublic, IsDeleted)
            VALUES (@OwnerUserId, @Title, @Description, @CoverScanFileId, @IsPublic, @IsDeleted);
            SET @NewAlbumId = SCOPE_IDENTITY();
        END
        ELSE
        BEGIN
            UPDATE arc.Albums
            SET Title = @Title, Description = @Description, CoverScanFileId = @CoverScanFileId,
                IsPublic = @IsPublic, IsDeleted = @IsDeleted, UpdatedAt = SYSUTCDATETIME()
            WHERE AlbumId = @AlbumId;
            SET @NewAlbumId = @AlbumId;
        END;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE arc.sp_SetAlbumPhoto
    @OwnerUserId INT,
    @AlbumId     INT,
    @ScanFileId  UNIQUEIDENTIFIER,
    @Action      NVARCHAR(6),        -- 'Add' | 'Remove'
    @SortOrder   SMALLINT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        EXEC sp_set_session_context @key = N'UserId', @value = @OwnerUserId;

        BEGIN TRAN;

        DECLARE @CurOwner INT;
        SELECT @CurOwner = OwnerUserId
        FROM arc.Albums WITH (UPDLOCK, HOLDLOCK)
        WHERE AlbumId = @AlbumId AND IsDeleted = 0;
        IF @CurOwner IS NULL
            THROW 50501, N'Album không tồn tại.', 1;
        IF @CurOwner <> @OwnerUserId
            THROW 50503, N'Album không thuộc về bạn.', 1;
        IF @Action IS NULL OR @Action NOT IN (N'Add', N'Remove')
            THROW 50505, N'Action phải là Add hoặc Remove.', 1;
        IF NOT EXISTS (SELECT 1 FROM arc.ScanFiles WHERE ScanFileId = @ScanFileId AND OwnerUserId = @OwnerUserId)
            THROW 50503, N'Ảnh không tồn tại hoặc không thuộc về bạn.', 1;

        IF @Action = N'Add'
        BEGIN
            IF EXISTS (SELECT 1 FROM arc.AlbumPhotos WHERE AlbumId = @AlbumId AND ScanFileId = @ScanFileId)
                UPDATE arc.AlbumPhotos SET SortOrder = ISNULL(@SortOrder, 0)
                WHERE AlbumId = @AlbumId AND ScanFileId = @ScanFileId;
            ELSE
                INSERT INTO arc.AlbumPhotos (AlbumId, ScanFileId, SortOrder)
                VALUES (@AlbumId, @ScanFileId, ISNULL(@SortOrder, 0));
        END
        ELSE
        BEGIN
            DELETE FROM arc.AlbumPhotos WHERE AlbumId = @AlbumId AND ScanFileId = @ScanFileId;
            UPDATE arc.Albums SET CoverScanFileId = NULL, UpdatedAt = SYSUTCDATETIME()
            WHERE AlbumId = @AlbumId AND CoverScanFileId = @ScanFileId;
        END;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE arc.sp_GetMyAlbums
    @UserId INT
AS
BEGIN
    SET NOCOUNT ON;
    EXEC sp_set_session_context @key = N'UserId', @value = @UserId;

    IF NOT EXISTS (SELECT 1 FROM iam.Users WHERE UserId = @UserId AND IsActive = 1 AND IsDeleted = 0)
        THROW 50501, N'Người dùng không tồn tại hoặc đã bị khóa.', 1;

    SELECT a.AlbumId, a.Title, a.Description, a.IsPublic, a.CoverScanFileId,
           cv.StorageUrl AS CoverStorageUrl, a.CreatedAt, a.UpdatedAt,
           (SELECT COUNT(*)
            FROM arc.AlbumPhotos ap
            JOIN arc.ScanFiles sf ON sf.ScanFileId = ap.ScanFileId AND sf.IsDeleted = 0
            WHERE ap.AlbumId = a.AlbumId) AS PhotoCount
    FROM arc.Albums a
    LEFT JOIN arc.ScanFiles cv ON cv.ScanFileId = a.CoverScanFileId AND cv.IsDeleted = 0
    WHERE a.OwnerUserId = @UserId AND a.IsDeleted = 0
    ORDER BY a.CreatedAt DESC;
END
GO

CREATE OR ALTER PROCEDURE arc.sp_GetAlbumPhotos
    @UserId  INT,
    @AlbumId INT
AS
BEGIN
    SET NOCOUNT ON;
    EXEC sp_set_session_context @key = N'UserId', @value = @UserId;

    IF NOT EXISTS (SELECT 1 FROM iam.Users WHERE UserId = @UserId AND IsActive = 1 AND IsDeleted = 0)
        THROW 50501, N'Người dùng không tồn tại hoặc đã bị khóa.', 1;

    DECLARE @Owner INT;
    SELECT @Owner = OwnerUserId FROM arc.Albums WHERE AlbumId = @AlbumId AND IsDeleted = 0;
    IF @Owner IS NULL
        THROW 50501, N'Album không tồn tại.', 1;
    IF @Owner <> @UserId
        THROW 50503, N'Album không thuộc về bạn.', 1;

    -- Result set 1: thông tin album
    SELECT AlbumId, Title, Description, IsPublic, CoverScanFileId, CreatedAt, UpdatedAt
    FROM arc.Albums WHERE AlbumId = @AlbumId;

    -- Result set 2: ảnh trong album
    SELECT sf.ScanFileId, sf.FileName, sf.StorageUrl, sf.ContentType, sf.FrameNumber,
           sf.WidthPx, sf.HeightPx, sf.QualityStatus, ap.SortOrder, ap.AddedAt
    FROM arc.AlbumPhotos ap
    JOIN arc.ScanFiles sf ON sf.ScanFileId = ap.ScanFileId AND sf.IsDeleted = 0
    WHERE ap.AlbumId = @AlbumId
    ORDER BY ap.SortOrder, ap.AddedAt;
END
GO