/* ============================================================
   File    : database/04_seed/sample/iam.sql
   Module  : iam - M1 Identity & Access
   Purpose : Dữ liệu mẫu cho test/demo (số dòng gợi ý trong docs/Requirements.md). Tiếng Việt có dấu dùng N'...'.
   Owner   : A (xem docs/Phan-cong.md)
   Depends : (gốc)
   Re-run  : Chạy sau REBUILD=1. Sample seed không gắn cứng ID của bảng IDENTITY.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;  -- bắt buộc cho filtered index, spatial index, computed column
SET ANSI_NULLS ON;
GO

SET NOCOUNT ON;

-- Dữ liệu mẫu iam. Không gắn cứng ID IDENTITY: tra bằng Email / RoleCode (Conventions mục 8).
-- Mật khẩu là hash giả, chỉ để demo; tầng web tạo hash thật khi đăng ký.
INSERT INTO iam.Users (Email, AuthProvider, PasswordHash, FullName, Phone) VALUES
    (N'admin@filmlab.vn', N'Local', N'SEED-ONLY-NOT-A-REAL-HASH', N'Nguyễn Quản Trị', N'0900000001'),
    (N'lab.saigon@filmlab.vn', N'Local', N'SEED-ONLY-NOT-A-REAL-HASH', N'Trần Minh Khoa', N'0900000002'),
    (N'lab.hanoi@filmlab.vn', N'Local', N'SEED-ONLY-NOT-A-REAL-HASH', N'Lê Thu Hà', N'0900000003'),
    (N'expert@filmlab.vn', N'Local', N'SEED-ONLY-NOT-A-REAL-HASH', N'Phạm Quang Huy', N'0900000004'),
    (N'shipper@filmlab.vn', N'Local', N'SEED-ONLY-NOT-A-REAL-HASH', N'Võ Văn Tài', N'0900000005'),
    (N'an.nguyen@example.com', N'Local', N'SEED-ONLY-NOT-A-REAL-HASH', N'Nguyễn Hoàng An', N'0911000001'),
    (N'binh.tran@example.com', N'Local', N'SEED-ONLY-NOT-A-REAL-HASH', N'Trần Gia Bình', N'0911000002'),
    (N'chi.le@example.com', N'Google', NULL, N'Lê Phương Chi', N'0911000003');
GO

-- Gán vai trò (AssignedBy NULL = tự đăng ký; riêng quyền đặc biệt do Admin gán)
INSERT INTO iam.UserRoles (UserId, RoleId, AssignedBy)
SELECT u.UserId, r.RoleId, CASE WHEN r.RoleCode IN ('Admin','LabOwner','Expert','Delivery') THEN a.UserId END
FROM (VALUES
    (N'admin@filmlab.vn',N'Admin'),
    (N'lab.saigon@filmlab.vn',N'LabOwner'), (N'lab.saigon@filmlab.vn',N'Customer'),
    (N'lab.hanoi@filmlab.vn',N'LabOwner'),
    (N'expert@filmlab.vn',N'Expert'), (N'expert@filmlab.vn',N'Customer'),
    (N'shipper@filmlab.vn',N'Delivery'),
    (N'an.nguyen@example.com',N'Customer'), (N'binh.tran@example.com',N'Customer'), (N'chi.le@example.com',N'Customer')
) v(Email, RoleCode)
JOIN iam.Users u ON u.Email = v.Email
JOIN iam.Roles r ON r.RoleCode = v.RoleCode
CROSS JOIN (SELECT UserId FROM iam.Users WHERE Email = N'admin@filmlab.vn') a;
GO

-- Địa chỉ (TP.HCM và Hà Nội); mỗi user tối đa 1 địa chỉ mặc định
INSERT INTO iam.Addresses (UserId, Label, RecipientName, Phone, Line1, Ward, District, City, Location, IsDefault)
SELECT u.UserId, v.Label, v.Recipient, v.Phone, v.Line1, v.Ward, v.District, v.City,
       geography::Point(v.Lat, v.Lng, 4326), v.IsDefault
FROM (VALUES
    (N'an.nguyen@example.com',   N'Nhà',      N'Nguyễn Hoàng An', N'0911000001', N'12 Nguyễn Huệ',        N'Bến Nghé',  N'Quận 1',       N'TP. Hồ Chí Minh', 10.7740, 106.7040, 1),
    (N'an.nguyen@example.com',   N'Công ty',  N'Nguyễn Hoàng An', N'0911000001', N'45 Lê Lợi',            N'Bến Thành', N'Quận 1',       N'TP. Hồ Chí Minh', 10.7730, 106.6980, 0),
    (N'binh.tran@example.com',   N'Nhà',      N'Trần Gia Bình',   N'0911000002', N'88 Cách Mạng Tháng 8', N'Phường 6',  N'Quận 3',       N'TP. Hồ Chí Minh', 10.7800, 106.6850, 1),
    (N'chi.le@example.com',      N'Nhà',      N'Lê Phương Chi',   N'0911000003', N'25 Hàng Bài',          N'Hàng Bài',  N'Hoàn Kiếm',    N'Hà Nội',          21.0230, 105.8530, 1),
    (N'lab.saigon@filmlab.vn',   N'Lab',      N'Trần Minh Khoa',  N'0900000002', N'101 Pasteur',          N'Bến Nghé',  N'Quận 1',       N'TP. Hồ Chí Minh', 10.7790, 106.6990, 1)
) v(Email, Label, Recipient, Phone, Line1, Ward, District, City, Lat, Lng, IsDefault)
JOIN iam.Users u ON u.Email = v.Email;
GO

-- Hồ sơ chuyên gia (đã xác minh bởi Admin)
INSERT INTO iam.ExpertProfiles (UserId, Bio, Expertise, YearsExperience, PortfolioUrl, IsVerified, VerifiedBy, VerifiedAt)
SELECT e.UserId, N'Nhiếp ảnh gia phim 10 năm, chuyên street và chân dung.', N'Street, chân dung, tráng phim tại nhà', 10,
       N'https://example.com/portfolio/huy', 1, a.UserId, SYSUTCDATETIME()
FROM iam.Users e CROSS JOIN iam.Users a
WHERE e.Email = N'expert@filmlab.vn' AND a.Email = N'admin@filmlab.vn';
GO

-- Đối tác giao nhận: 2 nền tảng + 1 shipper cá nhân (bắt buộc có UserId)
INSERT INTO iam.DeliveryPartners (ProviderType, PartnerName, UserId, VehicleType, PlateNumber, ApiCode)
VALUES (N'Platform', N'Ahamove', NULL, NULL, NULL, N'AHAMOVE'),
       (N'Platform', N'Lalamove', NULL, NULL, NULL, N'LALAMOVE');
INSERT INTO iam.DeliveryPartners (ProviderType, PartnerName, UserId, VehicleType, PlateNumber)
SELECT N'Individual', u.FullName, u.UserId, N'Xe máy', N'59X1-123.45'
FROM iam.Users u WHERE u.Email = N'shipper@filmlab.vn';
GO
