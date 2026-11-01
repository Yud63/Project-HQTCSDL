/* ============================================================
   File    : tests/18_manage_test.sql
   Purpose : Kiểm tra 9 procedure quản trị Đợt 8 + GRANT thật dưới role. Mong đợi 31 PASS.
   Cách chạy (trong thư mục tests, KHÔNG dùng -b):
     sqlcmd -S localhost -E -C -f 65001 -d FilmLabDB -i 18_manage_test.sql | find /c "PASS:"
   ============================================================ */
USE FilmLabDB;
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
SET NOCOUNT ON;

IF USER_ID(N'u_cus') IS NOT NULL DROP USER u_cus;
IF USER_ID(N'u_lab') IS NOT NULL DROP USER u_lab;
IF USER_ID(N'u_exp') IS NOT NULL DROP USER u_exp;
CREATE USER u_cus WITHOUT LOGIN;  ALTER ROLE role_Customer ADD MEMBER u_cus;
CREATE USER u_lab WITHOUT LOGIN;  ALTER ROLE role_LabOwner ADD MEMBER u_lab;
CREATE USER u_exp WITHOUT LOGIN;  ALTER ROLE role_Expert   ADD MEMBER u_exp;

DECLARE @admin INT = (SELECT UserId FROM iam.Users WHERE Email = N'admin@filmlab.vn');
DECLARE @exp   INT = (SELECT UserId FROM iam.Users WHERE Email = N'expert@filmlab.vn');
DECLARE @ship  INT = (SELECT UserId FROM iam.Users WHERE Email = N'shipper@filmlab.vn');
DECLARE @an    INT = (SELECT UserId FROM iam.Users WHERE Email = N'an.nguyen@example.com');
DECLARE @binh  INT = (SELECT UserId FROM iam.Users WHERE Email = N'binh.tran@example.com');
DECLARE @sg    INT = (SELECT LabId FROM lab.FilmLabs WHERE LabName = N'Sài Gòn Film Lab');
DECLARE @sgOwner INT = (SELECT OwnerUserId FROM lab.FilmLabs WHERE LabId = @sg);
DECLARE @other INT = (SELECT TOP 1 ur.UserId FROM iam.UserRoles ur JOIN iam.Roles r ON r.RoleId = ur.RoleId
                      WHERE r.RoleCode = N'LabOwner' AND ur.UserId <> @sgOwner ORDER BY ur.UserId);
DECLARE @stDev  INT = (SELECT TOP 1 ServiceTypeId FROM lab.ServiceTypes WHERE Category = N'Develop' ORDER BY ServiceTypeId);
DECLARE @stScan INT = (SELECT TOP 1 ServiceTypeId FROM lab.ServiceTypes WHERE Category = N'Scan' ORDER BY ServiceTypeId);
DECLARE @fmt    INT = (SELECT TOP 1 FormatId FROM lab.FilmFormats ORDER BY FormatId);
DECLARE @pkg    NVARCHAR(150) = (SELECT TOP 1 PackageName FROM lab.LabServices WHERE LabId = @sg AND IsDeleted = 0 ORDER BY LabServiceId);
DECLARE @st DATETIME2(0) = DATEADD(DAY, 30, SYSUTCDATETIME());
DECLARE @en DATETIME2(0) = DATEADD(HOUR, 3, DATEADD(DAY, 30, SYSUTCDATETIME()));
DECLARE @e INT, @id INT, @x INT, @y INT, @s NVARCHAR(30), @n NVARCHAR(150), @d DATE, @d2 DATE, @sc UNIQUEIDENTIFIER, @scOwner INT, @alb INT;

