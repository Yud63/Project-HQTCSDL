/* ============================================================
   File    : database/05_functions/ai.sql
   Module  : ai - M9 AI Support
   Purpose : Function: fn_LabScores.
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

CREATE OR ALTER FUNCTION ai.fn_LabScores (@UserId INT, @Latitude FLOAT, @Longitude FLOAT)
RETURNS TABLE
AS
RETURN
WITH Pref AS (
    SELECT up.PreferredFormatId, ISNULL(up.MaxDistanceKm, 30) AS MaxDist, up.MaxBudgetPerRoll AS Budget
    FROM (SELECT 1 AS One) d
    LEFT JOIN ai.UserPreferences up ON up.UserId = @UserId
),
Origin AS (
    SELECT CASE WHEN @Latitude IS NOT NULL AND @Longitude IS NOT NULL
                THEN geography::Point(@Latitude, @Longitude, 4326)
                ELSE (SELECT TOP (1) a.Location FROM iam.Addresses a
                      WHERE a.UserId = @UserId AND a.IsDeleted = 0 AND a.Location IS NOT NULL
                      ORDER BY a.IsDefault DESC, a.AddressId) END AS Geo
),
Glob AS (
    SELECT ISNULL(AVG(CAST(AvgRating AS FLOAT)), 3.0) AS C
    FROM lab.FilmLabs
    WHERE ApprovalStatus = N'Approved' AND IsDeleted = 0 AND ReviewCount > 0
),
Base AS (
    SELECT l.LabId, l.LabName, l.AvgRating, l.ReviewCount,
           (CAST(l.ReviewCount AS FLOAT) * l.AvgRating + 5.0 * g.C) / (l.ReviewCount + 5.0) AS Bayes,
           CAST(lab.fn_DistanceKm(o.Geo, l.Location) AS FLOAT) AS Dist,
           p.MaxDist, p.Budget, sv.MinPrice, sv.MinDays,
           CASE WHEN bad.N > 0 THEN 0.0 WHEN h.N >= 2 THEN 1.0 WHEN h.N = 1 THEN 0.5 ELSE 0.0 END AS Hist
    FROM lab.FilmLabs l
    CROSS JOIN Pref p
    CROSS JOIN Origin o
    CROSS JOIN Glob g
    OUTER APPLY (SELECT MIN(ls.UnitPrice) AS MinPrice, MIN(CAST(ls.TurnaroundDays AS INT)) AS MinDays
                 FROM lab.LabServices ls
                 WHERE ls.LabId = l.LabId AND ls.IsActive = 1 AND ls.IsDeleted = 0
                   AND (p.PreferredFormatId IS NULL OR ls.FormatId = p.PreferredFormatId)) sv
    OUTER APPLY (SELECT COUNT(*) AS N FROM ord.Orders od
                 WHERE od.CustomerId = @UserId AND od.LabId = l.LabId AND od.StageId = 12 AND od.IsDeleted = 0) h
    OUTER APPLY (SELECT COUNT(*) AS N FROM ord.Reviews rv
                 WHERE rv.CustomerId = @UserId AND rv.LabId = l.LabId AND rv.RatingOverall <= 2 AND rv.IsDeleted = 0) bad
    WHERE l.ApprovalStatus = N'Approved' AND l.IsDeleted = 0
),
Norm AS (
    SELECT b.*,
           MIN(CAST(b.MinPrice AS FLOAT)) OVER () AS MnP, MAX(CAST(b.MinPrice AS FLOAT)) OVER () AS MxP,
           MIN(CAST(b.MinDays AS FLOAT)) OVER ()  AS MnD, MAX(CAST(b.MinDays AS FLOAT)) OVER ()  AS MxD
    FROM Base b
),
Comp AS (
    SELECT n.*,
           n.Bayes / 5.0 AS RS,
           CASE WHEN n.Dist IS NULL THEN 0.5
                WHEN n.Dist >= n.MaxDist THEN 0.0
                ELSE 1.0 - n.Dist / n.MaxDist END AS DS,
           CASE WHEN n.MinPrice IS NULL THEN 0.0
                WHEN n.Budget IS NOT NULL AND n.MinPrice > n.Budget THEN 0.0
                WHEN n.MxP = n.MnP THEN 1.0
                ELSE 1.0 - (CAST(n.MinPrice AS FLOAT) - n.MnP) / (n.MxP - n.MnP) END AS PS,
           CASE WHEN n.MinDays IS NULL THEN 0.0
                WHEN n.MxD = n.MnD THEN 1.0
                ELSE 1.0 - (CAST(n.MinDays AS FLOAT) - n.MnD) / (n.MxD - n.MnD) END AS SS
    FROM Norm n
)
SELECT c.LabId, c.LabName, c.AvgRating, c.ReviewCount,
       CAST(c.Dist AS DECIMAL(9,2)) AS DistanceKm,
       c.MinPrice,
       CAST(c.MinDays AS TINYINT) AS MinTurnaroundDays,
       CAST(c.RS   AS DECIMAL(6,4)) AS RatingScore,
       CAST(c.DS   AS DECIMAL(6,4)) AS DistanceScore,
       CAST(c.PS   AS DECIMAL(6,4)) AS PriceScore,
       CAST(c.SS   AS DECIMAL(6,4)) AS SpeedScore,
       CAST(c.Hist AS DECIMAL(6,4)) AS HistoryScore,
       CAST(0.35 * c.RS + 0.25 * c.DS + 0.20 * c.PS + 0.10 * c.SS + 0.10 * c.Hist AS DECIMAL(6,4)) AS Score
FROM Comp c;
GO
