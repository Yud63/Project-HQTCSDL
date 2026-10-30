/* ============================================================
   File    : database/04_seed/sample/audit.sql
   Module  : audit - M10 System / Audit
   Purpose : Dữ liệu mẫu cho test/demo (số dòng gợi ý trong docs/Requirements.md). Tiếng Việt có dấu dùng N'...'.
   Owner   : A (xem docs/Phan-cong.md)
   Depends : (không FK)
   Re-run  : Chạy sau REBUILD=1. Sample seed không gắn cứng ID của bảng IDENTITY.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;  -- bắt buộc cho filtered index, spatial index, computed column
SET ANSI_NULLS ON;
GO

SET NOCOUNT ON;

-- Nhật ký thay đổi mẫu (trigger *_Audit ghi tự động ở Đợt 6; ChangedBy = Admin)
INSERT INTO audit.AuditLogs (TableSchema, TableName, PrimaryKeyValue, Action, ChangedBy, OldValues, NewValues, ChangedAt)
SELECT v.Sch, v.Tbl, v.Pk, v.Act, a.UserId, v.OldV, v.NewV, DATEADD(DAY, -v.DaysAgo, SYSUTCDATETIME())
FROM (VALUES
    (N'ord', N'Orders', (SELECT CAST((SELECT OrderId FROM ord.Orders WHERE OrderCode = N'FL-2026-000001') AS NVARCHAR(100))), N'INSERT', NULL, N'{"OrderCode": "FL-2026-000001", "StageId": 1}', 20),
    (N'ord', N'Orders', (SELECT CAST((SELECT OrderId FROM ord.Orders WHERE OrderCode = N'FL-2026-000001') AS NVARCHAR(100))), N'UPDATE', N'{"StageId": 11}', N'{"StageId": 12, "PaymentStatus": "Paid"}', 12),
    (N'lab', N'FilmLabs', (SELECT CAST((SELECT LabId FROM lab.FilmLabs WHERE LabName = N'Hà Nội Analog Lab') AS NVARCHAR(100))), N'UPDATE', N'{"ApprovalStatus": "Pending"}', N'{"ApprovalStatus": "Approved"}', 30),
    (N'mkt', N'Listings', (SELECT CAST((SELECT ListingId FROM mkt.Listings WHERE Title = N'Pentax K1000 body') AS NVARCHAR(100))), N'UPDATE', N'{"Status": "Active"}', N'{"Status": "Sold"}', 2)
) v(Sch, Tbl, Pk, Act, OldV, NewV, DaysAgo)
CROSS JOIN (SELECT UserId FROM iam.Users WHERE Email = N'admin@filmlab.vn') a;
GO
