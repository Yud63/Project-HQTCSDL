/* ============================================================
   File    : database/06_views/ord.sql
   Module  : ord - M3 Order, Processing, Payment, Fee
   Purpose : View: vw_LabRevenue, vw_OrdersInProgress.
   Owner   : B (xem docs/Phan-cong.md)
   Depends : iam, lab
   Re-run  : CREATE OR ALTER - chạy lại bao nhiêu lần cũng được.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER VIEW ord.vw_LabRevenue
AS
SELECT l.LabId,
       l.LabName,
       l.OwnerUserId,
       ISNULL(t.TotalOrders, 0)        AS TotalOrders,
       ISNULL(t.CompletedOrders, 0)    AS CompletedOrders,
       ISNULL(t.CancelledOrders, 0)    AS CancelledOrders,
       ISNULL(t.GrossRevenue, 0)       AS GrossRevenue,
       ISNULL(t.PlatformFeeTotal, 0)   AS PlatformFeeTotal,
       ISNULL(t.GrossRevenue, 0) - ISNULL(t.PlatformFeeTotal, 0) AS NetRevenue,
       ISNULL(t.DeliveryFeeTotal, 0)   AS DeliveryFeeTotal
FROM lab.FilmLabs l
OUTER APPLY (SELECT COUNT(*) AS TotalOrders,
                    SUM(CASE WHEN o.StageId = 12 THEN 1 ELSE 0 END) AS CompletedOrders,
                    SUM(CASE WHEN o.StageId = 13 THEN 1 ELSE 0 END) AS CancelledOrders,
                    SUM(CASE WHEN o.StageId = 12 AND o.PaymentStatus = N'Paid' THEN o.Subtotal ELSE 0 END)    AS GrossRevenue,
                    SUM(CASE WHEN o.StageId = 12 AND o.PaymentStatus = N'Paid' THEN o.PlatformFee ELSE 0 END) AS PlatformFeeTotal,
                    SUM(CASE WHEN o.StageId = 12 AND o.PaymentStatus = N'Paid' THEN o.DeliveryFee ELSE 0 END) AS DeliveryFeeTotal
             FROM ord.Orders o
             WHERE o.LabId = l.LabId AND o.IsDeleted = 0) t
WHERE l.IsDeleted = 0;
GO

CREATE OR ALTER VIEW ord.vw_OrdersInProgress
AS
SELECT o.OrderId,
       o.OrderCode,
       o.CustomerId,
       u.FullName AS CustomerName,
       o.LabId,
       l.LabName,
       o.StageId,
       s.StageCode,
       s.StageName,
       o.FulfillmentMethod,
       o.ReturnMethod,
       o.TotalAmount,
       o.PaymentStatus,
       o.EstimatedReadyDate,
       o.CreatedAt,
       DATEDIFF(DAY, o.CreatedAt, SYSUTCDATETIME()) AS DaysInProgress
FROM ord.Orders o
JOIN ord.ProcessingStages s ON s.StageId = o.StageId
JOIN lab.FilmLabs l ON l.LabId = o.LabId
JOIN iam.Users u ON u.UserId = o.CustomerId
WHERE o.IsDeleted = 0 AND o.StageId BETWEEN 2 AND 11;
GO
