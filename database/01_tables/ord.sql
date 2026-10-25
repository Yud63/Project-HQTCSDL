/* ============================================================
   File    : database/01_tables/ord.sql
   Module  : ord - M3 Order, Processing, Payment, Fee
   Purpose : Tables của M3 Order, Processing, Payment, Fee. Thứ tự CREATE TABLE: ProcessingStages -> FeeConfigs -> Orders -> OrderItems -> OrderStageLog -> Payments.
             Gồm PK, CHECK, UNIQUE, DEFAULT và FK TRONG CÙNG schema: FK_Orders_ProcessingStages, FK_OrderItems_Orders, FK_OrderStageLog_Orders, FK_OrderStageLog_ProcessingStages_FromStageId, FK_OrderStageLog_ProcessingStages_ToStageId, FK_Payments_Orders.
   Owner   : B (xem docs/Phan-cong.md)
   Depends : iam, lab
   Re-run  : Chạy lại bằng REBUILD=1 (DB tạo mới). Không DROP TABLE thủ công.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;  -- bắt buộc cho filtered index, spatial index, computed column
SET ANSI_NULLS ON;
GO

-- Danh mục giai đoạn xử lý đơn (13 giai đoạn)
CREATE TABLE ord.ProcessingStages
(
    StageId              INT NOT NULL
                           CONSTRAINT PK_ProcessingStages PRIMARY KEY,
    StageCode            NVARCHAR(20) NOT NULL
                           CONSTRAINT UQ_ProcessingStages_StageCode UNIQUE,
    StageName            NVARCHAR(100) NOT NULL,
    SortOrder            TINYINT NOT NULL
                           CONSTRAINT UQ_ProcessingStages_SortOrder UNIQUE,
    IsTerminal           BIT NOT NULL
                           CONSTRAINT DF_ProcessingStages_IsTerminal DEFAULT 0
);
GO

-- Cấu hình phí (hoa hồng, phí marketplace, phí giao)
CREATE TABLE ord.FeeConfigs
(
    FeeConfigId          INT IDENTITY(1,1) NOT NULL
                           CONSTRAINT PK_FeeConfigs PRIMARY KEY,
    FeeType              NVARCHAR(20) NOT NULL
                           CONSTRAINT CK_FeeConfigs_FeeType CHECK (FeeType IN ('PlatformCommission','MarketplaceFee','DeliveryBase')),
    Rate                 DECIMAL(5,4) NULL
                           CONSTRAINT CK_FeeConfigs_Rate CHECK (Rate BETWEEN 0 AND 1),
    FixedAmount          DECIMAL(18,0) NULL
                           CONSTRAINT CK_FeeConfigs_FixedAmount CHECK (FixedAmount >= 0),
    ScopeLabId           INT NULL,
    EffectiveFrom        DATE NOT NULL,
    EffectiveTo          DATE NULL,
    CreatedBy            INT NOT NULL,
    CreatedAt            DATETIME2(0) NOT NULL
                           CONSTRAINT DF_FeeConfigs_CreatedAt DEFAULT SYSUTCDATETIME(),
    CONSTRAINT CK_FeeConfigs_Rate_FixedAmount CHECK (Rate IS NOT NULL OR FixedAmount IS NOT NULL),
    CONSTRAINT CK_FeeConfigs_EffectiveTo_EffectiveFrom CHECK (EffectiveTo IS NULL OR EffectiveTo >= EffectiveFrom)
);
GO

-- Đơn dịch vụ tráng/scan/in phim
CREATE TABLE ord.Orders
(
    OrderId              INT IDENTITY(1,1) NOT NULL
                           CONSTRAINT PK_Orders PRIMARY KEY,
    OrderCode            NVARCHAR(20) NOT NULL
                           CONSTRAINT UQ_Orders_OrderCode UNIQUE,
    CustomerId           INT NOT NULL,
    LabId                INT NOT NULL,
    StageId              INT NOT NULL
                           CONSTRAINT DF_Orders_StageId DEFAULT 1,
    FulfillmentMethod    NVARCHAR(7) NOT NULL
                           CONSTRAINT CK_Orders_FulfillmentMethod CHECK (FulfillmentMethod IN ('DropOff','Pickup')),
    ReturnMethod         NVARCHAR(11) NOT NULL
                           CONSTRAINT CK_Orders_ReturnMethod CHECK (ReturnMethod IN ('SelfCollect','Delivery')),
    PickupAddressId      INT NULL,
    ReturnAddressId      INT NULL,
    Subtotal             DECIMAL(18,0) NOT NULL
                           CONSTRAINT CK_Orders_Subtotal CHECK (Subtotal >= 0),
    DeliveryFee          DECIMAL(18,0) NOT NULL
                           CONSTRAINT DF_Orders_DeliveryFee DEFAULT 0
                           CONSTRAINT CK_Orders_DeliveryFee CHECK (DeliveryFee >= 0),
    PlatformFee          DECIMAL(18,0) NOT NULL
                           CONSTRAINT DF_Orders_PlatformFee DEFAULT 0
                           CONSTRAINT CK_Orders_PlatformFee CHECK (PlatformFee >= 0),
    TotalAmount          DECIMAL(18,0) NOT NULL,
    PaymentStatus        NVARCHAR(9) NOT NULL
                           CONSTRAINT DF_Orders_PaymentStatus DEFAULT 'Unpaid'
                           CONSTRAINT CK_Orders_PaymentStatus CHECK (PaymentStatus IN ('Unpaid','Paid','Refunded')),
    CustomerNote         NVARCHAR(500) NULL,
    EstimatedReadyDate   DATE NULL,
    CompletedAt          DATETIME2(0) NULL,
    CancelReason         NVARCHAR(255) NULL,
    CreatedAt            DATETIME2(0) NOT NULL
                           CONSTRAINT DF_Orders_CreatedAt DEFAULT SYSUTCDATETIME(),
    UpdatedAt            DATETIME2(0) NULL,
    IsDeleted            BIT NOT NULL
                           CONSTRAINT DF_Orders_IsDeleted DEFAULT 0,
    CONSTRAINT CK_Orders_TotalAmount_Subtotal CHECK (TotalAmount = Subtotal + DeliveryFee),
    CONSTRAINT CK_Orders_FulfillmentMethod_PickupAddressId CHECK (FulfillmentMethod <> 'Pickup' OR PickupAddressId IS NOT NULL),
    CONSTRAINT CK_Orders_ReturnMethod_ReturnAddressId CHECK (ReturnMethod <> 'Delivery' OR ReturnAddressId IS NOT NULL),
    CONSTRAINT UQ_Orders_OrderId_CustomerId_LabId UNIQUE (OrderId, CustomerId, LabId),
    CONSTRAINT FK_Orders_ProcessingStages FOREIGN KEY (StageId) REFERENCES ord.ProcessingStages(StageId)
);
GO

-- Dòng dịch vụ trong đơn
CREATE TABLE ord.OrderItems
(
    OrderItemId          INT IDENTITY(1,1) NOT NULL
                           CONSTRAINT PK_OrderItems PRIMARY KEY,
    OrderId              INT NOT NULL,
    LabServiceId         INT NOT NULL,
    FilmStockId          INT NULL,
    Quantity             INT NOT NULL
                           CONSTRAINT CK_OrderItems_Quantity CHECK (Quantity > 0),
    UnitPriceSnapshot    DECIMAL(18,0) NOT NULL
                           CONSTRAINT CK_OrderItems_UnitPriceSnapshot CHECK (UnitPriceSnapshot >= 0),
    LineTotal            AS (CAST(Quantity * UnitPriceSnapshot AS DECIMAL(18,0))) PERSISTED NOT NULL,
    ProcessingNote       NVARCHAR(255) NULL,
    CreatedAt            DATETIME2(0) NOT NULL
                           CONSTRAINT DF_OrderItems_CreatedAt DEFAULT SYSUTCDATETIME(),
    CONSTRAINT FK_OrderItems_Orders FOREIGN KEY (OrderId) REFERENCES ord.Orders(OrderId)
);
GO

-- Nhật ký chuyển giai đoạn của đơn (bất biến, do trigger ghi)
CREATE TABLE ord.OrderStageLog
(
    LogId                INT IDENTITY(1,1) NOT NULL
                           CONSTRAINT PK_OrderStageLog PRIMARY KEY,
    OrderId              INT NOT NULL,
    FromStageId          INT NULL,
    ToStageId            INT NOT NULL,
    ChangedBy            INT NULL,
    Note                 NVARCHAR(255) NULL,
    ChangedAt            DATETIME2(0) NOT NULL
                           CONSTRAINT DF_OrderStageLog_ChangedAt DEFAULT SYSUTCDATETIME(),
    CONSTRAINT FK_OrderStageLog_Orders FOREIGN KEY (OrderId) REFERENCES ord.Orders(OrderId),
    CONSTRAINT FK_OrderStageLog_ProcessingStages_FromStageId FOREIGN KEY (FromStageId) REFERENCES ord.ProcessingStages(StageId),
    CONSTRAINT FK_OrderStageLog_ProcessingStages_ToStageId FOREIGN KEY (ToStageId) REFERENCES ord.ProcessingStages(StageId)
);
GO

-- Giao dịch thanh toán online của đơn
CREATE TABLE ord.Payments
(
    PaymentId            INT IDENTITY(1,1) NOT NULL
                           CONSTRAINT PK_Payments PRIMARY KEY,
    OrderId              INT NOT NULL,
    Method               NVARCHAR(12) NOT NULL
                           CONSTRAINT CK_Payments_Method CHECK (Method IN ('Card','EWallet','BankTransfer')),
    Provider             NVARCHAR(30) NULL,
    ProviderTxnId        NVARCHAR(100) NULL,
    Amount               DECIMAL(18,0) NOT NULL
                           CONSTRAINT CK_Payments_Amount CHECK (Amount > 0),
    Status               NVARCHAR(9) NOT NULL
                           CONSTRAINT DF_Payments_Status DEFAULT 'Pending'
                           CONSTRAINT CK_Payments_Status CHECK (Status IN ('Pending','Succeeded','Failed','Refunded')),
    PaidAt               DATETIME2(0) NULL,
    RefundedAt           DATETIME2(0) NULL,
    FailureReason        NVARCHAR(255) NULL,
    CreatedAt            DATETIME2(0) NOT NULL
                           CONSTRAINT DF_Payments_CreatedAt DEFAULT SYSUTCDATETIME(),
    CONSTRAINT FK_Payments_Orders FOREIGN KEY (OrderId) REFERENCES ord.Orders(OrderId)
);
GO
