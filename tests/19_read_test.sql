/* ============================================================
   File    : tests/19_read_test.sql
   Purpose : Kiểm tra 6 procedure đọc Đợt 8a và GRANT thật dưới role. Mong đợi 25 PASS.
   Cách chạy (trong thư mục tests, KHÔNG dùng -b):
     sqlcmd -S localhost -E -C -f 65001 -d FilmLabDB -i 19_read_test.sql | find /c "PASS:"
   Ghi chú : procedure trả nhiều result set sẽ in bảng ra màn hình, bỏ qua phần đó.
   ============================================================ */
USE FilmLabDB;
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
SET NOCOUNT ON;

IF USER_ID(N'u_auth') IS NOT NULL DROP USER u_auth;
IF USER_ID(N'u_cus')  IS NOT NULL DROP USER u_cus;
IF USER_ID(N'u_lab')  IS NOT NULL DROP USER u_lab;
IF USER_ID(N'u_exp')  IS NOT NULL DROP USER u_exp;
CREATE USER u_auth WITHOUT LOGIN;  ALTER ROLE role_Auth     ADD MEMBER u_auth;
CREATE USER u_cus  WITHOUT LOGIN;  ALTER ROLE role_Customer ADD MEMBER u_cus;
CREATE USER u_lab  WITHOUT LOGIN;  ALTER ROLE role_LabOwner ADD MEMBER u_lab;
CREATE USER u_exp  WITHOUT LOGIN;  ALTER ROLE role_Expert   ADD MEMBER u_exp;

DECLARE @admin   INT = (SELECT UserId FROM iam.Users WHERE Email = N'admin@filmlab.vn');
DECLARE @an      INT = (SELECT UserId FROM iam.Users WHERE Email = N'an.nguyen@example.com');
DECLARE @binh    INT = (SELECT UserId FROM iam.Users WHERE Email = N'binh.tran@example.com');
DECLARE @sg      INT = (SELECT LabId FROM lab.FilmLabs WHERE LabName = N'Sài Gòn Film Lab');
DECLARE @sgOwner INT = (SELECT OwnerUserId FROM lab.FilmLabs WHERE LabId = @sg);
DECLARE @ord     INT = (SELECT TOP 1 OrderId FROM ord.Orders WHERE CustomerId = @an AND IsDeleted = 0 ORDER BY OrderId);
DECLARE @ordLab  INT = (SELECT l.OwnerUserId FROM ord.Orders o JOIN lab.FilmLabs l ON l.LabId = o.LabId WHERE o.OrderId = @ord);
DECLARE @e INT, @n INT, @m INT, @id INT, @p NVARCHAR(20);

DECLARE @login TABLE (UserId INT, FullName NVARCHAR(100), AuthProvider NVARCHAR(20), PasswordHash NVARCHAR(255), IsActive BIT, Roles NVARCHAR(400));
DECLARE @ad TABLE (AddressId INT, Label NVARCHAR(50), RecipientName NVARCHAR(100), Phone NVARCHAR(20), Line1 NVARCHAR(255), Ward NVARCHAR(100), District NVARCHAR(100), City NVARCHAR(100), IsDefault BIT);
DECLARE @mo TABLE (OrderId INT, OrderCode NVARCHAR(20), CustomerId INT, CustomerName NVARCHAR(100), LabId INT, LabName NVARCHAR(150), StageId INT, StageCode NVARCHAR(20), StageName NVARCHAR(100), PaymentStatus NVARCHAR(9), TotalAmount DECIMAL(18,0), FulfillmentMethod NVARCHAR(7), ReturnMethod NVARCHAR(11), EstimatedReadyDate DATE, CreatedAt DATETIME2(0), TotalRows INT);

-- ===== ĐĂNG NHẬP / ĐĂNG KÝ =====
-- T1: lấy thông tin đăng nhập
INSERT @login EXEC iam.sp_GetLoginInfo @Email = N'an.nguyen@example.com';
IF (SELECT COUNT(*) FROM @login) = 1
   AND EXISTS (SELECT 1 FROM @login WHERE UserId = @an AND PasswordHash IS NOT NULL AND IsActive = 1 AND Roles LIKE N'%Customer%')
    PRINT N'PASS: T1 sp_GetLoginInfo trả hash, trạng thái và role';
ELSE PRINT N'FAIL: T1 sp_GetLoginInfo trả hash, trạng thái và role';

