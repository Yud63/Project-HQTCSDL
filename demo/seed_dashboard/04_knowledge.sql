/* ============================================================
   File    : demo/seed_dashboard/04_knowledge.sql
   Purpose : Seed dashboard C4 - 24 chunk tri thức tiếng Việt cho ai.KnowledgeDocs (RAG chatbot).
   Depends : Seed mẫu iam (expert@filmlab.vn là Expert, admin@filmlab.vn là Admin).
   LƯU Ý NỘI DUNG: Kiến thức nhiếp ảnh phim là THAM KHẢO, viết cho demo từ hiểu biết chung (nhiệt độ, thời gian, đặc điểm phim
                   là mức phổ biến). Cần đối chiếu datasheet của hãng (Kodak, Ilford, Fujifilm) nếu dùng cho báo cáo chính thức.
                   2 chunk "Đặt đơn FilmLab" mô tả đúng hành vi hiện tại của hệ thống (13 stage, chính sách hủy, phí giao).
   Sửa/thêm: Sửa Content hoặc Topic của 1 dòng trong @k rồi chạy lại -> script CẬP NHẬT tại chỗ theo Title (giữ nguyên trạng thái duyệt).
             Thêm dòng mới -> chỉ chunk mới được thêm. Đổi Title = chunk mới (chunk cũ ẩn bằng:
             UPDATE ai.KnowledgeDocs SET IsDeleted = 1 WHERE Title = N'<tiêu đề cũ>';).
             Đổi trạng thái duyệt: dùng ai.sp_ApproveKnowledgeDoc, không đổi qua file này.
   Re-run  : Chạy lại được (so khớp theo Title; chỉ UPDATE khi Content/Topic đổi; không tạo trùng).
   Chạy    : sqlcmd -S localhost -E -C -f 65001 -d FilmLabDB -W -i demo\seed_dashboard\04_knowledge.sql
   Lưu ý   : KHÔNG đưa vào 99_run_all.sql / build.cmd. EmbeddingJson = NULL (không giả embedding).
   ============================================================ */
USE FilmLabDB;
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
SET NOCOUNT ON;

DECLARE @Expert INT = (SELECT UserId FROM iam.Users WHERE Email = N'expert@filmlab.vn' AND IsDeleted = 0);
DECLARE @Admin  INT = (SELECT UserId FROM iam.Users WHERE Email = N'admin@filmlab.vn'  AND IsDeleted = 0);
IF @Expert IS NULL OR @Admin IS NULL
    THROW 50000, N'Thiếu expert@filmlab.vn hoặc admin@filmlab.vn: chạy build + seed mẫu trước.', 1;

