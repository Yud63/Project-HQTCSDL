/* TEMPLATE bảng - copy vào database/01_tables/<module>.sql rồi đổi tên.
   Mọi bảng chính có 3 cột chuẩn: CreatedAt, UpdatedAt, IsDeleted. */
CREATE TABLE ord.Orders
(
    OrderId     INT IDENTITY(1,1)  NOT NULL
                CONSTRAINT PK_Orders PRIMARY KEY,
    CustomerId  INT                NOT NULL,                 -- FK liên module -> tạo ở 02_foreign_keys
    LabId       INT                NOT NULL,                 -- FK liên module -> tạo ở 02_foreign_keys
    StageId     INT                NOT NULL,                 -- FK trong module (tới ProcessingStages)
    TotalAmount DECIMAL(18,0)      NOT NULL
                CONSTRAINT CK_Orders_TotalAmount CHECK (TotalAmount >= 0),
    Note        NVARCHAR(500)      NULL,
    -- cột chuẩn
    CreatedAt   DATETIME2(0)       NOT NULL
                CONSTRAINT DF_Orders_CreatedAt DEFAULT SYSUTCDATETIME(),
    UpdatedAt   DATETIME2(0)       NULL,
    IsDeleted   BIT                NOT NULL
                CONSTRAINT DF_Orders_IsDeleted DEFAULT 0
);
GO
