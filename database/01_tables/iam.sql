/* ============================================================
   File    : database/01_tables/iam.sql
   Module  : iam - M1 Identity & Access
   Purpose : Tables của M1 Identity & Access. Thứ tự CREATE TABLE: Users -> Roles -> UserRoles -> Addresses -> ExpertProfiles -> DeliveryPartners.
             Gồm PK, CHECK, UNIQUE, DEFAULT và FK TRONG CÙNG schema: FK_UserRoles_Users_UserId, FK_UserRoles_Roles, FK_UserRoles_Users_AssignedBy, FK_Addresses_Users, FK_ExpertProfiles_Users_UserId, FK_ExpertProfiles_Users_VerifiedBy, FK_DeliveryPartners_Users.
   Owner   : A (xem docs/Phan-cong.md)
   Depends : (gốc)
   Re-run  : Chạy lại bằng REBUILD=1 (DB tạo mới). Không DROP TABLE thủ công.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;  -- bắt buộc cho filtered index, spatial index, computed column
SET ANSI_NULLS ON;
GO

-- Tài khoản người dùng (khách, chủ lab, expert, shipper, admin)
CREATE TABLE iam.Users
(
    UserId               INT IDENTITY(1,1) NOT NULL
                           CONSTRAINT PK_Users PRIMARY KEY,
    Email                NVARCHAR(255) NOT NULL
                           CONSTRAINT CK_Users_Email CHECK (Email LIKE '%_@_%._%'),
    AuthProvider         NVARCHAR(20) NOT NULL
                           CONSTRAINT DF_Users_AuthProvider DEFAULT 'Local'
                           CONSTRAINT CK_Users_AuthProvider CHECK (AuthProvider IN ('Local','Google','Facebook')),
    PasswordHash         NVARCHAR(255) NULL,
    FullName             NVARCHAR(100) NOT NULL,
    Phone                NVARCHAR(20) NULL
                           CONSTRAINT CK_Users_Phone CHECK (Phone NOT LIKE '%[^0-9+]%' AND LEN(Phone) BETWEEN 9 AND 15),
    AvatarUrl            NVARCHAR(500) NULL,
    IsActive             BIT NOT NULL
                           CONSTRAINT DF_Users_IsActive DEFAULT 1,
    LastLoginAt          DATETIME2(0) NULL,
    CreatedAt            DATETIME2(0) NOT NULL
                           CONSTRAINT DF_Users_CreatedAt DEFAULT SYSUTCDATETIME(),
    UpdatedAt            DATETIME2(0) NULL,
    IsDeleted            BIT NOT NULL
                           CONSTRAINT DF_Users_IsDeleted DEFAULT 0,
    CONSTRAINT CK_Users_AuthProvider_PasswordHash CHECK (AuthProvider <> 'Local' OR PasswordHash IS NOT NULL)
);
GO

-- Danh mục vai trò hệ thống
CREATE TABLE iam.Roles
(
    RoleId               INT NOT NULL
                           CONSTRAINT PK_Roles PRIMARY KEY,
    RoleCode             NVARCHAR(30) NOT NULL
                           CONSTRAINT UQ_Roles_RoleCode UNIQUE,
    RoleName             NVARCHAR(100) NOT NULL,
    Description          NVARCHAR(255) NULL
);
GO

-- Gán vai trò cho người dùng (N-N Users-Roles)
CREATE TABLE iam.UserRoles
(
    UserId               INT NOT NULL,
    RoleId               INT NOT NULL,
    AssignedAt           DATETIME2(0) NOT NULL
                           CONSTRAINT DF_UserRoles_AssignedAt DEFAULT SYSUTCDATETIME(),
    AssignedBy           INT NULL,
    CONSTRAINT PK_UserRoles PRIMARY KEY (UserId, RoleId),
    CONSTRAINT FK_UserRoles_Users_UserId FOREIGN KEY (UserId) REFERENCES iam.Users(UserId),
    CONSTRAINT FK_UserRoles_Roles FOREIGN KEY (RoleId) REFERENCES iam.Roles(RoleId),
    CONSTRAINT FK_UserRoles_Users_AssignedBy FOREIGN KEY (AssignedBy) REFERENCES iam.Users(UserId)
);
GO

-- Địa chỉ của người dùng (nhận/trả phim)
CREATE TABLE iam.Addresses
(
    AddressId            INT IDENTITY(1,1) NOT NULL
                           CONSTRAINT PK_Addresses PRIMARY KEY,
    UserId               INT NOT NULL,
    Label                NVARCHAR(50) NULL,
    RecipientName        NVARCHAR(100) NOT NULL,
    Phone                NVARCHAR(20) NOT NULL,
    Line1                NVARCHAR(255) NOT NULL,
    Ward                 NVARCHAR(100) NOT NULL,
    District             NVARCHAR(100) NOT NULL,
    City                 NVARCHAR(100) NOT NULL,
    Location             geography NULL,
    IsDefault            BIT NOT NULL
                           CONSTRAINT DF_Addresses_IsDefault DEFAULT 0,
    CreatedAt            DATETIME2(0) NOT NULL
                           CONSTRAINT DF_Addresses_CreatedAt DEFAULT SYSUTCDATETIME(),
    UpdatedAt            DATETIME2(0) NULL,
    IsDeleted            BIT NOT NULL
                           CONSTRAINT DF_Addresses_IsDeleted DEFAULT 0,
    CONSTRAINT FK_Addresses_Users FOREIGN KEY (UserId) REFERENCES iam.Users(UserId)
);
GO

-- Hồ sơ chuyên gia nhiếp ảnh (1-1 với Users)
CREATE TABLE iam.ExpertProfiles
(
    UserId               INT NOT NULL
                           CONSTRAINT PK_ExpertProfiles PRIMARY KEY,
    Bio                  NVARCHAR(1000) NULL,
    Expertise            NVARCHAR(255) NULL,
    YearsExperience      SMALLINT NULL
                           CONSTRAINT CK_ExpertProfiles_YearsExperience CHECK (YearsExperience >= 0),
    PortfolioUrl         NVARCHAR(500) NULL,
    IsVerified           BIT NOT NULL
                           CONSTRAINT DF_ExpertProfiles_IsVerified DEFAULT 0,
    VerifiedBy           INT NULL,
    VerifiedAt           DATETIME2(0) NULL,
    CreatedAt            DATETIME2(0) NOT NULL
                           CONSTRAINT DF_ExpertProfiles_CreatedAt DEFAULT SYSUTCDATETIME(),
    UpdatedAt            DATETIME2(0) NULL,
    CONSTRAINT FK_ExpertProfiles_Users_UserId FOREIGN KEY (UserId) REFERENCES iam.Users(UserId),
    CONSTRAINT FK_ExpertProfiles_Users_VerifiedBy FOREIGN KEY (VerifiedBy) REFERENCES iam.Users(UserId)
);
GO

-- Đối tác giao nhận (nền tảng như Ahamove/Lalamove hoặc shipper cá nhân)
CREATE TABLE iam.DeliveryPartners
(
    DeliveryPartnerId    INT IDENTITY(1,1) NOT NULL
                           CONSTRAINT PK_DeliveryPartners PRIMARY KEY,
    ProviderType         NVARCHAR(12) NOT NULL
                           CONSTRAINT CK_DeliveryPartners_ProviderType CHECK (ProviderType IN ('Platform','Individual')),
    PartnerName          NVARCHAR(100) NOT NULL,
    UserId               INT NULL,
    VehicleType          NVARCHAR(30) NULL,
    PlateNumber          NVARCHAR(20) NULL,
    ApiCode              NVARCHAR(50) NULL,
    IsActive             BIT NOT NULL
                           CONSTRAINT DF_DeliveryPartners_IsActive DEFAULT 1,
    CreatedAt            DATETIME2(0) NOT NULL
                           CONSTRAINT DF_DeliveryPartners_CreatedAt DEFAULT SYSUTCDATETIME(),
    UpdatedAt            DATETIME2(0) NULL,
    IsDeleted            BIT NOT NULL
                           CONSTRAINT DF_DeliveryPartners_IsDeleted DEFAULT 0,
    CONSTRAINT CK_DeliveryPartners_ProviderType_UserId CHECK (ProviderType = 'Platform' OR UserId IS NOT NULL),
    CONSTRAINT FK_DeliveryPartners_Users FOREIGN KEY (UserId) REFERENCES iam.Users(UserId)
);
GO
