/* ============================================================
   Purpose : Bước 3/4. Tạo index cùng định nghĩa IX_Orders_Customer
             (CustomerId, CreatedAt DESC) rồi chạy lại hai truy vấn
             A và B. Kỳ vọng Index Seek, logical reads giảm mạnh.
             Muốn chụp plan: mở file này trong SSMS, bật Ctrl+M, F5.
   ============================================================ */
USE FilmLabDB;
GO
DROP INDEX IF EXISTS IX_OrdersPlan_Customer ON dbo.OrdersPlan;
GO
CREATE NONCLUSTERED INDEX IX_OrdersPlan_Customer
    ON dbo.OrdersPlan (CustomerId, CreatedAt DESC);
GO
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
GO
-- Truy vấn A: trang đầu danh sách đơn của một customer
SELECT OrderId, OrderCode, LabId, StageId, TotalAmount, CreatedAt
FROM dbo.OrdersPlan
WHERE CustomerId = 6 AND IsDeleted = 0
ORDER BY CreatedAt DESC, OrderId DESC
OFFSET 0 ROWS FETCH NEXT 20 ROWS ONLY;
GO
-- Truy vấn B: đếm đơn của customer
SELECT COUNT(*) AS OrderCount
FROM dbo.OrdersPlan
WHERE CustomerId = 6 AND IsDeleted = 0;
GO
SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO