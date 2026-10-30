/* ============================================================
   File    : database/08_triggers/iam.sql
   Module  : iam - M1 Identity & Access
   Purpose : Trigger: trg_Users_Audit. Dùng templates/trigger_template.sql.
   Owner   : A (xem docs/Phan-cong.md)
   Depends : (gốc)
   Re-run  : CREATE OR ALTER - chạy lại bao nhiêu lần cũng được.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- Ghi nhật ký khi Users đổi dữ liệu nghiệp vụ; KHÔNG ghi PasswordHash, chỉ cờ PasswordChanged
CREATE OR ALTER TRIGGER iam.trg_Users_Audit
ON iam.Users
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF TRIGGER_NESTLEVEL() > 1 RETURN;
    IF NOT (UPDATE(Email) OR UPDATE(AuthProvider) OR UPDATE(PasswordHash) OR UPDATE(FullName)
            OR UPDATE(Phone) OR UPDATE(AvatarUrl) OR UPDATE(IsActive) OR UPDATE(IsDeleted)) RETURN;

    DECLARE @Pk NVARCHAR(100), @Old NVARCHAR(MAX), @New NVARCHAR(MAX);
    DECLARE @By INT = TRY_CAST(SESSION_CONTEXT(N'UserId') AS INT);

    DECLARE c CURSOR LOCAL FAST_FORWARD FOR
        SELECT CAST(i.UserId AS NVARCHAR(100)),
               (SELECT d.UserId, d.Email, d.AuthProvider, d.FullName, d.Phone, d.AvatarUrl, d.IsActive, d.IsDeleted
                FOR JSON PATH, INCLUDE_NULL_VALUES, WITHOUT_ARRAY_WRAPPER),
               (SELECT i.UserId, i.Email, i.AuthProvider, i.FullName, i.Phone, i.AvatarUrl, i.IsActive, i.IsDeleted,
                       CAST(CASE WHEN EXISTS (SELECT i.PasswordHash EXCEPT SELECT d.PasswordHash) THEN 1 ELSE 0 END AS BIT) AS PasswordChanged
                FOR JSON PATH, INCLUDE_NULL_VALUES, WITHOUT_ARRAY_WRAPPER)
        FROM inserted i
        JOIN deleted d ON d.UserId = i.UserId
        WHERE EXISTS (SELECT i.Email, i.AuthProvider, i.PasswordHash, i.FullName, i.Phone, i.AvatarUrl, i.IsActive, i.IsDeleted
                      EXCEPT
                      SELECT d.Email, d.AuthProvider, d.PasswordHash, d.FullName, d.Phone, d.AvatarUrl, d.IsActive, d.IsDeleted);

    OPEN c;
    FETCH NEXT FROM c INTO @Pk, @Old, @New;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC audit.sp_WriteAudit N'iam', N'Users', @Pk, N'UPDATE', @Old, @New, @By;
        FETCH NEXT FROM c INTO @Pk, @Old, @New;
    END;
    CLOSE c;
    DEALLOCATE c;
END
GO