-- ===== LAB =====
-- T1-T2: tạo lab mới (Pending), sửa lab giữ nguyên ApprovalStatus
BEGIN TRAN;
EXEC lab.sp_SaveLabProfile @OwnerUserId = @sgOwner, @LabName = N'Lab Test T1', @AddressLine = N'1 Test', @Ward = N'P1', @District = N'Q1', @City = N'HCM', @NewLabId = @id OUTPUT;
SET @s = (SELECT ApprovalStatus FROM lab.FilmLabs WHERE LabId = @id);
SET @x = (SELECT OwnerUserId FROM lab.FilmLabs WHERE LabId = @id);
IF @id IS NOT NULL AND @s = N'Pending' AND @x = @sgOwner PRINT N'PASS: T1 Tạo lab mới ở trạng thái Pending';
ELSE PRINT N'FAIL: T1 Tạo lab mới ở trạng thái Pending';
SET @s = (SELECT ApprovalStatus FROM lab.FilmLabs WHERE LabId = @sg);
EXEC lab.sp_SaveLabProfile @OwnerUserId = @sgOwner, @LabId = @sg, @LabName = N'Sài Gòn Film Lab (T2)', @AddressLine = N'1 Test', @Ward = N'P1', @District = N'Q1', @City = N'HCM';
SET @n = (SELECT LabName FROM lab.FilmLabs WHERE LabId = @sg);
IF @n = N'Sài Gòn Film Lab (T2)' AND (SELECT ApprovalStatus FROM lab.FilmLabs WHERE LabId = @sg) = @s PRINT N'PASS: T2 Sửa lab không đổi ApprovalStatus';
ELSE PRINT N'FAIL: T2 Sửa lab không đổi ApprovalStatus';
ROLLBACK;

-- T3: Customer không tạo được lab
SET @e = NULL;
BEGIN TRY EXEC lab.sp_SaveLabProfile @OwnerUserId = @an, @LabName = N'Lab Test', @AddressLine = N'1 Test', @Ward = N'P1', @District = N'Q1', @City = N'HCM'; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50203 PRINT N'PASS: T3 Customer không tạo được lab (50203)'; ELSE PRINT N'FAIL: T3 Customer không tạo được lab';

-- T4: chủ lab khác không sửa được lab
SET @e = NULL;
BEGIN TRY EXEC lab.sp_SaveLabProfile @OwnerUserId = @other, @LabId = @sg, @LabName = N'Hack', @AddressLine = N'1 Test', @Ward = N'P1', @District = N'Q1', @City = N'HCM'; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50203 PRINT N'PASS: T4 Chủ lab khác không sửa được lab (50203)'; ELSE PRINT N'FAIL: T4 Chủ lab khác không sửa được lab';

-- T5: JSON sai
SET @e = NULL;
BEGIN TRY EXEC lab.sp_SaveLabProfile @OwnerUserId = @sgOwner, @LabId = @sg, @LabName = N'X', @AddressLine = N'1 Test', @Ward = N'P1', @District = N'Q1', @City = N'HCM', @OpenHoursJson = N'{bad'; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50205 PRINT N'PASS: T5 OpenHoursJson sai bị từ chối (50205)'; ELSE PRINT N'FAIL: T5 OpenHoursJson sai bị từ chối';

-- T6-T8: gói dịch vụ tạo, sửa giá, xóa mềm
BEGIN TRAN;
EXEC lab.sp_SaveLabService @OwnerUserId = @sgOwner, @LabId = @sg, @ServiceTypeId = @stDev, @FormatId = @fmt, @PackageName = N'Gói test T6', @UnitPrice = 55000, @TurnaroundDays = 3, @NewLabServiceId = @id OUTPUT;
IF @id IS NOT NULL AND EXISTS (SELECT 1 FROM lab.LabServices WHERE LabServiceId = @id AND UnitPrice = 55000 AND IsActive = 1 AND IsDeleted = 0)
    PRINT N'PASS: T6 Tạo gói dịch vụ'; ELSE PRINT N'FAIL: T6 Tạo gói dịch vụ';
