/* ============================================================
   Purpose : Phần 2a. Bảng sao KHÔNG khóa để đối chứng bán lố:
             dbo.LockDemoStock (Stock = 2, không CHECK) và
             dbo.LockDemoSold (ghi mỗi lần bán thành công).
             CHẠY TAY bằng sqlcmd, dọn ở Phần 4.
   ============================================================ */
USE FilmLabDB;
GO
DROP TABLE IF EXISTS dbo.LockDemoSold;
DROP TABLE IF EXISTS dbo.LockDemoStock;
GO
CREATE TABLE dbo.LockDemoStock
(
    Id    INT NOT NULL CONSTRAINT PK_LockDemoStock PRIMARY KEY,
    Stock INT NOT NULL
);
CREATE TABLE dbo.LockDemoSold
(
    SoldId  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_LockDemoSold PRIMARY KEY,
    BuyerId INT NOT NULL,
    Qty     INT NOT NULL
);
INSERT dbo.LockDemoStock (Id, Stock) VALUES (1, 2);
GO
-- Kiểm tra: Stock = 2, TotalSold = 0
SELECT s.Stock, (SELECT COUNT(*) FROM dbo.LockDemoSold) AS SoldRows
FROM dbo.LockDemoStock AS s;
GO