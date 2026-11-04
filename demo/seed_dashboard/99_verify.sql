/* ============================================================
   File    : demo/seed_dashboard/99_verify.sql
   Purpose : Kiểm tra dữ liệu seed dashboard C1-C4. Mong đợi 20 PASS.
   Cách chạy (từ thư mục gốc repo, KHÔNG dùng -b):
     sqlcmd -S localhost -E -C -f 65001 -d FilmLabDB -i demo\seed_dashboard\99_verify.sql | find /c "PASS:"
   Quy ước : Đơn seed và chunk dùng mốc tối thiểu (>=) nên thêm dòng vẫn PASS.
             Mốc cố định (13 stage, trạng thái 3 lab, đơn của UserId 6 = 2) dùng khớp đúng số.
   ============================================================ */
USE FilmLabDB;
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
SET NOCOUNT ON;

DECLARE @an INT = (SELECT UserId FROM iam.Users WHERE Email = N'an.nguyen@example.com');
DECLARE @r TABLE (Seq INT IDENTITY(1,1), Name NVARCHAR(200), Ok BIT);
DECLARE @kn TABLE (KnowledgeDocId INT, SourceArticleId INT, ChunkIndex INT, Title NVARCHAR(200), Topic NVARCHAR(50),
                   Content NVARCHAR(4000), Score INT, MatchMode NVARCHAR(10));

-- ===== C1: tài khoản + địa chỉ =====
INSERT @r (Name, Ok) SELECT N'T01 3 Customer mới có role Customer (không có LabOwner)',
    CASE WHEN (SELECT COUNT(*) FROM iam.Users u
               WHERE u.IsDeleted = 0 AND u.Email IN (N'khach.minh@example.com', N'khach.lan@example.com', N'khach.nam@example.com')
                 AND EXISTS (SELECT 1 FROM iam.UserRoles ur JOIN iam.Roles r ON r.RoleId = ur.RoleId WHERE ur.UserId = u.UserId AND r.RoleCode = N'Customer')
                 AND NOT EXISTS (SELECT 1 FROM iam.UserRoles ur JOIN iam.Roles r ON r.RoleId = ur.RoleId WHERE ur.UserId = u.UserId AND r.RoleCode = N'LabOwner')) = 3
         THEN 1 ELSE 0 END;

INSERT @r (Name, Ok) SELECT N'T02 2 LabOwner mới có cả role Customer và LabOwner',
    CASE WHEN (SELECT COUNT(*) FROM iam.Users u
               WHERE u.IsDeleted = 0 AND u.Email IN (N'lab.cantho@filmlab.vn', N'lab.dalat@filmlab.vn')
                 AND EXISTS (SELECT 1 FROM iam.UserRoles ur JOIN iam.Roles r ON r.RoleId = ur.RoleId WHERE ur.UserId = u.UserId AND r.RoleCode = N'Customer')
                 AND EXISTS (SELECT 1 FROM iam.UserRoles ur JOIN iam.Roles r ON r.RoleId = ur.RoleId WHERE ur.UserId = u.UserId AND r.RoleCode = N'LabOwner')) = 2
         THEN 1 ELSE 0 END;

INSERT @r (Name, Ok) SELECT N'T03 3 Customer mới có đúng 4 địa chỉ (Minh 2, Lan 1, Nam 1)',
    CASE WHEN (SELECT COUNT(*) FROM iam.Addresses a JOIN iam.Users u ON u.UserId = a.UserId
               WHERE a.IsDeleted = 0 AND u.Email IN (N'khach.minh@example.com', N'khach.lan@example.com', N'khach.nam@example.com')) = 4
          AND (SELECT COUNT(*) FROM iam.Addresses a JOIN iam.Users u ON u.UserId = a.UserId
               WHERE a.IsDeleted = 0 AND u.Email = N'khach.minh@example.com') = 2
         THEN 1 ELSE 0 END;

-- ===== C2: lab =====
INSERT @r (Name, Ok) SELECT N'T04 Cần Thơ Film Lab Approved, có >= 7 gói dịch vụ',
    CASE WHEN EXISTS (SELECT 1 FROM lab.FilmLabs l WHERE l.LabName = N'Cần Thơ Film Lab' AND l.IsDeleted = 0 AND l.ApprovalStatus = N'Approved'
                      AND (SELECT COUNT(*) FROM lab.LabServices s WHERE s.LabId = l.LabId AND s.IsDeleted = 0) >= 7)
         THEN 1 ELSE 0 END;