-- ===== 1. DANH SÁCH CHUNK (sửa / thêm dòng ở đây). Approved: 1 = đã duyệt, 0 = chưa duyệt (demo duyệt tri thức) =====
DECLARE @k TABLE (Seq INT IDENTITY(1,1), Title NVARCHAR(200), Topic NVARCHAR(50), Content NVARCHAR(4000), Approved BIT);
INSERT @k (Title, Topic, Content, Approved) VALUES
 (N'C-41: quy trình tráng phim màu negative', N'C-41',
  N'C-41 là quy trình tráng chuẩn cho phim màu negative như Portra, Gold, Ultramax hay Superia. Quy trình gồm developer, blix (bleach-fix), rửa nước và stabilizer rồi treo khô. Hầu hết lab nhận tráng C-41 vì đây là quy trình phổ biến và rẻ nhất. (Nội dung tham khảo.)', 1),
 (N'C-41: nhiệt độ, thời gian và khuấy đảo (tham khảo)', N'C-41',
  N'Developer C-41 thường được giữ quanh 38°C, thời gian khoảng 3 phút 15 giây, khuấy đảo đều theo chu kỳ để tránh loang màu. Nhiệt độ lệch vài phần mười độ đã có thể làm lệch màu, nên lab chuyên nghiệp dùng máy tráng hoặc bể giữ nhiệt. Số liệu mang tính tham khảo, hãy đối chiếu hướng dẫn của hãng hóa chất.', 1),
 (N'C-41: các lỗi thường gặp khi tráng', N'C-41',
  N'Ám vàng hoặc cam thường do developer nguội hoặc quá yếu; màu loang do khuấy đảo không đều; vệt nước do thiếu stabilizer hoặc sấy ở nơi nhiều bụi; hạt thô và màu nhạt có thể do phim quá hạn hoặc chụp thiếu sáng. Nếu nghi lỗi tráng, hãy giữ lại phim và khiếu nại với lab kèm ảnh scan. (Tham khảo.)', 1),
 (N'E-6: quy trình tráng phim slide', N'E-6',
  N'E-6 là quy trình tráng phim slide (đảo ngược) như Ektachrome và Velvia. Quy trình có nhiều bước hơn C-41: first developer, reversal, color developer, bleach, fix rồi stabilizer. Mỗi bước phải đúng nhiệt độ và thời gian, sai lệch nhỏ cũng ảnh hưởng đến màu và độ sáng của slide. (Nội dung tham khảo.)', 1),
 (N'E-6: vì sao tráng slide đắt hơn và lâu hơn', N'E-6',
  N'Tráng E-6 thường đắt hơn tráng phim màu negative vì ít lab nhận, hóa chất nhiều bước và phải kiểm soát chặt. Thời gian trả phim thường dài hơn, khoảng 3 đến 7 ngày tùy lab. Khi chọn lab hãy xem gói dịch vụ có ghi rõ quy trình E-6 hay không. (Tham khảo.)', 1),
 (N'E-6: push và pull phim slide', N'E-6',
  N'Phim slide có latitude hẹp, thường chỉ chịu sai lệch khoảng một stop, nên đo sáng chính xác rất quan trọng. Push hoặc pull slide được thực hiện bằng cách đổi thời gian first developer, và phải báo lab trước khi gửi phim. Không phải lab nào cũng nhận. (Tham khảo, chưa được duyệt.)', 0),
 (N'Tráng phim đen trắng (B&W): developer, stop và fix', N'Black & White',
  N'Quy trình B&W gồm developer, stop bath (hoặc rửa nước), fixer, rửa kỹ rồi thêm wetting agent trước khi sấy. Thời gian tráng phụ thuộc loại phim, loại developer, độ pha loãng và nhiệt độ, thường dùng khoảng 20°C. Hãy tra bảng thời gian của hãng phim hoặc hãng developer. (Tham khảo.)', 1),
 (N'B&W: kiểm soát nhiệt độ và khuấy đảo', N'Black & White',
  N'Với phim đen trắng, nhiệt độ lệch 1°C có thể cần chỉnh thời gian tráng. Khuấy đảo nhiều làm tăng độ tương phản và có thể gây vệt, khuấy ít gây tráng không đều. Nhiều lab dùng chu kỳ khuấy cố định (vài giây mỗi phút) để kết quả ổn định giữa các cuộn. (Tham khảo.)', 1),
 (N'B&W: chọn developer ảnh hưởng đến hạt và độ tương phản', N'Black & White',
  N'Developer khác nhau cho kết quả khác nhau: loại hạt mịn như D-76 cho tông mềm, loại đậm đặc như Rodinal cho hạt rõ và độ nét cao, HC-110 pha được nhiều nồng độ. Lab thường dùng một developer cố định, nếu muốn loại cụ thể hãy hỏi lab trước. (Tham khảo, chưa được duyệt.)', 0),
 (N'ECN-2: tráng phim điện ảnh Vision3 (tham khảo)', N'ECN-2',
  N'ECN-2 là quy trình tráng phim điện ảnh màu negative như Kodak Vision3 500T. Loại phim này có lớp remjet ở mặt sau cần được loại bỏ khi tráng, và không phải lab nào cũng nhận ECN-2. Nếu gửi phim điện ảnh, hãy hỏi lab trước thay vì chọn gói tráng thông thường. (Tham khảo.)', 1),
 (N'Push và pull là gì (tham khảo)', N'Push/Pull',
  N'Push là chụp phim ở ISO cao hơn ISO danh định rồi kéo dài thời gian tráng để bù, ví dụ phim 400 chụp ở 800 là push một stop. Pull ngược lại: chụp ở ISO thấp hơn và rút ngắn thời gian tráng. Push thường dùng khi thiếu sáng, pull khi muốn giảm độ tương phản. (Tham khảo.)', 1),
 (N'Push và pull: ảnh hưởng đến hạt, tương phản và lưu ý', N'Push/Pull',
  N'Push làm tăng hạt và độ tương phản, vùng tối có thể mất chi tiết; pull làm giảm tương phản và màu nhạt hơn. Cả cuộn phim phải chụp cùng một mức push hoặc pull, và cần ghi chú khi đặt đơn. Một số lab tính phụ phí cho dịch vụ này. (Tham khảo.)', 1),
 (N'Scan Basic, High và Ultra: khác nhau thế nào', N'Scan',
  N'Gói scan thường chia ba mức: Basic cho ảnh chia sẻ mạng xã hội (độ phân giải thấp, file JPEG), High cho ảnh in và lưu trữ (độ phân giải cao hơn, có thể kèm TIFF), Ultra cho độ phân giải cao nhất và hiệu chỉnh thủ công. Mức cụ thể tùy từng lab, hãy xem mô tả gói. (Tham khảo.)', 1),
 (N'Scan phim: JPEG, TIFF và dung lượng file', N'Scan',
  N'JPEG nhẹ, tiện chia sẻ nhưng nén mất dữ liệu; TIFF giữ nguyên chất lượng, phù hợp chỉnh sửa nhưng dung lượng lớn hơn nhiều lần. Scan độ phân giải càng cao thì file càng nặng, nên chuẩn bị dung lượng lưu trữ hoặc nhờ lab gửi qua liên kết tải. (Tham khảo.)', 1),
 (N'Scan: hiệu chỉnh màu thủ công, bụi và xước', N'Scan',
  N'Scan chất lượng cao có thể kèm hiệu chỉnh màu thủ công theo từng khung, giúp màu sát cảm nhận khi chụp hơn so với tự động. Bụi và xước trên phim có thể được xử lý bằng bước làm sạch hoặc retouch nhẹ, thường tính thêm phí. (Tham khảo, chưa được duyệt.)', 0),
 (N'Kodak Portra 160, 400 và 800: so sánh nhanh (tham khảo)', N'Film stock',
  N'Dòng Portra là phim màu negative, tông da ấm, latitude rộng. Portra 160 hạt rất mịn, hợp nơi nhiều sáng; Portra 400 đa dụng nhất; Portra 800 hợp thiếu sáng hoặc trong nhà. Cả ba đều tráng bằng quy trình màu negative phổ biến. (Tham khảo.)', 1),
 (N'Tri-X 400, HP5 Plus 400 và T-Max 100: phim đen trắng phổ biến (tham khảo)', N'Film stock',
  N'Tri-X 400 cho hạt rõ và tương phản cao, hợp chụp đường phố; HP5 Plus 400 có latitude rộng và dễ push; T-Max 100 hạt rất mịn, hợp chụp nhiều sáng cần độ chi tiết. Đây là gợi ý chung, cảm nhận hình ảnh còn tùy developer và cách tráng. (Tham khảo.)', 1),
 (N'Ektachrome E100 và Velvia 50: phim slide (tham khảo)', N'Film stock',
  N'Ektachrome E100 cho màu trung thực, hạt mịn; Velvia 50 màu bão hòa mạnh, hợp phong cảnh nhưng latitude hẹp nên cần đo sáng cẩn thận. Cả hai là phim slide, cần tráng bằng quy trình E-6. (Tham khảo.)', 1),
 (N'Cách đọc gói dịch vụ và giá của lab', N'Film lab',
  N'Mỗi gói dịch vụ ghi giá theo cuộn (Roll) hoặc theo khung (Frame), cùng thời gian xử lý. Đơn thường gồm gói tráng cộng gói scan, nên cộng giá hai gói và lấy thời gian của gói lâu nhất. Hãy kiểm tra khổ phim (35mm, 120), quy trình và mức scan trước khi chọn. (Tham khảo.)', 1),
 (N'Thời gian trả phim và cách chọn lab gần bạn', N'Film lab',
  N'Thời gian trả phim thường từ 2 đến 5 ngày tùy gói tráng và scan. Chọn lab gần giúp tiết kiệm phí giao nhận; lab ở xa có thể rẻ hơn nhưng mất thêm thời gian vận chuyển. Xem điểm đánh giá và nhận xét của khách trước khi đặt, đặc biệt với phim quan trọng. (Tham khảo.)', 1),
 (N'Bảo quản phim chưa chụp (tham khảo)', N'Bảo quản',
  N'Giữ phim chưa chụp ở nơi mát và khô, tránh nóng và ẩm; nếu cất lâu có thể để ngăn mát hoặc ngăn đá trong túi kín, rồi để về nhiệt độ phòng trước khi dùng. Phim ISO cao nhạy với tia X, nên khi đi máy bay hãy xin kiểm tra tay thay vì cho qua máy soi. (Tham khảo.)', 1),
 (N'Bảo quản phim đã tráng và file scan', N'Bảo quản',
  N'Phim đã tráng nên cất trong sleeve không axit, đặt thẳng đứng trong hộp khô thoáng, tránh ẩm gây nấm mốc. File scan cần sao lưu ở ít nhất hai nơi khác nhau, ví dụ ổ cứng và dịch vụ lưu trữ trực tuyến, vì phim có thể xuống cấp theo thời gian. (Tham khảo.)', 1),
 (N'Đơn hàng FilmLab: 13 giai đoạn xử lý', N'Đặt đơn FilmLab',
  N'Đơn đi qua các giai đoạn: Chờ lab xác nhận, Lab đã xác nhận, Chờ nhận phim, Đã nhận phim, Tráng, Rửa, Sấy, Scan, Chuẩn bị ảnh, Kiểm tra chất lượng, Sẵn sàng trả, Hoàn tất. Đơn không có gói tráng sẽ bỏ qua Tráng, Rửa, Sấy; đơn không có gói scan bỏ qua Scan và Chuẩn bị ảnh. Giai đoạn chỉ đi tiến; Đã hủy là trạng thái kết thúc thứ 13.', 1),
 (N'Thanh toán và hủy đơn trên FilmLab', N'Đặt đơn FilmLab',
  N'Khách thanh toán sau khi lab xác nhận đơn, số tiền phải đúng tổng đơn. Đơn chỉ hoàn tất khi đã thanh toán. Khách, chủ lab hoặc Admin có thể hủy đơn khi chưa vào giai đoạn tráng và phải nhập lý do; đơn đã thanh toán sẽ được hoàn tiền. Phí giao nhận mặc định 25.000đ mỗi chặng do Admin cấu hình.', 1);

