/* ============================================================
   File    : database/06_views/ord_feedback.sql
   Module  : ord_feedback - M6 Review & Complaint
   Purpose : View: vw_LabReviews, vw_OpenComplaints.
   Owner   : C (xem docs/Phan-cong.md)
   Depends : iam, lab, ord (ord.sql chạy trước)
   Re-run  : CREATE OR ALTER - chạy lại bao nhiêu lần cũng được.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER VIEW ord.vw_LabReviews
AS
SELECT r.ReviewId,
       r.OrderId,
       o.OrderCode,
       r.LabId,
       l.LabName,
       r.CustomerId,
       u.FullName AS CustomerName,
       r.RatingOverall,
       r.RatingScanQuality,
       r.RatingSpeed,
       r.Comment,
       r.LabReply,
       r.LabRepliedAt,
       r.IsVisible,
       r.ModerationReason,
       r.CreatedAt
FROM ord.Reviews r
JOIN ord.Orders o ON o.OrderId = r.OrderId
JOIN lab.FilmLabs l ON l.LabId = r.LabId
JOIN iam.Users u ON u.UserId = r.CustomerId
WHERE r.IsDeleted = 0;
GO

CREATE OR ALTER VIEW ord.vw_OpenComplaints
AS
SELECT c.ComplaintId,
       c.OrderId,
       o.OrderCode,
       c.CustomerId,
       u.FullName AS CustomerName,
       c.LabId,
       l.LabName,
       c.Category,
       c.Title,
       c.Status,
       c.AssignedAdminId,
       a.FullName AS AssignedAdminName,
       c.CreatedAt,
       DATEDIFF(DAY, c.CreatedAt, SYSUTCDATETIME()) AS AgeDays
FROM ord.Complaints c
JOIN ord.Orders o ON o.OrderId = c.OrderId
JOIN lab.FilmLabs l ON l.LabId = c.LabId
JOIN iam.Users u ON u.UserId = c.CustomerId
LEFT JOIN iam.Users a ON a.UserId = c.AssignedAdminId
WHERE c.IsDeleted = 0 AND c.Status IN (N'Open', N'InReview');
GO