EXEC lab.sp_SaveLabService @OwnerUserId = @sgOwner, @LabId = @sg, @LabServiceId = @id, @ServiceTypeId = @stDev, @FormatId = @fmt, @PackageName = N'Gói test T6', @UnitPrice = 60000, @TurnaroundDays = 3;
IF EXISTS (SELECT 1 FROM lab.LabServices WHERE LabServiceId = @id AND UnitPrice = 60000) PRINT N'PASS: T7 Sửa giá gói dịch vụ'; ELSE PRINT N'FAIL: T7 Sửa giá gói dịch vụ';
EXEC lab.sp_SaveLabService @OwnerUserId = @sgOwner, @LabId = @sg, @LabServiceId = @id, @ServiceTypeId = @stDev, @FormatId = @fmt, @PackageName = N'Gói test T6', @UnitPrice = 60000, @TurnaroundDays = 3, @IsDeleted = 1;
IF EXISTS (SELECT 1 FROM lab.LabServices WHERE LabServiceId = @id AND IsDeleted = 1 AND IsActive = 0) PRINT N'PASS: T8 Xóa mềm gói dịch vụ'; ELSE PRINT N'FAIL: T8 Xóa mềm gói dịch vụ';
ROLLBACK;

-- T9: gói Scan thiếu ScanQuality
SET @e = NULL;
BEGIN TRY EXEC lab.sp_SaveLabService @OwnerUserId = @sgOwner, @LabId = @sg, @ServiceTypeId = @stScan, @FormatId = @fmt, @PackageName = N'Scan test T9', @UnitPrice = 1000, @TurnaroundDays = 2; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50205 PRINT N'PASS: T9 Gói Scan thiếu ScanQuality bị từ chối (50205)'; ELSE PRINT N'FAIL: T9 Gói Scan thiếu ScanQuality';

-- T10: trùng tên gói trong lab
SET @e = NULL;
BEGIN TRY EXEC lab.sp_SaveLabService @OwnerUserId = @sgOwner, @LabId = @sg, @ServiceTypeId = @stDev, @FormatId = @fmt, @PackageName = @pkg, @UnitPrice = 1000, @TurnaroundDays = 2; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50205 PRINT N'PASS: T10 Trùng tên gói bị từ chối (50205)'; ELSE PRINT N'FAIL: T10 Trùng tên gói';

-- ===== EVENT =====
-- T11-T13: tạo Draft, công bố Open, không đưa về Draft
BEGIN TRAN;
EXEC com.sp_SaveEvent @OrganizerId = @exp, @EventType = N'Workshop', @Title = N'Workshop T11', @VenueName = N'Studio', @AddressLine = N'2 Test', @City = N'HCM', @StartAt = @st, @EndAt = @en, @Capacity = 20, @NewEventId = @id OUTPUT;
SET @s = (SELECT Status FROM com.Events WHERE EventId = @id);
IF @s = N'Draft' PRINT N'PASS: T11 Tạo sự kiện ở trạng thái Draft'; ELSE PRINT N'FAIL: T11 Tạo sự kiện ở trạng thái Draft';
EXEC com.sp_SaveEvent @OrganizerId = @exp, @EventId = @id, @EventType = N'Workshop', @Title = N'Workshop T11', @VenueName = N'Studio', @AddressLine = N'2 Test', @City = N'HCM', @StartAt = @st, @EndAt = @en, @Capacity = 20, @Status = N'Open';
SET @s = (SELECT Status FROM com.Events WHERE EventId = @id);
IF @s = N'Open' PRINT N'PASS: T12 Công bố sự kiện (Open)'; ELSE PRINT N'FAIL: T12 Công bố sự kiện (Open)';
SET @e = NULL;
BEGIN TRY EXEC com.sp_SaveEvent @OrganizerId = @exp, @EventId = @id, @EventType = N'Workshop', @Title = N'Workshop T11', @VenueName = N'Studio', @AddressLine = N'2 Test', @City = N'HCM', @StartAt = @st, @EndAt = @en, @Capacity = 20, @Status = N'Draft'; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50702 PRINT N'PASS: T13 Không đưa sự kiện đã công bố về Draft (50702)'; ELSE PRINT N'FAIL: T13 Không đưa sự kiện đã công bố về Draft';

-- T14: Customer không tạo được sự kiện
SET @e = NULL;
BEGIN TRY EXEC com.sp_SaveEvent @OrganizerId = @an, @EventType = N'Photowalk', @Title = N'Walk', @VenueName = N'Park', @AddressLine = N'3 Test', @City = N'HCM', @StartAt = @st, @EndAt = @en, @Capacity = 10; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50703 PRINT N'PASS: T14 Customer không tạo được sự kiện (50703)'; ELSE PRINT N'FAIL: T14 Customer không tạo được sự kiện';