-- T2: email không tồn tại trả rỗng
DELETE FROM @login;
INSERT @login EXEC iam.sp_GetLoginInfo @Email = N'khong.ton.tai@example.com';
IF (SELECT COUNT(*) FROM @login) = 0 PRINT N'PASS: T2 Email không tồn tại trả rỗng';
ELSE PRINT N'FAIL: T2 Email không tồn tại trả rỗng';

-- T3: email rỗng
SET @e = NULL;
BEGIN TRY EXEC iam.sp_GetLoginInfo @Email = N'  '; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
IF @e = 50105 PRINT N'PASS: T3 Email rỗng bị từ chối (50105)'; ELSE PRINT N'FAIL: T3 Email rỗng bị từ chối';

-- T4: role_Auth gọi sp_GetLoginInfo
DELETE FROM @login; SET @e = NULL;
EXECUTE AS USER = N'u_auth';
BEGIN TRY INSERT @login EXEC iam.sp_GetLoginInfo @Email = N'an.nguyen@example.com'; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
REVERT;
IF @e IS NULL AND EXISTS (SELECT 1 FROM @login WHERE UserId = @an) PRINT N'PASS: T4 role_Auth gọi sp_GetLoginInfo thành công';
ELSE PRINT N'FAIL: T4 role_Auth gọi sp_GetLoginInfo (lỗi ' + ISNULL(CAST(@e AS NVARCHAR(10)), N'NULL') + N')';

-- T5: role_Auth đăng ký người dùng
SET @e = NULL; SET @id = NULL;
BEGIN TRAN;
EXECUTE AS USER = N'u_auth';
BEGIN TRY EXEC iam.sp_RegisterUser @Email = N'new.user.t5@example.com', @FullName = N'User T5', @PasswordHash = N'hash-t5', @NewUserId = @id OUTPUT; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
REVERT;
EXEC sp_set_session_context N'UserId', NULL;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e IS NULL AND @id IS NOT NULL PRINT N'PASS: T5 role_Auth gọi sp_RegisterUser thành công';
ELSE PRINT N'FAIL: T5 role_Auth gọi sp_RegisterUser (lỗi ' + ISNULL(CAST(@e AS NVARCHAR(10)), N'NULL') + N')';

-- T6: role_Auth không gọi được procedure nghiệp vụ
SET @e = NULL;
EXECUTE AS USER = N'u_auth';
BEGIN TRY EXEC ord.sp_GetMyOrders @UserId = @an; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
REVERT;
IF @e = 229 PRINT N'PASS: T6 role_Auth bị từ chối ord.sp_GetMyOrders (229)'; ELSE PRINT N'FAIL: T6 role_Auth bị từ chối ord.sp_GetMyOrders';

-- ===== ĐỊA CHỈ =====
-- T7: số địa chỉ khớp dữ liệu
INSERT @ad EXEC iam.sp_GetMyAddresses @UserId = @an;
SET @n = (SELECT COUNT(*) FROM @ad);
SET @m = (SELECT COUNT(*) FROM iam.Addresses WHERE UserId = @an AND IsDeleted = 0);
IF @n = @m AND @n > 0 PRINT N'PASS: T7 sp_GetMyAddresses trả đủ địa chỉ'; ELSE PRINT N'FAIL: T7 sp_GetMyAddresses trả đủ địa chỉ';

-- T8: người dùng không tồn tại
SET @e = NULL;
BEGIN TRY EXEC iam.sp_GetMyAddresses @UserId = -1; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
IF @e = 50101 PRINT N'PASS: T8 sp_GetMyAddresses user không tồn tại (50101)'; ELSE PRINT N'FAIL: T8 sp_GetMyAddresses user không tồn tại';

-- T9: role_Customer thấy SĐT thật (không bị mask)
DELETE FROM @ad; SET @e = NULL;
EXECUTE AS USER = N'u_cus';
BEGIN TRY INSERT @ad EXEC iam.sp_GetMyAddresses @UserId = @an; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
REVERT;
SET @p = (SELECT TOP 1 Phone FROM @ad ORDER BY IsDefault DESC, AddressId);
IF @e IS NULL AND @p IS NOT NULL AND @p NOT LIKE N'%XXXX%'
   AND @p = (SELECT TOP 1 Phone FROM iam.Addresses WHERE UserId = @an AND IsDeleted = 0 ORDER BY IsDefault DESC, AddressId)
    PRINT N'PASS: T9 role_Customer thấy SĐT thật của chính mình';
ELSE PRINT N'FAIL: T9 role_Customer thấy SĐT thật của chính mình (Phone = ' + ISNULL(@p, N'NULL') + N')';

