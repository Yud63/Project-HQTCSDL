/* ============================================================
   File    : database/04_seed/sample/arc.sql
   Module  : arc - M5 Digital Archive
   Purpose : Dữ liệu mẫu cho test/demo (số dòng gợi ý trong docs/Requirements.md). Tiếng Việt có dấu dùng N'...'.
   Owner   : C (xem docs/Phan-cong.md)
   Depends : iam, lab, ord
   Re-run  : Chạy sau REBUILD=1. Sample seed không gắn cứng ID của bảng IDENTITY.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;  -- bắt buộc cho filtered index, spatial index, computed column
SET ANSI_NULLS ON;
GO

SET NOCOUNT ON;

-- File scan mẫu (URL giả; checksum là SHA-256 của tên file, chỉ để demo)
INSERT INTO arc.ScanFiles (OrderId, OrderItemId, OwnerUserId, UploadedBy, FrameNumber, FileName, StorageUrl, ContentType, FileSizeBytes, WidthPx, HeightPx, ChecksumSha256, QualityScore, QualityStatus)
SELECT o.OrderId, oi.OrderItemId, o.CustomerId, l.OwnerUserId, v.Frame, v.FileName, v.Url, N'image/jpeg', v.Size, v.W, v.H,
       CONVERT(CHAR(64), HASHBYTES('SHA2_256', v.FileName), 2), v.Score, v.QStatus
FROM (VALUES
    (N'FL-2026-000001', N'Scan High 35mm', 1, N'FL-2026-000001_001.jpg', N'https://storage.filmlab.vn/scans/FL-2026-000001/001.jpg', 3501000, 3000, 2000, 92.5, N'Passed'),
    (N'FL-2026-000001', N'Scan High 35mm', 2, N'FL-2026-000001_002.jpg', N'https://storage.filmlab.vn/scans/FL-2026-000001/002.jpg', 3502000, 3000, 2000, 92.5, N'Passed'),
    (N'FL-2026-000001', N'Scan High 35mm', 3, N'FL-2026-000001_003.jpg', N'https://storage.filmlab.vn/scans/FL-2026-000001/003.jpg', 3503000, 3000, 2000, 92.5, N'Passed'),
    (N'FL-2026-000001', N'Scan High 35mm', 4, N'FL-2026-000001_004.jpg', N'https://storage.filmlab.vn/scans/FL-2026-000001/004.jpg', 3504000, 3000, 2000, 92.5, N'Passed'),
    (N'FL-2026-000006', N'Scan Basic 35mm', 1, N'FL-2026-000006_001.jpg', N'https://storage.filmlab.vn/scans/FL-2026-000006/001.jpg', 3501000, 3000, 2000, 71.0, N'Warning'),
    (N'FL-2026-000006', N'Scan Basic 35mm', 2, N'FL-2026-000006_002.jpg', N'https://storage.filmlab.vn/scans/FL-2026-000006/002.jpg', 3502000, 3000, 2000, 71.0, N'Warning'),
    (N'FL-2026-000003', N'Scan Ultra 35mm', 1, N'FL-2026-000003_001.jpg', N'https://storage.filmlab.vn/scans/FL-2026-000003/001.jpg', 3501000, 3000, 2000, NULL, N'NotChecked'),
    (N'FL-2026-000003', N'Scan Ultra 35mm', 2, N'FL-2026-000003_002.jpg', N'https://storage.filmlab.vn/scans/FL-2026-000003/002.jpg', 3502000, 3000, 2000, NULL, N'NotChecked')
) v(OrderCode, Pkg, Frame, FileName, Url, Size, W, H, Score, QStatus)
JOIN ord.Orders o ON o.OrderCode = v.OrderCode
JOIN lab.FilmLabs l ON l.LabId = o.LabId
JOIN ord.OrderItems oi ON oi.OrderId = o.OrderId
JOIN lab.LabServices ls ON ls.LabServiceId = oi.LabServiceId AND ls.PackageName = v.Pkg;
GO

-- Metadata ảnh (1-1 với ScanFiles, chỉ cho ảnh đã kiểm tra)
INSERT INTO arc.PhotoMetadata (ScanFileId, FilmStockId, CameraModel, LensModel, ShootingDate, ExposedIso, ProcessMethod, ScannerModel, ScanResolutionDpi, ExtraJson)
SELECT sf.ScanFileId, fs.StockId, v.Camera, v.Lens, CAST(DATEADD(DAY, -v.DaysAgo, SYSUTCDATETIME()) AS DATE), v.Iso, v.Process, v.Scanner, v.Dpi, v.Extra
FROM (VALUES
    (N'FL-2026-000001', N'FL-2026-000001_001.jpg', N'Kodak', N'Portra 400', N'Canon AE-1 Program', N'FD 50mm f/1.8', 41, 400, N'C-41', N'Noritsu HS-1800', 4000, N'{"push": "+0"}'),
    (N'FL-2026-000001', N'FL-2026-000001_002.jpg', N'Kodak', N'Portra 400', N'Canon AE-1 Program', N'FD 50mm f/1.8', 42, 400, N'C-41', N'Noritsu HS-1800', 4000, N'{"push": "+0"}'),
    (N'FL-2026-000001', N'FL-2026-000001_003.jpg', N'Kodak', N'Portra 400', N'Canon AE-1 Program', N'FD 50mm f/1.8', 43, 400, N'C-41', N'Noritsu HS-1800', 4000, N'{"push": "+0"}'),
    (N'FL-2026-000001', N'FL-2026-000001_004.jpg', N'Kodak', N'Portra 400', N'Canon AE-1 Program', N'FD 50mm f/1.8', 44, 400, N'C-41', N'Noritsu HS-1800', 4000, N'{"push": "+0"}'),
    (N'FL-2026-000006', N'FL-2026-000006_001.jpg', N'Kodak', N'Ultramax 400', N'Canon AE-1 Program', N'FD 50mm f/1.8', 41, 400, N'C-41', N'Noritsu HS-1800', 4000, N'{"push": "+0"}'),
    (N'FL-2026-000006', N'FL-2026-000006_002.jpg', N'Kodak', N'Ultramax 400', N'Canon AE-1 Program', N'FD 50mm f/1.8', 42, 400, N'C-41', N'Noritsu HS-1800', 4000, N'{"push": "+0"}')
) v(OrderCode, FileName, Brand, Stock, Camera, Lens, DaysAgo, Iso, Process, Scanner, Dpi, Extra)
JOIN ord.Orders o ON o.OrderCode = v.OrderCode
JOIN arc.ScanFiles sf ON sf.OrderId = o.OrderId AND sf.FileName = v.FileName
JOIN lab.FilmStocks fs ON fs.Brand = v.Brand AND fs.StockName = v.Stock;
GO

-- Album của khách
INSERT INTO arc.Albums (OwnerUserId, Title, Description, CoverScanFileId, IsPublic)
SELECT u.UserId, v.Title, v.Descr, sf.ScanFileId, v.IsPublic
FROM (VALUES
    (N'an.nguyen@example.com', N'Đà Lạt 2026', N'Những khung hình Portra 400 trong chuyến đi Đà Lạt.', N'FL-2026-000001_001.jpg', 1),
    (N'binh.tran@example.com', N'Phim đầu tay', N'Cuộn Ultramax 400 đầu tiên.', N'FL-2026-000006_001.jpg', 0)
) v(Email, Title, Descr, CoverFile, IsPublic)
JOIN iam.Users u ON u.Email = v.Email
LEFT JOIN arc.ScanFiles sf ON sf.FileName = v.CoverFile;
GO

INSERT INTO arc.AlbumPhotos (AlbumId, ScanFileId, SortOrder)
SELECT a.AlbumId, sf.ScanFileId, v.Sort
FROM (VALUES
    (N'Đà Lạt 2026', N'FL-2026-000001_001.jpg', 1), (N'Đà Lạt 2026', N'FL-2026-000001_002.jpg', 2), (N'Đà Lạt 2026', N'FL-2026-000001_003.jpg', 3),
    (N'Phim đầu tay', N'FL-2026-000006_001.jpg', 1), (N'Phim đầu tay', N'FL-2026-000006_002.jpg', 2)
) v(Title, FileName, Sort)
JOIN arc.Albums a ON a.Title = v.Title
JOIN arc.ScanFiles sf ON sf.FileName = v.FileName;
GO

-- Thông báo (mọi module sẽ tạo qua arc.sp_CreateNotification ở Đợt 6)
INSERT INTO arc.Notifications (UserId, Type, Title, Body, OrderId, IsRead, ReadAt)
SELECT u.UserId, v.Type, v.Title, v.Body, o.OrderId, v.IsRead,
       CASE WHEN v.IsRead = 1 THEN DATEADD(HOUR, -1, SYSUTCDATETIME()) END
FROM (VALUES
    (N'an.nguyen@example.com', N'ScanReady', N'Scan phim đã sẵn sàng', N'Đơn FL-2026-000001 đã có 4 ảnh scan.', N'FL-2026-000001', 1),
    (N'an.nguyen@example.com', N'OrderStage', N'Đơn đã hoàn tất', N'Cảm ơn bạn đã sử dụng dịch vụ.', N'FL-2026-000001', 0),
    (N'an.nguyen@example.com', N'Delivery', N'Đã tạo yêu cầu lấy phim', N'Đơn FL-2026-000004 đang chờ phân công shipper.', N'FL-2026-000004', 0),
    (N'binh.tran@example.com', N'OrderStage', N'Đơn đang tráng phim', N'Đơn FL-2026-000002 đang ở bước tráng hóa chất.', N'FL-2026-000002', 0),
    (N'chi.le@example.com', N'Delivery', N'Đã phân công giao phim', N'Ahamove sẽ giao phim cho đơn FL-2026-000003.', N'FL-2026-000003', 0),
    (N'lab.saigon@filmlab.vn', N'Review', N'Có đánh giá mới', N'Khách vừa đánh giá 5 sao cho đơn FL-2026-000001.', N'FL-2026-000001', 1),
    (N'admin@filmlab.vn', N'Complaint', N'Khiếu nại mới cần xử lý', N'Đơn FL-2026-000003: giao trả phim chậm.', N'FL-2026-000003', 0)
) v(Email, Type, Title, Body, OrderCode, IsRead)
JOIN iam.Users u ON u.Email = v.Email
LEFT JOIN ord.Orders o ON o.OrderCode = v.OrderCode;
GO
