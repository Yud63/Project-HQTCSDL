/* ============================================================
   File    : database/05_functions/dlv.sql
   Module  : dlv - M4 Delivery
   Purpose : Function: fn_IsValidDeliveryTransition.
   Owner   : A (xem docs/Phan-cong.md)
   Depends : iam, ord
   Re-run  : CREATE OR ALTER - chạy lại bao nhiêu lần cũng được.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER FUNCTION dlv.fn_IsValidDeliveryTransition (@From NVARCHAR(10), @To NVARCHAR(10))
RETURNS BIT
AS
BEGIN
    RETURN CASE
        WHEN (@From = N'Requested' AND @To IN (N'Assigned', N'Cancelled'))
          OR (@From = N'Assigned'  AND @To IN (N'PickedUp', N'Failed', N'Cancelled'))
          OR (@From = N'PickedUp'  AND @To IN (N'Delivered', N'Failed'))
        THEN 1 ELSE 0 END;
END
GO