-- ===== ADDRESS =====
-- T15-T16: địa chỉ đầu tiên tự mặc định; địa chỉ mới đặt mặc định thì địa chỉ cũ bỏ mặc định
BEGIN TRAN;
EXEC iam.sp_SaveAddress @UserId = @exp, @RecipientName = N'Expert', @Phone = N'0900000004', @Line1 = N'4 Test', @Ward = N'P1', @District = N'Q1', @City = N'HCM', @NewAddressId = @id OUTPUT;
IF EXISTS (SELECT 1 FROM iam.Addresses WHERE AddressId = @id AND IsDefault = 1) PRINT N'PASS: T15 Địa chỉ đầu tiên tự là mặc định'; ELSE PRINT N'FAIL: T15 Địa chỉ đầu tiên tự là mặc định';
EXEC iam.sp_SaveAddress @UserId = @exp, @RecipientName = N'Expert', @Phone = N'0900000004', @Line1 = N'5 Test', @Ward = N'P1', @District = N'Q1', @City = N'HCM', @IsDefault = 1, @NewAddressId = @x OUTPUT;
IF (SELECT COUNT(*) FROM iam.Addresses WHERE UserId = @exp AND IsDefault = 1 AND IsDeleted = 0) = 1
   AND EXISTS (SELECT 1 FROM iam.Addresses WHERE AddressId = @x AND IsDefault = 1)
    PRINT N'PASS: T16 Đặt mặc định mới thì địa chỉ cũ bỏ mặc định'; ELSE PRINT N'FAIL: T16 Đặt mặc định mới';
ROLLBACK;

-- T17: sửa địa chỉ của người khác
SET @id = (SELECT TOP 1 AddressId FROM iam.Addresses WHERE UserId = @an ORDER BY AddressId);
SET @e = NULL;
BEGIN TRY EXEC iam.sp_SaveAddress @UserId = @binh, @AddressId = @id, @RecipientName = N'Hack', @Phone = N'0911000002', @Line1 = N'1 Test', @Ward = N'P1', @District = N'Q1', @City = N'HCM'; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50103 PRINT N'PASS: T17 Không sửa được địa chỉ của người khác (50103)'; ELSE PRINT N'FAIL: T17 Không sửa được địa chỉ của người khác';

-- ===== USER / ROLE =====
-- T18: khóa tài khoản
BEGIN TRAN;
EXEC iam.sp_SetUserStatus @AdminUserId = @admin, @UserId = @an, @IsActive = 0;
IF EXISTS (SELECT 1 FROM iam.Users WHERE UserId = @an AND IsActive = 0) PRINT N'PASS: T18 Admin khóa tài khoản'; ELSE PRINT N'FAIL: T18 Admin khóa tài khoản';
ROLLBACK;

-- T19: Admin tự khóa mình
SET @e = NULL;
BEGIN TRY EXEC iam.sp_SetUserStatus @AdminUserId = @admin, @UserId = @admin, @IsActive = 0; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50105 PRINT N'PASS: T19 Admin không tự khóa mình (50105)'; ELSE PRINT N'FAIL: T19 Admin không tự khóa mình';

-- T20: gán role
BEGIN TRAN;
EXEC iam.sp_AssignRole @AdminUserId = @admin, @UserId = @an, @RoleCode = N'Expert', @Action = N'Add';
IF EXISTS (SELECT 1 FROM iam.UserRoles ur JOIN iam.Roles r ON r.RoleId = ur.RoleId WHERE ur.UserId = @an AND r.RoleCode = N'Expert' AND ur.AssignedBy = @admin)
    PRINT N'PASS: T20 Admin gán role Expert'; ELSE PRINT N'FAIL: T20 Admin gán role Expert';
ROLLBACK;

-- T21: gán trùng role
SET @e = NULL;
BEGIN TRY EXEC iam.sp_AssignRole @AdminUserId = @admin, @UserId = @exp, @RoleCode = N'Expert', @Action = N'Add'; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50102 PRINT N'PASS: T21 Gán trùng role bị từ chối (50102)'; ELSE PRINT N'FAIL: T21 Gán trùng role';

