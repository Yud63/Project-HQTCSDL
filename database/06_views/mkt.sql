/* ============================================================
   File    : database/06_views/mkt.sql
   Module  : mkt - M7 Marketplace
   Purpose : View: vw_MarketActive, vw_SellerStats.
   Owner   : D (xem docs/Phan-cong.md)
   Depends : iam
   Re-run  : CREATE OR ALTER - chạy lại bao nhiêu lần cũng được.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER VIEW mkt.vw_MarketActive
AS
SELECT l.ListingId,
       l.SellerId,
       u.FullName AS SellerName,
       mkt.fn_SellerRating(l.SellerId) AS SellerRating,
       l.CategoryId,
       c.CategoryName,
       l.ListingType,
       l.Title,
       l.Brand,
       l.Model,
       l.Condition,
       l.Price,
       l.ExchangeWanted,
       l.Quantity,
       l.City,
       (SELECT TOP 1 li.ImageUrl FROM mkt.ListingImages li
        WHERE li.ListingId = l.ListingId AND li.IsPrimary = 1) AS PrimaryImageUrl,
       l.ExpiresAt,
       l.CreatedAt
FROM mkt.Listings l
JOIN iam.Users u ON u.UserId = l.SellerId
JOIN mkt.ListingCategories c ON c.CategoryId = l.CategoryId
WHERE l.Status = N'Active' AND l.IsDeleted = 0 AND l.ExpiresAt > SYSUTCDATETIME();
GO

CREATE OR ALTER VIEW mkt.vw_SellerStats
AS
SELECT u.UserId   AS SellerId,
       u.FullName AS SellerName,
       ISNULL(l.TotalListings, 0)         AS TotalListings,
       ISNULL(l.ActiveListings, 0)        AS ActiveListings,
       ISNULL(t.TotalTransactions, 0)     AS TotalTransactions,
       ISNULL(t.CompletedTransactions, 0) AS CompletedTransactions,
       ISNULL(t.CancelledTransactions, 0) AS CancelledTransactions,
       ISNULL(t.DisputedTransactions, 0)  AS DisputedTransactions,
       ISNULL(t.CompletedRevenue, 0)      AS CompletedRevenue,
       ISNULL(t.PlatformFeeTotal, 0)      AS PlatformFeeTotal,
       mkt.fn_SellerRating(u.UserId)      AS AvgRating,
       mkt.fn_SellerRatingCount(u.UserId) AS RatingCount
FROM iam.Users u
OUTER APPLY (SELECT COUNT(*) AS TotalListings,
                    SUM(CASE WHEN Status = N'Active' THEN 1 ELSE 0 END) AS ActiveListings
             FROM mkt.Listings WHERE SellerId = u.UserId AND IsDeleted = 0) l
OUTER APPLY (SELECT COUNT(*) AS TotalTransactions,
                    SUM(CASE WHEN Status = N'Completed' THEN 1 ELSE 0 END) AS CompletedTransactions,
                    SUM(CASE WHEN Status = N'Cancelled' THEN 1 ELSE 0 END) AS CancelledTransactions,
                    SUM(CASE WHEN Status = N'Disputed'  THEN 1 ELSE 0 END) AS DisputedTransactions,
                    SUM(CASE WHEN Status = N'Completed' THEN TotalAmount ELSE 0 END) AS CompletedRevenue,
                    SUM(CASE WHEN Status = N'Completed' THEN PlatformFee ELSE 0 END) AS PlatformFeeTotal
             FROM mkt.MarketTransactions WHERE SellerId = u.UserId) t
WHERE u.IsDeleted = 0 AND (l.TotalListings > 0 OR t.TotalTransactions > 0);
GO