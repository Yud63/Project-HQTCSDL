/* ============================================================
   File    : database/02_foreign_keys/lab.sql
   Module  : lab - M2 Lab & Catalog
   Purpose : FK LIÊN MODULE (2): FK_FilmLabs_Users, FK_LabApprovals_Users.
   Owner   : B (xem docs/Phan-cong.md)
   Depends : iam
   Re-run  : Chạy lại bằng REBUILD=1 (DB tạo mới). Không DROP TABLE thủ công.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;  -- bắt buộc cho filtered index, spatial index, computed column
SET ANSI_NULLS ON;
GO

ALTER TABLE lab.FilmLabs WITH CHECK
    ADD CONSTRAINT FK_FilmLabs_Users FOREIGN KEY (OwnerUserId) REFERENCES iam.Users(UserId);
GO

ALTER TABLE lab.LabApprovals WITH CHECK
    ADD CONSTRAINT FK_LabApprovals_Users FOREIGN KEY (ReviewedBy) REFERENCES iam.Users(UserId);
GO
