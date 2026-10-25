/* ============================================================
   File    : database/02_foreign_keys/ord_feedback.sql
   Module  : ord_feedback - M6 Review & Complaint
   Purpose : FK LIÊN MODULE (2): FK_Reviews_Users, FK_Complaints_Users.
   Owner   : C (xem docs/Phan-cong.md)
   Depends : iam, lab, ord (ord.sql chạy trước)
   Re-run  : Chạy lại bằng REBUILD=1 (DB tạo mới). Không DROP TABLE thủ công.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;  -- bắt buộc cho filtered index, spatial index, computed column
SET ANSI_NULLS ON;
GO

ALTER TABLE ord.Reviews WITH CHECK
    ADD CONSTRAINT FK_Reviews_Users FOREIGN KEY (ModeratedBy) REFERENCES iam.Users(UserId);
GO

ALTER TABLE ord.Complaints WITH CHECK
    ADD CONSTRAINT FK_Complaints_Users FOREIGN KEY (AssignedAdminId) REFERENCES iam.Users(UserId);
GO
