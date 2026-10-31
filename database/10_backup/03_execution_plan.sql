/* ============================================================
   File    : database/10_backup/03_execution_plan.sql
   Purpose : Demo Execution Plan trước/sau index (200.000 dòng giả). CHẠY TAY trong SSMS.
   Cách làm: Ctrl+M (Include Actual Execution Plan), tab Messages xem logical reads.
   ============================================================ */
USE FilmLabDB;
GO
DROP TABLE IF EXISTS dbo.PlanDemo;
CREATE TABLE dbo.PlanDemo (
    OrderId     INT IDENTITY PRIMARY KEY,
    CustomerId  INT NOT NULL,
    LabId       INT NOT NULL,
    StageId     INT NOT NULL,
    TotalAmount DECIMAL(18,0) NOT NULL,
    CreatedAt   DATETIME2(0) NOT NULL
);
INSERT dbo.PlanDemo (CustomerId, LabId, StageId, TotalAmount, CreatedAt)
SELECT 1 + ABS(CHECKSUM(NEWID())) % 2000,
       1 + ABS(CHECKSUM(NEWID())) % 20,
       1 + ABS(CHECKSUM(NEWID())) % 13,
       50000 + ABS(CHECKSUM(NEWID())) % 950000,
       DATEADD(MINUTE, -(ABS(CHECKSUM(NEWID())) % 525600), SYSUTCDATETIME())
FROM GENERATE_SERIES(1, 200000);
GO
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
GO
-- TRƯỚC index: kỳ vọng Clustered Index Scan
SELECT OrderId, CreatedAt, TotalAmount
FROM dbo.PlanDemo
WHERE CustomerId = 6 AND CreatedAt >= DATEADD(DAY, -90, SYSUTCDATETIME())
ORDER BY CreatedAt DESC;
GO
CREATE NONCLUSTERED INDEX IX_PlanDemo_Customer_Created
    ON dbo.PlanDemo (CustomerId, CreatedAt) INCLUDE (TotalAmount);
GO
-- SAU index: kỳ vọng Index Seek (cùng câu truy vấn)
SELECT OrderId, CreatedAt, TotalAmount
FROM dbo.PlanDemo
WHERE CustomerId = 6 AND CreatedAt >= DATEADD(DAY, -90, SYSUTCDATETIME())
ORDER BY CreatedAt DESC;
GO
SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
-- Dọn: DROP TABLE dbo.PlanDemo;