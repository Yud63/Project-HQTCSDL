/* ============================================================
   File    : database/02_foreign_keys/ai.sql
   Module  : ai - M9 AI Support
   Purpose : FK LIÊN MODULE (7): FK_UserPreferences_Users, FK_UserPreferences_FilmFormats, FK_AIChatLogs_Users, FK_RecommendationLogs_Users, FK_KnowledgeDocs_Articles, FK_KnowledgeDocs_Users_ContributedBy, FK_KnowledgeDocs_Users_ApprovedBy.
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

ALTER TABLE ai.UserPreferences WITH CHECK
    ADD CONSTRAINT FK_UserPreferences_Users FOREIGN KEY (UserId) REFERENCES iam.Users(UserId);
GO

ALTER TABLE ai.UserPreferences WITH CHECK
    ADD CONSTRAINT FK_UserPreferences_FilmFormats FOREIGN KEY (PreferredFormatId) REFERENCES lab.FilmFormats(FormatId);
GO

ALTER TABLE ai.AIChatLogs WITH CHECK
    ADD CONSTRAINT FK_AIChatLogs_Users FOREIGN KEY (UserId) REFERENCES iam.Users(UserId);
GO

ALTER TABLE ai.RecommendationLogs WITH CHECK
    ADD CONSTRAINT FK_RecommendationLogs_Users FOREIGN KEY (UserId) REFERENCES iam.Users(UserId);
GO

ALTER TABLE ai.KnowledgeDocs WITH CHECK
    ADD CONSTRAINT FK_KnowledgeDocs_Articles FOREIGN KEY (SourceArticleId) REFERENCES com.Articles(ArticleId);
GO

ALTER TABLE ai.KnowledgeDocs WITH CHECK
    ADD CONSTRAINT FK_KnowledgeDocs_Users_ContributedBy FOREIGN KEY (ContributedBy) REFERENCES iam.Users(UserId);
GO

ALTER TABLE ai.KnowledgeDocs WITH CHECK
    ADD CONSTRAINT FK_KnowledgeDocs_Users_ApprovedBy FOREIGN KEY (ApprovedBy) REFERENCES iam.Users(UserId);
GO
