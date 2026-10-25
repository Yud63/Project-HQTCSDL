/* ============================================================
   File    : database/03_indexes/ai.sql
   Module  : ai - M9 AI Support
   Purpose : Index của M9 AI Support (chi tiết trong docs/Requirements.md, mục Index dự kiến). Đặt tên IX_/UX_/SIX_<Bang>_<Cot>. Full-Text bọc IF SERVERPROPERTY('IsFullTextInstalled') = 1.
   Owner   : E (xem docs/Phan-cong.md)
   Depends : iam, lab, com
   Re-run  : Chạy lại bằng REBUILD=1 (DB tạo mới). Không DROP TABLE thủ công.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;  -- bắt buộc cho filtered index, spatial index, computed column
SET ANSI_NULLS ON;
GO

CREATE UNIQUE NONCLUSTERED INDEX UX_Knowledge_Chunk
    ON ai.KnowledgeDocs (SourceArticleId, ChunkIndex)
    WHERE SourceArticleId IS NOT NULL AND IsDeleted = 0;
GO

CREATE NONCLUSTERED INDEX IX_ChatLogs_Session
    ON ai.AIChatLogs (SessionId, CreatedAt);
GO

CREATE NONCLUSTERED INDEX IX_ChatLogs_User
    ON ai.AIChatLogs (UserId, CreatedAt DESC);
GO

CREATE NONCLUSTERED INDEX IX_RecLogs_User
    ON ai.RecommendationLogs (UserId, CreatedAt DESC);
GO

CREATE NONCLUSTERED INDEX IX_RecLogs_Item
    ON ai.RecommendationLogs (RecommendationType, ItemId);
GO

-- Full-Text (D-20): chỉ tạo khi instance có cài Full-Text (image Linux của CI không có)
IF SERVERPROPERTY('IsFullTextInstalled') = 1
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sys.fulltext_catalogs WHERE name = N'ftc_FilmLabDB')
        EXEC(N'CREATE FULLTEXT CATALOG ftc_FilmLabDB;');
    EXEC(N'CREATE FULLTEXT INDEX ON ai.KnowledgeDocs (Title LANGUAGE 0, Content LANGUAGE 0) KEY INDEX PK_KnowledgeDocs ON ftc_FilmLabDB WITH CHANGE_TRACKING AUTO;');
END
GO
