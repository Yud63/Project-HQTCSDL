/* ============================================================
   File    : database/06_views/arc.sql
   Module  : arc - M5 Digital Archive
   Purpose : View: vw_CustomerArchive.
   Owner   : C (xem docs/Phan-cong.md)
   Depends : iam, lab, ord
   Re-run  : CREATE OR ALTER - chạy lại bao nhiêu lần cũng được.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER VIEW arc.vw_CustomerArchive
AS
SELECT sf.OwnerUserId,
       sf.ScanFileId,
       sf.OrderId,
       o.OrderCode,
       o.LabId,
       l.LabName,
       sf.OrderItemId,
       sf.FrameNumber,
       sf.FileName,
       sf.StorageUrl,
       sf.ContentType,
       sf.FileSizeBytes,
       sf.WidthPx,
       sf.HeightPx,
       sf.QualityScore,
       sf.QualityStatus,
       sf.UploadedAt,
       pm.FilmStockId,
       fs.Brand     AS FilmBrand,
       fs.StockName AS FilmStockName,
       pm.CameraModel,
       pm.LensModel,
       pm.ShootingDate,
       pm.ExposedIso,
       pm.ProcessMethod,
       pm.ScannerModel,
       pm.ScanResolutionDpi,
       (SELECT COUNT(*)
        FROM arc.AlbumPhotos ap
        JOIN arc.Albums a ON a.AlbumId = ap.AlbumId
        WHERE ap.ScanFileId = sf.ScanFileId AND a.IsDeleted = 0) AS AlbumCount
FROM arc.ScanFiles sf
JOIN ord.Orders o ON o.OrderId = sf.OrderId
JOIN lab.FilmLabs l ON l.LabId = o.LabId
LEFT JOIN arc.PhotoMetadata pm ON pm.ScanFileId = sf.ScanFileId
LEFT JOIN lab.FilmStocks fs ON fs.StockId = pm.FilmStockId
WHERE sf.IsDeleted = 0;
GO
