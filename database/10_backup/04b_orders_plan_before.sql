/* ============================================================
   Purpose : Bước 2/4. Đo TRƯỚC index. Truy vấn bám sp_GetMyOrders
             (lọc CustomerId + IsDeleted, ORDER BY CreatedAt DESC,
             OrderId DESC, phân trang). Kỳ vọng Clustered Index Scan.
             Muốn chụp plan: mở file này trong SSMS, bật Ctrl+M, F5.
   ============================================================ */
USE FilmLabDB;
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