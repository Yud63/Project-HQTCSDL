/* ============================================================
   File    : database/04_seed/sample/lab.sql
   Module  : lab - M2 Lab & Catalog
   Purpose : Dữ liệu mẫu cho test/demo (số dòng gợi ý trong docs/Requirements.md). Tiếng Việt có dấu dùng N'...'.
   Owner   : B (xem docs/Phan-cong.md)
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

-- Film Lab mẫu (2 lab đã duyệt, 1 lab chờ duyệt để demo sp_ApproveLab)
INSERT INTO lab.FilmLabs (OwnerUserId, LabName, Description, AddressLine, Ward, District, City, Location, Phone, Email, OpenHoursJson, SpecialTechniques, DailyCapacityRolls, ApprovalStatus)
SELECT u.UserId, v.LabName, v.Descr, v.Addr, v.Ward, v.District, v.City, geography::Point(v.Lat, v.Lng, 4326), v.Phone, v.Email, v.Hours, v.Tech, v.Cap, v.Status
FROM (VALUES
    (N'lab.saigon@filmlab.vn', N'Sài Gòn Film Lab', N'Lab tráng và scan phim 35mm, 120 tại trung tâm Quận 1. Nhận push/pull process.', N'101 Pasteur', N'Bến Nghé', N'Quận 1', N'TP. Hồ Chí Minh', 10.779, 106.699, N'0900000002', N'hello@saigonfilmlab.vn', N'{"mon-sat": "09:00-18:00", "sun": "closed"}', N'["push", "pull", "cross-process"]', 60, N'Approved'),
    (N'lab.hanoi@filmlab.vn', N'Hà Nội Analog Lab', N'Lab chuyên scan chất lượng cao và tráng phim slide E-6 tại phố cổ.', N'15 Phố Huế', N'Ngô Thị Nhậm', N'Hai Bà Trưng', N'Hà Nội', 21.015, 105.849, N'0900000003', N'contact@hanoianalog.vn', N'{"mon-fri": "08:30-17:30", "sat": "09:00-12:00", "sun": "closed"}', N'["E-6", "scan-ultra"]', 40, N'Approved'),
    (N'lab.hanoi@filmlab.vn', N'Đà Nẵng Retro Lab', N'Lab mới đăng ký, đang chờ Admin duyệt.', N'88 Bạch Đằng', N'Hải Châu 1', N'Hải Châu', N'Đà Nẵng', 16.068, 108.224, N'0900000003', NULL, NULL, NULL, 30, N'Pending')
) v(OwnerEmail, LabName, Descr, Addr, Ward, District, City, Lat, Lng, Phone, Email, Hours, Tech, Cap, Status)
JOIN iam.Users u ON u.Email = v.OwnerEmail;
GO

-- Lịch sử duyệt (lab Pending chưa có quyết định)
INSERT INTO lab.LabApprovals (LabId, ReviewedBy, Decision)
SELECT l.LabId, a.UserId, N'Approved'
FROM lab.FilmLabs l CROSS JOIN (SELECT UserId FROM iam.Users WHERE Email = N'admin@filmlab.vn') a
WHERE l.ApprovalStatus = N'Approved';
GO

-- Gói dịch vụ và giá (LabServices là temporal table: mọi thay đổi giá về sau tự lưu lịch sử)
INSERT INTO lab.LabServices (LabId, ServiceTypeId, FormatId, ProcessCode, PackageName, Description, UnitPrice, PriceUnit, ScanQuality, TurnaroundDays)
SELECT l.LabId, st.ServiceTypeId, ff.FormatId, v.Process, v.Pkg, v.Descr, v.Price, v.Unit, v.ScanQ, v.Days
FROM (VALUES
    (N'Sài Gòn Film Lab', N'DEV', N'35mm', N'C-41', N'Tráng C-41 35mm', N'Tráng phim màu C-41 khổ 35mm', 60000, N'Roll', NULL, 2),
    (N'Sài Gòn Film Lab', N'DEV', N'35mm', N'BW', N'Tráng B&W 35mm', N'Tráng phim đen trắng khổ 35mm', 70000, N'Roll', NULL, 3),
    (N'Sài Gòn Film Lab', N'DEV', N'120', N'C-41', N'Tráng C-41 120', N'Tráng phim màu C-41 khổ 120', 80000, N'Roll', NULL, 2),
    (N'Sài Gòn Film Lab', N'SCAN', N'35mm', N'ANY', N'Scan Basic 35mm', N'Scan 2000px, file JPEG', 80000, N'Roll', N'Basic', 2),
    (N'Sài Gòn Film Lab', N'SCAN', N'35mm', N'ANY', N'Scan High 35mm', N'Scan 4000px, JPEG + TIFF', 150000, N'Roll', N'High', 3),
    (N'Hà Nội Analog Lab', N'DEV', N'35mm', N'C-41', N'Tráng C-41 35mm', N'Tráng phim màu C-41 khổ 35mm', 55000, N'Roll', NULL, 3),
    (N'Hà Nội Analog Lab', N'DEV', N'35mm', N'E-6', N'Tráng E-6 35mm', N'Tráng phim slide E-6', 150000, N'Roll', NULL, 5),
    (N'Hà Nội Analog Lab', N'SCAN', N'35mm', N'ANY', N'Scan Ultra 35mm', N'Scan độ phân giải cao nhất, hiệu chỉnh màu thủ công', 200000, N'Roll', N'Ultra', 5),
    (N'Hà Nội Analog Lab', N'PRINT', N'35mm', N'ANY', N'In ảnh 4x6', N'In ảnh 4x6 inch trên giấy lustre', 5000, N'Frame', NULL, 3)
) v(LabName, ServiceCode, FormatCode, Process, Pkg, Descr, Price, Unit, ScanQ, Days)
JOIN lab.FilmLabs l ON l.LabName = v.LabName
JOIN lab.ServiceTypes st ON st.ServiceCode = v.ServiceCode
JOIN lab.FilmFormats ff ON ff.FormatCode = v.FormatCode;
GO
