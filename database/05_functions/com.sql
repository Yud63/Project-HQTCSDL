/* ============================================================
   File    : database/05_functions/com.sql
   Module  : com - M8 Community & Knowledge
   Purpose : Function: fn_EventSeatsLeft.
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

CREATE OR ALTER FUNCTION com.fn_EventSeatsLeft (@EventId INT)
RETURNS INT
AS
BEGIN
    DECLARE @Left INT;
    SELECT @Left = e.Capacity - (SELECT COUNT(*) FROM com.EventRegistrations r
                                 WHERE r.EventId = e.EventId AND r.Status IN (N'Registered', N'Attended'))
    FROM com.Events e
    WHERE e.EventId = @EventId AND e.IsDeleted = 0;
    IF @Left < 0 SET @Left = 0;
    RETURN @Left;
END
GO
