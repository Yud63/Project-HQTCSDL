/* ============================================================
   File    : database/05_functions/lab.sql
   Module  : lab - M2 Lab & Catalog
   Purpose : Function: fn_LabCapacityLeft, fn_DistanceKm.
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

CREATE OR ALTER FUNCTION lab.fn_DistanceKm (@From geography, @To geography)
RETURNS DECIMAL(6,2)
AS
BEGIN
    DECLARE @km DECIMAL(18,2) =
        CASE WHEN @From IS NULL OR @To IS NULL THEN NULL
             ELSE CAST(ROUND(@From.STDistance(@To) / 1000.0, 2) AS DECIMAL(18,2)) END;
    RETURN CASE WHEN @km > 9999.99 THEN 9999.99 ELSE @km END;
END
GO

-- Số cuộn lab còn nhận được trong ngày @OnDate (chỉ đếm dòng Develop tính theo Roll, bỏ đơn Cancelled)
CREATE OR ALTER FUNCTION lab.fn_LabCapacityLeft (@LabId INT, @OnDate DATE)
RETURNS INT
AS
BEGIN
    DECLARE @Cap INT = (SELECT DailyCapacityRolls FROM lab.FilmLabs WHERE LabId = @LabId);
    IF @Cap IS NULL RETURN NULL;

    DECLARE @Used INT = ISNULL((
        SELECT SUM(oi.Quantity)
        FROM ord.Orders o
        JOIN ord.OrderItems oi ON oi.OrderId = o.OrderId
        JOIN lab.LabServices ls ON ls.LabServiceId = oi.LabServiceId
        JOIN lab.ServiceTypes st ON st.ServiceTypeId = ls.ServiceTypeId
        WHERE o.LabId = @LabId
          AND CAST(o.CreatedAt AS DATE) = @OnDate
          AND o.StageId <> 13 AND o.IsDeleted = 0
          AND st.Category = N'Develop' AND ls.PriceUnit = N'Roll'), 0);

    RETURN CASE WHEN @Cap - @Used < 0 THEN 0 ELSE @Cap - @Used END;
END
GO
