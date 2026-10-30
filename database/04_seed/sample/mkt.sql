/* ============================================================
   File    : database/04_seed/sample/mkt.sql
   Module  : mkt - M7 Marketplace
   Purpose : Dữ liệu mẫu cho test/demo (số dòng gợi ý trong docs/Requirements.md). Tiếng Việt có dấu dùng N'...'.
   Owner   : D (xem docs/Phan-cong.md)
   Depends : iam
   Re-run  : Chạy sau REBUILD=1. Sample seed không gắn cứng ID của bảng IDENTITY.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;  -- bắt buộc cho filtered index, spatial index, computed column
SET ANSI_NULLS ON;
GO

SET NOCOUNT ON;

-- Tin đăng mẫu (6 tin: bán, đổi, cần mua; đủ trạng thái Active/Reserved/Sold)
INSERT INTO mkt.Listings (SellerId, CategoryId, ListingType, Title, Description, Brand, Model, Condition, Price, ExchangeWanted, Quantity, City, Status)
SELECT u.UserId, c.CategoryId, v.Type, v.Title, v.Descr, v.Brand, v.Model, v.Cond, v.Price, v.Exch, v.Qty, v.City, v.Status
FROM (VALUES
    (N'an.nguyen@example.com', N'CAMERA', N'Sell', N'Canon AE-1 Program kèm lens 50mm f/1.8', N'Máy hoạt động tốt, kèm dây đeo và bao da.', N'Canon', N'AE-1 Program', N'Good', 4500000, NULL, 1, N'TP. Hồ Chí Minh', N'Reserved'),
    (N'chi.le@example.com', N'LENS', N'Sell', N'Helios 44-2 58mm f/2 (M42)', N'Ống kính Liên Xô, bokeh xoáy đặc trưng.', N'Helios', N'44-2', N'Good', 900000, NULL, 1, N'Hà Nội', N'Reserved'),
    (N'binh.tran@example.com', N'CAMERA', N'Exchange', N'Đổi Olympus Trip 35 lấy Yashica T4', N'Trip 35 còn rất mới, đổi ngang.', N'Olympus', N'Trip 35', N'LikeNew', NULL, N'Yashica T4', 1, N'TP. Hồ Chí Minh', N'Active'),
    (N'lab.saigon@filmlab.vn', N'FILM', N'Sell', N'Kodak Portra 400 (hạn dùng 2027)', N'Cuộn mới, bảo quản tủ lạnh.', N'Kodak', N'Portra 400', N'New', 120000, NULL, 10, N'TP. Hồ Chí Minh', N'Active'),
    (N'an.nguyen@example.com', N'CAMERA', N'Wanted', N'Cần tìm Nikon FM2', N'Ưu tiên bản body còn đẹp, giá hợp lý.', N'Nikon', N'FM2', NULL, NULL, NULL, 1, N'TP. Hồ Chí Minh', N'Active'),
    (N'chi.le@example.com', N'CAMERA', N'Sell', N'Pentax K1000 body', N'Máy cơ nguyên bản, đã bán.', N'Pentax', N'K1000', N'Good', 3200000, NULL, 1, N'Hà Nội', N'Sold')
) v(Email, CatCode, Type, Title, Descr, Brand, Model, Cond, Price, Exch, Qty, City, Status)
JOIN iam.Users u ON u.Email = v.Email
JOIN mkt.ListingCategories c ON c.CategoryCode = v.CatCode;
GO

INSERT INTO mkt.ListingImages (ListingId, ImageUrl, SortOrder, IsPrimary)
SELECT l.ListingId, v.Url, v.Sort, v.IsPrimary
FROM (VALUES
    (N'Canon AE-1 Program kèm lens 50mm f/1.8', N'https://storage.filmlab.vn/market/1_0.jpg', 0, 1),
    (N'Canon AE-1 Program kèm lens 50mm f/1.8', N'https://storage.filmlab.vn/market/1_1.jpg', 1, 0),
    (N'Helios 44-2 58mm f/2 (M42)', N'https://storage.filmlab.vn/market/2_0.jpg', 0, 1),
    (N'Helios 44-2 58mm f/2 (M42)', N'https://storage.filmlab.vn/market/2_1.jpg', 1, 0),
    (N'Đổi Olympus Trip 35 lấy Yashica T4', N'https://storage.filmlab.vn/market/3_0.jpg', 0, 1),
    (N'Đổi Olympus Trip 35 lấy Yashica T4', N'https://storage.filmlab.vn/market/3_1.jpg', 1, 0),
    (N'Kodak Portra 400 (hạn dùng 2027)', N'https://storage.filmlab.vn/market/4_0.jpg', 0, 1),
    (N'Kodak Portra 400 (hạn dùng 2027)', N'https://storage.filmlab.vn/market/4_1.jpg', 1, 0),
    (N'Cần tìm Nikon FM2', N'https://storage.filmlab.vn/market/5_0.jpg', 0, 1),
    (N'Pentax K1000 body', N'https://storage.filmlab.vn/market/6_0.jpg', 0, 1)
) v(Title, Url, Sort, IsPrimary)
JOIN mkt.Listings l ON l.Title = v.Title;
GO

-- Giao dịch: giá chốt từ tin đăng, phí marketplace 5% (D-12, chỉ ghi nhận, không xử lý tiền thật)
INSERT INTO mkt.MarketTransactions (TransactionCode, ListingId, SellerId, BuyerId, Quantity, UnitPrice, PlatformFee, Status, Note,
                                    ConfirmedAt, ShippedAt, CompletedAt, CancelReason, DisputeReason, DisputedAt, BuyerRating, BuyerComment, RatedAt)
SELECT v.Code, l.ListingId, l.SellerId, b.UserId, v.Qty, l.Price, CAST(ROUND(l.Price * v.Qty * 0.05, 0) AS DECIMAL(18,0)), v.Status, v.Note,
       CASE WHEN v.Status IN (N'Confirmed', N'Completed', N'Disputed') THEN DATEADD(DAY, -3, SYSUTCDATETIME()) END,
       CASE WHEN v.Status = N'Completed' THEN DATEADD(DAY, -2, SYSUTCDATETIME()) END,
       CASE WHEN v.Status = N'Completed' THEN DATEADD(DAY, -1, SYSUTCDATETIME()) END,
       CASE WHEN v.Status = N'Cancelled' THEN N'Người mua đổi ý' END,
       CASE WHEN v.Status = N'Disputed' THEN N'Ống kính bị mốc nhẹ, không đúng mô tả' END,
       CASE WHEN v.Status = N'Disputed' THEN DATEADD(DAY, -1, SYSUTCDATETIME()) END,
       CASE WHEN v.Status = N'Completed' THEN 5 END,
       CASE WHEN v.Status = N'Completed' THEN N'Người bán nhiệt tình, máy đúng mô tả.' END,
       CASE WHEN v.Status = N'Completed' THEN SYSUTCDATETIME() END
FROM (VALUES
    (N'MK-2026-000001', N'Pentax K1000 body', N'binh.tran@example.com', 1, N'Completed', N'Đã nhận máy, đúng mô tả.'),
    (N'MK-2026-000002', N'Canon AE-1 Program kèm lens 50mm f/1.8', N'chi.le@example.com', 1, N'Confirmed', N'Hẹn gặp trực tiếp cuối tuần.'),
    (N'MK-2026-000003', N'Helios 44-2 58mm f/2 (M42)', N'an.nguyen@example.com', 1, N'Disputed', NULL),
    (N'MK-2026-000004', N'Kodak Portra 400 (hạn dùng 2027)', N'an.nguyen@example.com', 2, N'Cancelled', NULL)
) v(Code, Title, BuyerEmail, Qty, Status, Note)
JOIN mkt.Listings l ON l.Title = v.Title
JOIN iam.Users b ON b.Email = v.BuyerEmail;
GO

INSERT INTO mkt.Messages (ListingId, SenderId, ReceiverId, Body, SentAt, ReadAt)
SELECT l.ListingId, s.UserId, r.UserId, v.Body, DATEADD(MINUTE, -v.MinAgo, SYSUTCDATETIME()),
       CASE WHEN v.IsRead = 1 THEN DATEADD(MINUTE, -v.MinAgo + 5, SYSUTCDATETIME()) END
FROM (VALUES
    (N'Canon AE-1 Program kèm lens 50mm f/1.8', N'chi.le@example.com', N'an.nguyen@example.com', N'Máy còn bảo hành đèn pin không bạn?', 300, 1),
    (N'Canon AE-1 Program kèm lens 50mm f/1.8', N'an.nguyen@example.com', N'chi.le@example.com', N'Máy không bảo hành nhưng mình cho dùng thử trước.', 280, 1),
    (N'Đổi Olympus Trip 35 lấy Yashica T4', N'an.nguyen@example.com', N'binh.tran@example.com', N'Mình có Yashica T4 đời đầu, bạn có muốn đổi không?', 60, 0)
) v(Title, SenderEmail, ReceiverEmail, Body, MinAgo, IsRead)
JOIN mkt.Listings l ON l.Title = v.Title
JOIN iam.Users s ON s.Email = v.SenderEmail
JOIN iam.Users r ON r.Email = v.ReceiverEmail;
GO
