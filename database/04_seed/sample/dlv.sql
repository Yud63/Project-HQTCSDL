/* ============================================================
   File    : database/04_seed/sample/dlv.sql
   Module  : dlv - M4 Delivery
   Purpose : Dữ liệu mẫu cho test/demo (số dòng gợi ý trong docs/Requirements.md). Tiếng Việt có dấu dùng N'...'.
   Owner   : A (xem docs/Phan-cong.md)
   Depends : iam, ord
   Re-run  : Chạy sau REBUILD=1. Sample seed không gắn cứng ID của bảng IDENTITY.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;  -- bắt buộc cho filtered index, spatial index, computed column
SET ANSI_NULLS ON;
GO

SET NOCOUNT ON;

-- Chặng giao nhận mẫu: 1 đã giao (đơn 000006), 1 đã phân công (000003), 2 đang chờ phân công (000004)
INSERT INTO dlv.DeliveryRequests (OrderId, Direction, CustomerAddressId, DeliveryPartnerId, Status, Fee, DistanceKm, ScheduledAt, PickedUpAt, DeliveredAt, ExternalTrackingCode, CreatedAt)
SELECT o.OrderId, v.Direction, a.AddressId, p.DeliveryPartnerId, v.Status, v.Fee, v.Dist,
       CASE WHEN v.Status = N'Delivered' THEN DATEADD(DAY, -1, o.CompletedAt) WHEN v.Status = N'Assigned' THEN DATEADD(DAY, 1, SYSUTCDATETIME()) END,
       CASE WHEN v.Status = N'Delivered' THEN DATEADD(HOUR, -5, o.CompletedAt) END,
       CASE WHEN v.Status = N'Delivered' THEN o.CompletedAt END,
       v.Track, DATEADD(HOUR, 3, o.CreatedAt)
FROM (VALUES
    (N'FL-2026-000003', N'Return', N'Nhà', N'Ahamove', N'Assigned', 25000, 4.8, N'AHM-778812'),
    (N'FL-2026-000004', N'Pickup', N'Nhà', NULL, N'Requested', 25000, 3.1, NULL),
    (N'FL-2026-000004', N'Return', N'Nhà', NULL, N'Requested', 25000, 3.1, NULL),
    (N'FL-2026-000006', N'Return', N'Nhà', N'Võ Văn Tài', N'Delivered', 25000, 5.4, NULL)
) v(OrderCode, Direction, AddrLbl, Partner, Status, Fee, Dist, Track)
JOIN ord.Orders o ON o.OrderCode = v.OrderCode
JOIN iam.Addresses a ON a.UserId = o.CustomerId AND a.Label = v.AddrLbl
LEFT JOIN iam.DeliveryPartners p ON p.PartnerName = v.Partner;
GO

-- Nhật ký trạng thái chặng giao
INSERT INTO dlv.DeliveryStatusLog (DeliveryRequestId, FromStatus, ToStatus, ChangedBy, ChangedAt)
SELECT d.DeliveryRequestId, v.FromSt, v.ToSt, o.CustomerId, DATEADD(HOUR, v.H, d.CreatedAt)
FROM (VALUES
    (N'FL-2026-000003', N'Return', NULL, N'Requested', 0),
    (N'FL-2026-000003', N'Return', N'Requested', N'Assigned', 1),
    (N'FL-2026-000004', N'Pickup', NULL, N'Requested', 0),
    (N'FL-2026-000004', N'Return', NULL, N'Requested', 0),
    (N'FL-2026-000006', N'Return', NULL, N'Requested', 0),
    (N'FL-2026-000006', N'Return', N'Requested', N'Assigned', 1),
    (N'FL-2026-000006', N'Return', N'Assigned', N'PickedUp', 2),
    (N'FL-2026-000006', N'Return', N'PickedUp', N'Delivered', 3)
) v(OrderCode, Direction, FromSt, ToSt, H)
JOIN ord.Orders o ON o.OrderCode = v.OrderCode
JOIN dlv.DeliveryRequests d ON d.OrderId = o.OrderId AND d.Direction = v.Direction;
GO

-- Kiểm tra: DeliveryFee của đơn = tổng phí các chặng (THROW nếu seed lệch)
IF EXISTS (SELECT 1 FROM ord.Orders o
           WHERE o.DeliveryFee <> ISNULL((SELECT SUM(Fee) FROM dlv.DeliveryRequests d WHERE d.OrderId = o.OrderId), 0))
    THROW 50499, N'Seed dlv: Orders.DeliveryFee không khớp tổng phí các chặng', 1;
GO
