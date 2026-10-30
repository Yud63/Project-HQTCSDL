/* ============================================================
   File    : database/04_seed/sample/ai.sql
   Module  : ai - M9 AI Support
   Purpose : Dữ liệu mẫu cho test/demo (số dòng gợi ý trong docs/Requirements.md). Tiếng Việt có dấu dùng N'...'.
   Owner   : E (xem docs/Phan-cong.md)
   Depends : iam, lab, com
   Re-run  : Chạy sau REBUILD=1. Sample seed không gắn cứng ID của bảng IDENTITY.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;  -- bắt buộc cho filtered index, spatial index, computed column
SET ANSI_NULLS ON;
GO

SET NOCOUNT ON;

-- Sở thích người dùng (nguồn dữ liệu cho điểm gợi ý lab)
INSERT INTO ai.UserPreferences (UserId, PreferredFormatId, PreferredFilmType, PreferredCity, MaxDistanceKm, MaxBudgetPerRoll, PrioritizeQuality, PrioritizeSpeed, Source)
SELECT u.UserId, ff.FormatId, v.FilmType, v.City, v.MaxKm, v.Budget, v.PQ, v.PS, v.Source
FROM (VALUES
    (N'an.nguyen@example.com', N'35mm', N'ColorNegative', N'TP. Hồ Chí Minh', 10.0, 200000, 1, 0, N'UserSet'),
    (N'binh.tran@example.com', N'35mm', N'BlackWhite', N'TP. Hồ Chí Minh', 15.0, 150000, 0, 1, N'Inferred')
) v(Email, FormatCode, FilmType, City, MaxKm, Budget, PQ, PS, Source)
JOIN iam.Users u ON u.Email = v.Email
JOIN lab.FilmFormats ff ON ff.FormatCode = v.FormatCode;
GO

-- Tri thức cho RAG (chunk từ bài viết Expert; chỉ chunk đã duyệt mới dùng cho AI; embedding là placeholder)
INSERT INTO ai.KnowledgeDocs (SourceArticleId, ChunkIndex, Title, Topic, Content, ContentHash, EmbeddingJson, EmbeddingModel, ContributedBy, IsApproved, ApprovedBy, ApprovedAt)
SELECT a.ArticleId, v.Chunk, v.Title, v.Topic, v.Content, CONVERT(CHAR(64), HASHBYTES('SHA2_256', v.Content), 2),
       v.Emb, CASE WHEN v.Emb IS NOT NULL THEN N'placeholder-embedding-v0' END, e.UserId, v.Approved,
       CASE WHEN v.Approved = 1 THEN ad.UserId END, CASE WHEN v.Approved = 1 THEN SYSUTCDATETIME() END
FROM (VALUES
    (N'huong-dan-trang-phim-c41-tai-nha', 0, N'Tráng phim C-41: nhiệt độ và thời gian', N'C-41', N'Developer C-41 giữ ở 38°C, thời gian 3 phút 15 giây, khuấy đảo đều theo chu kỳ để tránh loang màu.', 1, N'[0.12,0.08,0.31]'),
    (N'huong-dan-trang-phim-c41-tai-nha', 1, N'Tráng phim C-41: blix, rửa và stabilizer', N'C-41', N'Sau developer là blix 6 phút, rửa nước 3 phút, ngâm stabilizer 1 phút rồi treo khô nơi sạch bụi.', 1, N'[0.05,0.22,0.17]'),
    (N'review-kodak-portra-400', 0, N'Kodak Portra 400: đặc điểm', N'Film stock', N'Portra 400 cho màu da ấm, hạt mịn, latitude rộng, chịu push +1 đến +2 stop.', 1, N'[0.40,0.11,0.09]'),
    (N'cach-chon-film-lab-tphcm', 0, N'Tiêu chí chọn film lab', N'Film lab', N'So sánh chất lượng scan, thời gian trả phim, giá theo cuộn và chính sách khiếu nại.', 0, NULL)
) v(Slug, Chunk, Title, Topic, Content, Approved, Emb)
JOIN com.Articles a ON a.Slug = v.Slug
CROSS JOIN (SELECT UserId FROM iam.Users WHERE Email = N'expert@filmlab.vn') e
CROSS JOIN (SELECT UserId FROM iam.Users WHERE Email = N'admin@filmlab.vn') ad;
GO

-- Nhật ký chat với trợ lý AI
INSERT INTO ai.AIChatLogs (SessionId, UserId, Role, Message, ModelName, PromptTokens, CompletionTokens, LatencyMs, SourcesJson, Feedback, CreatedAt)
SELECT CONVERT(UNIQUEIDENTIFIER, v.Session), u.UserId, v.Role, v.Msg, v.Model, v.PT, v.CT, v.Lat, v.Src, v.Fb, DATEADD(MINUTE, -v.MinAgo, SYSUTCDATETIME())
FROM (VALUES
    (N'6F9619FF-8B86-D011-B42D-00C04FC964FF', N'an.nguyen@example.com', N'User', N'Tôi nên tráng phim C-41 ở nhiệt độ nào?', NULL, NULL, NULL, NULL, NULL, NULL, 30),
    (N'6F9619FF-8B86-D011-B42D-00C04FC964FF', N'an.nguyen@example.com', N'Assistant', N'Developer C-41 thường giữ ở 38°C trong khoảng 3 phút 15 giây, bạn nên khuấy đều theo chu kỳ.', N'filmlab-assistant-v1', 120, 60, 850, CONCAT('[', (SELECT MIN(KnowledgeDocId) FROM ai.KnowledgeDocs WHERE Topic = N'C-41'), ']'), N'Helpful', 29),
    (N'0B7F1E2A-5C31-4A58-9D77-3E8C5A6B1D02', N'binh.tran@example.com', N'User', N'Gợi ý lab scan chất lượng cao ở Hà Nội?', NULL, NULL, NULL, NULL, NULL, NULL, 20),
    (N'0B7F1E2A-5C31-4A58-9D77-3E8C5A6B1D02', N'binh.tran@example.com', N'Assistant', N'Hà Nội Analog Lab có gói Scan Ultra 35mm, thời gian khoảng 5 ngày.', N'filmlab-assistant-v1', 95, 48, 720, NULL, NULL, 19)
) v(Session, Email, Role, Msg, Model, PT, CT, Lat, Src, Fb, MinAgo)
JOIN iam.Users u ON u.Email = v.Email;
GO

-- Nhật ký gợi ý lab (ItemId trỏ tới lab.FilmLabs.LabId, không có FK có chủ ý)
INSERT INTO ai.RecommendationLogs (UserId, RecommendationType, ItemId, Rank, Score, ModelVersion, ContextJson, Action, ActedAt)
SELECT u.UserId, v.Type, l.LabId, v.Rnk, v.Score, N'tsql-v1', v.Ctx, v.Action,
       CASE WHEN v.Action IS NOT NULL THEN DATEADD(MINUTE, -10, SYSUTCDATETIME()) END
FROM (VALUES
    (N'an.nguyen@example.com', N'Lab', N'Sài Gòn Film Lab', 1, 0.8123, N'{"format": "35mm", "city": "TP. Hồ Chí Minh"}', N'Clicked'),
    (N'an.nguyen@example.com', N'Lab', N'Hà Nội Analog Lab', 2, 0.612, N'{"format": "35mm", "city": "TP. Hồ Chí Minh"}', NULL),
    (N'binh.tran@example.com', N'Lab', N'Sài Gòn Film Lab', 1, 0.774, N'{"format": "35mm"}', N'Ordered')
) v(Email, Type, LabName, Rnk, Score, Ctx, Action)
JOIN iam.Users u ON u.Email = v.Email
JOIN lab.FilmLabs l ON l.LabName = v.LabName;
GO
