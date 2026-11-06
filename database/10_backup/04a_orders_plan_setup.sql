/* ============================================================
   Purpose : Bước 1/4 của demo Execution Plan trước/sau index thật
             IX_Orders_Customer (03_indexes/ord.sql). Dựng bảng sao
             dbo.OrdersPlan, 200.000 dòng, chưa có index nào ngoài PK.
             CHẠY TAY bằng sqlcmd, không đụng ord.Orders, không nằm
             trong 99_run_all.sql.
   ============================================================ */
USE FilmLabDB;
GO
DROP TABLE IF EXISTS dbo.OrdersPlan;
GO
CREATE TABLE dbo.OrdersPlan
(
    OrderId       INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_OrdersPlan PRIMARY KEY,
    OrderCode     NVARCHAR(20)  NOT NULL,
    CustomerId    INT           NOT NULL,
    LabId         INT           NOT NULL,
    StageId       INT           NOT NULL,
    Subtotal      DECIMAL(18,0) NOT NULL,
    DeliveryFee   DECIMAL(18,0) NOT NULL,
    PlatformFee   DECIMAL(18,0) NOT NULL,
    TotalAmount   DECIMAL(18,0) NOT NULL,
    PaymentStatus NVARCHAR(9)   NOT NULL,
    CustomerNote  NVARCHAR(500) NULL,
    CreatedAt     DATETIME2(0)  NOT NULL,
    IsDeleted     BIT           NOT NULL
);
GO
INSERT dbo.OrdersPlan
    (OrderCode, CustomerId, LabId, StageId, Subtotal, DeliveryFee, PlatformFee,
     TotalAmount, PaymentStatus, CustomerNote, CreatedAt, IsDeleted)
SELECT N'PLAN' + CAST(n.value AS NVARCHAR(10)),
       1 + ABS(CHECKSUM(NEWID())) % 2000,
       1 + ABS(CHECKSUM(NEWID())) % 20,
       1 + ABS(CHECKSUM(NEWID())) % 13,
       50000 + ABS(CHECKSUM(NEWID())) % 950000,
       0, 0,
       0,
       N'Paid',
       N'Ghi chú mẫu cho đơn số ' + CAST(n.value AS NVARCHAR(10)),
       DATEADD(MINUTE, -(ABS(CHECKSUM(NEWID())) % 525600), SYSUTCDATETIME()),
       0
FROM GENERATE_SERIES(1, 200000) AS n;
GO
-- Giữ đúng quy tắc của bảng thật: TotalAmount = Subtotal + DeliveryFee
UPDATE dbo.OrdersPlan SET TotalAmount = Subtotal + DeliveryFee;
GO
-- Kiểm tra: Total = 200000, Bad = 0, IdxCount = 1 (chỉ có PK)
SELECT COUNT(*) AS Total,
       SUM(CASE WHEN TotalAmount <> Subtotal + DeliveryFee THEN 1 ELSE 0 END) AS Bad,
       (SELECT COUNT(*) FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.OrdersPlan') AND index_id > 0) AS IdxCount
FROM dbo.OrdersPlan;
GO