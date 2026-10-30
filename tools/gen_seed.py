# -*- coding: utf-8 -*-
"""Sinh 04_seed/reference/*.sql (danh mục cố định) và sample cho iam + FeeConfigs. Chạy: python tools/gen_seed.py"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_sql as G
SEED = os.path.join(G.ROOT, "04_seed")
HDR = G.SETOPT + "\nSET NOCOUNT ON;\n\n"
NONE = "-- Không có dữ liệu danh mục cố định cho module này.\n"

def ins(table, cols, rows):
    out = "INSERT INTO %s (%s) VALUES\n" % (table, ", ".join(cols))
    out += ",\n".join("    (" + ", ".join(r) + ")" for r in rows) + ";\nGO\n"
    return out
def n(s): return "N'" + s.replace("'", "''") + "'"

ref = {}
ref["iam"] = HDR + "-- Vai trò hệ thống (ID cố định, D-04: user có thể có nhiều role)\n" + ins("iam.Roles", ["RoleId","RoleCode","RoleName","Description"], [
 ("1",n("Customer"),n("Khách hàng"),n("Đặt đơn, xem scan, mua bán, tham gia cộng đồng")),
 ("2",n("LabOwner"),n("Chủ Film Lab"),n("Quản lý lab, dịch vụ, xử lý đơn, upload scan")),
 ("3",n("Expert"),n("Chuyên gia"),n("Viết bài, tổ chức workshop, đóng góp tri thức cho AI")),
 ("4",n("Delivery"),n("Giao nhận"),n("Nhận và cập nhật các chặng lấy/trả phim")),
 ("5",n("Admin"),n("Quản trị viên"),n("Duyệt lab, kiểm duyệt, xử lý khiếu nại, cấu hình phí"))])
ref["lab"] = HDR + "-- Định dạng phim\n" + ins("lab.FilmFormats", ["FormatId","FormatCode","FormatName"], [
 ("1",n("35mm"),n("Phim 35mm (135)")),("2",n("120"),n("Phim cuộn 120 (medium format)")),
 ("3",n("4x5"),n("Phim tấm 4x5 inch")),("4",n("110"),n("Phim cartridge 110")),("5",n("APS"),n("Phim APS"))]) \
 + "\n-- Dịch vụ\n" + ins("lab.ServiceTypes", ["ServiceTypeId","ServiceCode","ServiceName","Category","Description"], [
 ("1",n("DEV"),n("Tráng phim"),n("Develop"),n("Tráng hóa chất (C-41, E-6, B&W, ECN-2)")),
 ("2",n("SCAN"),n("Scan phim"),n("Scan"),n("Scan thành file số")),
 ("3",n("PRINT"),n("In ảnh"),n("Print"),n("In ảnh từ phim hoặc file scan")),
 ("4",n("EXTRA"),n("Dịch vụ phụ trợ"),n("Other"),n("Cắt phim, sleeve, hộp lưu trữ..."))]) \
 + "\n-- Loại phim phổ biến\n" + ins("lab.FilmStocks", ["StockId","Brand","StockName","Iso","FilmType","ProcessCode"], [
 ("1",n("Kodak"),n("Portra 160"),"160",n("ColorNegative"),n("C-41")),
 ("2",n("Kodak"),n("Portra 400"),"400",n("ColorNegative"),n("C-41")),
 ("3",n("Kodak"),n("Portra 800"),"800",n("ColorNegative"),n("C-41")),
 ("4",n("Kodak"),n("Gold 200"),"200",n("ColorNegative"),n("C-41")),
 ("5",n("Kodak"),n("Ultramax 400"),"400",n("ColorNegative"),n("C-41")),
 ("6",n("Kodak"),n("Ektar 100"),"100",n("ColorNegative"),n("C-41")),
 ("7",n("Fujifilm"),n("Superia X-tra 400"),"400",n("ColorNegative"),n("C-41")),
 ("8",n("Kodak"),n("Tri-X 400"),"400",n("BlackWhite"),n("BW")),
 ("9",n("Kodak"),n("T-Max 100"),"100",n("BlackWhite"),n("BW")),
 ("10",n("Ilford"),n("HP5 Plus 400"),"400",n("BlackWhite"),n("BW")),
 ("11",n("Ilford"),n("FP4 Plus 125"),"125",n("BlackWhite"),n("BW")),
 ("12",n("Ilford"),n("Delta 3200"),"3200",n("BlackWhite"),n("BW")),
 ("13",n("Kodak"),n("Ektachrome E100"),"100",n("ColorSlide"),n("E-6")),
 ("14",n("Fujifilm"),n("Velvia 50"),"50",n("ColorSlide"),n("E-6")),
 ("15",n("Kodak"),n("Vision3 500T"),"500",n("ColorNegative"),n("ECN-2"))])
ref["ord"] = HDR + "-- 13 giai đoạn xử lý đơn (docs/Requirements.md mục C.2)\n" + ins("ord.ProcessingStages", ["StageId","StageCode","StageName","SortOrder","IsTerminal"], [
 ("1",n("Pending"),n("Chờ lab xác nhận"),"10","0"),("2",n("Confirmed"),n("Lab đã xác nhận"),"20","0"),
 ("3",n("AwaitingFilm"),n("Chờ nhận phim"),"30","0"),("4",n("FilmReceived"),n("Đã nhận phim tại lab"),"40","0"),
 ("5",n("Developing"),n("Tráng hóa chất"),"50","0"),("6",n("Washing"),n("Rửa"),"60","0"),
 ("7",n("Drying"),n("Sấy"),"70","0"),("8",n("Scanning"),n("Scan"),"80","0"),
 ("9",n("ImagePrep"),n("Chuẩn bị ảnh"),"90","0"),("10",n("QualityCheck"),n("Kiểm tra chất lượng"),"100","0"),
 ("11",n("ReadyToReturn"),n("Sẵn sàng trả phim/ảnh"),"110","0"),("12",n("Completed"),n("Hoàn tất"),"120","1"),
 ("13",n("Cancelled"),n("Đã hủy"),"255","1")])
ref["mkt"] = HDR + "-- Danh mục loại hàng Marketplace\n" + ins("mkt.ListingCategories", ["CategoryId","CategoryCode","CategoryName"], [
 ("1",n("CAMERA"),n("Máy ảnh")),("2",n("LENS"),n("Ống kính")),("3",n("FILM"),n("Phim")),
 ("4",n("FLASH"),n("Đèn flash")),("5",n("ACCESSORY"),n("Phụ kiện")),("6",n("OTHER"),n("Khác"))])

HASH = n("SEED-ONLY-NOT-A-REAL-HASH")
iam_sample = HDR + """-- Dữ liệu mẫu iam. Không gắn cứng ID IDENTITY: tra bằng Email / RoleCode (Conventions mục 8).
-- Mật khẩu là hash giả, chỉ để demo; tầng web tạo hash thật khi đăng ký.
""" + ins("iam.Users", ["Email","AuthProvider","PasswordHash","FullName","Phone"], [
 (n("admin@filmlab.vn"),n("Local"),HASH,n("Nguyễn Quản Trị"),n("0900000001")),
 (n("lab.saigon@filmlab.vn"),n("Local"),HASH,n("Trần Minh Khoa"),n("0900000002")),
 (n("lab.hanoi@filmlab.vn"),n("Local"),HASH,n("Lê Thu Hà"),n("0900000003")),
 (n("expert@filmlab.vn"),n("Local"),HASH,n("Phạm Quang Huy"),n("0900000004")),
 (n("shipper@filmlab.vn"),n("Local"),HASH,n("Võ Văn Tài"),n("0900000005")),
 (n("an.nguyen@example.com"),n("Local"),HASH,n("Nguyễn Hoàng An"),n("0911000001")),
 (n("binh.tran@example.com"),n("Local"),HASH,n("Trần Gia Bình"),n("0911000002")),
 (n("chi.le@example.com"),n("Google"),"NULL",n("Lê Phương Chi"),n("0911000003"))]) + """
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
"""
ord_sample = HDR + """-- Cấu hình phí mặc định toàn hệ thống (D-01, D-06, D-12). Cần Admin của iam sample.
INSERT INTO ord.FeeConfigs (FeeType, Rate, FixedAmount, ScopeLabId, EffectiveFrom, CreatedBy)
SELECT v.FeeType, v.Rate, v.FixedAmount, NULL, '2026-01-01', a.UserId
FROM (VALUES (N'PlatformCommission', 0.1000, NULL),
             (N'MarketplaceFee',     0.0500, NULL),
             (N'DeliveryBase',       NULL,   25000)) v(FeeType, Rate, FixedAmount)
CROSS JOIN (SELECT UserId FROM iam.Users WHERE Email = N'admin@filmlab.vn') a;
GO
"""

def main():
    for key in G.S.MODULE_ORDER + ["ord_feedback"]:
        G.write_into(os.path.join(SEED, "reference", key + ".sql"), ref.get(key, NONE))
    G.write_into(os.path.join(SEED, "sample", "iam.sql"), iam_sample)
    print("OK seed")
if __name__ == "__main__":
    main()
