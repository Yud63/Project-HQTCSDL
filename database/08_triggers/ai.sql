/* ============================================================
   File    : database/08_triggers/ai.sql
   Module  : ai - M9 AI Support
   Purpose : Trigger: trg_KnowledgeDocs_Guard. Dùng templates/trigger_template.sql.
   Owner   : E (xem docs/Phan-cong.md)
   Depends : iam, lab, com
   Re-run  : CREATE OR ALTER - chạy lại bao nhiêu lần cũng được.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER TRIGGER ai.trg_KnowledgeDocs_Guard
ON ai.KnowledgeDocs
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF TRIGGER_NESTLEVEL() > 1 RETURN;

    IF UPDATE(ContributedBy)
       AND EXISTS (SELECT 1
                   FROM inserted i
                   WHERE NOT EXISTS (SELECT 1 FROM iam.UserRoles ur
                                     JOIN iam.Roles r ON r.RoleId = ur.RoleId
                                     WHERE ur.UserId = i.ContributedBy AND r.RoleCode = N'Expert'))
        THROW 50803, N'Chỉ Expert được đóng góp tri thức.', 1;

    IF (UPDATE(IsApproved) OR UPDATE(ApprovedBy))
       AND EXISTS (SELECT 1
                   FROM inserted i
                   WHERE i.IsApproved = 1
                     AND NOT EXISTS (SELECT 1 FROM iam.UserRoles ur
                                     JOIN iam.Roles r ON r.RoleId = ur.RoleId
                                     WHERE ur.UserId = i.ApprovedBy AND r.RoleCode = N'Admin'))
        THROW 50803, N'Chỉ Admin được duyệt chunk tri thức.', 1;
END
GO