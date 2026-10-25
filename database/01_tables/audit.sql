/* ============================================================
   File    : database/01_tables/audit.sql
   Module  : audit - M10 System / Audit
   Purpose : Tables của M10 System / Audit. Thứ tự CREATE TABLE: AuditLogs.
             Gồm PK, CHECK, UNIQUE, DEFAULT và FK TRONG CÙNG schema (không có).
   Owner   : A (xem docs/Phan-cong.md)
   Depends : (không FK)
   Re-run  : Chạy lại bằng REBUILD=1 (DB tạo mới). Không DROP TABLE thủ công.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;  -- bắt buộc cho filtered index, spatial index, computed column
SET ANSI_NULLS ON;
GO

-- Nhật ký thay đổi dữ liệu (chỉ thêm, ghi qua audit.sp_WriteAudit)
CREATE TABLE audit.AuditLogs
(
    AuditLogId           BIGINT IDENTITY(1,1) NOT NULL
                           CONSTRAINT PK_AuditLogs PRIMARY KEY,
    TableSchema          NVARCHAR(128) NOT NULL,
    TableName            NVARCHAR(128) NOT NULL,
    PrimaryKeyValue      NVARCHAR(100) NOT NULL,
    Action               NVARCHAR(6) NOT NULL
                           CONSTRAINT CK_AuditLogs_Action CHECK (Action IN ('INSERT','UPDATE','DELETE')),
    ChangedBy            INT NULL,
    OldValues            NVARCHAR(MAX) NULL
                           CONSTRAINT CK_AuditLogs_OldValues CHECK (ISJSON(OldValues) = 1),
    NewValues            NVARCHAR(MAX) NULL
                           CONSTRAINT CK_AuditLogs_NewValues CHECK (ISJSON(NewValues) = 1),
    AppName              NVARCHAR(128) NULL
                           CONSTRAINT DF_AuditLogs_AppName DEFAULT APP_NAME(),
    HostName             NVARCHAR(128) NULL
                           CONSTRAINT DF_AuditLogs_HostName DEFAULT HOST_NAME(),
    ChangedAt            DATETIME2(0) NOT NULL
                           CONSTRAINT DF_AuditLogs_ChangedAt DEFAULT SYSUTCDATETIME(),
    CONSTRAINT CK_AuditLogs_Action_OldValues CHECK ((Action = 'INSERT' AND OldValues IS NULL) OR (Action = 'DELETE' AND NewValues IS NULL) OR Action = 'UPDATE')
);
GO
