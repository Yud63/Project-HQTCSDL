/* ============================================================
   File    : demo/seed_dashboard/01_customers.sql
   Purpose : Seed dashboard C1 - 3 Customer mới + 2 LabOwner mới + địa chỉ cho Customer.
   Re-run  : Chạy lại được (kiểm tra theo Email / RoleCode / Label, không tạo trùng).
   Chạy    : sqlcmd -S localhost -E -C -f 65001 -d FilmLabDB -i demo\seed_dashboard\01_customers.sql
   Lưu ý   : KHÔNG đưa vào 99_run_all.sql / build.cmd. Hash là placeholder, các tài khoản này không đăng nhập web được.
   ============================================================ */
USE FilmLabDB;
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
SET NOCOUNT ON;

DECLARE @Admin INT = (SELECT UserId FROM iam.Users WHERE Email = N'admin@filmlab.vn' AND IsDeleted = 0);
IF @Admin IS NULL
    THROW 50000, N'Thiếu admin@filmlab.vn: chạy build + seed mẫu trước.', 1;

-- ===== 1. Tài khoản =====
DECLARE @acc TABLE (Seq INT IDENTITY(1,1), Email NVARCHAR(255), FullName NVARCHAR(100), Phone NVARCHAR(20), IsLabOwner BIT);
INSERT @acc (Email, FullName, Phone, IsLabOwner) VALUES
    (N'khach.minh@example.com', N'Phạm Quốc Minh',    N'0911000004', 0),
    (N'khach.lan@example.com',  N'Đặng Ngọc Lan',     N'0911000005', 0),
    (N'khach.nam@example.com',  N'Hoàng Văn Nam',     N'0911000006', 0),
    (N'lab.cantho@filmlab.vn',  N'Nguyễn Thanh Phong', N'0900000006', 1),
    (N'lab.dalat@filmlab.vn',   N'Trịnh Mai Anh',     N'0900000007', 1);

DECLARE @i INT = 1, @n INT = (SELECT COUNT(*) FROM @acc);
DECLARE @Email NVARCHAR(255), @Name NVARCHAR(100), @Phone NVARCHAR(20), @IsOwner BIT, @Uid INT;

WHILE @i <= @n
BEGIN
    SELECT @Email = Email, @Name = FullName, @Phone = Phone, @IsOwner = IsLabOwner FROM @acc WHERE Seq = @i;
    SET @Uid = (SELECT UserId FROM iam.Users WHERE Email = @Email AND IsDeleted = 0);

    IF @Uid IS NULL
        EXEC iam.sp_RegisterUser @Email = @Email, @FullName = @Name, @PasswordHash = N'SEED-ONLY-NOT-A-REAL-HASH',
                                 @Phone = @Phone, @NewUserId = @Uid OUTPUT;   -- tự gán role Customer

    IF @IsOwner = 1
       AND NOT EXISTS (SELECT 1 FROM iam.UserRoles ur JOIN iam.Roles r ON r.RoleId = ur.RoleId
                       WHERE ur.UserId = @Uid AND r.RoleCode = N'LabOwner')
        EXEC iam.sp_AssignRole @AdminUserId = @Admin, @UserId = @Uid, @RoleCode = N'LabOwner', @Action = N'Add';

    SET @i += 1;
END;

-- ===== 2. Địa chỉ Customer (cần cho đơn Pickup / Delivery ở C3) =====
DECLARE @adr TABLE (Seq INT IDENTITY(1,1), Email NVARCHAR(255), Label NVARCHAR(50), Recipient NVARCHAR(100), Phone NVARCHAR(20),
                    Line1 NVARCHAR(255), Ward NVARCHAR(100), District NVARCHAR(100), City NVARCHAR(100), Lat FLOAT, Lng FLOAT, IsDefault BIT);
INSERT @adr (Email, Label, Recipient, Phone, Line1, Ward, District, City, Lat, Lng, IsDefault) VALUES
    (N'khach.minh@example.com', N'Nhà',     N'Phạm Quốc Minh', N'0911000004', N'210 Võ Văn Tần',    N'Phường 5',  N'Quận 3',     N'TP. Hồ Chí Minh', 10.7740, 106.6880, 1),
    (N'khach.minh@example.com', N'Công ty', N'Phạm Quốc Minh', N'0911000004', N'72 Lê Thánh Tôn',   N'Bến Nghé',  N'Quận 1',     N'TP. Hồ Chí Minh', 10.7765, 106.7010, 0),
    (N'khach.lan@example.com',  N'Nhà',     N'Đặng Ngọc Lan',  N'0911000005', N'33 Phan Xích Long', N'Phường 2',  N'Phú Nhuận',  N'TP. Hồ Chí Minh', 10.7990, 106.6840, 1),
    (N'khach.nam@example.com',  N'Nhà',     N'Hoàng Văn Nam',  N'0911000006', N'15 Nguyễn Văn Linh', N'Tân Phong', N'Quận 7',     N'TP. Hồ Chí Minh', 10.7300, 106.7060, 1);

SET @i = 1; SET @n = (SELECT COUNT(*) FROM @adr);
DECLARE @Label NVARCHAR(50), @Rec NVARCHAR(100), @L1 NVARCHAR(255), @Ward NVARCHAR(100), @Dist NVARCHAR(100), @City NVARCHAR(100),
        @Lat FLOAT, @Lng FLOAT, @Def BIT, @NewAdr INT;

WHILE @i <= @n
BEGIN
    SELECT @Email = Email, @Label = Label, @Rec = Recipient, @Phone = Phone, @L1 = Line1, @Ward = Ward,
           @Dist = District, @City = City, @Lat = Lat, @Lng = Lng, @Def = IsDefault
    FROM @adr WHERE Seq = @i;
    SET @Uid = (SELECT UserId FROM iam.Users WHERE Email = @Email AND IsDeleted = 0);

    IF NOT EXISTS (SELECT 1 FROM iam.Addresses WHERE UserId = @Uid AND Label = @Label AND IsDeleted = 0)
        EXEC iam.sp_SaveAddress @UserId = @Uid, @RecipientName = @Rec, @Phone = @Phone, @Line1 = @L1, @Ward = @Ward,
                                @District = @Dist, @City = @City, @Label = @Label, @Latitude = @Lat, @Longitude = @Lng,
                                @IsDefault = @Def, @NewAddressId = @NewAdr OUTPUT;
    SET @i += 1;
END;

EXEC sp_set_session_context @key = N'UserId', @value = NULL;
GO

-- ===== 3. Kiểm tra nhanh =====
SELECT u.Email,
       (SELECT STRING_AGG(r.RoleCode, N',') WITHIN GROUP (ORDER BY r.RoleCode)
        FROM iam.UserRoles ur JOIN iam.Roles r ON r.RoleId = ur.RoleId WHERE ur.UserId = u.UserId) AS Roles,
       (SELECT COUNT(*) FROM iam.Addresses a WHERE a.UserId = u.UserId AND a.IsDeleted = 0) AS Addresses
FROM iam.Users u
WHERE u.Email IN (N'khach.minh@example.com', N'khach.lan@example.com', N'khach.nam@example.com',
                  N'lab.cantho@filmlab.vn', N'lab.dalat@filmlab.vn')
ORDER BY u.UserId;

SELECT (SELECT COUNT(*) FROM iam.Users WHERE IsDeleted = 0) AS TotalUsers,
       (SELECT COUNT(*) FROM ord.Orders o JOIN iam.Users u ON u.UserId = o.CustomerId
        WHERE u.Email = N'an.nguyen@example.com') AS OrdersOfAn;
GO