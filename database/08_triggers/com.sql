/* ============================================================
   File    : database/08_triggers/com.sql
   Module  : com - M8 Community & Knowledge
   Purpose : Trigger: trg_Articles_CheckAuthorRole, trg_ArticleComments_CheckLevel, trg_EventRegistrations_CheckSeats. Dùng templates/trigger_template.sql.
   Owner   : D (xem docs/Phan-cong.md)
   Depends : iam, lab
   Re-run  : CREATE OR ALTER - chạy lại bao nhiêu lần cũng được.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER TRIGGER com.trg_Articles_CheckAuthorRole
ON com.Articles
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF TRIGGER_NESTLEVEL() > 1 RETURN;
    IF NOT (UPDATE(AuthorId) OR UPDATE(ArticleType)) RETURN;

    IF EXISTS (SELECT 1
               FROM inserted i
               WHERE i.ArticleType IN (N'Tutorial', N'Technical', N'LabGuide')
                 AND NOT EXISTS (SELECT 1
                                 FROM iam.UserRoles ur
                                 JOIN iam.Roles r ON r.RoleId = ur.RoleId
                                 WHERE ur.UserId = i.AuthorId AND r.RoleCode IN (N'Expert', N'Admin')))
        THROW 50703, N'Bài Tutorial/Technical/LabGuide chỉ do Expert hoặc Admin đăng.', 1;
END
GO

CREATE OR ALTER TRIGGER com.trg_ArticleComments_CheckLevel
ON com.ArticleComments
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF TRIGGER_NESTLEVEL() > 1 RETURN;
    IF NOT UPDATE(ParentCommentId) RETURN;

    IF EXISTS (SELECT 1
               FROM inserted i
               JOIN com.ArticleComments p ON p.CommentId = i.ParentCommentId
               WHERE p.ParentCommentId IS NOT NULL OR p.ArticleId <> i.ArticleId)
        THROW 50705, N'Bình luận chỉ được trả lời 1 cấp và phải cùng bài viết.', 1;
END
GO

CREATE OR ALTER TRIGGER com.trg_EventRegistrations_CheckSeats
ON com.EventRegistrations
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF TRIGGER_NESTLEVEL() > 1 RETURN;

    IF EXISTS (SELECT 1
               FROM com.Events e
               JOIN (SELECT DISTINCT EventId FROM inserted) i ON i.EventId = e.EventId
               WHERE (SELECT COUNT(*) FROM com.EventRegistrations r
                      WHERE r.EventId = e.EventId AND r.Status IN (N'Registered', N'Attended')) > e.Capacity)
        THROW 50706, N'Số người đăng ký vượt sức chứa của sự kiện.', 1;
END
GO
