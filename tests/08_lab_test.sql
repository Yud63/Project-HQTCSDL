USE FilmLabDB;
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
SET NOCOUNT ON;
DROP TABLE IF EXISTS #r;
CREATE TABLE #r (Seq INT IDENTITY(1,1), LabId INT, LabName NVARCHAR(150), City NVARCHAR(100), DistanceKm DECIMAL(6,2),
                 AvgRating DECIMAL(3,2), ReviewCount INT, MinPrice DECIMAL(18,0), MinTurnaroundDays TINYINT);
GO

DECLARE @an INT = (SELECT UserId FROM iam.Users WHERE Email = N'an.nguyen@example.com');
DECLARE @binh INT = (SELECT UserId FROM iam.Users WHERE Email = N'binh.tran@example.com');
DECLARE @admin INT = (SELECT UserId FROM iam.Users WHERE Email = N'admin@filmlab.vn');
DECLARE @sg INT = (SELECT LabId FROM lab.FilmLabs WHERE LabName = N'Sài Gòn Film Lab');
DECLARE @svc1 INT = (SELECT LabServiceId FROM lab.LabServices WHERE LabId = @sg AND PackageName = N'Tráng C-41 35mm');
DECLARE @stype INT = (SELECT ServiceTypeId FROM lab.LabServices WHERE LabServiceId = @svc1);
DECLARE @p1 DECIMAL(18,0) = (SELECT UnitPrice FROM lab.LabServices WHERE LabServiceId = @svc1);
DECLARE @avg DECIMAL(3,2) = (SELECT AvgRating FROM lab.FilmLabs WHERE LabId = @sg);
DECLARE @minp DECIMAL(18,0) = (SELECT MIN(ls.UnitPrice) FROM lab.LabServices ls JOIN lab.FilmLabs l ON l.LabId = ls.LabId
                               WHERE ls.IsActive = 1 AND ls.IsDeleted = 0 AND l.ApprovalStatus = N'Approved' AND l.IsDeleted = 0);
DECLARE @scanType INT = (SELECT TOP 1 ServiceTypeId FROM lab.ServiceTypes WHERE Category = N'Scan' ORDER BY ServiceTypeId);
DECLARE @devType INT = (SELECT TOP 1 ServiceTypeId FROM lab.ServiceTypes WHERE Category = N'Develop' ORDER BY ServiceTypeId);
DECLARE @fmt INT = (SELECT TOP 1 FormatId FROM lab.FilmFormats ORDER BY FormatId);
DECLARE @nl INT, @e INT, @first INT, @n INT, @minr DECIMAL(3,2), @tech NVARCHAR(50);