INSERT @r (Name, Ok) SELECT N'T05 Đà Lạt Retro Lab Suspended, lịch sử có Approved và Suspended kèm lý do',
    CASE WHEN EXISTS (SELECT 1 FROM lab.FilmLabs l WHERE l.LabName = N'Đà Lạt Retro Lab' AND l.IsDeleted = 0 AND l.ApprovalStatus = N'Suspended'
                      AND EXISTS (SELECT 1 FROM lab.LabApprovals a WHERE a.LabId = l.LabId AND a.Decision = N'Approved')
                      AND EXISTS (SELECT 1 FROM lab.LabApprovals a WHERE a.LabId = l.LabId AND a.Decision = N'Suspended' AND a.Reason IS NOT NULL))
         THEN 1 ELSE 0 END;

INSERT @r (Name, Ok) SELECT N'T06 Đà Nẵng Retro Lab vẫn Pending (không bị seed đụng)',
    CASE WHEN EXISTS (SELECT 1 FROM lab.FilmLabs WHERE LabName = N'Đà Nẵng Retro Lab' AND IsDeleted = 0 AND ApprovalStatus = N'Pending')
         THEN 1 ELSE 0 END;

-- ===== C3: đơn =====
INSERT @r (Name, Ok) SELECT N'T07 Có >= 12 đơn seed C3 và tất cả thuộc Cần Thơ Film Lab',
    CASE WHEN (SELECT COUNT(*) FROM ord.Orders WHERE IsDeleted = 0 AND CustomerNote LIKE N'[[]seed-c3-%') >= 12
          AND (SELECT COUNT(*) FROM ord.Orders WHERE IsDeleted = 0 AND CustomerNote LIKE N'[[]seed-c3-%')
            = (SELECT COUNT(*) FROM ord.Orders o JOIN lab.FilmLabs l ON l.LabId = o.LabId
               WHERE o.IsDeleted = 0 AND o.CustomerNote LIKE N'[[]seed-c3-%' AND l.LabName = N'Cần Thơ Film Lab')
         THEN 1 ELSE 0 END;

INSERT @r (Name, Ok) SELECT N'T08 Đơn seed C3 chỉ của 3 Customer mới (không đụng khách cũ)',
    CASE WHEN NOT EXISTS (SELECT 1 FROM ord.Orders o JOIN iam.Users u ON u.UserId = o.CustomerId
                          WHERE o.IsDeleted = 0 AND o.CustomerNote LIKE N'[[]seed-c3-%'
                            AND u.Email NOT IN (N'khach.minh@example.com', N'khach.lan@example.com', N'khach.nam@example.com'))
         THEN 1 ELSE 0 END;

INSERT @r (Name, Ok) SELECT N'T09 Đơn seed-c3-07 là Completed (stage 12) và Paid',
    CASE WHEN EXISTS (SELECT 1 FROM ord.Orders WHERE IsDeleted = 0 AND CustomerNote LIKE N'[[]seed-c3-07]%'
                      AND StageId = 12 AND PaymentStatus = N'Paid') THEN 1 ELSE 0 END;

INSERT @r (Name, Ok) SELECT N'T10 Đơn seed-c3-08 Cancelled (stage 13), Refunded và có payment Refunded',
    CASE WHEN EXISTS (SELECT 1 FROM ord.Orders o WHERE o.IsDeleted = 0 AND o.CustomerNote LIKE N'[[]seed-c3-08]%'
                      AND o.StageId = 13 AND o.PaymentStatus = N'Refunded'
                      AND EXISTS (SELECT 1 FROM ord.Payments p WHERE p.OrderId = o.OrderId AND p.Status = N'Refunded'))
         THEN 1 ELSE 0 END;

INSERT @r (Name, Ok) SELECT N'T11 Đơn seed-c3-09 Cancelled (stage 13) và Unpaid',
    CASE WHEN EXISTS (SELECT 1 FROM ord.Orders WHERE IsDeleted = 0 AND CustomerNote LIKE N'[[]seed-c3-09]%'
                      AND StageId = 13 AND PaymentStatus = N'Unpaid') THEN 1 ELSE 0 END;

INSERT @r (Name, Ok) SELECT N'T12 Toàn bộ 13 stage đều có ít nhất 1 đơn',
    CASE WHEN (SELECT COUNT(DISTINCT StageId) FROM ord.Orders WHERE IsDeleted = 0) = 13 THEN 1 ELSE 0 END;

INSERT @r (Name, Ok) SELECT N'T13 Đơn của UserId 6 (an.nguyen) vẫn đúng 2',
    CASE WHEN (SELECT COUNT(*) FROM ord.Orders WHERE CustomerId = @an) = 2 THEN 1 ELSE 0 END;

