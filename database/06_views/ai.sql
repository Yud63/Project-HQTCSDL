/* ============================================================
   File    : database/06_views/ai.sql
   Module  : ai - M9 AI Support
   Purpose : View: vw_RecommendationMetrics.
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

CREATE OR ALTER VIEW ai.vw_RecommendationMetrics
AS
SELECT rl.ModelVersion,
       rl.RecommendationType,
       COUNT(*) AS Impressions,
       SUM(CASE WHEN rl.[Action] = N'Clicked'   THEN 1 ELSE 0 END) AS Clicked,
       SUM(CASE WHEN rl.[Action] = N'Ordered'   THEN 1 ELSE 0 END) AS Ordered,
       SUM(CASE WHEN rl.[Action] = N'Dismissed' THEN 1 ELSE 0 END) AS Dismissed,
       CAST(1.0 * SUM(CASE WHEN rl.[Action] IN (N'Clicked', N'Ordered') THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,4)) AS CtrRate,
       CAST(1.0 * SUM(CASE WHEN rl.[Action] = N'Ordered' THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,4)) AS OrderRate,
       CAST(AVG(rl.Score) AS DECIMAL(6,4)) AS AvgScore,
       MIN(rl.CreatedAt) AS FirstAt,
       MAX(rl.CreatedAt) AS LastAt
FROM ai.RecommendationLogs rl
GROUP BY rl.ModelVersion, rl.RecommendationType;
GO