-- T22: gỡ role cuối cùng
SET @e = NULL;
BEGIN TRY EXEC iam.sp_AssignRole @AdminUserId = @admin, @UserId = @ship, @RoleCode = N'Delivery', @Action = N'Remove'; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50105 PRINT N'PASS: T22 Không gỡ role cuối cùng (50105)'; ELSE PRINT N'FAIL: T22 Không gỡ role cuối cùng';

-- ===== FEE =====
-- T23: cấu hình phí mới đóng bản cũ
BEGIN TRAN;
SET @d = DATEADD(YEAR, 1, CAST(SYSUTCDATETIME() AS DATE));
SET @id = (SELECT TOP 1 FeeConfigId FROM ord.FeeConfigs WHERE FeeType = N'PlatformCommission' AND ScopeLabId IS NULL AND EffectiveTo IS NULL ORDER BY EffectiveFrom DESC);
EXEC ord.sp_SetFeeConfig @AdminUserId = @admin, @FeeType = N'PlatformCommission', @EffectiveFrom = @d, @Rate = 0.1000, @NewFeeConfigId = @x OUTPUT;
SET @d2 = (SELECT EffectiveTo FROM ord.FeeConfigs WHERE FeeConfigId = @id);
IF @x IS NOT NULL AND EXISTS (SELECT 1 FROM ord.FeeConfigs WHERE FeeConfigId = @x AND Rate = 0.1000 AND EffectiveTo IS NULL)
   AND (@id IS NULL OR @d2 = DATEADD(DAY, -1, @d))
    PRINT N'PASS: T23 Cấu hình phí mới đóng bản đang mở'; ELSE PRINT N'FAIL: T23 Cấu hình phí mới đóng bản đang mở';
ROLLBACK;

-- T24: không phải Admin
SET @e = NULL;
BEGIN TRY EXEC ord.sp_SetFeeConfig @AdminUserId = @an, @FeeType = N'MarketplaceFee', @EffectiveFrom = @st, @Rate = 0.05; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50303 PRINT N'PASS: T24 Không phải Admin không chỉnh phí (50303)'; ELSE PRINT N'FAIL: T24 Không phải Admin không chỉnh phí';

-- ===== ALBUM =====
SELECT TOP 1 @sc = ScanFileId, @scOwner = OwnerUserId FROM arc.ScanFiles ORDER BY OwnerUserId;
-- T25-T26: thêm và gỡ ảnh khỏi album
BEGIN TRAN;
EXEC arc.sp_SaveAlbum @OwnerUserId = @scOwner, @Title = N'Album test', @NewAlbumId = @alb OUTPUT;
EXEC arc.sp_SetAlbumPhoto @OwnerUserId = @scOwner, @AlbumId = @alb, @ScanFileId = @sc, @Action = N'Add';
IF @alb IS NOT NULL AND EXISTS (SELECT 1 FROM arc.AlbumPhotos WHERE AlbumId = @alb AND ScanFileId = @sc) PRINT N'PASS: T25 Thêm ảnh vào album'; ELSE PRINT N'FAIL: T25 Thêm ảnh vào album';
EXEC arc.sp_SetAlbumPhoto @OwnerUserId = @scOwner, @AlbumId = @alb, @ScanFileId = @sc, @Action = N'Remove';
IF NOT EXISTS (SELECT 1 FROM arc.AlbumPhotos WHERE AlbumId = @alb AND ScanFileId = @sc) PRINT N'PASS: T26 Gỡ ảnh khỏi album'; ELSE PRINT N'FAIL: T26 Gỡ ảnh khỏi album';
ROLLBACK;

