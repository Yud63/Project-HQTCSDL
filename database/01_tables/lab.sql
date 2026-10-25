/* ============================================================
   File    : database/01_tables/lab.sql
   Module  : lab - M2 Lab & Catalog
   Purpose : Tables của M2 Lab & Catalog. Thứ tự CREATE TABLE: FilmLabs -> FilmFormats -> FilmStocks -> ServiceTypes -> LabApprovals -> LabServices.
             Gồm PK, CHECK, UNIQUE, DEFAULT và FK TRONG CÙNG schema: FK_LabApprovals_FilmLabs, FK_LabServices_FilmLabs, FK_LabServices_ServiceTypes, FK_LabServices_FilmFormats.
   Owner   : B (xem docs/Phan-cong.md)
   Depends : iam
   Re-run  : Chạy lại bằng REBUILD=1 (DB tạo mới). Không DROP TABLE thủ công.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;  -- bắt buộc cho filtered index, spatial index, computed column
SET ANSI_NULLS ON;
GO

-- Hồ sơ Film Lab (MiniLab)
CREATE TABLE lab.FilmLabs
(
    LabId                INT IDENTITY(1,1) NOT NULL
                           CONSTRAINT PK_FilmLabs PRIMARY KEY,
    OwnerUserId          INT NOT NULL,
    LabName              NVARCHAR(150) NOT NULL,
    Description          NVARCHAR(1000) NULL,
    AddressLine          NVARCHAR(255) NOT NULL,
    Ward                 NVARCHAR(100) NOT NULL,
    District             NVARCHAR(100) NOT NULL,
    City                 NVARCHAR(100) NOT NULL,
    Location             geography NULL,
    Phone                NVARCHAR(20) NULL,
    Email                NVARCHAR(255) NULL,
    OpenHoursJson        NVARCHAR(MAX) NULL
                           CONSTRAINT CK_FilmLabs_OpenHoursJson CHECK (ISJSON(OpenHoursJson) = 1),
    SpecialTechniques    NVARCHAR(MAX) NULL
                           CONSTRAINT CK_FilmLabs_SpecialTechniques CHECK (ISJSON(SpecialTechniques) = 1),
    DailyCapacityRolls   SMALLINT NOT NULL
                           CONSTRAINT DF_FilmLabs_DailyCapacityRolls DEFAULT 50
                           CONSTRAINT CK_FilmLabs_DailyCapacityRolls CHECK (DailyCapacityRolls > 0),
    ApprovalStatus       NVARCHAR(12) NOT NULL
                           CONSTRAINT DF_FilmLabs_ApprovalStatus DEFAULT 'Pending'
                           CONSTRAINT CK_FilmLabs_ApprovalStatus CHECK (ApprovalStatus IN ('Pending','Approved','Rejected','Suspended')),
    AvgRating            DECIMAL(3,2) NOT NULL
                           CONSTRAINT DF_FilmLabs_AvgRating DEFAULT 0
                           CONSTRAINT CK_FilmLabs_AvgRating CHECK (AvgRating BETWEEN 0 AND 5),
    ReviewCount          INT NOT NULL
                           CONSTRAINT DF_FilmLabs_ReviewCount DEFAULT 0
                           CONSTRAINT CK_FilmLabs_ReviewCount CHECK (ReviewCount >= 0),
    CreatedAt            DATETIME2(0) NOT NULL
                           CONSTRAINT DF_FilmLabs_CreatedAt DEFAULT SYSUTCDATETIME(),
    UpdatedAt            DATETIME2(0) NULL,
    IsDeleted            BIT NOT NULL
                           CONSTRAINT DF_FilmLabs_IsDeleted DEFAULT 0
);
GO

-- Danh mục định dạng phim (35mm, 120...)
CREATE TABLE lab.FilmFormats
(
    FormatId             INT NOT NULL
                           CONSTRAINT PK_FilmFormats PRIMARY KEY,
    FormatCode           NVARCHAR(20) NOT NULL
                           CONSTRAINT UQ_FilmFormats_FormatCode UNIQUE,
    FormatName           NVARCHAR(100) NOT NULL
);
GO

-- Danh mục loại phim (Portra 400, HP5...)
CREATE TABLE lab.FilmStocks
(
    StockId              INT NOT NULL
                           CONSTRAINT PK_FilmStocks PRIMARY KEY,
    Brand                NVARCHAR(50) NOT NULL,
    StockName            NVARCHAR(100) NOT NULL,
    Iso                  SMALLINT NOT NULL
                           CONSTRAINT CK_FilmStocks_Iso CHECK (Iso > 0),
    FilmType             NVARCHAR(15) NOT NULL
                           CONSTRAINT CK_FilmStocks_FilmType CHECK (FilmType IN ('ColorNegative','BlackWhite','ColorSlide')),
    ProcessCode          NVARCHAR(10) NOT NULL
                           CONSTRAINT CK_FilmStocks_ProcessCode CHECK (ProcessCode IN ('C-41','E-6','BW','ECN-2')),
    IsActive             BIT NOT NULL
                           CONSTRAINT DF_FilmStocks_IsActive DEFAULT 1,
    CONSTRAINT UQ_FilmStocks_Brand_StockName UNIQUE (Brand, StockName)
);
GO

-- Danh mục loại dịch vụ (tráng, scan, in, phụ trợ)
CREATE TABLE lab.ServiceTypes
(
    ServiceTypeId        INT NOT NULL
                           CONSTRAINT PK_ServiceTypes PRIMARY KEY,
    ServiceCode          NVARCHAR(20) NOT NULL
                           CONSTRAINT UQ_ServiceTypes_ServiceCode UNIQUE,
    ServiceName          NVARCHAR(100) NOT NULL,
    Category             NVARCHAR(10) NOT NULL
                           CONSTRAINT CK_ServiceTypes_Category CHECK (Category IN ('Develop','Scan','Print','Other')),
    Description          NVARCHAR(255) NULL
);
GO

-- Lịch sử duyệt/từ chối/đình chỉ lab của Admin (chỉ thêm)
CREATE TABLE lab.LabApprovals
(
    ApprovalId           INT IDENTITY(1,1) NOT NULL
                           CONSTRAINT PK_LabApprovals PRIMARY KEY,
    LabId                INT NOT NULL,
    ReviewedBy           INT NOT NULL,
    Decision             NVARCHAR(12) NOT NULL
                           CONSTRAINT CK_LabApprovals_Decision CHECK (Decision IN ('Approved','Rejected','Suspended')),
    Reason               NVARCHAR(500) NULL,
    DecidedAt            DATETIME2(0) NOT NULL
                           CONSTRAINT DF_LabApprovals_DecidedAt DEFAULT SYSUTCDATETIME(),
    CONSTRAINT CK_LabApprovals_Decision_Reason CHECK (Decision = 'Approved' OR Reason IS NOT NULL),
    CONSTRAINT FK_LabApprovals_FilmLabs FOREIGN KEY (LabId) REFERENCES lab.FilmLabs(LabId)
);
GO

-- Gói dịch vụ và giá của từng lab (Temporal Table lưu lịch sử đổi giá)
CREATE TABLE lab.LabServices
(
    LabServiceId         INT IDENTITY(1,1) NOT NULL
                           CONSTRAINT PK_LabServices PRIMARY KEY,
    LabId                INT NOT NULL,
    ServiceTypeId        INT NOT NULL,
    FormatId             INT NOT NULL,
    ProcessCode          NVARCHAR(10) NOT NULL
                           CONSTRAINT DF_LabServices_ProcessCode DEFAULT 'ANY'
                           CONSTRAINT CK_LabServices_ProcessCode CHECK (ProcessCode IN ('C-41','E-6','BW','ECN-2','ANY')),
    PackageName          NVARCHAR(150) NOT NULL,
    Description          NVARCHAR(500) NULL,
    UnitPrice            DECIMAL(18,0) NOT NULL
                           CONSTRAINT CK_LabServices_UnitPrice CHECK (UnitPrice >= 0),
    PriceUnit            NVARCHAR(5) NOT NULL
                           CONSTRAINT DF_LabServices_PriceUnit DEFAULT 'Roll'
                           CONSTRAINT CK_LabServices_PriceUnit CHECK (PriceUnit IN ('Roll','Frame')),
    ScanQuality          NVARCHAR(5) NULL
                           CONSTRAINT CK_LabServices_ScanQuality CHECK (ScanQuality IN ('Basic','High','Ultra')),
    TurnaroundDays       TINYINT NOT NULL
                           CONSTRAINT CK_LabServices_TurnaroundDays CHECK (TurnaroundDays BETWEEN 1 AND 60),
    IsActive             BIT NOT NULL
                           CONSTRAINT DF_LabServices_IsActive DEFAULT 1,
    CreatedAt            DATETIME2(0) NOT NULL
                           CONSTRAINT DF_LabServices_CreatedAt DEFAULT SYSUTCDATETIME(),
    UpdatedAt            DATETIME2(0) NULL,
    IsDeleted            BIT NOT NULL
                           CONSTRAINT DF_LabServices_IsDeleted DEFAULT 0,
    ValidFrom            DATETIME2(0) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    ValidTo              DATETIME2(0) GENERATED ALWAYS AS ROW END HIDDEN NOT NULL,
    CONSTRAINT UQ_LabServices_LabId_PackageName UNIQUE (LabId, PackageName),
    CONSTRAINT FK_LabServices_FilmLabs FOREIGN KEY (LabId) REFERENCES lab.FilmLabs(LabId),
    CONSTRAINT FK_LabServices_ServiceTypes FOREIGN KEY (ServiceTypeId) REFERENCES lab.ServiceTypes(ServiceTypeId),
    CONSTRAINT FK_LabServices_FilmFormats FOREIGN KEY (FormatId) REFERENCES lab.FilmFormats(FormatId),
    PERIOD FOR SYSTEM_TIME (ValidFrom, ValidTo)
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = lab.LabServicesHistory));
GO
