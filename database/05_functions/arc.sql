/* ============================================================
   File    : database/05_functions/arc.sql
   Module  : arc - M5 Digital Archive
   Purpose : Function: fn_GetPhotoMetadata.
   Owner   : C (xem docs/Phan-cong.md)
   Depends : iam, lab, ord
   Re-run  : CREATE OR ALTER - chạy lại bao nhiêu lần cũng được.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER FUNCTION arc.fn_GetPhotoMetadata (@ScanFileId UNIQUEIDENTIFIER)
RETURNS TABLE
AS
RETURN
(
    SELECT pm.ScanFileId,
           j.[key]   AS MetaKey,
           j.[value] AS MetaValue,
           j.[type]  AS JsonType
    FROM arc.PhotoMetadata pm
    CROSS APPLY OPENJSON(pm.ExtraJson) j
    WHERE pm.ScanFileId = @ScanFileId
);
GO
