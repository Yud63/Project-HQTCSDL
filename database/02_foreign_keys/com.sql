/* ============================================================
   File    : database/02_foreign_keys/com.sql
   Module  : com - M8 Community & Knowledge
   Purpose : FK LIÊN MODULE (8): FK_Articles_Users_AuthorId, FK_Articles_FilmLabs, FK_Articles_FilmStocks, FK_Articles_Users_ModeratedBy, FK_ArticleComments_Users, FK_Events_Users, FK_Events_FilmLabs, FK_EventRegistrations_Users.
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

ALTER TABLE com.Articles WITH CHECK
    ADD CONSTRAINT FK_Articles_Users_AuthorId FOREIGN KEY (AuthorId) REFERENCES iam.Users(UserId);
GO

ALTER TABLE com.Articles WITH CHECK
    ADD CONSTRAINT FK_Articles_FilmLabs FOREIGN KEY (RelatedLabId) REFERENCES lab.FilmLabs(LabId);
GO

ALTER TABLE com.Articles WITH CHECK
    ADD CONSTRAINT FK_Articles_FilmStocks FOREIGN KEY (RelatedStockId) REFERENCES lab.FilmStocks(StockId);
GO

ALTER TABLE com.Articles WITH CHECK
    ADD CONSTRAINT FK_Articles_Users_ModeratedBy FOREIGN KEY (ModeratedBy) REFERENCES iam.Users(UserId);
GO

ALTER TABLE com.Events WITH CHECK
    ADD CONSTRAINT FK_Events_Users FOREIGN KEY (OrganizerId) REFERENCES iam.Users(UserId);
GO

ALTER TABLE com.Events WITH CHECK
    ADD CONSTRAINT FK_Events_FilmLabs FOREIGN KEY (HostLabId) REFERENCES lab.FilmLabs(LabId);
GO

ALTER TABLE com.ArticleComments WITH CHECK
    ADD CONSTRAINT FK_ArticleComments_Users FOREIGN KEY (UserId) REFERENCES iam.Users(UserId);
GO

ALTER TABLE com.EventRegistrations WITH CHECK
    ADD CONSTRAINT FK_EventRegistrations_Users FOREIGN KEY (UserId) REFERENCES iam.Users(UserId);
GO