-- ===== 2. Cập nhật chunk đã có (so khớp Title; chỉ khi Content hoặc Topic đổi) =====
UPDATE d
SET Content = v.Content, Topic = v.Topic,
    ContentHash = CONVERT(CHAR(64), HASHBYTES('SHA2_256', v.Content), 2),
    UpdatedAt = SYSUTCDATETIME()
FROM ai.KnowledgeDocs d
JOIN @k v ON v.Title = d.Title
WHERE d.IsDeleted = 0
  AND (ISNULL(d.ContentHash, '') <> CONVERT(CHAR(64), HASHBYTES('SHA2_256', v.Content), 2)
       OR ISNULL(d.Topic, N'') COLLATE Latin1_General_BIN2 <> v.Topic COLLATE Latin1_General_BIN2);

-- ===== 3. Thêm chunk mới (theo thứ tự Seq để chunk C-41 có ID thấp) =====
INSERT INTO ai.KnowledgeDocs (SourceArticleId, ChunkIndex, Title, Topic, Content, ContentHash, EmbeddingJson, EmbeddingModel,
                              ContributedBy, IsApproved, ApprovedBy, ApprovedAt)
SELECT NULL, 0, v.Title, v.Topic, v.Content, CONVERT(CHAR(64), HASHBYTES('SHA2_256', v.Content), 2), NULL, NULL,
       @Expert, v.Approved,
       CASE WHEN v.Approved = 1 THEN @Admin END,
       CASE WHEN v.Approved = 1 THEN SYSUTCDATETIME() END
