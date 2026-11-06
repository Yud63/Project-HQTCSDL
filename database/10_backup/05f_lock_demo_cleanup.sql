/* ============================================================
   Purpose : Phần 4/4 demo UPDLOCK/HOLDLOCK. Dọn toàn bộ dữ liệu demo:
             thông báo, giao dịch và tin LOCKDEMO-BR-MKT-06, rồi các bảng
             dbo.LockDemoSold, dbo.LockDemoStock, dbo.LockDemoCtx.
             Không xóa audit.AuditLogs (bảng chỉ-thêm, BR-AUD-01).
   ============================================================ */
USE FilmLabDB;
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET XACT_ABORT ON;
GO
DECLARE @ids TABLE (ListingId INT PRIMARY KEY, SellerId INT NOT NULL);
INSERT @ids (ListingId, SellerId)
SELECT ListingId, SellerId FROM mkt.Listings WHERE Title = N'LOCKDEMO-BR-MKT-06';

BEGIN TRAN;

DELETE n
FROM arc.Notifications AS n
JOIN @ids AS i ON i.SellerId = n.UserId
WHERE n.Type = N'Market' AND n.Body LIKE N'% x LOCKDEMO-BR-MKT-06';
PRINT 'Notifications da xoa: ' + CAST(@@ROWCOUNT AS VARCHAR(10));

DELETE t
FROM mkt.MarketTransactions AS t
JOIN @ids AS i ON i.ListingId = t.ListingId;
PRINT 'MarketTransactions da xoa: ' + CAST(@@ROWCOUNT AS VARCHAR(10));

DELETE l
FROM mkt.Listings AS l
JOIN @ids AS i ON i.ListingId = l.ListingId
WHERE l.Title = N'LOCKDEMO-BR-MKT-06';
PRINT 'Listings da xoa: ' + CAST(@@ROWCOUNT AS VARCHAR(10));

COMMIT;
GO
DROP TABLE IF EXISTS dbo.LockDemoSold;
DROP TABLE IF EXISTS dbo.LockDemoStock;
DROP TABLE IF EXISTS dbo.LockDemoCtx;
GO
SELECT OBJECT_ID(N'dbo.LockDemoCtx')   AS CtxGone,
       OBJECT_ID(N'dbo.LockDemoStock') AS StockGone,
       OBJECT_ID(N'dbo.LockDemoSold')  AS SoldGone,
       (SELECT COUNT(*) FROM mkt.Listings WHERE Title = N'LOCKDEMO-BR-MKT-06') AS DemoListings;
GO