/* ============================================================
   File    : database/06_views/com.sql
   Module  : com - M8 Community & Knowledge
   Purpose : View: vw_ExpertContributions, vw_UpcomingEvents.
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

CREATE OR ALTER VIEW com.vw_UpcomingEvents
AS
SELECT e.EventId, e.EventType, e.Title, e.StartAt, e.EndAt, e.RegistrationDeadline,
       e.VenueName, e.City, e.HostLabId, hl.LabName AS HostLabName,
       e.OrganizerId, o.FullName AS OrganizerName, e.Capacity, e.Fee,
       ISNULL(r.RegisteredCount, 0) AS RegisteredCount,
       CASE WHEN e.Capacity - ISNULL(r.RegisteredCount, 0) < 0 THEN 0
            ELSE e.Capacity - ISNULL(r.RegisteredCount, 0) END AS SeatsLeft,
       ISNULL(r.WaitlistCount, 0) AS WaitlistCount
FROM com.Events e
JOIN iam.Users o ON o.UserId = e.OrganizerId
LEFT JOIN lab.FilmLabs hl ON hl.LabId = e.HostLabId
OUTER APPLY (SELECT SUM(CASE WHEN Status IN (N'Registered', N'Attended') THEN 1 ELSE 0 END) AS RegisteredCount,
                    SUM(CASE WHEN Status = N'Waitlisted' THEN 1 ELSE 0 END) AS WaitlistCount
             FROM com.EventRegistrations WHERE EventId = e.EventId) r
WHERE e.Status = N'Open' AND e.IsDeleted = 0 AND e.StartAt > SYSUTCDATETIME();
GO

CREATE OR ALTER VIEW com.vw_ExpertContributions
AS
SELECT u.UserId   AS ExpertId,
       u.FullName AS ExpertName,
       ISNULL(a.PublishedArticles, 0) AS PublishedArticles,
       ISNULL(a.HiddenArticles, 0)    AS HiddenArticles,
       ISNULL(m.AnswersGiven, 0)      AS AnswersGiven,
       ISNULL(m.AcceptedAnswers, 0)   AS AcceptedAnswers,
       ISNULL(ev.EventsOrganized, 0)  AS EventsOrganized,
       ISNULL(k.KnowledgeChunks, 0)   AS KnowledgeChunks,
       ISNULL(k.ApprovedChunks, 0)    AS ApprovedChunks
FROM iam.Users u
JOIN iam.UserRoles ur ON ur.UserId = u.UserId
JOIN iam.Roles rl ON rl.RoleId = ur.RoleId AND rl.RoleCode = N'Expert'
OUTER APPLY (SELECT SUM(CASE WHEN Status = N'Published' THEN 1 ELSE 0 END) AS PublishedArticles,
                    SUM(CASE WHEN Status = N'Hidden' THEN 1 ELSE 0 END) AS HiddenArticles
             FROM com.Articles WHERE AuthorId = u.UserId AND IsDeleted = 0) a
OUTER APPLY (SELECT COUNT(*) AS AnswersGiven,
                    SUM(CASE WHEN c.IsAccepted = 1 THEN 1 ELSE 0 END) AS AcceptedAnswers
             FROM com.ArticleComments c
             JOIN com.Articles qa ON qa.ArticleId = c.ArticleId AND qa.ArticleType = N'Question'
             WHERE c.UserId = u.UserId AND c.IsDeleted = 0) m
OUTER APPLY (SELECT COUNT(*) AS EventsOrganized
             FROM com.Events WHERE OrganizerId = u.UserId AND IsDeleted = 0) ev
OUTER APPLY (SELECT COUNT(*) AS KnowledgeChunks,
                    SUM(CASE WHEN IsApproved = 1 THEN 1 ELSE 0 END) AS ApprovedChunks
             FROM ai.KnowledgeDocs WHERE ContributedBy = u.UserId AND IsDeleted = 0) k
WHERE u.IsDeleted = 0;
GO
