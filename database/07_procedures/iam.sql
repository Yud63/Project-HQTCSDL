/* ============================================================
   File    : database/07_procedures/iam.sql
   Module  : iam - M1 Identity & Access
   Purpose : Procedure (★ = bắt buộc): ★sp_RegisterUser. Dùng templates/procedure_template.sql; chữ ký theo docs/Contracts.md mục 7.
   Owner   : A (xem docs/Phan-cong.md)
   Depends : (gốc)
   Re-run  : CREATE OR ALTER - chạy lại bao nhiêu lần cũng được.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;  -- bắt buộc: iam.Users có filtered index
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE iam.sp_RegisterUser
    @Email         NVARCHAR(255),
    @FullName      NVARCHAR(100),
    @PasswordHash  NVARCHAR(255) = NULL,
    @AuthProvider  NVARCHAR(20)  = N'Local',
    @Phone         NVARCHAR(20)  = NULL,
    @NewUserId     INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        SET @Email = LTRIM(RTRIM(@Email));
        IF NULLIF(@Email, N'') IS NULL OR NULLIF(LTRIM(RTRIM(@FullName)), N'') IS NULL
            THROW 50105, N'Email và họ tên không được rỗng.', 1;
        IF @AuthProvider NOT IN (N'Local', N'Google', N'Facebook')
            THROW 50105, N'AuthProvider không hợp lệ.', 1;
        IF @AuthProvider = N'Local' AND NULLIF(@PasswordHash, N'') IS NULL
            THROW 50105, N'Tài khoản Local bắt buộc có PasswordHash.', 1;
        IF EXISTS (SELECT 1 FROM iam.Users WHERE Email = @Email AND IsDeleted = 0)
            THROW 50104, N'Email đã tồn tại.', 1;

        BEGIN TRAN;
            INSERT INTO iam.Users (Email, AuthProvider, PasswordHash, FullName, Phone)
            VALUES (@Email, @AuthProvider, @PasswordHash, @FullName, @Phone);
            SET @NewUserId = SCOPE_IDENTITY();

            EXEC sp_set_session_context @key = N'UserId', @value = @NewUserId;

            INSERT INTO iam.UserRoles (UserId, RoleId, AssignedBy)
            SELECT @NewUserId, RoleId, NULL FROM iam.Roles WHERE RoleCode = N'Customer';
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        -- Hai request cùng email chạy đồng thời: unique index bắt được, đổi sang mã lỗi chuẩn
        IF ERROR_NUMBER() IN (2601, 2627)
            THROW 50104, N'Email đã tồn tại.', 1;
        THROW;
    END CATCH
END
GO