-- 1. Tìm lab không lọc: chỉ lab Approved, có Sài Gòn
INSERT INTO #r (LabId, LabName, City, DistanceKm, AvgRating, ReviewCount, MinPrice, MinTurnaroundDays) EXEC lab.sp_SearchLabs;
IF EXISTS (SELECT 1 FROM #r WHERE LabId = @sg)
   AND NOT EXISTS (SELECT 1 FROM #r r JOIN lab.FilmLabs l ON l.LabId = r.LabId WHERE l.ApprovalStatus <> N'Approved' OR l.IsDeleted = 1)
    PRINT N'PASS: SearchLabs không lọc chỉ trả lab Approved';
ELSE PRINT N'FAIL: SearchLabs không lọc';
SET @n = (SELECT COUNT(*) FROM #r);
SET @first = (SELECT TOP 1 LabId FROM #r ORDER BY Seq);

-- 2. Lab bị đình chỉ không xuất hiện
BEGIN TRAN;
UPDATE lab.FilmLabs SET ApprovalStatus = N'Suspended' WHERE LabId = @sg;
TRUNCATE TABLE #r;
INSERT INTO #r (LabId, LabName, City, DistanceKm, AvgRating, ReviewCount, MinPrice, MinTurnaroundDays) EXEC lab.sp_SearchLabs;
IF NOT EXISTS (SELECT 1 FROM #r WHERE LabId = @sg) PRINT N'PASS: lab bị đình chỉ không xuất hiện';
ELSE PRINT N'FAIL: lab bị đình chỉ vẫn xuất hiện';
IF @@TRANCOUNT > 0 ROLLBACK;

-- 3. MinRating: bằng điểm của lab thì có, cao hơn 0.01 thì không
TRUNCATE TABLE #r;
INSERT INTO #r (LabId, LabName, City, DistanceKm, AvgRating, ReviewCount, MinPrice, MinTurnaroundDays) EXEC lab.sp_SearchLabs @MinRating = @avg;
SET @e = CASE WHEN EXISTS (SELECT 1 FROM #r WHERE LabId = @sg) THEN 1 ELSE 0 END;
SET @minr = @avg + 0.01;
TRUNCATE TABLE #r;
INSERT INTO #r (LabId, LabName, City, DistanceKm, AvgRating, ReviewCount, MinPrice, MinTurnaroundDays) EXEC lab.sp_SearchLabs @MinRating = @minr;
IF @e = 1 AND @avg < 5 AND NOT EXISTS (SELECT 1 FROM #r WHERE LabId = @sg) AND NOT EXISTS (SELECT 1 FROM #r WHERE AvgRating < @minr)
    PRINT N'PASS: lọc MinRating';
ELSE PRINT N'FAIL: lọc MinRating';

-- 4. MaxPrice = giá thấp nhất của mọi lab: có kết quả, không dòng nào vượt
TRUNCATE TABLE #r;
INSERT INTO #r (LabId, LabName, City, DistanceKm, AvgRating, ReviewCount, MinPrice, MinTurnaroundDays) EXEC lab.sp_SearchLabs @MaxPrice = @minp;
IF EXISTS (SELECT 1 FROM #r) AND NOT EXISTS (SELECT 1 FROM #r WHERE MinPrice > @minp) PRINT N'PASS: lọc MaxPrice';
ELSE PRINT N'FAIL: lọc MaxPrice';

-- 5. Lọc loại dịch vụ: có lab Sài Gòn, MinPrice không vượt giá gói đã biết
TRUNCATE TABLE #r;
INSERT INTO #r (LabId, LabName, City, DistanceKm, AvgRating, ReviewCount, MinPrice, MinTurnaroundDays) EXEC lab.sp_SearchLabs @ServiceTypeId = @stype;
IF EXISTS (SELECT 1 FROM #r WHERE LabId = @sg AND MinPrice <= @p1) PRINT N'PASS: lọc ServiceTypeId';
ELSE PRINT N'FAIL: lọc ServiceTypeId';

-- 6. Sắp xếp theo giá tăng dần
TRUNCATE TABLE #r;
INSERT INTO #r (LabId, LabName, City, DistanceKm, AvgRating, ReviewCount, MinPrice, MinTurnaroundDays) EXEC lab.sp_SearchLabs @SortBy = N'Price';
IF NOT EXISTS (SELECT 1 FROM #r a JOIN #r b ON b.Seq = a.Seq + 1 WHERE a.MinPrice > b.MinPrice) PRINT N'PASS: SortBy Price tăng dần';
ELSE PRINT N'FAIL: SortBy Price';

-- 7. Phân trang: trang 1 cỡ 1 là dòng đầu của kết quả đầy đủ; trang 2 là dòng khác (nếu có từ 2 lab)
TRUNCATE TABLE #r;
INSERT INTO #r (LabId, LabName, City, DistanceKm, AvgRating, ReviewCount, MinPrice, MinTurnaroundDays) EXEC lab.sp_SearchLabs @PageNo = 1, @PageSize = 1;
SET @e = CASE WHEN (SELECT COUNT(*) FROM #r) = 1 AND (SELECT TOP 1 LabId FROM #r) = @first THEN 1 ELSE 0 END;
TRUNCATE TABLE #r;
INSERT INTO #r (LabId, LabName, City, DistanceKm, AvgRating, ReviewCount, MinPrice, MinTurnaroundDays) EXEC lab.sp_SearchLabs @PageNo = 2, @PageSize = 1;
IF @e = 1 AND ((@n < 2 AND NOT EXISTS (SELECT 1 FROM #r)) OR (@n >= 2 AND (SELECT TOP 1 LabId FROM #r) <> @first))
    PRINT N'PASS: phân trang';
ELSE PRINT N'FAIL: phân trang';

-- 8. Sắp xếp theo khoảng cách (có tọa độ TP.HCM): tăng dần, lab thiếu tọa độ xếp cuối
TRUNCATE TABLE #r;
INSERT INTO #r (LabId, LabName, City, DistanceKm, AvgRating, ReviewCount, MinPrice, MinTurnaroundDays)
    EXEC lab.sp_SearchLabs @Latitude = 10.7769, @Longitude = 106.7009, @SortBy = N'Distance';
IF NOT EXISTS (SELECT 1 FROM #r a JOIN #r b ON b.Seq = a.Seq + 1 WHERE a.DistanceKm > b.DistanceKm)
   AND NOT EXISTS (SELECT 1 FROM #r a JOIN #r b ON b.Seq = a.Seq + 1 WHERE a.DistanceKm IS NULL AND b.DistanceKm IS NOT NULL)
    PRINT N'PASS: SortBy Distance tăng dần, NULL xếp cuối';
ELSE PRINT N'FAIL: SortBy Distance';

-- 9. MaxDistanceKm = 50: mọi dòng có khoảng cách và không quá 50
TRUNCATE TABLE #r;
INSERT INTO #r (LabId, LabName, City, DistanceKm, AvgRating, ReviewCount, MinPrice, MinTurnaroundDays)
    EXEC lab.sp_SearchLabs @Latitude = 10.7769, @Longitude = 106.7009, @MaxDistanceKm = 50;
IF NOT EXISTS (SELECT 1 FROM #r WHERE DistanceKm IS NULL OR DistanceKm > 50) PRINT N'PASS: lọc MaxDistanceKm';
ELSE PRINT N'FAIL: lọc MaxDistanceKm';

-- 10. Lọc kỹ thuật đặc biệt: mọi lab trả về phải chứa kỹ thuật đó
SET @tech = (SELECT TOP 1 CAST(j.[value] AS NVARCHAR(50)) FROM lab.FilmLabs l CROSS APPLY OPENJSON(l.SpecialTechniques) j
             WHERE l.SpecialTechniques IS NOT NULL AND j.[type] = 1 ORDER BY l.LabId);
IF @tech IS NULL PRINT N'SKIP: seed không có kỹ thuật đặc biệt dạng chuỗi';
ELSE
BEGIN
    TRUNCATE TABLE #r;
    INSERT INTO #r (LabId, LabName, City, DistanceKm, AvgRating, ReviewCount, MinPrice, MinTurnaroundDays) EXEC lab.sp_SearchLabs @Technique = @tech;
    IF NOT EXISTS (SELECT 1 FROM #r r JOIN lab.FilmLabs l ON l.LabId = r.LabId
                   WHERE NOT EXISTS (SELECT 1 FROM OPENJSON(l.SpecialTechniques) j WHERE j.[value] = @tech))
        PRINT N'PASS: lọc Technique';
    ELSE PRINT N'FAIL: lọc Technique';
END;

-- 11. PageNo = 0 -> 50205
SET @e = 0; BEGIN TRY EXEC lab.sp_SearchLabs @PageNo = 0; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @e = 50205 PRINT N'PASS: PageNo = 0 -> 50205'; ELSE PRINT N'FAIL: PageNo, nhận ' + CAST(@e AS NVARCHAR(10));
-- 12. PageSize = 101 -> 50205
SET @e = 0; BEGIN TRY EXEC lab.sp_SearchLabs @PageSize = 101; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @e = 50205 PRINT N'PASS: PageSize = 101 -> 50205'; ELSE PRINT N'FAIL: PageSize, nhận ' + CAST(@e AS NVARCHAR(10));
-- 13. SortBy lạ -> 50205
SET @e = 0; BEGIN TRY EXEC lab.sp_SearchLabs @SortBy = N'Foo'; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @e = 50205 PRINT N'PASS: SortBy lạ -> 50205'; ELSE PRINT N'FAIL: SortBy, nhận ' + CAST(@e AS NVARCHAR(10));
-- 14. MaxDistanceKm thiếu tọa độ -> 50205
SET @e = 0; BEGIN TRY EXEC lab.sp_SearchLabs @MaxDistanceKm = 10; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @e = 50205 PRINT N'PASS: MaxDistanceKm thiếu tọa độ -> 50205'; ELSE PRINT N'FAIL: MaxDistanceKm, nhận ' + CAST(@e AS NVARCHAR(10));
-- 15. Vĩ độ ngoài phạm vi -> 50205
SET @e = 0; BEGIN TRY EXEC lab.sp_SearchLabs @Latitude = 100, @Longitude = 106; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @e = 50205 PRINT N'PASS: vĩ độ ngoài phạm vi -> 50205'; ELSE PRINT N'FAIL: vĩ độ, nhận ' + CAST(@e AS NVARCHAR(10));

-- 16. Duyệt lab Pending: Approved + LabApprovals + nhật ký audit UPDATE
BEGIN TRAN;
BEGIN TRY
    INSERT INTO lab.FilmLabs (OwnerUserId, LabName, AddressLine, Ward, District, City)
    VALUES (@binh, N'Lab thử duyệt', N'1 Đường Thử', N'Phường 1', N'Quận 1', N'TP.HCM');
    SET @nl = SCOPE_IDENTITY();
    EXEC lab.sp_ApproveLab @nl, @admin, N'Approved', NULL;
    IF EXISTS (SELECT 1 FROM lab.FilmLabs WHERE LabId = @nl AND ApprovalStatus = N'Approved')
       AND EXISTS (SELECT 1 FROM lab.LabApprovals WHERE LabId = @nl AND Decision = N'Approved' AND ReviewedBy = @admin)
       AND EXISTS (SELECT 1 FROM audit.AuditLogs WHERE TableSchema = N'lab' AND TableName = N'FilmLabs'
                   AND PrimaryKeyValue = CAST(@nl AS NVARCHAR(100)) AND Action = N'UPDATE' AND ChangedBy = @admin)
        PRINT N'PASS: duyệt lab + LabApprovals + audit';
    ELSE PRINT N'FAIL: duyệt lab';
END TRY
BEGIN CATCH PRINT N'FAIL: duyệt lab, lỗi ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;

-- 17. Từ chối không có lý do -> 50205
SET @e = 0; BEGIN TRAN;
INSERT INTO lab.FilmLabs (OwnerUserId, LabName, AddressLine, Ward, District, City) VALUES (@binh, N'Lab thử duyệt', N'1 Đường Thử', N'Phường 1', N'Quận 1', N'TP.HCM');
SET @nl = SCOPE_IDENTITY();
BEGIN TRY EXEC lab.sp_ApproveLab @nl, @admin, N'Rejected', NULL; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50205 PRINT N'PASS: từ chối thiếu lý do -> 50205'; ELSE PRINT N'FAIL: từ chối thiếu lý do, nhận ' + CAST(@e AS NVARCHAR(10));

-- 18. Từ chối có lý do: Rejected + lưu lý do
BEGIN TRAN;
BEGIN TRY
    INSERT INTO lab.FilmLabs (OwnerUserId, LabName, AddressLine, Ward, District, City) VALUES (@binh, N'Lab thử duyệt', N'1 Đường Thử', N'Phường 1', N'Quận 1', N'TP.HCM');
    SET @nl = SCOPE_IDENTITY();
    EXEC lab.sp_ApproveLab @nl, @admin, N'Rejected', N'Thiếu giấy phép kinh doanh';
    IF EXISTS (SELECT 1 FROM lab.FilmLabs WHERE LabId = @nl AND ApprovalStatus = N'Rejected')
       AND EXISTS (SELECT 1 FROM lab.LabApprovals WHERE LabId = @nl AND Decision = N'Rejected' AND Reason = N'Thiếu giấy phép kinh doanh')
        PRINT N'PASS: từ chối lab có lý do';
    ELSE PRINT N'FAIL: từ chối lab';
END TRY
BEGIN CATCH PRINT N'FAIL: từ chối lab, lỗi ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;

-- 19. Duyệt hai lần -> 50202
SET @e = 0; BEGIN TRAN;
INSERT INTO lab.FilmLabs (OwnerUserId, LabName, AddressLine, Ward, District, City) VALUES (@binh, N'Lab thử duyệt', N'1 Đường Thử', N'Phường 1', N'Quận 1', N'TP.HCM');
SET @nl = SCOPE_IDENTITY();
EXEC lab.sp_ApproveLab @nl, @admin, N'Approved', NULL;
BEGIN TRY EXEC lab.sp_ApproveLab @nl, @admin, N'Approved', NULL; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50202 PRINT N'PASS: duyệt lần hai -> 50202'; ELSE PRINT N'FAIL: duyệt lần hai, nhận ' + CAST(@e AS NVARCHAR(10));

-- 20. Người không phải Admin -> 50203
SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC lab.sp_ApproveLab @sg, @an, N'Suspended', N'Thử'; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50203 PRINT N'PASS: không phải Admin -> 50203'; ELSE PRINT N'FAIL: không phải Admin, nhận ' + CAST(@e AS NVARCHAR(10));

-- 21. Lab không tồn tại -> 50201
SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC lab.sp_ApproveLab -1, @admin, N'Approved', NULL; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50201 PRINT N'PASS: lab không tồn tại -> 50201'; ELSE PRINT N'FAIL: lab không tồn tại, nhận ' + CAST(@e AS NVARCHAR(10));

-- 22. Quyết định không hợp lệ -> 50205
SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC lab.sp_ApproveLab @sg, @admin, N'Pending', NULL; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50205 PRINT N'PASS: quyết định không hợp lệ -> 50205'; ELSE PRINT N'FAIL: quyết định không hợp lệ, nhận ' + CAST(@e AS NVARCHAR(10));

-- 23. Đình chỉ rồi duyệt lại: Approved -> Suspended -> Approved, 3 dòng LabApprovals
BEGIN TRAN;
BEGIN TRY
    INSERT INTO lab.FilmLabs (OwnerUserId, LabName, AddressLine, Ward, District, City) VALUES (@binh, N'Lab thử duyệt', N'1 Đường Thử', N'Phường 1', N'Quận 1', N'TP.HCM');
    SET @nl = SCOPE_IDENTITY();
    EXEC lab.sp_ApproveLab @nl, @admin, N'Approved', NULL;
    EXEC lab.sp_ApproveLab @nl, @admin, N'Suspended', N'Khiếu nại nhiều';
    EXEC lab.sp_ApproveLab @nl, @admin, N'Approved', NULL;
    IF EXISTS (SELECT 1 FROM lab.FilmLabs WHERE LabId = @nl AND ApprovalStatus = N'Approved')
       AND (SELECT COUNT(*) FROM lab.LabApprovals WHERE LabId = @nl) = 3
        PRINT N'PASS: đình chỉ rồi duyệt lại';
    ELSE PRINT N'FAIL: đình chỉ rồi duyệt lại';
END TRY
BEGIN CATCH PRINT N'FAIL: đình chỉ rồi duyệt lại, lỗi ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;

-- 24. Gói Scan thiếu ScanQuality -> 50205
SET @e = 0; BEGIN TRAN;
BEGIN TRY INSERT INTO lab.LabServices (LabId, ServiceTypeId, FormatId, PackageName, UnitPrice, TurnaroundDays)
          VALUES (@sg, @scanType, @fmt, N'Gói scan thử', 1000, 1); END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50205 PRINT N'PASS: gói Scan thiếu ScanQuality -> 50205'; ELSE PRINT N'FAIL: gói Scan thiếu ScanQuality, nhận ' + CAST(@e AS NVARCHAR(10));

-- 25. Gói Develop có ScanQuality -> 50205
SET @e = 0; BEGIN TRAN;
BEGIN TRY INSERT INTO lab.LabServices (LabId, ServiceTypeId, FormatId, PackageName, UnitPrice, ScanQuality, TurnaroundDays)
          VALUES (@sg, @devType, @fmt, N'Gói tráng thử', 1000, N'High', 1); END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50205 PRINT N'PASS: gói Develop có ScanQuality -> 50205'; ELSE PRINT N'FAIL: gói Develop có ScanQuality, nhận ' + CAST(@e AS NVARCHAR(10));

-- 26. Gói Scan có ScanQuality thì hợp lệ
BEGIN TRAN;
BEGIN TRY
    INSERT INTO lab.LabServices (LabId, ServiceTypeId, FormatId, PackageName, UnitPrice, ScanQuality, TurnaroundDays)
    VALUES (@sg, @scanType, @fmt, N'Gói scan thử', 1000, N'High', 1);
    PRINT N'PASS: gói Scan hợp lệ được thêm';
END TRY
BEGIN CATCH PRINT N'FAIL: gói Scan hợp lệ, lỗi ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;

-- 27. Dữ liệu seed hiện có không vi phạm quy tắc Scan
IF NOT EXISTS (SELECT 1 FROM lab.LabServices ls JOIN lab.ServiceTypes st ON st.ServiceTypeId = ls.ServiceTypeId
               WHERE (st.Category = N'Scan' AND ls.ScanQuality IS NULL) OR (st.Category <> N'Scan' AND ls.ScanQuality IS NOT NULL))
    PRINT N'PASS: seed LabServices khớp quy tắc ScanQuality';
ELSE PRINT N'FAIL: seed LabServices có gói vi phạm quy tắc ScanQuality';

-- 28. UPDATE trực tiếp FilmLabs ghi audit
BEGIN TRAN;
BEGIN TRY
    EXEC sp_set_session_context @key = N'UserId', @value = @admin;
    UPDATE lab.FilmLabs SET DailyCapacityRolls = DailyCapacityRolls + 1 WHERE LabId = @sg;
    IF EXISTS (SELECT 1 FROM audit.AuditLogs WHERE TableSchema = N'lab' AND TableName = N'FilmLabs'
               AND PrimaryKeyValue = CAST(@sg AS NVARCHAR(100)) AND Action = N'UPDATE' AND ChangedBy = @admin
               AND OldValues IS NOT NULL AND NewValues IS NOT NULL)
        PRINT N'PASS: trigger FilmLabs_Audit ghi UPDATE';
    ELSE PRINT N'FAIL: trigger FilmLabs_Audit';
END TRY
BEGIN CATCH PRINT N'FAIL: FilmLabs_Audit, lỗi ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;

-- 29. lab.vw_TopLabs: chỉ lab Approved có đánh giá, xếp hạng liên tục, điểm giảm dần, có Sài Gòn
IF EXISTS (SELECT 1 FROM lab.vw_TopLabs WHERE LabId = @sg)
   AND NOT EXISTS (SELECT 1 FROM lab.vw_TopLabs v JOIN lab.FilmLabs l ON l.LabId = v.LabId WHERE l.ApprovalStatus <> N'Approved' OR v.ReviewCount < 1)
   AND NOT EXISTS (SELECT 1 FROM lab.vw_TopLabs a JOIN lab.vw_TopLabs b ON b.RankNo = a.RankNo + 1 WHERE a.AvgRating < b.AvgRating)
    PRINT N'PASS: lab.vw_TopLabs';
ELSE PRINT N'FAIL: lab.vw_TopLabs';
GO