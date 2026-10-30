/* ============================================================
   File    : database/04_seed/sample/ord_feedback.sql
   Module  : ord_feedback - M6 Review & Complaint
   Purpose : Dữ liệu mẫu cho test/demo (số dòng gợi ý trong docs/Requirements.md). Tiếng Việt có dấu dùng N'...'.
   Owner   : C (xem docs/Phan-cong.md)
   Depends : iam, lab, ord (ord.sql chạy trước)
   Re-run  : Chạy sau REBUILD=1. Sample seed không gắn cứng ID của bảng IDENTITY.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;  -- bắt buộc cho filtered index, spatial index, computed column
SET ANSI_NULLS ON;
GO

SET NOCOUNT ON;

-- Đánh giá (đơn Completed, trong 30 ngày). AvgRating/ReviewCount sẽ do trigger cập nhật ở Đợt 6; ở đây tính tay cho khớp.
INSERT INTO ord.Reviews (OrderId, CustomerId, LabId, RatingOverall, RatingScanQuality, RatingSpeed, Comment, LabReply, LabRepliedAt, CreatedAt)
SELECT o.OrderId, o.CustomerId, o.LabId, v.Overall, v.ScanQ, v.Speed, v.Comment, v.Reply,
       CASE WHEN v.Reply IS NOT NULL THEN DATEADD(DAY, 2, o.CompletedAt) END, DATEADD(DAY, 1, o.CompletedAt)
FROM (VALUES
    (N'FL-2026-000001', 5, 5, 4, N'Màu Portra 400 rất đẹp, scan sắc nét. Nhân viên nhiệt tình.', N'Cảm ơn bạn đã tin tưởng, hẹn gặp lại ở cuộn tiếp theo!'),
    (N'FL-2026-000006', 4, 3, 5, N'Tráng nhanh, giao tận nhà. Vài khung scan hơi tối.', NULL)
) v(OrderCode, Overall, ScanQ, Speed, Comment, Reply)
JOIN ord.Orders o ON o.OrderCode = v.OrderCode;
GO

UPDATE l SET AvgRating = r.AvgR, ReviewCount = r.Cnt
FROM lab.FilmLabs l
JOIN (SELECT LabId, CAST(AVG(CAST(RatingOverall AS DECIMAL(5,2))) AS DECIMAL(3,2)) AS AvgR, COUNT(*) AS Cnt
      FROM ord.Reviews WHERE IsVisible = 1 AND IsDeleted = 0 GROUP BY LabId) r ON r.LabId = l.LabId;
GO

-- Khiếu nại: 1 Open, 1 InReview, 1 Resolved (hoàn một phần phí)
INSERT INTO ord.Complaints (OrderId, CustomerId, LabId, Category, Title, Description, Status, LabResponse, AssignedAdminId, ResolutionType, Resolution, RefundAmount, ResolvedAt)
SELECT o.OrderId, o.CustomerId, o.LabId, v.Category, v.Title, v.Descr, v.Status, v.LabResp,
       CASE WHEN v.Status = N'Open' THEN NULL ELSE a.UserId END,
       v.ResType, v.Resolution, v.Refund, CASE WHEN v.Status = N'Resolved' THEN DATEADD(DAY, -1, SYSUTCDATETIME()) END
FROM (VALUES
    (N'FL-2026-000003', N'Delay', N'Giao trả phim chậm hơn dự kiến', N'Hẹn giao trước 2 ngày nhưng đến nay chưa nhận được phim.', N'Open', NULL, NULL, NULL, NULL),
    (N'FL-2026-000002', N'Delay', N'Thời gian tráng lâu hơn hẹn', N'Đơn đã quá thời gian dự kiến nhưng vẫn ở bước tráng.', N'InReview', N'Lab đang bù ca xử lý, sẽ hoàn tất trong hôm nay.', NULL, NULL, NULL),
    (N'FL-2026-000006', N'ScanQuality', N'Một số khung scan bị tối', N'Khung 5 và 6 scan tối hơn so với mẫu.', N'Resolved', N'Lab đồng ý scan lại hoặc hoàn một phần phí.', N'Refund', N'Hoàn 20.000đ phí scan cho các khung lỗi.', 20000)
) v(OrderCode, Category, Title, Descr, Status, LabResp, ResType, Resolution, Refund)
JOIN ord.Orders o ON o.OrderCode = v.OrderCode
CROSS JOIN (SELECT UserId FROM iam.Users WHERE Email = N'admin@filmlab.vn') a;
GO