-- ===== ĐƠN HÀNG =====
-- T10: đơn của khách (dbo)
INSERT @mo EXEC ord.sp_GetMyOrders @UserId = @an;
SET @n = (SELECT COUNT(*) FROM @mo);
SET @m = (SELECT COUNT(*) FROM ord.Orders WHERE CustomerId = @an AND IsDeleted = 0);
IF @n = @m AND @n > 0 AND (SELECT MAX(TotalRows) FROM @mo) = @m PRINT N'PASS: T10 sp_GetMyOrders (Customer) đúng số đơn và TotalRows';
ELSE PRINT N'FAIL: T10 sp_GetMyOrders (Customer) đúng số đơn và TotalRows';

-- T11: đơn của lab (dbo)
DELETE FROM @mo;
INSERT @mo EXEC ord.sp_GetMyOrders @UserId = @sgOwner, @AsRole = N'LabOwner';
SET @n = (SELECT COUNT(*) FROM @mo);
SET @m = (SELECT COUNT(*) FROM ord.Orders o JOIN lab.FilmLabs l ON l.LabId = o.LabId WHERE l.OwnerUserId = @sgOwner AND o.IsDeleted = 0);
IF @n = @m AND NOT EXISTS (SELECT 1 FROM @mo WHERE LabId NOT IN (SELECT LabId FROM lab.FilmLabs WHERE OwnerUserId = @sgOwner))
    PRINT N'PASS: T11 sp_GetMyOrders (LabOwner) chỉ trả đơn của lab mình';
ELSE PRINT N'FAIL: T11 sp_GetMyOrders (LabOwner) chỉ trả đơn của lab mình';

-- T12: dưới role_Customer vẫn trả đủ (RLS + ownership chaining)
DELETE FROM @mo; SET @e = NULL;
EXECUTE AS USER = N'u_cus';
BEGIN TRY INSERT @mo EXEC ord.sp_GetMyOrders @UserId = @an; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
REVERT;
EXEC sp_set_session_context N'UserId', NULL;
SET @m = (SELECT COUNT(*) FROM ord.Orders WHERE CustomerId = @an AND IsDeleted = 0);
IF @e IS NULL AND (SELECT COUNT(*) FROM @mo) = @m AND @m > 0 PRINT N'PASS: T12 role_Customer gọi sp_GetMyOrders thành công';
ELSE PRINT N'FAIL: T12 role_Customer gọi sp_GetMyOrders (lỗi ' + ISNULL(CAST(@e AS NVARCHAR(10)), N'NULL') + N')';

-- T13: AsRole sai
SET @e = NULL;
BEGIN TRY EXEC ord.sp_GetMyOrders @UserId = @an, @AsRole = N'Admin'; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
IF @e = 50305 PRINT N'PASS: T13 AsRole sai bị từ chối (50305)'; ELSE PRINT N'FAIL: T13 AsRole sai bị từ chối';

-- T14: PageSize sai
SET @e = NULL;
BEGIN TRY EXEC ord.sp_GetMyOrders @UserId = @an, @PageSize = 0; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
IF @e = 50305 PRINT N'PASS: T14 PageSize sai bị từ chối (50305)'; ELSE PRINT N'FAIL: T14 PageSize sai bị từ chối';

-- T15: chủ đơn xem chi tiết dưới role_Customer
SET @e = NULL;
EXECUTE AS USER = N'u_cus';
BEGIN TRY EXEC ord.sp_GetOrderDetail @OrderId = @ord, @UserId = @an; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
REVERT;
EXEC sp_set_session_context N'UserId', NULL;
IF @e IS NULL PRINT N'PASS: T15 role_Customer xem chi tiết đơn của mình';
ELSE PRINT N'FAIL: T15 role_Customer xem chi tiết đơn của mình (lỗi ' + CAST(@e AS NVARCHAR(10)) + N')';

-- T16: xem đơn của người khác (dbo, không có RLS)
SET @e = NULL;
BEGIN TRY EXEC ord.sp_GetOrderDetail @OrderId = @ord, @UserId = @binh; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
IF @e = 50303 PRINT N'PASS: T16 Xem đơn của người khác bị từ chối (50303)'; ELSE PRINT N'FAIL: T16 Xem đơn của người khác bị từ chối';

-- T17: xem đơn của người khác dưới role_Customer (RLS ẩn đơn nên 50301 hoặc 50303)
SET @e = NULL;
EXECUTE AS USER = N'u_cus';
BEGIN TRY EXEC ord.sp_GetOrderDetail @OrderId = @ord, @UserId = @binh; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
REVERT;
EXEC sp_set_session_context N'UserId', NULL;
IF @e IN (50301, 50303) PRINT N'PASS: T17 role_Customer không xem được đơn của người khác';
ELSE PRINT N'FAIL: T17 role_Customer không xem được đơn của người khác';

