/* ============================================================
   File    : database/01_tables/arc.sql
   Module  : arc - M5 Digital Archive
   Purpose : Tables của M5 Digital Archive. Thứ tự CREATE TABLE: ScanFiles -> Notifications -> PhotoMetadata -> Albums -> AlbumPhotos.
             Gồm PK, CHECK, UNIQUE, DEFAULT và FK TRONG CÙNG schema: FK_PhotoMetadata_ScanFiles, FK_Albums_ScanFiles, FK_AlbumPhotos_Albums, FK_AlbumPhotos_ScanFiles.
   Owner   : C (xem docs/Phan-cong.md)
   Depends : iam, lab, ord
   Re-run  : Chạy lại bằng REBUILD=1 (DB tạo mới). Không DROP TABLE thủ công.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;  -- bắt buộc cho filtered index, spatial index, computed column
SET ANSI_NULLS ON;
GO

-- File ảnh scan (chỉ lưu URL và metadata, không lưu nhị phân)
CREATE TABLE arc.ScanFiles
(
    ScanFileId           UNIQUEIDENTIFIER NOT NULL
                           CONSTRAINT DF_ScanFiles_ScanFileId DEFAULT NEWSEQUENTIALID()
                           CONSTRAINT PK_ScanFiles PRIMARY KEY,
    OrderId              INT NOT NULL,
    OrderItemId          INT NULL,
    OwnerUserId          INT NOT NULL,
    UploadedBy           INT NOT NULL,
    FrameNumber          SMALLINT NULL
                           CONSTRAINT CK_ScanFiles_FrameNumber CHECK (FrameNumber > 0),
    FileName             NVARCHAR(255) NOT NULL,
    StorageUrl           NVARCHAR(1000) NOT NULL,
    ContentType          NVARCHAR(20) NOT NULL
                           CONSTRAINT CK_ScanFiles_ContentType CHECK (ContentType IN ('image/jpeg','image/tiff','image/png')),
    FileSizeBytes        BIGINT NOT NULL
                           CONSTRAINT CK_ScanFiles_FileSizeBytes CHECK (FileSizeBytes BETWEEN 1 AND 209715200),
    WidthPx              INT NULL
                           CONSTRAINT CK_ScanFiles_WidthPx CHECK (WidthPx > 0),
    HeightPx             INT NULL
                           CONSTRAINT CK_ScanFiles_HeightPx CHECK (HeightPx > 0),
    ChecksumSha256       CHAR(64) NULL,
    QualityScore         DECIMAL(5,2) NULL
                           CONSTRAINT CK_ScanFiles_QualityScore CHECK (QualityScore BETWEEN 0 AND 100),
    QualityStatus        NVARCHAR(10) NOT NULL
                           CONSTRAINT DF_ScanFiles_QualityStatus DEFAULT 'NotChecked'
                           CONSTRAINT CK_ScanFiles_QualityStatus CHECK (QualityStatus IN ('NotChecked','Passed','Warning','Failed')),
    UploadedAt           DATETIME2(0) NOT NULL
                           CONSTRAINT DF_ScanFiles_UploadedAt DEFAULT SYSUTCDATETIME(),
    CreatedAt            DATETIME2(0) NOT NULL
                           CONSTRAINT DF_ScanFiles_CreatedAt DEFAULT SYSUTCDATETIME(),
    UpdatedAt            DATETIME2(0) NULL,
    IsDeleted            BIT NOT NULL
                           CONSTRAINT DF_ScanFiles_IsDeleted DEFAULT 0,
    CONSTRAINT UQ_ScanFiles_OrderId_FileName UNIQUE (OrderId, FileName),
    CONSTRAINT CK_ScanFiles_QualityStatus_QualityScore CHECK (QualityStatus = 'NotChecked' OR QualityScore IS NOT NULL)
);
GO

-- Thông báo cho người dùng (mọi module tạo qua arc.sp_CreateNotification)
CREATE TABLE arc.Notifications
(
    NotificationId       INT IDENTITY(1,1) NOT NULL
                           CONSTRAINT PK_Notifications PRIMARY KEY,
    UserId               INT NOT NULL,
    Type                 NVARCHAR(12) NOT NULL
                           CONSTRAINT CK_Notifications_Type CHECK (Type IN ('OrderStage','ScanReady','Delivery','Payment','Review','Complaint','Event','Market','System')),
    Title                NVARCHAR(150) NOT NULL,
    Body                 NVARCHAR(500) NULL,
    OrderId              INT NULL,
    IsRead               BIT NOT NULL
                           CONSTRAINT DF_Notifications_IsRead DEFAULT 0,
    ReadAt               DATETIME2(0) NULL,
    CreatedAt            DATETIME2(0) NOT NULL
                           CONSTRAINT DF_Notifications_CreatedAt DEFAULT SYSUTCDATETIME(),
    CONSTRAINT CK_Notifications_IsRead_ReadAt CHECK (IsRead = 0 OR ReadAt IS NOT NULL)
);
GO

-- Metadata của ảnh scan (1-1 với ScanFiles)
CREATE TABLE arc.PhotoMetadata
(
    ScanFileId           UNIQUEIDENTIFIER NOT NULL
                           CONSTRAINT PK_PhotoMetadata PRIMARY KEY,
    FilmStockId          INT NULL,
    CameraModel          NVARCHAR(100) NULL,
    LensModel            NVARCHAR(100) NULL,
    ShootingDate         DATE NULL
                           CONSTRAINT CK_PhotoMetadata_ShootingDate CHECK (ShootingDate <= CAST(SYSUTCDATETIME() AS DATE)),
    ExposedIso           SMALLINT NULL
                           CONSTRAINT CK_PhotoMetadata_ExposedIso CHECK (ExposedIso > 0),
    ProcessMethod        NVARCHAR(100) NULL,
    ScannerModel         NVARCHAR(100) NULL,
    ScanResolutionDpi    INT NULL
                           CONSTRAINT CK_PhotoMetadata_ScanResolutionDpi CHECK (ScanResolutionDpi > 0),
    ExtraJson            NVARCHAR(MAX) NULL
                           CONSTRAINT CK_PhotoMetadata_ExtraJson CHECK (ISJSON(ExtraJson) = 1),
    CreatedAt            DATETIME2(0) NOT NULL
                           CONSTRAINT DF_PhotoMetadata_CreatedAt DEFAULT SYSUTCDATETIME(),
    UpdatedAt            DATETIME2(0) NULL,
    CONSTRAINT FK_PhotoMetadata_ScanFiles FOREIGN KEY (ScanFileId) REFERENCES arc.ScanFiles(ScanFileId)
);
GO

-- Album do khách tự tổ chức trong Digital Film Archive
CREATE TABLE arc.Albums
(
    AlbumId              INT IDENTITY(1,1) NOT NULL
                           CONSTRAINT PK_Albums PRIMARY KEY,
    OwnerUserId          INT NOT NULL,
    Title                NVARCHAR(150) NOT NULL,
    Description          NVARCHAR(500) NULL,
    CoverScanFileId      UNIQUEIDENTIFIER NULL,
    IsPublic             BIT NOT NULL
                           CONSTRAINT DF_Albums_IsPublic DEFAULT 0,
    CreatedAt            DATETIME2(0) NOT NULL
                           CONSTRAINT DF_Albums_CreatedAt DEFAULT SYSUTCDATETIME(),
    UpdatedAt            DATETIME2(0) NULL,
    IsDeleted            BIT NOT NULL
                           CONSTRAINT DF_Albums_IsDeleted DEFAULT 0,
    CONSTRAINT FK_Albums_ScanFiles FOREIGN KEY (CoverScanFileId) REFERENCES arc.ScanFiles(ScanFileId)
);
GO

-- Ảnh trong album (N-N Albums-ScanFiles)
CREATE TABLE arc.AlbumPhotos
(
    AlbumId              INT NOT NULL,
    ScanFileId           UNIQUEIDENTIFIER NOT NULL,
    SortOrder            SMALLINT NOT NULL
                           CONSTRAINT DF_AlbumPhotos_SortOrder DEFAULT 0,
    AddedAt              DATETIME2(0) NOT NULL
                           CONSTRAINT DF_AlbumPhotos_AddedAt DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_AlbumPhotos PRIMARY KEY (AlbumId, ScanFileId),
    CONSTRAINT FK_AlbumPhotos_Albums FOREIGN KEY (AlbumId) REFERENCES arc.Albums(AlbumId),
    CONSTRAINT FK_AlbumPhotos_ScanFiles FOREIGN KEY (ScanFileId) REFERENCES arc.ScanFiles(ScanFileId)
);
GO
