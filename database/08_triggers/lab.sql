/* ============================================================
   File    : database/08_triggers/lab.sql
   Module  : lab - M2 Lab & Catalog
   Purpose : Trigger: trg_LabServices_CheckScan, trg_FilmLabs_Audit. Dùng templates/trigger_template.sql.
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

-- Gói Scan phải có ScanQuality, gói khác phải để trống
CREATE OR ALTER TRIGGER lab.trg_LabServices_CheckScan
ON lab.LabServices
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF TRIGGER_NESTLEVEL() > 1 RETURN;

    IF EXISTS (SELECT 1
               FROM inserted i JOIN lab.ServiceTypes st ON st.ServiceTypeId = i.ServiceTypeId
               WHERE (st.Category = N'Scan' AND i.ScanQuality IS NULL)
                  OR (st.Category <> N'Scan' AND i.ScanQuality IS NOT NULL))
        THROW 50205, N'Gói Scan phải có ScanQuality, gói khác phải để trống.', 1;
END
GO

-- Ghi nhật ký thay đổi lab qua audit.sp_WriteAudit
-- (bị gọi từ trigger khác, ví dụ tính lại điểm sau đánh giá, thì không ghi để tránh nhật ký rác)
CREATE OR ALTER TRIGGER lab.trg_FilmLabs_Audit
ON lab.FilmLabs
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF TRIGGER_NESTLEVEL() > 1 RETURN;

    DECLARE @ids TABLE (Seq INT IDENTITY(1,1), Id INT, IsNew BIT);
    INSERT INTO @ids (Id, IsNew)
    SELECT i.LabId, CASE WHEN d.LabId IS NULL THEN 1 ELSE 0 END
    FROM inserted i LEFT JOIN deleted d ON d.LabId = i.LabId;

    DECLARE @s INT = 0, @id INT, @isnew BIT, @act NVARCHAR(6), @pk NVARCHAR(100), @old NVARCHAR(MAX), @new NVARCHAR(MAX);
    WHILE 1 = 1
    BEGIN
        SELECT TOP 1 @s = Seq, @id = Id, @isnew = IsNew FROM @ids WHERE Seq > @s ORDER BY Seq;
        IF @@ROWCOUNT = 0 BREAK;

        SET @new = (SELECT LabId, OwnerUserId, LabName, City, ApprovalStatus, DailyCapacityRolls, AvgRating, ReviewCount, IsDeleted
                    FROM inserted WHERE LabId = @id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        SET @old = CASE WHEN @isnew = 1 THEN NULL ELSE
                   (SELECT LabId, OwnerUserId, LabName, City, ApprovalStatus, DailyCapacityRolls, AvgRating, ReviewCount, IsDeleted
                    FROM deleted WHERE LabId = @id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) END;
        SET @act = CASE WHEN @isnew = 1 THEN N'INSERT' ELSE N'UPDATE' END;
        SET @pk = CAST(@id AS NVARCHAR(100));

        EXEC audit.sp_WriteAudit @TableSchema = N'lab', @TableName = N'FilmLabs', @PrimaryKeyValue = @pk,
                                 @Action = @act, @OldValues = @old, @NewValues = @new;
    END;
END
GO