INSERT @r (Name, Ok) SELECT N'T14 Mỗi đơn seed Paid có đúng 1 payment Succeeded khớp TotalAmount',
    CASE WHEN NOT EXISTS (SELECT 1 FROM ord.Orders o
                          WHERE o.IsDeleted = 0 AND o.CustomerNote LIKE N'[[]seed-c3-%' AND o.PaymentStatus = N'Paid'
                            AND (SELECT COUNT(*) FROM ord.Payments p
                                 WHERE p.OrderId = o.OrderId AND p.Status = N'Succeeded' AND p.Amount = o.TotalAmount) <> 1)
         THEN 1 ELSE 0 END;

INSERT @r (Name, Ok) SELECT N'T15 Mỗi đơn seed có dòng OrderStageLog khớp stage hiện tại',
    CASE WHEN NOT EXISTS (SELECT 1 FROM ord.Orders o
                          WHERE o.IsDeleted = 0 AND o.CustomerNote LIKE N'[[]seed-c3-%'
                            AND NOT EXISTS (SELECT 1 FROM ord.OrderStageLog g WHERE g.OrderId = o.OrderId AND g.ToStageId = o.StageId))
         THEN 1 ELSE 0 END;

-- ===== C4: tri thức =====
INSERT @r (Name, Ok) SELECT N'T16 Có >= 24 chunk do Expert đóng góp, không gắn bài viết',
    CASE WHEN (SELECT COUNT(*) FROM ai.KnowledgeDocs d JOIN iam.Users u ON u.UserId = d.ContributedBy
               WHERE d.IsDeleted = 0 AND d.SourceArticleId IS NULL AND u.Email = N'expert@filmlab.vn') >= 24
         THEN 1 ELSE 0 END;

INSERT @r (Name, Ok) SELECT N'T17 Có >= 3 chunk chưa duyệt; mọi chunk đã duyệt đều có ApprovedBy',
    CASE WHEN (SELECT COUNT(*) FROM ai.KnowledgeDocs WHERE IsDeleted = 0 AND IsApproved = 0) >= 3
          AND NOT EXISTS (SELECT 1 FROM ai.KnowledgeDocs WHERE IsDeleted = 0 AND IsApproved = 1 AND (ApprovedBy IS NULL OR ApprovedAt IS NULL))
         THEN 1 ELSE 0 END;

INSERT @r (Name, Ok) SELECT N'T18 Có >= 3 chunk đã duyệt có "C-41" trong Title',
    CASE WHEN (SELECT COUNT(*) FROM ai.KnowledgeDocs WHERE IsDeleted = 0 AND IsApproved = 1 AND Title LIKE N'%C-41%') >= 3
         THEN 1 ELSE 0 END;

DELETE FROM @kn;
INSERT @kn EXEC ai.sp_SearchKnowledge @UserId = @an, @Query = N'C-41';
INSERT @r (Name, Ok) SELECT N'T19 Tìm "C-41" (TopN mặc định 3) có chunk Title chứa C-41',
    CASE WHEN EXISTS (SELECT 1 FROM @kn WHERE Title LIKE N'%C-41%') THEN 1 ELSE 0 END;

DELETE FROM @kn;
INSERT @kn EXEC ai.sp_SearchKnowledge @UserId = @an, @Query = N'hiệu chỉnh màu thủ công', @TopN = 10;
INSERT @r (Name, Ok) SELECT N'T20 Tìm kiếm không bao giờ trả chunk chưa duyệt',
    CASE WHEN EXISTS (SELECT 1 FROM @kn)
          AND NOT EXISTS (SELECT 1 FROM @kn k JOIN ai.KnowledgeDocs d ON d.KnowledgeDocId = k.KnowledgeDocId WHERE d.IsApproved = 0)
         THEN 1 ELSE 0 END;

-- ===== In kết quả =====
SELECT Seq, Name, Ok INTO #r FROM @r;
DECLARE @s INT = 1, @cnt INT = (SELECT COUNT(*) FROM #r), @nm NVARCHAR(200), @ok BIT, @pass INT = 0;
WHILE @s <= @cnt
BEGIN
    SELECT @nm = Name, @ok = Ok FROM #r WHERE Seq = @s;
    IF @ok = 1 BEGIN PRINT N'PASS: ' + @nm; SET @pass += 1; END
    ELSE PRINT N'FAIL: ' + @nm;
    SET @s += 1;
END;
PRINT N'INFO: ' + CAST(@pass AS NVARCHAR(5)) + N'/' + CAST(@cnt AS NVARCHAR(5)) + N' kiểm tra đạt';
DROP TABLE #r;
GO