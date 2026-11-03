/* ============================================================
   File    : tests/20_support_test.sql
   Purpose : Kiểm tra 4 procedure bổ sung Đợt 8a-2 (lab.sp_GetReferenceData, lab.sp_ListLabsForApproval,
             iam.sp_ListUsers, ai.sp_SearchKnowledge) và GRANT thật dưới role. Mong đợi 38 PASS.
   Cách chạy (trong thư mục tests, KHÔNG dùng -b):
     sqlcmd -S localhost -E -C -f 65001 -d FilmLabDB -i 20_support_test.sql | find /c "PASS:"
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
IF USER_ID(N'u_adm')  IS NOT NULL DROP USER u_adm;
CREATE USER u_auth WITHOUT LOGIN;  ALTER ROLE role_Auth     ADD MEMBER u_auth;
CREATE USER u_cus  WITHOUT LOGIN;  ALTER ROLE role_Customer ADD MEMBER u_cus;
CREATE USER u_lab  WITHOUT LOGIN;  ALTER ROLE role_LabOwner ADD MEMBER u_lab;
CREATE USER u_exp  WITHOUT LOGIN;  ALTER ROLE role_Expert   ADD MEMBER u_exp;
CREATE USER u_adm  WITHOUT LOGIN;  ALTER ROLE role_Admin    ADD MEMBER u_adm;

DECLARE @admin INT = (SELECT UserId FROM iam.Users WHERE Email = N'admin@filmlab.vn');
DECLARE @an    INT = (SELECT UserId FROM iam.Users WHERE Email = N'an.nguyen@example.com');
DECLARE @sg    INT = (SELECT LabId FROM lab.FilmLabs WHERE LabName = N'Sài Gòn Film Lab');
DECLARE @e INT, @n INT;

DECLARE @labs TABLE (LabId INT, LabName NVARCHAR(150), OwnerUserId INT, OwnerName NVARCHAR(100), OwnerEmail NVARCHAR(255),
                     AddressLine NVARCHAR(255), Ward NVARCHAR(100), District NVARCHAR(100), City NVARCHAR(100), Phone NVARCHAR(20),
                     ApprovalStatus NVARCHAR(12), ServiceCount INT, CreatedAt DATETIME2(0),
                     LastDecision NVARCHAR(12), LastDecisionReason NVARCHAR(500), LastDecidedAt DATETIME2(0), TotalRows INT);
DECLARE @usr TABLE (UserId INT, Email NVARCHAR(255), FullName NVARCHAR(100), AuthProvider NVARCHAR(20), IsActive BIT,
                    Roles NVARCHAR(400), LastLoginAt DATETIME2(0), CreatedAt DATETIME2(0), TotalRows INT);
DECLARE @kn TABLE (KnowledgeDocId INT, SourceArticleId INT, ChunkIndex INT, Title NVARCHAR(200), Topic NVARCHAR(50),
                   Content NVARCHAR(4000), Score INT, MatchMode NVARCHAR(10));

-- ===== lab.sp_GetReferenceData =====
SET @e = NULL; EXECUTE AS USER = N'u_cus';
BEGIN TRY EXEC lab.sp_GetReferenceData; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
REVERT;
IF @e IS NULL PRINT N'PASS: T1 role_Customer gọi sp_GetReferenceData thành công';
ELSE PRINT N'FAIL: T1 role_Customer gọi sp_GetReferenceData (lỗi ' + CAST(@e AS NVARCHAR(10)) + N')';

SET @e = NULL; EXECUTE AS USER = N'u_lab';
BEGIN TRY EXEC lab.sp_GetReferenceData; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
REVERT;
IF @e IS NULL PRINT N'PASS: T2 role_LabOwner gọi sp_GetReferenceData thành công';
ELSE PRINT N'FAIL: T2 role_LabOwner gọi sp_GetReferenceData (lỗi ' + CAST(@e AS NVARCHAR(10)) + N')';

SET @e = NULL; EXECUTE AS USER = N'u_exp';
BEGIN TRY EXEC lab.sp_GetReferenceData; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
REVERT;
IF @e IS NULL PRINT N'PASS: T3 role_Expert gọi sp_GetReferenceData thành công';
ELSE PRINT N'FAIL: T3 role_Expert gọi sp_GetReferenceData (lỗi ' + CAST(@e AS NVARCHAR(10)) + N')';

SET @e = NULL; EXECUTE AS USER = N'u_auth';
BEGIN TRY EXEC lab.sp_GetReferenceData; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
REVERT;
IF @e = 229 PRINT N'PASS: T4 role_Auth bị từ chối sp_GetReferenceData (229)';
ELSE PRINT N'FAIL: T4 role_Auth bị từ chối sp_GetReferenceData';

SET @e = NULL; EXECUTE AS USER = N'u_adm';
BEGIN TRY EXEC lab.sp_GetReferenceData; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
REVERT;
IF @e IS NULL AND (SELECT COUNT(*) FROM ord.ProcessingStages) = 13
   AND (SELECT COUNT(*) FROM lab.FilmFormats) > 0 AND (SELECT COUNT(*) FROM lab.ServiceTypes) > 0
    PRINT N'PASS: T5 role_Admin gọi được và danh mục đủ dữ liệu (13 stage)';
ELSE PRINT N'FAIL: T5 role_Admin gọi sp_GetReferenceData hoặc danh mục thiếu';

-- ===== lab.sp_ListLabsForApproval =====
DELETE FROM @labs;
INSERT @labs EXEC lab.sp_ListLabsForApproval @AdminUserId = @admin, @Status = N'Approved', @PageSize = 100;
IF EXISTS (SELECT 1 FROM @labs WHERE LabId = @sg) AND NOT EXISTS (SELECT 1 FROM @labs WHERE ApprovalStatus <> N'Approved')
    PRINT N'PASS: T6 Lọc Approved trả đúng lab đã duyệt';
ELSE PRINT N'FAIL: T6 Lọc Approved trả đúng lab đã duyệt';

DELETE FROM @labs;
BEGIN TRAN;
EXEC sp_set_session_context N'UserId', @admin;
UPDATE lab.FilmLabs SET ApprovalStatus = N'Pending' WHERE LabId = @sg;
INSERT @labs EXEC lab.sp_ListLabsForApproval @AdminUserId = @admin;
ROLLBACK;
EXEC sp_set_session_context N'UserId', NULL;
IF EXISTS (SELECT 1 FROM @labs WHERE LabId = @sg) AND NOT EXISTS (SELECT 1 FROM @labs WHERE ApprovalStatus <> N'Pending')
    PRINT N'PASS: T7 Mặc định lọc Pending (lab vừa chuyển Pending xuất hiện)';
ELSE PRINT N'FAIL: T7 Mặc định lọc Pending';

DELETE FROM @labs;
INSERT @labs EXEC lab.sp_ListLabsForApproval @AdminUserId = @admin, @Status = NULL, @PageSize = 100;
SET @n = (SELECT COUNT(*) FROM lab.FilmLabs WHERE IsDeleted = 0);
IF @n > 0 AND (SELECT COUNT(*) FROM @labs) = @n AND (SELECT MAX(TotalRows) FROM @labs) = @n
    PRINT N'PASS: T8 Status NULL trả mọi lab, TotalRows đúng';
ELSE PRINT N'FAIL: T8 Status NULL trả mọi lab, TotalRows đúng';

DELETE FROM @labs;
INSERT @labs EXEC lab.sp_ListLabsForApproval @AdminUserId = @admin, @Status = NULL, @PageNo = 1, @PageSize = 1;
IF (SELECT COUNT(*) FROM @labs) = 1 AND (SELECT MAX(TotalRows) FROM @labs) = @n
    PRINT N'PASS: T9 Phân trang PageSize=1 trả 1 dòng, TotalRows giữ nguyên';
ELSE PRINT N'FAIL: T9 Phân trang PageSize=1';

SET @e = NULL;
BEGIN TRY EXEC lab.sp_ListLabsForApproval @AdminUserId = @admin, @Status = N'Banana'; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
IF @e = 50205 PRINT N'PASS: T10 Status sai bị từ chối (50205)'; ELSE PRINT N'FAIL: T10 Status sai bị từ chối';

SET @e = NULL;
BEGIN TRY EXEC lab.sp_ListLabsForApproval @AdminUserId = @admin, @PageSize = 0; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
IF @e = 50205 PRINT N'PASS: T11 PageSize=0 bị từ chối (50205)'; ELSE PRINT N'FAIL: T11 PageSize=0 bị từ chối';

SET @e = NULL;
BEGIN TRY EXEC lab.sp_ListLabsForApproval @AdminUserId = @an; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
IF @e = 50203 PRINT N'PASS: T12 Người không phải Admin bị từ chối (50203)'; ELSE PRINT N'FAIL: T12 Người không phải Admin bị từ chối';

DELETE FROM @labs; SET @e = NULL;
EXECUTE AS USER = N'u_adm';
BEGIN TRY INSERT @labs EXEC lab.sp_ListLabsForApproval @AdminUserId = @admin, @Status = NULL; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
REVERT;
IF @e IS NULL AND EXISTS (SELECT 1 FROM @labs) PRINT N'PASS: T13 role_Admin gọi sp_ListLabsForApproval thành công';
ELSE PRINT N'FAIL: T13 role_Admin gọi sp_ListLabsForApproval (lỗi ' + ISNULL(CAST(@e AS NVARCHAR(10)), N'NULL') + N')';

SET @e = NULL; EXECUTE AS USER = N'u_cus';
BEGIN TRY EXEC lab.sp_ListLabsForApproval @AdminUserId = @admin; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
REVERT;
IF @e = 229 PRINT N'PASS: T14 role_Customer bị từ chối sp_ListLabsForApproval (229)';
ELSE PRINT N'FAIL: T14 role_Customer bị từ chối sp_ListLabsForApproval';

SET @e = NULL; EXECUTE AS USER = N'u_lab';
BEGIN TRY EXEC lab.sp_ListLabsForApproval @AdminUserId = @admin; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
REVERT;
IF @e = 229 PRINT N'PASS: T15 role_LabOwner bị từ chối sp_ListLabsForApproval (229)';
ELSE PRINT N'FAIL: T15 role_LabOwner bị từ chối sp_ListLabsForApproval';

-- ===== iam.sp_ListUsers =====
DELETE FROM @usr;
INSERT @usr EXEC iam.sp_ListUsers @AdminUserId = @admin, @PageSize = 100;
SET @n = (SELECT COUNT(*) FROM iam.Users WHERE IsDeleted = 0);
IF (SELECT COUNT(*) FROM @usr) = @n AND (SELECT MAX(TotalRows) FROM @usr) = @n
    PRINT N'PASS: T16 Liệt kê mọi user, TotalRows đúng';
ELSE PRINT N'FAIL: T16 Liệt kê mọi user, TotalRows đúng';

DELETE FROM @usr;
INSERT @usr EXEC iam.sp_ListUsers @AdminUserId = @admin, @RoleCode = N'Customer', @PageSize = 100;
IF EXISTS (SELECT 1 FROM @usr WHERE UserId = @an) AND NOT EXISTS (SELECT 1 FROM @usr WHERE Roles NOT LIKE N'%Customer%')
    PRINT N'PASS: T17 Lọc RoleCode=Customer đúng';
ELSE PRINT N'FAIL: T17 Lọc RoleCode=Customer đúng';

DELETE FROM @usr;
INSERT @usr EXEC iam.sp_ListUsers @AdminUserId = @admin, @IsActive = 0, @PageSize = 100;
IF NOT EXISTS (SELECT 1 FROM @usr WHERE IsActive = 1)
   AND (SELECT COUNT(*) FROM @usr) = (SELECT COUNT(*) FROM iam.Users WHERE IsDeleted = 0 AND IsActive = 0)
    PRINT N'PASS: T18 Lọc IsActive=0 đúng';
ELSE PRINT N'FAIL: T18 Lọc IsActive=0 đúng';

DELETE FROM @usr;
INSERT @usr EXEC iam.sp_ListUsers @AdminUserId = @admin, @Keyword = N'an.nguyen@example';
IF (SELECT COUNT(*) FROM @usr) = 1 AND EXISTS (SELECT 1 FROM @usr WHERE UserId = @an)
    PRINT N'PASS: T19 Tìm theo từ khóa email đúng 1 người';
ELSE PRINT N'FAIL: T19 Tìm theo từ khóa email đúng 1 người';

IF (SELECT COUNT(*) FROM sys.dm_exec_describe_first_result_set_for_object(OBJECT_ID(N'iam.sp_ListUsers'), NULL)
    WHERE name IN (N'PasswordHash', N'Phone')) = 0
   AND (SELECT COUNT(*) FROM sys.dm_exec_describe_first_result_set_for_object(OBJECT_ID(N'iam.sp_ListUsers'), NULL)) = 9
    PRINT N'PASS: T20 Kết quả không chứa PasswordHash và Phone (9 cột)';
ELSE PRINT N'FAIL: T20 Kết quả không chứa PasswordHash và Phone';

SET @e = NULL;
BEGIN TRY EXEC iam.sp_ListUsers @AdminUserId = @admin, @RoleCode = N'Khong.Co'; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
IF @e = 50105 PRINT N'PASS: T21 RoleCode không tồn tại bị từ chối (50105)'; ELSE PRINT N'FAIL: T21 RoleCode không tồn tại bị từ chối';

SET @e = NULL;
BEGIN TRY EXEC iam.sp_ListUsers @AdminUserId = @an; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
IF @e = 50103 PRINT N'PASS: T22 Người không phải Admin bị từ chối (50103)'; ELSE PRINT N'FAIL: T22 Người không phải Admin bị từ chối';

DELETE FROM @usr; SET @e = NULL;
EXECUTE AS USER = N'u_adm';
BEGIN TRY INSERT @usr EXEC iam.sp_ListUsers @AdminUserId = @admin; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
REVERT;
IF @e IS NULL AND EXISTS (SELECT 1 FROM @usr) PRINT N'PASS: T23 role_Admin gọi sp_ListUsers thành công';
ELSE PRINT N'FAIL: T23 role_Admin gọi sp_ListUsers (lỗi ' + ISNULL(CAST(@e AS NVARCHAR(10)), N'NULL') + N')';

SET @e = NULL; EXECUTE AS USER = N'u_cus';
BEGIN TRY EXEC iam.sp_ListUsers @AdminUserId = @admin; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
REVERT;
IF @e = 229 PRINT N'PASS: T24 role_Customer bị từ chối sp_ListUsers (229)'; ELSE PRINT N'FAIL: T24 role_Customer bị từ chối sp_ListUsers';

SET @e = NULL; EXECUTE AS USER = N'u_lab';
BEGIN TRY EXEC iam.sp_ListUsers @AdminUserId = @admin; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
REVERT;
IF @e = 229 PRINT N'PASS: T25 role_LabOwner bị từ chối sp_ListUsers (229)'; ELSE PRINT N'FAIL: T25 role_LabOwner bị từ chối sp_ListUsers';

SET @e = NULL;
BEGIN TRY EXEC iam.sp_ListUsers @AdminUserId = @admin, @PageSize = 0; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
IF @e = 50105 PRINT N'PASS: T26 PageSize=0 bị từ chối (50105)'; ELSE PRINT N'FAIL: T26 PageSize=0 bị từ chối';

-- ===== ai.sp_SearchKnowledge =====
DELETE FROM @kn; SET @e = NULL;
EXECUTE AS USER = N'u_cus';
BEGIN TRY INSERT @kn EXEC ai.sp_SearchKnowledge @UserId = @an, @Query = N'C-41'; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
REVERT;
IF @e IS NULL AND EXISTS (SELECT 1 FROM @kn WHERE Title LIKE N'%C-41%')
    PRINT N'PASS: T27 role_Customer tìm "C-41" ra chunk C-41';
ELSE PRINT N'FAIL: T27 role_Customer tìm "C-41" (lỗi ' + ISNULL(CAST(@e AS NVARCHAR(10)), N'NULL') + N')';

DELETE FROM @kn;
INSERT @kn EXEC ai.sp_SearchKnowledge @UserId = @an, @Query = N'Tiêu chí chọn film lab', @TopN = 10;
IF NOT EXISTS (SELECT 1 FROM @kn k JOIN ai.KnowledgeDocs d ON d.KnowledgeDocId = k.KnowledgeDocId
               WHERE d.IsApproved = 0 OR d.IsDeleted = 1)
    PRINT N'PASS: T28 Không bao giờ trả chunk chưa duyệt';
ELSE PRINT N'FAIL: T28 Không bao giờ trả chunk chưa duyệt';

DELETE FROM @kn;
INSERT @kn EXEC ai.sp_SearchKnowledge @UserId = @an, @Query = N'phim', @TopN = 1;
IF (SELECT COUNT(*) FROM @kn) = 1 PRINT N'PASS: T29 TopN=1 trả đúng 1 chunk'; ELSE PRINT N'FAIL: T29 TopN=1 trả đúng 1 chunk';

SET @e = NULL;
BEGIN TRY EXEC ai.sp_SearchKnowledge @UserId = @an, @Query = N'   '; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
IF @e = 50805 PRINT N'PASS: T30 Câu hỏi rỗng bị từ chối (50805)'; ELSE PRINT N'FAIL: T30 Câu hỏi rỗng bị từ chối';

SET @e = NULL;
BEGIN TRY EXEC ai.sp_SearchKnowledge @UserId = @an, @Query = N'C-41', @TopN = 0; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
IF @e = 50805 PRINT N'PASS: T31 TopN=0 bị từ chối (50805)'; ELSE PRINT N'FAIL: T31 TopN=0 bị từ chối';

SET @e = NULL;
BEGIN TRY EXEC ai.sp_SearchKnowledge @UserId = -1, @Query = N'C-41'; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
IF @e = 50801 PRINT N'PASS: T32 User không tồn tại bị từ chối (50801)'; ELSE PRINT N'FAIL: T32 User không tồn tại bị từ chối';

SET @e = NULL;
EXECUTE AS USER = N'u_cus';
BEGIN TRY EXEC ai.sp_SearchKnowledge @UserId = @an, @Query = N'C-41"; DROP TABLE ai.KnowledgeDocs; -- [%_'; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
REVERT;
IF @e IS NULL AND OBJECT_ID(N'ai.KnowledgeDocs') IS NOT NULL
    PRINT N'PASS: T33 Ký tự đặc biệt/chuỗi kiểu injection không gây lỗi và không phá bảng';
ELSE PRINT N'FAIL: T33 Ký tự đặc biệt/chuỗi kiểu injection (lỗi ' + ISNULL(CAST(@e AS NVARCHAR(10)), N'NULL') + N')';

SET @e = NULL; EXECUTE AS USER = N'u_lab';
BEGIN TRY EXEC ai.sp_SearchKnowledge @UserId = @an, @Query = N'C-41'; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
REVERT;
IF @e IS NULL PRINT N'PASS: T34 role_LabOwner gọi sp_SearchKnowledge thành công';
ELSE PRINT N'FAIL: T34 role_LabOwner gọi sp_SearchKnowledge (lỗi ' + CAST(@e AS NVARCHAR(10)) + N')';

SET @e = NULL; EXECUTE AS USER = N'u_exp';
BEGIN TRY EXEC ai.sp_SearchKnowledge @UserId = @an, @Query = N'C-41'; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
REVERT;
IF @e IS NULL PRINT N'PASS: T35 role_Expert gọi sp_SearchKnowledge thành công';
ELSE PRINT N'FAIL: T35 role_Expert gọi sp_SearchKnowledge (lỗi ' + CAST(@e AS NVARCHAR(10)) + N')';

SET @e = NULL; EXECUTE AS USER = N'u_adm';
BEGIN TRY EXEC ai.sp_SearchKnowledge @UserId = @admin, @Query = N'C-41'; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
REVERT;
IF @e IS NULL PRINT N'PASS: T36 role_Admin gọi sp_SearchKnowledge thành công';
ELSE PRINT N'FAIL: T36 role_Admin gọi sp_SearchKnowledge (lỗi ' + CAST(@e AS NVARCHAR(10)) + N')';

SET @e = NULL; EXECUTE AS USER = N'u_auth';
BEGIN TRY EXEC ai.sp_SearchKnowledge @UserId = @an, @Query = N'C-41'; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH
REVERT;
IF @e = 229 PRINT N'PASS: T37 role_Auth bị từ chối sp_SearchKnowledge (229)';
ELSE PRINT N'FAIL: T37 role_Auth bị từ chối sp_SearchKnowledge';

DELETE FROM @kn;
INSERT @kn EXEC ai.sp_SearchKnowledge @UserId = @an, @Query = N'C-41';
IF EXISTS (SELECT 1 FROM @kn) AND NOT EXISTS (SELECT 1 FROM @kn WHERE MatchMode NOT IN (N'FullText', N'Like'))
    PRINT N'PASS: T38 MatchMode hợp lệ (FullText hoặc Like)';
ELSE PRINT N'FAIL: T38 MatchMode hợp lệ';
DECLARE @mode NVARCHAR(10) = (SELECT TOP 1 MatchMode FROM @kn);
PRINT N'INFO: chế độ tìm kiếm hiện tại = ' + ISNULL(@mode, N'NULL');

DROP USER u_auth;
DROP USER u_cus;
DROP USER u_lab;
DROP USER u_exp;
DROP USER u_adm;
GO