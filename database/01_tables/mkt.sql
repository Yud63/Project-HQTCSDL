/* ============================================================
   File    : database/01_tables/mkt.sql
   Module  : mkt - M7 Marketplace
   Purpose : Tables của M7 Marketplace. Thứ tự CREATE TABLE: ListingCategories -> Listings -> ListingImages -> MarketTransactions -> Messages.
             Gồm PK, CHECK, UNIQUE, DEFAULT và FK TRONG CÙNG schema: FK_Listings_ListingCategories, FK_ListingImages_Listings, FK_Messages_Listings, FK_MarketTransactions_Listings.
   Owner   : D (xem docs/Phan-cong.md)
   Depends : iam
   Re-run  : Chạy lại bằng REBUILD=1 (DB tạo mới). Không DROP TABLE thủ công.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;  -- bắt buộc cho filtered index, spatial index, computed column
SET ANSI_NULLS ON;
GO

-- Danh mục loại hàng Marketplace
CREATE TABLE mkt.ListingCategories
(
    CategoryId           INT NOT NULL
                           CONSTRAINT PK_ListingCategories PRIMARY KEY,
    CategoryCode         NVARCHAR(20) NOT NULL
                           CONSTRAINT UQ_ListingCategories_CategoryCode UNIQUE,
    CategoryName         NVARCHAR(100) NOT NULL,
    IsActive             BIT NOT NULL
                           CONSTRAINT DF_ListingCategories_IsActive DEFAULT 1
);
GO

-- Tin đăng mua, bán, trao đổi thiết bị
CREATE TABLE mkt.Listings
(
    ListingId            INT IDENTITY(1,1) NOT NULL
                           CONSTRAINT PK_Listings PRIMARY KEY,
    SellerId             INT NOT NULL,
    CategoryId           INT NOT NULL,
    ListingType          NVARCHAR(8) NOT NULL
                           CONSTRAINT CK_Listings_ListingType CHECK (ListingType IN ('Sell','Exchange','Wanted')),
    Title                NVARCHAR(200) NOT NULL,
    Description          NVARCHAR(2000) NULL,
    Brand                NVARCHAR(50) NULL,
    Model                NVARCHAR(100) NULL,
    Condition            NVARCHAR(10) NULL
                           CONSTRAINT CK_Listings_Condition CHECK (Condition IN ('New','LikeNew','Good','Fair','ForParts')),
    Price                DECIMAL(18,0) NULL
                           CONSTRAINT CK_Listings_Price CHECK (Price >= 0),
    ExchangeWanted       NVARCHAR(255) NULL,
    Quantity             INT NOT NULL
                           CONSTRAINT DF_Listings_Quantity DEFAULT 1
                           CONSTRAINT CK_Listings_Quantity CHECK (Quantity >= 0),
    City                 NVARCHAR(100) NOT NULL,
    Status               NVARCHAR(8) NOT NULL
                           CONSTRAINT DF_Listings_Status DEFAULT 'Active'
                           CONSTRAINT CK_Listings_Status CHECK (Status IN ('Active','Reserved','Sold','Closed','Removed')),
    ExpiresAt            DATETIME2(0) NOT NULL
                           CONSTRAINT DF_Listings_ExpiresAt DEFAULT DATEADD(DAY, 30, SYSUTCDATETIME()),
    ModerationReason     NVARCHAR(255) NULL,
    ModeratedBy          INT NULL,
    CreatedAt            DATETIME2(0) NOT NULL
                           CONSTRAINT DF_Listings_CreatedAt DEFAULT SYSUTCDATETIME(),
    UpdatedAt            DATETIME2(0) NULL,
    IsDeleted            BIT NOT NULL
                           CONSTRAINT DF_Listings_IsDeleted DEFAULT 0,
    CONSTRAINT CK_Listings_ListingType_Price CHECK (ListingType <> 'Sell' OR Price IS NOT NULL),
    CONSTRAINT CK_Listings_ListingType_ExchangeWanted CHECK (ListingType <> 'Exchange' OR ExchangeWanted IS NOT NULL),
    CONSTRAINT CK_Listings_ListingType_Condition CHECK (ListingType = 'Wanted' OR Condition IS NOT NULL),
    CONSTRAINT CK_Listings_Status_ModerationReason CHECK (Status <> 'Removed' OR ModerationReason IS NOT NULL),
    CONSTRAINT UQ_Listings_ListingId_SellerId UNIQUE (ListingId, SellerId),
    CONSTRAINT FK_Listings_ListingCategories FOREIGN KEY (CategoryId) REFERENCES mkt.ListingCategories(CategoryId)
);
GO

-- Ảnh của tin đăng (tối đa 8, đúng 1 ảnh chính)
CREATE TABLE mkt.ListingImages
(
    ImageId              INT IDENTITY(1,1) NOT NULL
                           CONSTRAINT PK_ListingImages PRIMARY KEY,
    ListingId            INT NOT NULL,
    ImageUrl             NVARCHAR(1000) NOT NULL,
    SortOrder            TINYINT NOT NULL
                           CONSTRAINT DF_ListingImages_SortOrder DEFAULT 0,
    IsPrimary            BIT NOT NULL
                           CONSTRAINT DF_ListingImages_IsPrimary DEFAULT 0,
    CreatedAt            DATETIME2(0) NOT NULL
                           CONSTRAINT DF_ListingImages_CreatedAt DEFAULT SYSUTCDATETIME(),
    CONSTRAINT FK_ListingImages_Listings FOREIGN KEY (ListingId) REFERENCES mkt.Listings(ListingId)
);
GO

-- Giao dịch mua bán/trao đổi và đánh giá người bán
CREATE TABLE mkt.MarketTransactions
(
    TransactionId        INT IDENTITY(1,1) NOT NULL
                           CONSTRAINT PK_MarketTransactions PRIMARY KEY,
    TransactionCode      NVARCHAR(20) NOT NULL
                           CONSTRAINT UQ_MarketTransactions_TransactionCode UNIQUE,
    ListingId            INT NOT NULL,
    SellerId             INT NOT NULL,
    BuyerId              INT NOT NULL,
    Quantity             INT NOT NULL
                           CONSTRAINT CK_MarketTransactions_Quantity CHECK (Quantity > 0),
    UnitPrice            DECIMAL(18,0) NOT NULL
                           CONSTRAINT DF_MarketTransactions_UnitPrice DEFAULT 0
                           CONSTRAINT CK_MarketTransactions_UnitPrice CHECK (UnitPrice >= 0),
    TotalAmount          AS (CAST(Quantity * UnitPrice AS DECIMAL(18,0))) PERSISTED NOT NULL,
    PlatformFee          DECIMAL(18,0) NOT NULL
                           CONSTRAINT DF_MarketTransactions_PlatformFee DEFAULT 0
                           CONSTRAINT CK_MarketTransactions_PlatformFee CHECK (PlatformFee >= 0),
    Status               NVARCHAR(9) NOT NULL
                           CONSTRAINT DF_MarketTransactions_Status DEFAULT 'Pending'
                           CONSTRAINT CK_MarketTransactions_Status CHECK (Status IN ('Pending','Confirmed','Shipped','Completed','Cancelled','Disputed')),
    Note                 NVARCHAR(500) NULL,
    ConfirmedAt          DATETIME2(0) NULL,
    ShippedAt            DATETIME2(0) NULL,
    CompletedAt          DATETIME2(0) NULL,
    CancelReason         NVARCHAR(255) NULL,
    DisputeReason        NVARCHAR(500) NULL,
    DisputedAt           DATETIME2(0) NULL,
    DisputeResolution    NVARCHAR(500) NULL,
    ResolvedBy           INT NULL,
    ResolvedAt           DATETIME2(0) NULL,
    BuyerRating          TINYINT NULL
                           CONSTRAINT CK_MarketTransactions_BuyerRating CHECK (BuyerRating BETWEEN 1 AND 5),
    BuyerComment         NVARCHAR(500) NULL,
    RatedAt              DATETIME2(0) NULL,
    CreatedAt            DATETIME2(0) NOT NULL
                           CONSTRAINT DF_MarketTransactions_CreatedAt DEFAULT SYSUTCDATETIME(),
    UpdatedAt            DATETIME2(0) NULL,
    CONSTRAINT CK_MarketTransactions_BuyerId_SellerId CHECK (BuyerId <> SellerId),
    CONSTRAINT CK_MarketTransactions_PlatformFee_TotalAmount CHECK (PlatformFee <= TotalAmount),
    CONSTRAINT CK_MarketTransactions_Status_CancelReason CHECK (Status <> 'Cancelled' OR CancelReason IS NOT NULL),
    CONSTRAINT CK_MarketTransactions_Status_DisputeReason CHECK (Status <> 'Disputed' OR DisputeReason IS NOT NULL),
    CONSTRAINT CK_MarketTransactions_BuyerRating_Status CHECK (BuyerRating IS NULL OR Status = 'Completed'),
    CONSTRAINT FK_MarketTransactions_Listings FOREIGN KEY (ListingId, SellerId) REFERENCES mkt.Listings(ListingId, SellerId)
);
GO

-- Tin nhắn giữa người mua và người bán về một tin đăng
CREATE TABLE mkt.Messages
(
    MessageId            INT IDENTITY(1,1) NOT NULL
                           CONSTRAINT PK_Messages PRIMARY KEY,
    ListingId            INT NOT NULL,
    SenderId             INT NOT NULL,
    ReceiverId           INT NOT NULL,
    Body                 NVARCHAR(1000) NOT NULL
                           CONSTRAINT CK_Messages_Body CHECK (LEN(Body) > 0),
    SentAt               DATETIME2(0) NOT NULL
                           CONSTRAINT DF_Messages_SentAt DEFAULT SYSUTCDATETIME(),
    ReadAt               DATETIME2(0) NULL,
    CONSTRAINT CK_Messages_SenderId_ReceiverId CHECK (SenderId <> ReceiverId),
    CONSTRAINT FK_Messages_Listings FOREIGN KEY (ListingId) REFERENCES mkt.Listings(ListingId)
);
GO