-- T27: thêm ảnh của người khác vào album của mình
SET @y = (SELECT TOP 1 UserId FROM iam.Users WHERE UserId <> @scOwner AND IsActive = 1 AND IsDeleted = 0 ORDER BY UserId);
SET @e = NULL;
BEGIN TRAN;
EXEC arc.sp_SaveAlbum @OwnerUserId = @y, @Title = N'Album test T27', @NewAlbumId = @alb OUTPUT;
BEGIN TRY EXEC arc.sp_SetAlbumPhoto @OwnerUserId = @y, @AlbumId = @alb, @ScanFileId = @sc, @Action = N'Add'; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50503 PRINT N'PASS: T27 Không thêm ảnh của người khác vào album (50503)'; ELSE PRINT N'FAIL: T27 Không thêm ảnh của người khác vào album';

-- ===== GỌI PROCEDURE THẬT DƯỚI ROLE =====
-- T28: role_Customer không có EXECUTE lab.sp_SaveLabProfile (lỗi 229)
SET @e = NULL;
EXECUTE AS USER = N'u_cus';
BEGIN TRY EXEC lab.sp_SaveLabProfile @OwnerUserId = @an, @LabName = N'Lab', @AddressLine = N'1', @Ward = N'P', @District = N'Q', @City = N'HCM'; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
REVERT;
EXEC sp_set_session_context N'UserId', NULL;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 229 PRINT N'PASS: T28 role_Customer bị từ chối EXECUTE sp_SaveLabProfile (229)'; ELSE PRINT N'FAIL: T28 role_Customer bị từ chối EXECUTE sp_SaveLabProfile';

-- T29: role_Customer gọi sp_SaveAddress thành công
SET @e = NULL; SET @id = NULL;
BEGIN TRAN;
EXECUTE AS USER = N'u_cus';
BEGIN TRY EXEC iam.sp_SaveAddress @UserId = @an, @RecipientName = N'An', @Phone = N'0911000001', @Line1 = N'9 Test', @Ward = N'P1', @District = N'Q1', @City = N'HCM', @NewAddressId = @id OUTPUT; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
REVERT;
EXEC sp_set_session_context N'UserId', NULL;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e IS NULL AND @id IS NOT NULL PRINT N'PASS: T29 role_Customer gọi sp_SaveAddress thành công'; ELSE PRINT N'FAIL: T29 role_Customer gọi sp_SaveAddress (lỗi ' + ISNULL(CAST(@e AS NVARCHAR(10)), N'NULL') + N')';

-- T30: role_LabOwner sửa hồ sơ lab của mình
SET @e = NULL; SET @id = NULL;
BEGIN TRAN;
EXECUTE AS USER = N'u_lab';
BEGIN TRY EXEC lab.sp_SaveLabProfile @OwnerUserId = @sgOwner, @LabId = @sg, @LabName = N'Sài Gòn Film Lab (T30)', @AddressLine = N'1', @Ward = N'P', @District = N'Q', @City = N'HCM', @NewLabId = @id OUTPUT; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
REVERT;
EXEC sp_set_session_context N'UserId', NULL;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e IS NULL AND @id = @sg PRINT N'PASS: T30 role_LabOwner gọi sp_SaveLabProfile thành công'; ELSE PRINT N'FAIL: T30 role_LabOwner gọi sp_SaveLabProfile (lỗi ' + ISNULL(CAST(@e AS NVARCHAR(10)), N'NULL') + N')';

-- T31: role_Expert tạo sự kiện
SET @e = NULL; SET @id = NULL;
BEGIN TRAN;
EXECUTE AS USER = N'u_exp';
BEGIN TRY EXEC com.sp_SaveEvent @OrganizerId = @exp, @EventType = N'Photowalk', @Title = N'Walk T31', @VenueName = N'Park', @AddressLine = N'3', @City = N'HCM', @StartAt = @st, @EndAt = @en, @Capacity = 10, @NewEventId = @id OUTPUT; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
REVERT;
EXEC sp_set_session_context N'UserId', NULL;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e IS NULL AND @id IS NOT NULL PRINT N'PASS: T31 role_Expert gọi sp_SaveEvent thành công'; ELSE PRINT N'FAIL: T31 role_Expert gọi sp_SaveEvent (lỗi ' + ISNULL(CAST(@e AS NVARCHAR(10)), N'NULL') + N')';

DROP USER u_cus;
DROP USER u_lab;
DROP USER u_exp;
GO