-- T18: đơn không tồn tại
SET @e = NULL;
BEGIN TRY EXEC ord.sp_GetOrderDetail @OrderId = -1, @UserId = @an; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
IF @e = 50301 PRINT N'PASS: T18 Đơn không tồn tại (50301)'; ELSE PRINT N'FAIL: T18 Đơn không tồn tại';

-- T19: chủ lab xem chi tiết đơn của lab mình dưới role_LabOwner
SET @e = NULL;
EXECUTE AS USER = N'u_lab';
BEGIN TRY EXEC ord.sp_GetOrderDetail @OrderId = @ord, @UserId = @ordLab; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
REVERT;
EXEC sp_set_session_context N'UserId', NULL;
IF @e IS NULL PRINT N'PASS: T19 role_LabOwner xem chi tiết đơn của lab mình';
ELSE PRINT N'FAIL: T19 role_LabOwner xem chi tiết đơn của lab mình (lỗi ' + CAST(@e AS NVARCHAR(10)) + N')';

-- ===== LAB =====
-- T20: chi tiết lab đã duyệt dưới role_Expert
SET @e = NULL;
EXECUTE AS USER = N'u_exp';
BEGIN TRY EXEC lab.sp_GetLabDetail @LabId = @sg; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
REVERT;
IF @e IS NULL PRINT N'PASS: T20 role_Expert gọi sp_GetLabDetail thành công';
ELSE PRINT N'FAIL: T20 role_Expert gọi sp_GetLabDetail (lỗi ' + CAST(@e AS NVARCHAR(10)) + N')';

-- T21: lab không tồn tại
SET @e = NULL;
BEGIN TRY EXEC lab.sp_GetLabDetail @LabId = -1; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
IF @e = 50201 PRINT N'PASS: T21 Lab không tồn tại (50201)'; ELSE PRINT N'FAIL: T21 Lab không tồn tại';

-- T22: lab chưa duyệt không hiện cho khách
SET @e = NULL; SET @id = NULL;
BEGIN TRAN;
EXEC lab.sp_SaveLabProfile @OwnerUserId = @sgOwner, @LabName = N'Lab Pending T22', @AddressLine = N'1 Test', @Ward = N'P1', @District = N'Q1', @City = N'HCM', @NewLabId = @id OUTPUT;
BEGIN TRY EXEC lab.sp_GetLabDetail @LabId = @id; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50201 PRINT N'PASS: T22 Lab Pending không hiện ra (50201)'; ELSE PRINT N'FAIL: T22 Lab Pending không hiện ra';

-- T23: chủ lab xem lab của mình dưới role_LabOwner
SET @e = NULL;
EXECUTE AS USER = N'u_lab';
BEGIN TRY EXEC lab.sp_GetMyLabs @OwnerUserId = @sgOwner; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
REVERT;
IF @e IS NULL PRINT N'PASS: T23 role_LabOwner gọi sp_GetMyLabs thành công';
ELSE PRINT N'FAIL: T23 role_LabOwner gọi sp_GetMyLabs (lỗi ' + CAST(@e AS NVARCHAR(10)) + N')';

-- ===== PHÂN QUYỀN =====
-- T24: role_Customer không gọi được sp_GetMyLabs
SET @e = NULL;
EXECUTE AS USER = N'u_cus';
BEGIN TRY EXEC lab.sp_GetMyLabs @OwnerUserId = @sgOwner; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
REVERT;
IF @e = 229 PRINT N'PASS: T24 role_Customer bị từ chối lab.sp_GetMyLabs (229)'; ELSE PRINT N'FAIL: T24 role_Customer bị từ chối lab.sp_GetMyLabs';

-- T25: role_LabOwner không gọi được sp_GetMyAddresses
SET @e = NULL;
EXECUTE AS USER = N'u_lab';
BEGIN TRY EXEC iam.sp_GetMyAddresses @UserId = @sgOwner; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
REVERT;
IF @e = 229 PRINT N'PASS: T25 role_LabOwner bị từ chối iam.sp_GetMyAddresses (229)'; ELSE PRINT N'FAIL: T25 role_LabOwner bị từ chối iam.sp_GetMyAddresses';

DROP USER u_auth;
DROP USER u_cus;
DROP USER u_lab;
DROP USER u_exp;
GO