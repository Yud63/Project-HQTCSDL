/* ============================================================
   File    : demo/seed_dashboard/02_labs.sql
   Purpose : Seed dashboard C2 - 2 lab mới: Cần Thơ Film Lab (Approved), Đà Lạt Retro Lab (Approved -> Suspended) + gói dịch vụ.
   Depends : 01_customers.sql (lab.cantho, lab.dalat đã có role LabOwner)
   Re-run  : Chạy lại được (kiểm tra theo LabName, PackageName và trạng thái hiện tại, không tạo trùng, không duyệt lại).
   Chạy    : sqlcmd -S localhost -E -C -f 65001 -d FilmLabDB -W -i demo\seed_dashboard\02_labs.sql
   Lưu ý   : KHÔNG đưa vào 99_run_all.sql / build.cmd. Không đụng Đà Nẵng Retro Lab (Pending, dùng demo sp_ApproveLab).
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
IF NOT EXISTS (SELECT 1 FROM iam.Users WHERE Email = N'lab.cantho@filmlab.vn' AND IsDeleted = 0)
   OR NOT EXISTS (SELECT 1 FROM iam.Users WHERE Email = N'lab.dalat@filmlab.vn' AND IsDeleted = 0)
    THROW 50000, N'Thiếu lab.cantho / lab.dalat: chạy 01_customers.sql trước.', 1;

-- ===== 1. Hồ sơ lab =====
DECLARE @labs TABLE (Seq INT IDENTITY(1,1), OwnerEmail NVARCHAR(255), LabName NVARCHAR(150), Descr NVARCHAR(1000),
                     Addr NVARCHAR(255), Ward NVARCHAR(100), District NVARCHAR(100), City NVARCHAR(100),
                     Lat FLOAT, Lng FLOAT, Phone NVARCHAR(20), Email NVARCHAR(255),
                     Hours NVARCHAR(MAX), Tech NVARCHAR(MAX), Cap SMALLINT, FinalStatus NVARCHAR(12));
INSERT @labs (OwnerEmail, LabName, Descr, Addr, Ward, District, City, Lat, Lng, Phone, Email, Hours, Tech, Cap, FinalStatus) VALUES
    (N'lab.cantho@filmlab.vn', N'Cần Thơ Film Lab',
     N'Lab tráng và scan phim 35mm, 120 tại trung tâm Ninh Kiều. Nhận tráng C-41, B&W, E-6 và in ảnh.',
     N'45 Hòa Bình', N'Tân An', N'Ninh Kiều', N'Cần Thơ', 10.0340, 105.7880, N'0900000006', N'hello@canthofilmlab.vn',
     N'{"mon-sat": "08:00-18:00", "sun": "closed"}', N'["push", "pull", "E-6"]', 40, N'Approved'),
    (N'lab.dalat@filmlab.vn', N'Đà Lạt Retro Lab',
     N'Lab nhỏ tại Đà Lạt chuyên tráng C-41 và B&W, scan cơ bản. Dùng để demo trạng thái bị đình chỉ.',
     N'12 Trần Phú', N'Phường 3', N'Đà Lạt', N'Lâm Đồng', 11.9400, 108.4380, N'0900000007', N'contact@dalatretro.vn',
     N'{"mon-sun": "09:00-17:00"}', N'["B&W"]', 20, N'Suspended');

DECLARE @i INT = 1, @n INT = (SELECT COUNT(*) FROM @labs);
DECLARE @Owner INT, @OwnerEmail NVARCHAR(255), @LabName NVARCHAR(150), @LabId INT,
        @Descr NVARCHAR(1000), @Addr NVARCHAR(255), @Ward NVARCHAR(100), @District NVARCHAR(100), @City NVARCHAR(100),
        @Lat FLOAT, @Lng FLOAT, @Phone NVARCHAR(20), @LabEmail NVARCHAR(255),
        @Hours NVARCHAR(MAX), @Tech NVARCHAR(MAX), @Cap SMALLINT, @Final NVARCHAR(12), @Cur NVARCHAR(12);

WHILE @i <= @n
BEGIN
    SELECT @OwnerEmail = OwnerEmail, @LabName = LabName, @Descr = Descr, @Addr = Addr, @Ward = Ward, @District = District,
           @City = City, @Lat = Lat, @Lng = Lng, @Phone = Phone, @LabEmail = Email, @Hours = Hours, @Tech = Tech, @Cap = Cap
    FROM @labs WHERE Seq = @i;
    SET @Owner = (SELECT UserId FROM iam.Users WHERE Email = @OwnerEmail AND IsDeleted = 0);
    SET @LabId = (SELECT LabId FROM lab.FilmLabs WHERE LabName = @LabName AND IsDeleted = 0);

    IF @LabId IS NULL
        EXEC lab.sp_SaveLabProfile @OwnerUserId = @Owner, @LabName = @LabName, @AddressLine = @Addr, @Ward = @Ward,
                                   @District = @District, @City = @City, @Description = @Descr,
                                   @Latitude = @Lat, @Longitude = @Lng, @Phone = @Phone, @Email = @LabEmail,
                                   @OpenHoursJson = @Hours, @SpecialTechniques = @Tech, @DailyCapacityRolls = @Cap,
                                   @NewLabId = @LabId OUTPUT;     -- lab mới luôn là Pending
    SET @i += 1;
END;

-- ===== 2. Gói dịch vụ =====
DECLARE @svc TABLE (Seq INT IDENTITY(1,1), LabName NVARCHAR(150), ServiceCode NVARCHAR(20), FormatCode NVARCHAR(10),
                    Process NVARCHAR(10), Pkg NVARCHAR(150), Descr NVARCHAR(500), Price DECIMAL(18,0),
                    Unit NVARCHAR(5), ScanQ NVARCHAR(5), Days TINYINT);
INSERT @svc (LabName, ServiceCode, FormatCode, Process, Pkg, Descr, Price, Unit, ScanQ, Days) VALUES
    (N'Cần Thơ Film Lab', N'DEV',   N'35mm', N'C-41', N'Tráng C-41 35mm', N'Tráng phim màu C-41 khổ 35mm', 50000, N'Roll', NULL, 2),
    (N'Cần Thơ Film Lab', N'DEV',   N'35mm', N'BW',   N'Tráng B&W 35mm',  N'Tráng phim đen trắng khổ 35mm', 65000, N'Roll', NULL, 3),
    (N'Cần Thơ Film Lab', N'DEV',   N'35mm', N'E-6',  N'Tráng E-6 35mm',  N'Tráng phim slide E-6 khổ 35mm', 140000, N'Roll', NULL, 4),
    (N'Cần Thơ Film Lab', N'DEV',   N'120',  N'C-41', N'Tráng C-41 120',  N'Tráng phim màu C-41 khổ 120', 75000, N'Roll', NULL, 2),
    (N'Cần Thơ Film Lab', N'SCAN',  N'35mm', N'ANY',  N'Scan Basic 35mm', N'Scan 2000px, file JPEG', 70000, N'Roll', N'Basic', 2),
    (N'Cần Thơ Film Lab', N'SCAN',  N'35mm', N'ANY',  N'Scan High 35mm',  N'Scan 4000px, JPEG + TIFF', 140000, N'Roll', N'High', 3),
    (N'Cần Thơ Film Lab', N'PRINT', N'35mm', N'ANY',  N'In ảnh 4x6',      N'In ảnh 4x6 inch trên giấy lustre', 4500, N'Frame', NULL, 3),
    (N'Đà Lạt Retro Lab', N'DEV',   N'35mm', N'C-41', N'Tráng C-41 35mm', N'Tráng phim màu C-41 khổ 35mm', 65000, N'Roll', NULL, 3),
    (N'Đà Lạt Retro Lab', N'DEV',   N'35mm', N'BW',   N'Tráng B&W 35mm',  N'Tráng phim đen trắng khổ 35mm', 80000, N'Roll', NULL, 4),
    (N'Đà Lạt Retro Lab', N'SCAN',  N'35mm', N'ANY',  N'Scan Basic 35mm', N'Scan 2000px, file JPEG', 90000, N'Roll', N'Basic', 3);

SET @i = 1; SET @n = (SELECT COUNT(*) FROM @svc);
DECLARE @Pkg NVARCHAR(150), @SvcCode NVARCHAR(20), @FmtCode NVARCHAR(10), @Proc NVARCHAR(10), @SvcDescr NVARCHAR(500),
        @Price DECIMAL(18,0), @Unit NVARCHAR(5), @ScanQ NVARCHAR(5), @Days TINYINT,
        @SvcTypeId INT, @FmtId INT, @NewSvc INT;

WHILE @i <= @n
BEGIN
    SELECT @LabName = LabName, @SvcCode = ServiceCode, @FmtCode = FormatCode, @Proc = Process, @Pkg = Pkg,
           @SvcDescr = Descr, @Price = Price, @Unit = Unit, @ScanQ = ScanQ, @Days = Days
    FROM @svc WHERE Seq = @i;

    SELECT @LabId = LabId, @Owner = OwnerUserId FROM lab.FilmLabs WHERE LabName = @LabName AND IsDeleted = 0;
    SET @SvcTypeId = (SELECT ServiceTypeId FROM lab.ServiceTypes WHERE ServiceCode = @SvcCode);
    SET @FmtId = (SELECT FormatId FROM lab.FilmFormats WHERE FormatCode = @FmtCode);

    IF NOT EXISTS (SELECT 1 FROM lab.LabServices WHERE LabId = @LabId AND PackageName = @Pkg)
        EXEC lab.sp_SaveLabService @OwnerUserId = @Owner, @LabId = @LabId, @ServiceTypeId = @SvcTypeId, @FormatId = @FmtId,
                                   @PackageName = @Pkg, @UnitPrice = @Price, @TurnaroundDays = @Days,
                                   @ProcessCode = @Proc, @Description = @SvcDescr, @PriceUnit = @Unit,
                                   @ScanQuality = @ScanQ, @NewLabServiceId = @NewSvc OUTPUT;
    SET @i += 1;
END;

-- ===== 3. Duyệt / đình chỉ (theo trạng thái hiện tại nên chạy lại không duyệt trùng) =====
SET @i = 1; SET @n = (SELECT COUNT(*) FROM @labs);
WHILE @i <= @n
BEGIN
    SELECT @LabName = LabName, @Final = FinalStatus FROM @labs WHERE Seq = @i;
    SET @LabId = (SELECT LabId FROM lab.FilmLabs WHERE LabName = @LabName AND IsDeleted = 0);

    SET @Cur = (SELECT ApprovalStatus FROM lab.FilmLabs WHERE LabId = @LabId);
    IF @Cur = N'Pending'
        EXEC lab.sp_ApproveLab @LabId = @LabId, @AdminUserId = @Admin, @Decision = N'Approved';

    SET @Cur = (SELECT ApprovalStatus FROM lab.FilmLabs WHERE LabId = @LabId);
    IF @Final = N'Suspended' AND @Cur = N'Approved'
        EXEC lab.sp_ApproveLab @LabId = @LabId, @AdminUserId = @Admin, @Decision = N'Suspended',
                               @Reason = N'Demo dashboard: lab trả phim trễ hạn nhiều lần, tạm đình chỉ chờ xử lý.';
    SET @i += 1;
END;

EXEC sp_set_session_context @key = N'UserId', @value = NULL;
GO

-- ===== 4. Kiểm tra nhanh =====
SELECT l.LabName, l.City, l.ApprovalStatus, l.DailyCapacityRolls AS Cap,
       (SELECT COUNT(*) FROM lab.LabServices s WHERE s.LabId = l.LabId AND s.IsDeleted = 0) AS Services,
       (SELECT COUNT(*) FROM lab.LabApprovals a WHERE a.LabId = l.LabId) AS Approvals
FROM lab.FilmLabs l
WHERE l.IsDeleted = 0
ORDER BY l.LabId;

SELECT ApprovalStatus, COUNT(*) AS Labs
FROM lab.FilmLabs WHERE IsDeleted = 0
GROUP BY ApprovalStatus ORDER BY ApprovalStatus;

SELECT l.LabName, a.Decision, a.Reason
FROM lab.LabApprovals a JOIN lab.FilmLabs l ON l.LabId = a.LabId
WHERE l.LabName IN (N'Cần Thơ Film Lab', N'Đà Lạt Retro Lab')
ORDER BY a.ApprovalId;
GO