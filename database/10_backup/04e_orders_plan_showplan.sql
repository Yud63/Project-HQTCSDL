/* ============================================================
   Purpose : Xem Execution Plan dạng văn bản (SHOWPLAN_TEXT) cho
             truy vấn A và B, TRƯỚC và SAU khi tạo index, bằng sqlcmd
             (thay cho việc chụp plan đồ họa trong SSMS).
             Chạy sau 04a, trước 04d.
   ============================================================ */
USE FilmLabDB;
GO
DROP INDEX IF EXISTS IX_OrdersPlan_Customer ON dbo.OrdersPlan;
GO
PRINT N'===== PLAN TRƯỚC INDEX =====';
GO
SET SHOWPLAN_TEXT ON;
GO
SELECT OrderId, OrderCode, LabId, StageId, TotalAmount, CreatedAt
FROM dbo.OrdersPlan
WHERE CustomerId = 6 AND IsDeleted = 0
ORDER BY CreatedAt DESC, OrderId DESC
OFFSET 0 ROWS FETCH NEXT 20 ROWS ONLY;
GO
SELECT COUNT(*) AS OrderCount
FROM dbo.OrdersPlan
WHERE CustomerId = 6 AND IsDeleted = 0;
GO
SET SHOWPLAN_TEXT OFF;
GO
CREATE NONCLUSTERED INDEX IX_OrdersPlan_Customer
    ON dbo.OrdersPlan (CustomerId, CreatedAt DESC);
GO
PRINT N'===== PLAN SAU INDEX =====';
GO
SET SHOWPLAN_TEXT ON;
GO
SELECT OrderId, OrderCode, LabId, StageId, TotalAmount, CreatedAt
FROM dbo.OrdersPlan
WHERE CustomerId = 6 AND IsDeleted = 0
ORDER BY CreatedAt DESC, OrderId DESC
OFFSET 0 ROWS FETCH NEXT 20 ROWS ONLY;
GO
SELECT COUNT(*) AS OrderCount
FROM dbo.OrdersPlan
WHERE CustomerId = 6 AND IsDeleted = 0;
GO
SET SHOWPLAN_TEXT OFF;
GO