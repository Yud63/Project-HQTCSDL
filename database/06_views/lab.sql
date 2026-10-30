/* ============================================================
   File    : database/06_views/lab.sql
   Module  : lab - M2 Lab & Catalog
   Purpose : View: vw_TopLabs.
   Owner   : B (xem docs/Phan-cong.md)
   Depends : iam
   Re-run  : CREATE OR ALTER - chạy lại bao nhiêu lần cũng được.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER VIEW lab.vw_TopLabs
AS
SELECT ROW_NUMBER() OVER (ORDER BY l.AvgRating DESC, l.ReviewCount DESC, l.LabId) AS RankNo,
       l.LabId, l.LabName, l.City, l.District, l.AvgRating, l.ReviewCount,
       s.MinPrice, s.MinTurnaroundDays
FROM lab.FilmLabs l
OUTER APPLY (SELECT MIN(ls.UnitPrice) AS MinPrice, MIN(CAST(ls.TurnaroundDays AS INT)) AS MinTurnaroundDays
             FROM lab.LabServices ls
             WHERE ls.LabId = l.LabId AND ls.IsActive = 1 AND ls.IsDeleted = 0) s
WHERE l.ApprovalStatus = N'Approved' AND l.IsDeleted = 0 AND l.ReviewCount > 0;
GO
