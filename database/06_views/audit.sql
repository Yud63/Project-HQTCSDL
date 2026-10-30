/* ============================================================
   File    : database/06_views/audit.sql
   Module  : audit - M10 System / Audit
   Purpose : View: vw_RecentChanges, vw_AdminDashboard.
   Owner   : A (xem docs/Phan-cong.md)
   Depends : (không FK)
   Re-run  : CREATE OR ALTER - chạy lại bao nhiêu lần cũng được.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER VIEW audit.vw_RecentChanges
AS
SELECT a.AuditLogId,
       a.TableSchema,
       a.TableName,
       a.PrimaryKeyValue,
       a.Action,
       a.ChangedBy,
       u.FullName AS ChangedByName,
       a.OldValues,
       a.NewValues,
       a.AppName,
       a.HostName,
       a.ChangedAt
FROM audit.AuditLogs a
LEFT JOIN iam.Users u ON u.UserId = a.ChangedBy
WHERE a.ChangedAt >= DATEADD(DAY, -30, SYSUTCDATETIME());
GO

CREATE OR ALTER VIEW audit.vw_AdminDashboard
AS
SELECT
    (SELECT COUNT(*) FROM iam.Users WHERE IsDeleted = 0)                                   AS TotalUsers,
    (SELECT COUNT(*) FROM lab.FilmLabs WHERE IsDeleted = 0 AND ApprovalStatus = N'Approved') AS ApprovedLabs,
    (SELECT COUNT(*) FROM lab.FilmLabs WHERE IsDeleted = 0 AND ApprovalStatus = N'Pending')  AS PendingLabs,
    (SELECT COUNT(*) FROM ord.Orders WHERE IsDeleted = 0 AND StageId BETWEEN 2 AND 11)       AS OrdersInProgress,
    (SELECT COUNT(*) FROM ord.Orders
     WHERE IsDeleted = 0 AND CreatedAt >= DATEFROMPARTS(YEAR(SYSUTCDATETIME()), MONTH(SYSUTCDATETIME()), 1)) AS OrdersThisMonth,
    (SELECT ISNULL(SUM(TotalAmount), 0) FROM ord.Orders
     WHERE IsDeleted = 0 AND StageId = 12 AND PaymentStatus = N'Paid'
       AND CompletedAt >= DATEFROMPARTS(YEAR(SYSUTCDATETIME()), MONTH(SYSUTCDATETIME()), 1)) AS RevenueThisMonth,
    (SELECT ISNULL(SUM(PlatformFee), 0) FROM ord.Orders
     WHERE IsDeleted = 0 AND StageId = 12 AND PaymentStatus = N'Paid'
       AND CompletedAt >= DATEFROMPARTS(YEAR(SYSUTCDATETIME()), MONTH(SYSUTCDATETIME()), 1)) AS PlatformFeeThisMonth,
    (SELECT COUNT(*) FROM ord.Complaints WHERE IsDeleted = 0 AND Status IN (N'Open', N'InReview')) AS OpenComplaints,
    (SELECT COUNT(*) FROM mkt.Listings
     WHERE IsDeleted = 0 AND Status = N'Active' AND ExpiresAt > SYSUTCDATETIME())           AS ActiveListings,
    (SELECT COUNT(*) FROM com.Events
     WHERE IsDeleted = 0 AND Status = N'Open' AND StartAt > SYSUTCDATETIME())               AS UpcomingEvents,
    (SELECT COUNT(*) FROM ai.KnowledgeDocs WHERE IsDeleted = 0 AND IsApproved = 0)          AS PendingKnowledgeDocs,
    (SELECT COUNT(*) FROM audit.AuditLogs
     WHERE ChangedAt >= CONVERT(DATETIME2(0), CONVERT(DATE, SYSUTCDATETIME())))             AS AuditEventsToday;
GO
