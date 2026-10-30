/* ============================================================
   File    : database/05_functions/ord_feedback.sql
   Module  : ord_feedback - M6 Review & Complaint
   Purpose : Function: fn_LabAvgRating.
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

CREATE OR ALTER FUNCTION ord.fn_IsValidComplaintTransition (@From NVARCHAR(9), @To NVARCHAR(9))
RETURNS BIT
AS
BEGIN
    RETURN CASE
        WHEN (@From = N'Open'     AND @To IN (N'InReview', N'Resolved', N'Rejected'))
          OR (@From = N'InReview' AND @To IN (N'Resolved', N'Rejected'))
        THEN 1 ELSE 0 END;
END
GO

CREATE OR ALTER FUNCTION ord.fn_LabAvgRating (@LabId INT)
RETURNS DECIMAL(3,2)
AS
BEGIN
    RETURN (SELECT CAST(AVG(CAST(RatingOverall AS DECIMAL(5,2))) AS DECIMAL(3,2))
            FROM ord.Reviews
            WHERE LabId = @LabId AND IsVisible = 1 AND IsDeleted = 0);
END
GO