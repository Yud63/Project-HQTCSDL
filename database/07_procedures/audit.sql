/* ============================================================
   File    : database/07_procedures/audit.sql
   Module  : audit - M10 System / Audit
   Purpose : Điểm ghi nhật ký duy nhất cho mọi trigger audit
   Owner   : A (xem docs/Phan-cong.md)
   Depends : audit.AuditLogs
   Re-run  : CREATE OR ALTER, chạy lại được
   Ref     : docs/Conventions.md, docs/Contracts.md
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE audit.sp_WriteAudit
    @TableSchema      NVARCHAR(128),
    @TableName        NVARCHAR(128),
    @PrimaryKeyValue  NVARCHAR(100),
    @Action           NVARCHAR(6),
    @OldValues        NVARCHAR(MAX) = NULL,
    @NewValues        NVARCHAR(MAX) = NULL,
    @ChangedBy        INT = NULL      -- NULL: lấy từ SESSION_CONTEXT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        -- Không mở transaction riêng: chạy trong transaction của nơi gọi (trigger/procedure)
        IF @Action NOT IN (N'INSERT', N'UPDATE', N'DELETE')
            THROW 50905, N'Action phải là INSERT, UPDATE hoặc DELETE.', 1;
        IF @TableSchema IS NULL OR @TableName IS NULL OR @PrimaryKeyValue IS NULL
            THROW 50905, N'Thiếu TableSchema, TableName hoặc PrimaryKeyValue.', 1;
        IF (@OldValues IS NOT NULL AND ISJSON(@OldValues) = 0)
           OR (@NewValues IS NOT NULL AND ISJSON(@NewValues) = 0)
            THROW 50905, N'OldValues/NewValues phải là JSON hợp lệ.', 1;
        IF (@Action = N'INSERT' AND @OldValues IS NOT NULL)
           OR (@Action = N'DELETE' AND @NewValues IS NOT NULL)
            THROW 50905, N'INSERT không có OldValues, DELETE không có NewValues.', 1;

        SET @ChangedBy = COALESCE(@ChangedBy, TRY_CONVERT(INT, SESSION_CONTEXT(N'UserId')));

        INSERT INTO audit.AuditLogs
            (TableSchema, TableName, PrimaryKeyValue, Action, ChangedBy, OldValues, NewValues)
        VALUES
            (@TableSchema, @TableName, @PrimaryKeyValue, @Action, @ChangedBy, @OldValues, @NewValues);
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO