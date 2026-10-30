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

-- Đơn hàng mẫu: nhiều giai đoạn, tổng tiền tính theo D-01 (hoa hồng 10%) và D-06 (25.000đ/chặng)
INSERT INTO ord.Orders (OrderCode, CustomerId, LabId, StageId, FulfillmentMethod, ReturnMethod, PickupAddressId, ReturnAddressId,
                        Subtotal, DeliveryFee, PlatformFee, TotalAmount, PaymentStatus, CustomerNote, EstimatedReadyDate, CompletedAt, CancelReason, CreatedAt)
SELECT v.OrderCode, u.UserId, l.LabId, v.StageId, v.Fulfil, v.Ret, pa.AddressId, ra.AddressId,
       v.Subtotal, v.DeliveryFee, v.PlatformFee, v.Total, v.PayStatus, v.Note,
       CASE WHEN v.Est IS NOT NULL THEN CAST(DATEADD(DAY, v.Est, SYSUTCDATETIME()) AS DATE) END,
       CASE WHEN v.CompD IS NOT NULL THEN DATEADD(DAY, -v.CompD, SYSUTCDATETIME()) END,
       v.CancelReason, DATEADD(DAY, -v.D, SYSUTCDATETIME())
FROM (VALUES
    (N'FL-2026-000001', N'an.nguyen@example.com', N'Sài Gòn Film Lab', 12, N'DropOff', N'SelfCollect', NULL, NULL, 420000, 0, 42000, 420000, N'Paid', N'Phim đi Đà Lạt tháng trước', NULL, 20, 12, NULL),
    (N'FL-2026-000002', N'binh.tran@example.com', N'Sài Gòn Film Lab', 5, N'DropOff', N'SelfCollect', NULL, NULL, 70000, 0, 7000, 70000, N'Unpaid', NULL, NULL, 6, NULL, NULL),
    (N'FL-2026-000003', N'chi.le@example.com', N'Hà Nội Analog Lab', 11, N'DropOff', N'Delivery', NULL, N'Nhà', 255000, 25000, 25500, 280000, N'Paid', N'Giao trả phim tận nhà', NULL, 9, NULL, NULL),
    (N'FL-2026-000004', N'an.nguyen@example.com', N'Sài Gòn Film Lab', 1, N'Pickup', N'Delivery', N'Nhà', N'Nhà', 80000, 50000, 8000, 130000, N'Unpaid', NULL, 3, 1, NULL, NULL),
    (N'FL-2026-000005', N'binh.tran@example.com', N'Sài Gòn Film Lab', 13, N'DropOff', N'SelfCollect', NULL, NULL, 80000, 0, 8000, 80000, N'Unpaid', NULL, NULL, 15, NULL, N'Khách đổi ý, không cần xử lý nữa'),
    (N'FL-2026-000006', N'binh.tran@example.com', N'Sài Gòn Film Lab', 12, N'DropOff', N'Delivery', NULL, N'Nhà', 140000, 25000, 14000, 165000, N'Paid', NULL, NULL, 18, 9, NULL)
) v(OrderCode, Email, LabName, StageId, Fulfil, Ret, PickupLbl, ReturnLbl, Subtotal, DeliveryFee, PlatformFee, Total, PayStatus, Note, Est, D, CompD, CancelReason)
JOIN iam.Users u ON u.Email = v.Email
JOIN lab.FilmLabs l ON l.LabName = v.LabName
LEFT JOIN iam.Addresses pa ON pa.UserId = u.UserId AND pa.Label = v.PickupLbl
LEFT JOIN iam.Addresses ra ON ra.UserId = u.UserId AND ra.Label = v.ReturnLbl;
GO

-- Chi tiết đơn (giá chốt từ LabServices lúc đặt)
INSERT INTO ord.OrderItems (OrderId, LabServiceId, FilmStockId, Quantity, UnitPriceSnapshot, ProcessingNote)
SELECT o.OrderId, ls.LabServiceId, fs.StockId, v.Qty, ls.UnitPrice, v.Note
FROM (VALUES
    (N'FL-2026-000001', N'Tráng C-41 35mm', N'Kodak', N'Portra 400', 2, NULL),
    (N'FL-2026-000001', N'Scan High 35mm', N'Kodak', N'Portra 400', 2, NULL),
    (N'FL-2026-000002', N'Tráng B&W 35mm', N'Kodak', N'Tri-X 400', 1, N'Đẩy +1 stop'),
    (N'FL-2026-000003', N'Tráng C-41 35mm', N'Fujifilm', N'Superia X-tra 400', 1, NULL),
    (N'FL-2026-000003', N'Scan Ultra 35mm', N'Fujifilm', N'Superia X-tra 400', 1, NULL),
    (N'FL-2026-000004', N'Tráng C-41 120', N'Kodak', N'Portra 160', 1, NULL),
    (N'FL-2026-000005', N'Scan Basic 35mm', NULL, NULL, 1, NULL),
    (N'FL-2026-000006', N'Tráng C-41 35mm', N'Kodak', N'Ultramax 400', 1, NULL),
    (N'FL-2026-000006', N'Scan Basic 35mm', N'Kodak', N'Ultramax 400', 1, NULL)
) v(OrderCode, Pkg, Brand, Stock, Qty, Note)
JOIN ord.Orders o ON o.OrderCode = v.OrderCode
JOIN lab.LabServices ls ON ls.LabId = o.LabId AND ls.PackageName = v.Pkg
LEFT JOIN lab.FilmStocks fs ON fs.Brand = v.Brand AND fs.StockName = v.Stock;
GO

-- Nhật ký giai đoạn (trigger ghi tự động sẽ có ở Đợt 6; dữ liệu mẫu ghi tay cho khớp)
INSERT INTO ord.OrderStageLog (OrderId, FromStageId, ToStageId, ChangedBy, Note, ChangedAt)
SELECT o.OrderId, v.FromStage, v.ToStage, u.UserId, v.Note, DATEADD(HOUR, v.H, o.CreatedAt)
FROM (VALUES
    (N'FL-2026-000001', NULL, 1, N'an.nguyen@example.com', N'Khởi tạo đơn', 0),
    (N'FL-2026-000001', 1, 2, N'lab.saigon@filmlab.vn', NULL, 1),
    (N'FL-2026-000001', 2, 3, N'lab.saigon@filmlab.vn', NULL, 2),
    (N'FL-2026-000001', 3, 4, N'lab.saigon@filmlab.vn', NULL, 3),
    (N'FL-2026-000001', 4, 5, N'lab.saigon@filmlab.vn', NULL, 4),
    (N'FL-2026-000001', 5, 6, N'lab.saigon@filmlab.vn', NULL, 5),
    (N'FL-2026-000001', 6, 7, N'lab.saigon@filmlab.vn', NULL, 6),
    (N'FL-2026-000001', 7, 8, N'lab.saigon@filmlab.vn', NULL, 7),
    (N'FL-2026-000001', 8, 9, N'lab.saigon@filmlab.vn', NULL, 8),
    (N'FL-2026-000001', 9, 10, N'lab.saigon@filmlab.vn', NULL, 9),
    (N'FL-2026-000001', 10, 11, N'lab.saigon@filmlab.vn', NULL, 10),
    (N'FL-2026-000001', 11, 12, N'lab.saigon@filmlab.vn', NULL, 11),
    (N'FL-2026-000002', NULL, 1, N'binh.tran@example.com', N'Khởi tạo đơn', 0),
    (N'FL-2026-000002', 1, 2, N'lab.saigon@filmlab.vn', NULL, 1),
    (N'FL-2026-000002', 2, 3, N'lab.saigon@filmlab.vn', NULL, 2),
    (N'FL-2026-000002', 3, 4, N'lab.saigon@filmlab.vn', NULL, 3),
    (N'FL-2026-000002', 4, 5, N'lab.saigon@filmlab.vn', NULL, 4),
    (N'FL-2026-000003', NULL, 1, N'chi.le@example.com', N'Khởi tạo đơn', 0),
    (N'FL-2026-000003', 1, 2, N'lab.hanoi@filmlab.vn', NULL, 1),
    (N'FL-2026-000003', 2, 3, N'lab.hanoi@filmlab.vn', NULL, 2),
    (N'FL-2026-000003', 3, 4, N'lab.hanoi@filmlab.vn', NULL, 3),
    (N'FL-2026-000003', 4, 5, N'lab.hanoi@filmlab.vn', NULL, 4),
    (N'FL-2026-000003', 5, 6, N'lab.hanoi@filmlab.vn', NULL, 5),
    (N'FL-2026-000003', 6, 7, N'lab.hanoi@filmlab.vn', NULL, 6),
    (N'FL-2026-000003', 7, 8, N'lab.hanoi@filmlab.vn', NULL, 7),
    (N'FL-2026-000003', 8, 9, N'lab.hanoi@filmlab.vn', NULL, 8),
    (N'FL-2026-000003', 9, 10, N'lab.hanoi@filmlab.vn', NULL, 9),
    (N'FL-2026-000003', 10, 11, N'lab.hanoi@filmlab.vn', NULL, 10),
    (N'FL-2026-000004', NULL, 1, N'an.nguyen@example.com', N'Khởi tạo đơn', 0),
    (N'FL-2026-000005', NULL, 1, N'binh.tran@example.com', N'Khởi tạo đơn', 0),
    (N'FL-2026-000005', 1, 13, N'lab.saigon@filmlab.vn', NULL, 1),
    (N'FL-2026-000006', NULL, 1, N'binh.tran@example.com', N'Khởi tạo đơn', 0),
    (N'FL-2026-000006', 1, 2, N'lab.saigon@filmlab.vn', NULL, 1),
    (N'FL-2026-000006', 2, 3, N'lab.saigon@filmlab.vn', NULL, 2),
    (N'FL-2026-000006', 3, 4, N'lab.saigon@filmlab.vn', NULL, 3),
    (N'FL-2026-000006', 4, 5, N'lab.saigon@filmlab.vn', NULL, 4),
    (N'FL-2026-000006', 5, 6, N'lab.saigon@filmlab.vn', NULL, 5),
    (N'FL-2026-000006', 6, 7, N'lab.saigon@filmlab.vn', NULL, 6),
    (N'FL-2026-000006', 7, 8, N'lab.saigon@filmlab.vn', NULL, 7),
    (N'FL-2026-000006', 8, 9, N'lab.saigon@filmlab.vn', NULL, 8),
    (N'FL-2026-000006', 9, 10, N'lab.saigon@filmlab.vn', NULL, 9),
    (N'FL-2026-000006', 10, 11, N'lab.saigon@filmlab.vn', NULL, 10),
    (N'FL-2026-000006', 11, 12, N'lab.saigon@filmlab.vn', NULL, 11)
) v(OrderCode, FromStage, ToStage, ByEmail, Note, H)
JOIN ord.Orders o ON o.OrderCode = v.OrderCode
JOIN iam.Users u ON u.Email = v.ByEmail;
GO

-- Thanh toán: số tiền lấy đúng Orders.TotalAmount; đơn 000002 có 1 lần thất bại
INSERT INTO ord.Payments (OrderId, Method, Provider, ProviderTxnId, Amount, Status, PaidAt, FailureReason)
SELECT o.OrderId, v.Method, v.Provider, v.Txn, o.TotalAmount, v.Status,
       CASE WHEN v.Status = N'Succeeded' THEN DATEADD(HOUR, 2, o.CreatedAt) END, v.Reason
FROM (VALUES
    (N'FL-2026-000001', N'EWallet', N'MoMo', N'MOMO-20260001', N'Succeeded', NULL),
    (N'FL-2026-000002', N'Card', N'VNPay', NULL, N'Failed', N'Thẻ bị từ chối'),
    (N'FL-2026-000003', N'Card', N'VNPay', N'VNP-20260003', N'Succeeded', NULL),
    (N'FL-2026-000006', N'BankTransfer', N'Vietcombank', N'VCB-20260006', N'Succeeded', NULL)
) v(OrderCode, Method, Provider, Txn, Status, Reason)
JOIN ord.Orders o ON o.OrderCode = v.OrderCode;
GO

-- Kiểm tra nhanh: tổng tiền khớp chi tiết đơn (THROW nếu seed lệch)
IF EXISTS (SELECT 1 FROM ord.Orders o
           WHERE o.Subtotal <> (SELECT SUM(LineTotal) FROM ord.OrderItems i WHERE i.OrderId = o.OrderId))
    THROW 50399, N'Seed ord: Subtotal không khớp tổng LineTotal', 1;
GO
