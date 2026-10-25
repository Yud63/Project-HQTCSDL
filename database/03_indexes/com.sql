/* ============================================================
   File    : database/03_indexes/com.sql
   Module  : com - M8 Community & Knowledge
   Purpose : Index của M8 Community & Knowledge (chi tiết trong docs/Requirements.md, mục Index dự kiến). Đặt tên IX_/UX_/SIX_<Bang>_<Cot>. Full-Text bọc IF SERVERPROPERTY('IsFullTextInstalled') = 1.
   Owner   : D (xem docs/Phan-cong.md)
   Depends : iam, lab
   Re-run  : Chạy lại bằng REBUILD=1 (DB tạo mới). Không DROP TABLE thủ công.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;  -- bắt buộc cho filtered index, spatial index, computed column
SET ANSI_NULLS ON;
GO

CREATE UNIQUE NONCLUSTERED INDEX UX_Articles_Slug
    ON com.Articles (Slug)
    WHERE IsDeleted = 0;
GO

CREATE UNIQUE NONCLUSTERED INDEX UX_Comments_Accepted
    ON com.ArticleComments (ArticleId)
    WHERE IsAccepted = 1;
GO

CREATE NONCLUSTERED INDEX IX_Articles_Feed
    ON com.Articles (Status, ArticleType, PublishedAt DESC);
GO

CREATE NONCLUSTERED INDEX IX_Comments_Article
    ON com.ArticleComments (ArticleId, CreatedAt);
GO

CREATE NONCLUSTERED INDEX IX_Events_Upcoming
    ON com.Events (Status, StartAt);
GO

CREATE NONCLUSTERED INDEX IX_EventReg_User
    ON com.EventRegistrations (UserId, Status);
GO

-- Full-Text (D-20): chỉ tạo khi instance có cài Full-Text (image Linux của CI không có)
IF SERVERPROPERTY('IsFullTextInstalled') = 1
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sys.fulltext_catalogs WHERE name = N'ftc_FilmLabDB')
        EXEC(N'CREATE FULLTEXT CATALOG ftc_FilmLabDB;');
    EXEC(N'CREATE FULLTEXT INDEX ON com.Articles (Title LANGUAGE 0, Summary LANGUAGE 0, Body LANGUAGE 0) KEY INDEX PK_Articles ON ftc_FilmLabDB WITH CHANGE_TRACKING AUTO;');
END
GO
