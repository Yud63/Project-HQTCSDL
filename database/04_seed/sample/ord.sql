/* ============================================================
   File    : database/04_seed/sample/ord.sql
   Module  : ord - M3 Order, Processing, Payment, Fee
   Purpose : Dữ liệu mẫu cho test/demo (số dòng gợi ý trong docs/Requirements.md). Tiếng Việt có dấu dùng N'...'.
   Owner   : B (xem docs/Phan-cong.md)
   Depends : iam, lab
   Re-run  : Chạy sau REBUILD=1. Sample seed không gắn cứng ID của bảng IDENTITY.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;  -- bắt buộc cho filtered index, spatial index, computed column
SET ANSI_NULLS ON;
GO

SET NOCOUNT ON;

-- Cấu hình phí mặc định toàn hệ thống (D-01, D-06, D-12). Cần Admin của iam sample.
INSERT INTO ord.FeeConfigs (FeeType, Rate, FixedAmount, ScopeLabId, EffectiveFrom, CreatedBy)
SELECT v.FeeType, v.Rate, v.FixedAmount, NULL, '2026-01-01', a.UserId
FROM (VALUES (N'PlatformCommission', 0.1000, NULL),
             (N'MarketplaceFee',     0.0500, NULL),
             (N'DeliveryBase',       NULL,   25000)) v(FeeType, Rate, FixedAmount)
CROSS JOIN (SELECT UserId FROM iam.Users WHERE Email = N'admin@filmlab.vn') a;
GO