FROM @k v
WHERE NOT EXISTS (SELECT 1 FROM ai.KnowledgeDocs d WHERE d.Title = v.Title AND d.IsDeleted = 0)
ORDER BY v.Seq;
GO

-- ===== 4. Kiểm tra nhanh =====
-- 4a. Tổng quan
SELECT COUNT(*) AS Total,
       SUM(CASE WHEN IsApproved = 1 THEN 1 ELSE 0 END) AS Approved,
       SUM(CASE WHEN IsApproved = 0 THEN 1 ELSE 0 END) AS Pending,
       SUM(CASE WHEN ContentHash IS NULL THEN 1 ELSE 0 END) AS NullHash
FROM ai.KnowledgeDocs WHERE IsDeleted = 0;

-- 4b. Theo chủ đề
SELECT Topic, COUNT(*) AS Total, SUM(CASE WHEN IsApproved = 1 THEN 1 ELSE 0 END) AS Approved
FROM ai.KnowledgeDocs WHERE IsDeleted = 0
GROUP BY Topic ORDER BY Topic;

-- 4c. Tìm kiếm thử dưới user có thật (chỉ trả chunk đã duyệt)
DECLARE @u INT = (SELECT UserId FROM iam.Users WHERE Email = N'an.nguyen@example.com');
EXEC ai.sp_SearchKnowledge @UserId = @u, @Query = N'push pull', @TopN = 3;
EXEC ai.sp_SearchKnowledge @UserId = @u, @Query = N'hủy đơn', @TopN = 3;
GO