/* ============================================================
   File    : database/04_seed/sample/com.sql
   Module  : com - M8 Community & Knowledge
   Purpose : Dữ liệu mẫu cho test/demo (số dòng gợi ý trong docs/Requirements.md). Tiếng Việt có dấu dùng N'...'.
   Owner   : D (xem docs/Phan-cong.md)
   Depends : iam, lab
   Re-run  : Chạy sau REBUILD=1. Sample seed không gắn cứng ID của bảng IDENTITY.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;  -- bắt buộc cho filtered index, spatial index, computed column
SET ANSI_NULLS ON;
GO

SET NOCOUNT ON;

-- Bài viết (Expert viết; có Draft, Hidden để demo kiểm duyệt; 1 câu hỏi của khách)
INSERT INTO com.Articles (AuthorId, ArticleType, Title, Slug, Summary, Body, Tags, RelatedLabId, RelatedStockId, Status, PublishedAt, ModerationReason, ModeratedBy)
SELECT u.UserId, v.Type, v.Title, v.Slug, v.Summ, v.Body, v.Tags, l.LabId, fs.StockId, v.Status,
       CASE WHEN v.DaysAgo IS NOT NULL THEN DATEADD(DAY, -v.DaysAgo, SYSUTCDATETIME()) END,
       CASE WHEN v.Status = N'Hidden' THEN N'Vi phạm quy định cộng đồng (bài mẫu)' END,
       CASE WHEN v.Status = N'Hidden' THEN a.UserId END
FROM (VALUES
    (N'expert@filmlab.vn', N'Tutorial', N'Hướng dẫn tráng phim C-41 tại nhà', N'huong-dan-trang-phim-c41-tai-nha', N'Các bước tráng phim màu C-41 với bộ hóa chất cơ bản.', N'Chuẩn bị tank, hóa chất C-41 (developer, blix, stabilizer) và nhiệt kế. Giữ nhiệt độ developer ở 38°C, tráng 3 phút 15 giây, khuấy đều theo chu kỳ. Sau đó blix, rửa và ngâm stabilizer trước khi treo khô.', N'["c41", "trang-phim", "tai-nha"]', NULL, NULL, NULL, N'Published', 14),
    (N'expert@filmlab.vn', N'Review', N'Review Kodak Portra 400: màu da đẹp, dải nhạy sáng rộng', N'review-kodak-portra-400', N'Đánh giá Portra 400 sau 10 cuộn: màu da, độ hạt, khả năng đẩy.', N'Portra 400 cho màu da ấm, độ hạt mịn và latitude rộng. Phim chịu được push +1 đến +2 stop mà vẫn giữ màu. Phù hợp chân dung và street trong điều kiện ánh sáng thay đổi.', N'["portra", "kodak", "review"]', NULL, N'Kodak', N'Portra 400', N'Published', 9),
    (N'expert@filmlab.vn', N'LabGuide', N'Cách chọn film lab ở TP.HCM', N'cach-chon-film-lab-tphcm', N'Tiêu chí chọn lab: chất lượng scan, thời gian, giá, dịch vụ giao nhận.', N'Hãy so sánh chất lượng scan mẫu, thời gian trả phim, mức giá theo cuộn và chính sách xử lý khi có sự cố. Lab có đánh giá công khai và chính sách khiếu nại rõ ràng thường đáng tin hơn.', N'["film-lab", "tphcm"]', N'Sài Gòn Film Lab', NULL, NULL, N'Published', 5),
    (N'expert@filmlab.vn', N'Technical', N'Push và pull process: khi nào nên dùng', N'push-pull-process', N'Giải thích push/pull, ảnh hưởng đến độ tương phản và hạt.', N'Bản nháp, sẽ bổ sung ví dụ thực tế.', N'["push", "pull"]', NULL, NULL, NULL, N'Draft', NULL),
    (N'an.nguyen@example.com', N'Question', N'Phim C-41 hết hạn 2 năm có tráng được không?', N'phim-c41-het-han-2-nam', N'Mình có cuộn Gold 200 hết hạn 2 năm, bảo quản nhiệt độ phòng.', N'Cuộn phim hết hạn 2 năm, để ở nhiệt độ phòng. Mình nên overexpose bao nhiêu stop và có cần báo lab không?', N'["het-han", "c41"]', NULL, N'Kodak', N'Gold 200', N'Published', 3),
    (N'expert@filmlab.vn', N'Experience', N'Bài đã bị ẩn do vi phạm quy định', N'bai-bi-an-vi-pham', N'Bài mẫu để demo kiểm duyệt.', N'Nội dung vi phạm quy định cộng đồng (mẫu).', NULL, NULL, NULL, NULL, N'Hidden', 7)
) v(Email, Type, Title, Slug, Summ, Body, Tags, LabName, Brand, Stock, Status, DaysAgo)
JOIN iam.Users u ON u.Email = v.Email
LEFT JOIN lab.FilmLabs l ON l.LabName = v.LabName
LEFT JOIN lab.FilmStocks fs ON fs.Brand = v.Brand AND fs.StockName = v.Stock
CROSS JOIN (SELECT UserId FROM iam.Users WHERE Email = N'admin@filmlab.vn') a;
GO

-- Bình luận cấp 1 (câu trả lời của Expert cho bài Question được chọn là đúng)
INSERT INTO com.ArticleComments (ArticleId, UserId, Body, IsAccepted)
SELECT a.ArticleId, u.UserId, v.Body, v.IsAccepted
FROM (VALUES
    (N'phim-c41-het-han-2-nam', N'expert@filmlab.vn', N'Thường nên overexpose 1-2 stop và báo lab để họ tráng đúng quy trình. Phim bảo quản nhiệt độ phòng có thể bị fog nhẹ.', 1),
    (N'huong-dan-trang-phim-c41-tai-nha', N'an.nguyen@example.com', N'Bài rất dễ hiểu! Cho mình hỏi dùng nước máy để pha hóa chất được không?', 0),
    (N'review-kodak-portra-400', N'binh.tran@example.com', N'Cảm ơn bạn, mình đang cân nhắc Portra 400 cho chuyến đi sắp tới.', 0)
) v(Slug, Email, Body, IsAccepted)
JOIN com.Articles a ON a.Slug = v.Slug
JOIN iam.Users u ON u.Email = v.Email;
GO

-- Trả lời bình luận (chỉ 1 cấp)
INSERT INTO com.ArticleComments (ArticleId, UserId, ParentCommentId, Body)
SELECT a.ArticleId, u.UserId, p.CommentId, v.Body
FROM (VALUES
    (N'huong-dan-trang-phim-c41-tai-nha', N'expert@filmlab.vn', N'Nên dùng nước cất hoặc nước lọc để tránh cặn, nhất là bước pha stabilizer.', N'Bài rất dễ hiểu! Cho mình hỏi dùng nước máy để pha hóa chất được không?')
) v(Slug, Email, Body, ParentBody)
JOIN com.Articles a ON a.Slug = v.Slug
JOIN iam.Users u ON u.Email = v.Email
JOIN com.ArticleComments p ON p.ArticleId = a.ArticleId AND p.Body = v.ParentBody;
GO

-- Sự kiện: 2 sắp diễn ra, 1 đã hoàn tất
INSERT INTO com.Events (OrganizerId, HostLabId, EventType, Title, Description, StartAt, EndAt, RegistrationDeadline, VenueName, AddressLine, City, Location, Capacity, Fee, Status)
SELECT u.UserId, l.LabId, v.Type, v.Title, v.Descr,
       DATEADD(DAY, v.StartD, SYSUTCDATETIME()), DATEADD(HOUR, v.Hours, DATEADD(DAY, v.StartD, SYSUTCDATETIME())),
       CASE WHEN v.DeadlineD IS NOT NULL THEN DATEADD(DAY, v.DeadlineD, SYSUTCDATETIME()) END,
       v.Venue, v.Addr, v.City, geography::Point(v.Lat, v.Lng, 4326), v.Cap, v.Fee, v.Status
FROM (VALUES
    (N'expert@filmlab.vn', N'Sài Gòn Film Lab', N'Workshop', N'Workshop tráng phim đen trắng tại nhà', N'Thực hành tráng B&W từ A-Z, mang theo cuộn phim của bạn.', 14, 3, 12, N'Sài Gòn Film Lab', N'101 Pasteur, Quận 1', N'TP. Hồ Chí Minh', 10.779, 106.699, 12, 250000, N'Open'),
    (N'expert@filmlab.vn', NULL, N'Photowalk', N'Photowalk Chợ Lớn cùng máy film', N'Đi bộ chụp phim khu Chợ Lớn, chia sẻ kỹ thuật đo sáng.', 21, 4, NULL, N'Chùa Bà Thiên Hậu', N'710 Nguyễn Trãi, Quận 5', N'TP. Hồ Chí Minh', 10.753, 106.66, 20, 0, N'Open'),
    (N'expert@filmlab.vn', N'Hà Nội Analog Lab', N'Workshop', N'Workshop scan phim và xử lý màu', N'Đã tổ chức xong, mẫu cho trạng thái Completed.', -20, 3, -22, N'Hà Nội Analog Lab', N'15 Phố Huế', N'Hà Nội', 21.015, 105.849, 10, 200000, N'Completed')
) v(Email, LabName, Type, Title, Descr, StartD, Hours, DeadlineD, Venue, Addr, City, Lat, Lng, Cap, Fee, Status)
JOIN iam.Users u ON u.Email = v.Email
LEFT JOIN lab.FilmLabs l ON l.LabName = v.LabName;
GO

INSERT INTO com.EventRegistrations (EventId, UserId, Status, IsPaid, CancelledAt)
SELECT e.EventId, u.UserId, v.Status, v.IsPaid, CASE WHEN v.Status = N'Cancelled' THEN DATEADD(DAY, -1, SYSUTCDATETIME()) END
FROM (VALUES
    (N'Workshop tráng phim đen trắng tại nhà', N'an.nguyen@example.com', N'Registered', 1),
    (N'Workshop tráng phim đen trắng tại nhà', N'binh.tran@example.com', N'Registered', 1),
    (N'Workshop tráng phim đen trắng tại nhà', N'chi.le@example.com', N'Cancelled', 0),
    (N'Photowalk Chợ Lớn cùng máy film', N'an.nguyen@example.com', N'Registered', 0),
    (N'Workshop scan phim và xử lý màu', N'chi.le@example.com', N'Attended', 1)
) v(Title, Email, Status, IsPaid)
JOIN com.Events e ON e.Title = v.Title
JOIN iam.Users u ON u.Email = v.Email;
GO
